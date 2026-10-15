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

    @Test func statusSummaries() {
        #expect(AppStatus.notInstalled.summary == "Not installed")
        #expect(AppStatus.notRunning.summary == "Not open")
        #expect(AppStatus.running(nil).summary == "Nothing new")
        #expect(AppStatus.running(Badge(label: "3")).summary == "3 new")
        #expect(AppStatus.running(Badge(label: "•")).summary == "Something new")
    }
}
