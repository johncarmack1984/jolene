import AppKit
import Testing
@testable import Jolene

struct SettingsTests {
    @Test func cancelingAddAppsGoesBack() {
        let router = SettingsRouter()
        router.selection = .app("com.apple.mail")
        router.addApps()
        #expect(router.selection == .addApps)
        router.addApps()
        router.cancelAddingApps()
        #expect(router.selection == .app("com.apple.mail"))
    }

    /// Clicking the sidebar's Add Apps row sets the selection directly, without addApps().
    @Test func cancelingAfterPickingTheAddAppsRowGoesBack() {
        let router = SettingsRouter()
        router.selection = .app("com.tinyspeck.slackmacgap")
        router.selection = .addApps
        router.cancelAddingApps()
        #expect(router.selection == .app("com.tinyspeck.slackmacgap"))
    }

    @Test func removedAppsAreForgotten() {
        let router = SettingsRouter()
        router.selection = .app("com.apple.mail")
        router.addApps()
        router.forget("com.apple.mail")
        router.cancelAddingApps()
        #expect(router.selection == .general)

        router.selection = .app("com.linear")
        router.forget("com.linear")
        #expect(router.selection == .general)
    }

    @Test func cancelingWithNowhereToGoBackShowsGeneral() {
        let router = SettingsRouter()
        router.selection = nil
        router.addApps()
        router.cancelAddingApps()
        #expect(router.selection == .general)
    }

    @Test func appNamesNeverEndInDotApp() {
        #expect(AppNames.name(of: URL(fileURLWithPath: "/System/Applications/Mail.app")) == "Mail")
        #expect(AppNames.name(of: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")) == "Finder")
    }

    /// The "Open Notification Settings" button relies on System Settings handling this address.
    @Test func notificationSettingsLinkOpensSystemSettings() throws {
        let url = try #require(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.apple.mail"))
        let handler = try #require(NSWorkspace.shared.urlForApplication(toOpen: url))
        #expect(Bundle(url: handler)?.bundleIdentifier == "com.apple.systempreferences")
    }

    /// Exactly one of two copies keeps running, even when both start at once.
    @Test func onlyOneCopyStays() {
        let now = Date()
        let later = now.addingTimeInterval(0.5)
        #expect(AppDelegate.startedFirst(now, 900, before: later, 100))
        #expect(!AppDelegate.startedFirst(later, 100, before: now, 900))
        #expect(AppDelegate.startedFirst(now, 100, before: now, 900))
        #expect(!AppDelegate.startedFirst(now, 900, before: now, 100))
        #expect(AppDelegate.startedFirst(nil, 100, before: now, 900))
        #expect(!AppDelegate.startedFirst(nil, 900, before: nil, 100))
    }

    /// Jolene keeps something in the menu bar even when every app hides itself.
    @Test func combinedItemStandsInWhenNothingShows() {
        var preferences = Preferences()
        let empty = BadgeMonitor.Snapshot()
        #expect(MenuBarController.usesCombinedItem(preferences, empty))

        preferences.apps = [
            MonitoredApp(bundleID: "com.apple.mail", name: "Mail", visibility: .whileRunning),
            MonitoredApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", visibility: .whenBadged),
        ]
        #expect(MenuBarController.usesCombinedItem(preferences, empty))

        let mailOpen = BadgeMonitor.Snapshot(running: ["com.apple.mail"], badges: [:])
        #expect(!MenuBarController.usesCombinedItem(preferences, mailOpen))

        let slackOpenButQuiet = BadgeMonitor.Snapshot(running: ["com.tinyspeck.slackmacgap"], badges: [:])
        #expect(MenuBarController.usesCombinedItem(preferences, slackOpenButQuiet))

        preferences.layout = .combined
        #expect(MenuBarController.usesCombinedItem(preferences, mailOpen))
    }

    @Test func statusSummaries() {
        #expect(AppStatus.notInstalled.summary == "Not installed")
        #expect(AppStatus.notRunning.summary == "Not open")
        #expect(AppStatus.running(nil).summary == "Nothing new")
        #expect(AppStatus.running(Badge(label: "3")).summary == "3 new")
        #expect(AppStatus.running(Badge(label: "•")).summary == "Something new")
    }
}
