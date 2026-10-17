import AppKit

@main
enum JoleneMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private let updates = UpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app. Leave the menu bar and settings alone for them.
        guard !Self.isRunningTests else { return }
        guard !handedOverToRunningCopy() else { return }

        NSApp.mainMenu = MainMenu.make()
        let model = AppModel(store: PreferencesStore(defaults: .standard), monitor: BadgeMonitor())
        let settingsWindow = SettingsWindowController(model: model, updates: updates)
        self.model = model
        self.settingsWindow = settingsWindow
        // Read the badges first, so items that show only while their app is open don't flash.
        model.start()
        menuBar = MenuBarController(model: model, updates: updates) { [weak settingsWindow] page in
            settingsWindow?.show(page: page)
        }

        // An update installs by relaunching Jolene, so it waits while settings are open.
        updates.shouldDeferInstall = { [weak settingsWindow] in settingsWindow?.isOpen ?? false }
        settingsWindow.onClose = { [weak updates] in updates?.installPendingUpdate() }
        updates.start()

        // Settings opens by itself when there's nothing to watch yet, and while Jolene runs from
        // somewhere it can't stay, since its first page offers to move it.
        if model.preferences.apps.isEmpty || AppMover.isNeeded {
            settingsWindow.show()
        }
        #if DEBUG
        showSettingsIfAsked()
        #endif
    }

    #if DEBUG
    /// While developing, `open Jolene.app --args -JoleneShowSettings general` opens settings, a
    /// bundle identifier in place of "general" opens that app's page, and `-JoleneAddApps YES`
    /// goes on to the Add Apps page.
    private func showSettingsIfAsked() {
        guard let page = UserDefaults.standard.string(forKey: "JoleneShowSettings") else { return }
        settingsWindow?.show(page: page == "general" ? .general : .app(page))
        if UserDefaults.standard.bool(forKey: "JoleneAddApps") {
            settingsWindow?.show(page: .addApps)
        }
    }
    #endif

    /// Opening Jolene again, from Finder, Spotlight or the Dock, brings up settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }

    @objc func showSettings(_ sender: Any?) {
        settingsWindow?.show()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updates.checkForUpdates(sender)
    }

    /// Two copies of Jolene, say an installed one and a development build, would show every
    /// badge twice. The copy that started later opens the other's settings and quits.
    private func handedOverToRunningCopy() -> Bool {
        let current = NSRunningApplication.current
        guard let bundleID = Bundle.main.bundleIdentifier,
              let earlier = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { other in
                  other.processIdentifier != current.processIdentifier && !other.isTerminated
                      && Self.startedFirst(other.launchDate, other.processIdentifier, before: current.launchDate, current.processIdentifier)
              }),
              let url = earlier.bundleURL
        else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    /// Which of two copies keeps running: the one launched first, or with the lower process id
    /// when the launch times match or aren't known. Copies starting together, as two login items
    /// would, still agree on exactly one.
    nonisolated static func startedFirst(_ launch: Date?, _ pid: pid_t, before otherLaunch: Date?, _ otherPID: pid_t) -> Bool {
        if let launch, let otherLaunch, launch != otherLaunch {
            return launch < otherLaunch
        }
        return pid < otherPID
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
    }
}
