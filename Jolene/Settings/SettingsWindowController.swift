import AppKit
import SwiftUI

/// The settings window: an ordinary resizable window that remembers its size and position.
/// While it's open, Jolene appears in the Dock and the app switcher like any other app.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    /// Shows the window, on the given app's page if there is one.
    func show(selecting bundleID: String?) {
        if let bundleID {
            model.router.selection = .app(bundleID)
        }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // macOS doesn't let a menu bar app make itself active when it opens at launch, so put
        // the window on top anyway. Clicking it then makes Jolene active as usual.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // The window, not the content, decides the size, so it can be resized freely.
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]

        let window = NSWindow(contentViewController: hosting)
        window.title = "Jolene"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.setContentSize(NSSize(width: 820, height: 580))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        // Restores the saved frame, if there is one, over the centered default.
        window.setFrameAutosaveName("JoleneSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
