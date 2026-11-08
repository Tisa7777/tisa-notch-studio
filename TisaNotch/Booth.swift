import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Booth: ObservableObject {
    @Published var layout = StampLayout.three
    @Published var delay = 3
    @Published private(set) var isCapturing = false
    @Published private(set) var photoNumber = 0
    @Published private(set) var countdown: Int?
    @Published private(set) var artwork: CGImage?
    @Published private(set) var message: String?
    @Published private(set) var isSaving = false

    let camera = Camera()
    private var sequence: Task<Void, Never>?
    private var artworkLayout = StampLayout.three

    func opened() {
        if artwork == nil {
            camera.start()
        }
    }

    func closed() {
        sequence?.cancel()
        camera.stop()
    }

    func startSequence() {
        guard camera.status == .ready, sequence == nil, artwork == nil else { return }
        let chosenLayout = layout
        let delay = self.delay
        message = nil
        isCapturing = true
        sequence = Task {
            defer {
                isCapturing = false
                photoNumber = 0
                countdown = nil
                sequence = nil
            }
            do {
                var photos: [CGImage] = []
                for index in 1...chosenLayout.rawValue {
                    try Task.checkCancellation()
                    photoNumber = index
                    for second in stride(from: delay, through: 1, by: -1) {
                        countdown = second
                        try await Task.sleep(for: .seconds(1))
                    }
                    countdown = nil
                    let photo = try await camera.takePhoto()
                    try Task.checkCancellation()
                    photos.append(photo)
                }
                let frames = photos
                let image = await Task.detached(priority: .userInitiated) {
                    PostageStamp.render(chosenLayout, photos: frames)
                }.value
                try Task.checkCancellation()
                guard let image else { throw PostageStamp.Failure.render }
                artworkLayout = chosenLayout
                artwork = image
                camera.stop()
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func cancelSequence() {
        sequence?.cancel()
    }

    func retake() {
        guard !isSaving else { return }
        artwork = nil
        message = nil
        camera.start()
    }

    func save(in window: NSWindow) {
        guard let artwork, !isSaving else { return }
        isSaving = true
        message = nil
        let picker = NSSavePanel()
        picker.title = "Save Khmer postage stamp"
        picker.allowedContentTypes = [.png]
        picker.canCreateDirectories = true
        picker.nameFieldStringValue = "Tisa Notch - Khmer \(artworkLayout.rawValue).png"
        picker.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isSaving = false }
                guard response == .OK, let url = picker.url else { return }

                do {
                    try await Task.detached(priority: .userInitiated) {
                        try PostageStamp.writePNG(artwork, to: url)
                    }.value
                    self.message = "Saved \(url.lastPathComponent)"
                } catch {
                    self.message = "Couldn’t save the stamp. \(error.localizedDescription)"
                }
            }
        }
    }
}

@MainActor
struct BoothView: View {
    @ObservedObject var booth: Booth
    @ObservedObject var camera: Camera
    var close: () -> Void
    var save: () -> Void

    private let mint = Color(red: 0.64, green: 0.86, blue: 0.73)
    private let forest = Color(red: 0.075, green: 0.15, blue: 0.13)
    private let cream = Color(red: 0.96, green: 0.91, blue: 0.80)

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if let artwork = booth.artwork {
                resultView(artwork)
            } else {
                captureView
            }
            if let message = booth.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(cream)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(forest, in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(mint.opacity(0.28)))
        .padding(5)
        .foregroundStyle(cream)
        .tint(mint)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(mint)
                .frame(width: 38, height: 38)
                .background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("TISA NOTCH")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(mint)
                Text("Khmer Photo Booth")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Photo Booth")
            .help("Close Photo Booth")
            .keyboardShortcut(.cancelAction)
            .disabled(booth.isSaving)
        }
    }

    private var captureView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.4))
                if camera.status == .ready {
                    CameraPreview(session: camera.session)
                    if booth.isCapturing {
                        captureOverlay
                    }
                } else {
                    cameraPlaceholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(minHeight: 125, maxHeight: .infinity)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STAMP LAYOUT").font(.caption2.weight(.semibold)).tracking(1.2)
                    Picker("Stamp layout", selection: $booth.layout) {
                        ForEach(StampLayout.allCases) { layout in
                            Text("\(layout.rawValue) photos").tag(layout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 155)
                    .disabled(booth.isCapturing)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TIMER").font(.caption2.weight(.semibold)).tracking(1.2)
                    Picker("Countdown", selection: $booth.delay) {
                        Text("3 sec").tag(3)
                        Text("5 sec").tag(5)
                        Text("8 sec").tag(8)
                    }
                    .labelsHidden()
                    .frame(width: 82)
                    .disabled(booth.isCapturing)
                }
                Spacer(minLength: 0)
                if booth.isCapturing {
                    Button("Cancel", action: booth.cancelSequence)
                        .controlSize(.large)
                } else {
                    Button {
                        booth.startSequence()
                    } label: {
                        Label("Start", systemImage: "camera")
                            .frame(minWidth: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(camera.status != .ready)
                }
            }
        }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 8) {
            switch camera.status {
            case .opening:
                ProgressView().controlSize(.small)
                Text("Opening camera…")
            case .denied:
                Image(systemName: "camera.fill").font(.title2)
                Text("Allow camera access in System Settings")
                    .font(.headline)
                Text("Privacy & Security → Camera → Tisa Notch")
                    .font(.caption)
                Button("Try again") { camera.start() }
            case .failed(let reason):
                Image(systemName: "camera.fill").font(.title2)
                Text(reason).multilineTextAlignment(.center)
                Button("Try again") { camera.start() }
            case .off, .ready:
                Text("Camera is off").font(.caption)
            }
        }
        .padding()
    }

    private var captureOverlay: some View {
        VStack {
            Text("PHOTO \(booth.photoNumber) OF \(booth.layout.rawValue)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.72), in: Capsule())
            Spacer()
            if let countdown = booth.countdown {
                Text("\(countdown)")
                    .font(.system(size: 57, weight: .bold, design: .monospaced))
                    .frame(width: 86, height: 86)
                    .background(.black.opacity(0.68), in: Circle())
                    .accessibilityLabel("\(countdown) seconds remaining")
            } else {
                ProgressView().padding(16).background(.black.opacity(0.68), in: Circle())
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(_ artwork: CGImage) -> some View {
        HStack(spacing: 20) {
            Image(artwork, scale: 1, label: Text("Preview of the finished Khmer postage stamp"))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 210, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text("READY TO EXPORT")
                    .font(.caption2.weight(.bold)).tracking(1.5)
                    .foregroundStyle(mint)
                Text("Your stamp is ready.")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                Text("Save the full-size PNG, or take another set.")
                    .font(.subheadline)
                    .foregroundStyle(cream.opacity(0.75))
                Button(action: save) {
                    Label("Save PNG…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Take another", action: booth.retake)
            }
            .disabled(booth.isSaving)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
            wantsLayer = true
        }

        required init?(coder: NSCoder) { return nil }

        override func makeBackingLayer() -> CALayer {
            previewLayer
        }
    }
}
