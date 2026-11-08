import AppKit
import SwiftUI

@main
enum TisaNotchApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
private final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let booth = Booth()
    private var item: NSStatusItem?
    private var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Tisa Notch")
            if button.image == nil { button.title = "T" }
            button.toolTip = "Tisa Notch"
        }

        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Photo Booth", action: #selector(toggleBooth), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Tisa Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first?.title = panel?.isVisible == true ? "Close Photo Booth" : "Open Photo Booth"
    }

    @objc private func toggleBooth() {
        if panel?.isVisible == true {
            closeBooth()
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        place(panel, on: screen)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        booth.opened()
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.title = "Tisa Notch Photo Booth"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let view = BoothView(booth: booth, camera: booth.camera, close: { [weak self] in
            self?.closeBooth()
        }, save: { [weak self, weak panel] in
            guard let panel else { return }
            self?.booth.save(in: panel)
        })
        panel.contentViewController = NSHostingController(rootView: view)
        return panel
    }

    private func place(_ panel: NotchPanel, on screen: NSScreen) {
        let area = screen.visibleFrame
        let top = min(area.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        let width = min(548, area.width - 16)
        let height = min(428, top - area.minY - 14)
        let originX = min(max(screen.frame.midX - width / 2, area.minX + 8), area.maxX - width - 8)
        panel.setFrame(NSRect(x: originX, y: top - height - 5, width: width, height: height), display: true)
    }

    private func closeBooth() {
        guard !booth.isSaving else { return }
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        booth.closed()
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
