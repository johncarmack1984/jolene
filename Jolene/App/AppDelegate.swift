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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app. Leave the menu bar and settings alone for them.
        guard !Self.isRunningTests else { return }

        NSApp.mainMenu = MainMenu.make()
        let model = AppModel(store: PreferencesStore(defaults: .standard), monitor: BadgeMonitor())
        let settingsWindow = SettingsWindowController(model: model)
        self.model = model
        self.settingsWindow = settingsWindow
        menuBar = MenuBarController(model: model) { [weak settingsWindow] bundleID in
            settingsWindow?.show(selecting: bundleID)
        }
        model.start()

        if model.preferences.apps.isEmpty {
            settingsWindow.show(selecting: nil)
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
        settingsWindow?.show(selecting: page == "general" ? nil : page)
        if UserDefaults.standard.bool(forKey: "JoleneAddApps") {
            model?.router.addApps()
        }
    }
    #endif

    /// Opening Jolene again, from Finder, Spotlight or the Dock, brings up settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show(selecting: nil)
        return false
    }

    @objc func showSettings(_ sender: Any?) {
        settingsWindow?.show(selecting: nil)
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
    }
}
