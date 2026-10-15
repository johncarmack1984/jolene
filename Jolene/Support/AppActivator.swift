import AppKit
import os

/// Opens, shows and hides apps when their menu bar items are clicked.
enum AppActivator {
    nonisolated private static let logger = Logger(subsystem: "com.johncarmack.jolene", category: "activation")

    /// A click brings the app forward, or opens it. If it's already in front with a window
    /// showing, the click hides it instead, so the item works as a switch.
    static func toggle(bundleID: String) {
        if let app = runningApp(bundleID), app.isActive, !app.isHidden, hasWindowOnScreen(app) {
            app.hide()
        } else {
            open(bundleID: bundleID)
        }
    }

    /// Opens the app the way clicking its Dock icon does: it launches, or comes forward and
    /// reopens its main window if that was closed.
    static func open(bundleID: String) {
        guard let url = runningApp(bundleID)?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                logger.error("Couldn't open \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func hide(bundleID: String) {
        runningApp(bundleID)?.hide()
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// Whether the app has a normal window on screen in the current Space. Window owners and
    /// layers need no permission to read; only window titles do.
    private static func hasWindowOnScreen(_ app: NSRunningApplication) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return windows.contains { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
                && (window[kCGWindowLayer as String] as? Int) == 0
                && ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0
        }
    }
}
