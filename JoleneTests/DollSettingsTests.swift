import Foundation
import Testing
@testable import Jolene

struct DollSettingsTests {
    /// Doll's preferences as written by Doll 0.0.9.2.
    private func dollDefaults(_ values: [String: Any]) throws -> (UserDefaults, String) {
        let suite = "jolene.tests.doll.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return (defaults, suite)
    }

    @Test func noDollMeansNothingToImport() throws {
        let (defaults, suite) = try dollDefaults([:])
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DollSettings(defaults: defaults) == nil)
        #expect(DollSettings(defaults: nil) == nil)
    }

    @Test func readsAppsInOrderWithoutDuplicates() throws {
        let (defaults, suite) = try dollDefaults([
            "SETTING_MONITORED_APP_IDS": "com.apple.MobileSMS,com.linear, com.apple.MobileSMS,,com.apple.mail",
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let doll = try #require(DollSettings(defaults: defaults))
        #expect(doll.bundleIDs == ["com.apple.MobileSMS", "com.linear", "com.apple.mail"])
    }

    @Test func carriesOverRedBadgesWhileRunning() throws {
        let (defaults, suite) = try dollDefaults([
            "SETTING_MONITORED_APP_IDS": "com.tinyspeck.slackmacgap,com.apple.mail",
            "SETTINGS_Hide_When_App_Not_Running": true,
            "SETTINGS_Hide_When_Nothing_Coming": false,
            "SETTINGS_Show_As_Red_Badge": true,
            "SETTINGS_Show_Only_App_Icon": false,
            "SETTINGS_Grayout_Icon_When_Nothing_Coming": false,
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let apps = try #require(DollSettings(defaults: defaults)).monitoredApps { $0 == "com.apple.mail" ? "Mail" : "Slack" }
        #expect(apps.map(\.name) == ["Slack", "Mail"])
        for app in apps {
            #expect(app.visibility == .whileRunning)
            #expect(app.badgeStyle == .badge)
            #expect(app.iconStyle == .color)
            #expect(app.dimWhenQuiet == false)
        }
    }

    @Test func hidingWhenQuietWins() throws {
        let (defaults, suite) = try dollDefaults([
            "SETTING_MONITORED_APP_IDS": "com.apple.mail",
            "SETTINGS_Hide_When_App_Not_Running": true,
            "SETTINGS_Hide_When_Nothing_Coming": true,
            "SETTINGS_Show_Only_App_Icon": true,
            "SETTINGS_Grayout_Icon_When_Nothing_Coming": true,
        ])
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = try #require(DollSettings(defaults: defaults)?.monitoredApps { _ in "Mail" }.first)
        #expect(app.visibility == .whenBadged)
        #expect(app.badgeStyle == .none)
        #expect(app.dimWhenQuiet)
    }

    @Test func plainNumbersWithoutRedBadges() throws {
        let (defaults, suite) = try dollDefaults(["SETTING_MONITORED_APP_IDS": "com.apple.mail"])
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = try #require(DollSettings(defaults: defaults)?.monitoredApps { _ in "Mail" }.first)
        #expect(app.visibility == .always)
        #expect(app.badgeStyle == .number)
    }
}
