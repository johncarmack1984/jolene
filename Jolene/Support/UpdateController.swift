import AppKit
import Observation
import Sparkle

/// Keeps Jolene current with Sparkle. It checks for a new version once a day, downloads it in
/// the background and installs it by relaunching Jolene, whose items come back where they were.
/// Every release is signed twice, with the Developer ID and with the key in Info.plist, and
/// Sparkle checks both before installing.
@Observable
final class UpdateController: NSObject {
    /// A version a scheduled check found while Jolene wasn't in front, waiting for the person.
    /// Only happens when automatic installation is off.
    private(set) var availableVersion: String?

    /// Whether to hold an install back until later, because the settings window is open.
    @ObservationIgnored var shouldDeferInstall: () -> Bool = { false }
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var pendingInstall: (() -> Void)?

    var updater: SPUUpdater? { controller?.updater }

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    /// Installs an update that was held back while the settings window was open.
    func installPendingUpdate() {
        let install = pendingInstall
        pendingInstall = nil
        install?()
    }

    /// A menu item for an update waiting on the person, for the top of Jolene's menus.
    func availableUpdateMenuItem() -> NSMenuItem? {
        guard let availableVersion else { return nil }
        let item = NSMenuItem(title: "Update Jolene to \(availableVersion)…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        return item
    }
}

extension UpdateController: SPUUpdaterDelegate {
    /// Sparkle normally installs a downloaded update when the app quits, which for a menu bar
    /// app can be weeks away. Install right away instead, unless the settings window is open.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        if shouldDeferInstall() {
            pendingInstall = immediateInstallHandler
        } else {
            immediateInstallHandler()
        }
        return true
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    /// Scheduled checks don't put an alert in front of whatever the person is doing. A found
    /// update waits in Jolene's menus and settings instead.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
