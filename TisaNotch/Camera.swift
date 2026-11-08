import AVFoundation
import Combine
import Foundation
import ImageIO

// The main actor owns the UI state. The serial camera queue owns session
// configuration and pending captures. The preview only attaches to the session.
final class Camera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Status: Equatable {
        case off
        case opening
        case ready
        case denied
        case failed(String)
    }

    enum Failure: LocalizedError {
        case unavailable, setup, busy, emptyPhoto, timedOut

        var errorDescription: String? {
            switch self {
            case .unavailable: return "A camera could not be opened."
            case .setup: return "This camera could not be configured for still photos."
            case .busy: return "The camera is finishing another photo. Try again in a moment."
            case .emptyPhoto: return "The camera returned an unreadable photo."
            case .timedOut: return "The camera took too long to respond. Try again."
            }
        }
    }

    private struct Capture {
        let id: Int64
        let continuation: CheckedContinuation<CGImage, Error>
        var result: Result<CGImage, Error>?
    }

    let session = AVCaptureSession()
    @MainActor @Published private(set) var status: Status = .off
    @MainActor @Published private(set) var canMirrorFrontCamera = false

    private let queue = DispatchQueue(label: "com.kuntisa.tisanotch.studio.camera")
    private let output = AVCapturePhotoOutput()
    // Session graph and photo requests are accessed only on the camera queue.
    private var capture: Capture?
    @MainActor private var openingID = UUID()

    @MainActor func start() {
        guard status != .opening, status != .ready else { return }
        status = .opening
        let id = UUID()
        openingID = id

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession(for: id)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.openingID == id else { return }
                    if granted {
                        self.startSession(for: id)
                    } else {
                        self.status = .denied
                    }
                }
            }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .failed("macOS did not report a usable camera authorization state.")
        }
    }

    @MainActor func stop() {
        openingID = UUID()
        status = .off
        canMirrorFrontCamera = false
        queue.async {
            if let pending = self.capture {
                self.capture = nil
                pending.continuation.resume(throwing: CancellationError())
            }
            self.resetSession()
        }
    }

    @MainActor private func startSession(for id: UUID) {
        queue.async {
            let next: (status: Status, canMirrorFrontCamera: Bool)
            do {
                let isFrontCamera = try self.configureSession()
                self.session.startRunning()
                guard self.session.isRunning else { throw Failure.unavailable }
                let supportsMirroring = self.output.connection(with: .video)?.isVideoMirroringSupported == true
                next = (.ready, isFrontCamera && supportsMirroring)
            } catch {
                self.resetSession()
                next = (.failed(error.localizedDescription), false)
            }
            DispatchQueue.main.async {
                guard self.openingID == id else { return }
                self.canMirrorFrontCamera = next.canMirrorFrontCamera
                self.status = next.status
            }
        }
    }

    private func configureSession() throws -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw Failure.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        guard session.canAddInput(input) else { throw Failure.setup }
        session.addInput(input)
        guard session.canAddOutput(output) else { throw Failure.setup }
        session.addOutput(output)
        // The built-in camera on some Macs reports an unspecified position.
        return device.position == .front ||
            (device.position == .unspecified && device.deviceType == .builtInWideAngleCamera)
    }

    private func resetSession() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        if session.outputs.contains(where: { $0 === output }) {
            session.removeOutput(output)
        }
        session.commitConfiguration()
    }

    @MainActor func takePhoto(mirroring: Bool?) async throws -> CGImage {
        try Task.checkCancellation()
        guard status == .ready else { throw Failure.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning,
                      let connection = self.output.connection(with: .video), connection.isActive else {
                    continuation.resume(throwing: Failure.unavailable)
                    return
                }
                guard self.capture == nil else {
                    continuation.resume(throwing: Failure.busy)
                    return
                }

                connection.setVideoMirroring(mirroring)
                let settings = AVCapturePhotoSettings()
                let id = settings.uniqueID
                self.capture = Capture(id: id, continuation: continuation)
                self.output.capturePhoto(with: settings, delegate: self)
                self.queue.asyncAfter(deadline: .now() + 12) { [weak self] in
                    guard let self, let pending = self.capture, pending.id == id else { return }
                    self.capture = nil
                    pending.continuation.resume(throwing: Failure.timedOut)
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let result = Result {
            if let error { throw error }
            guard let data = photo.fileDataRepresentation(),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                    kCGImageSourceCreateThumbnailWithTransform as String: true,
                    kCGImageSourceThumbnailMaxPixelSize as String: 1800
                  ] as CFDictionary) else {
                throw Failure.emptyPhoto
            }
            return image
        }
        queue.async {
            guard self.capture?.id == id else { return }
            self.capture?.result = result
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        let id = resolvedSettings.uniqueID
        queue.async {
            guard let pending = self.capture, pending.id == id else { return }
            self.capture = nil
            if let error {
                pending.continuation.resume(throwing: error)
            } else {
                pending.continuation.resume(with: pending.result ?? .failure(Failure.emptyPhoto))
            }
        }
    }
}

extension AVCaptureConnection {
    func setVideoMirroring(_ mirroring: Bool?) {
        guard let mirroring, isVideoMirroringSupported else { return }
        automaticallyAdjustsVideoMirroring = false
        if isVideoMirrored != mirroring {
            isVideoMirrored = mirroring
        }
    }
}
