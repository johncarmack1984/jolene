import Foundation
import Testing
@testable import Jolene

struct PreferencesTests {
    @Test func roundTrips() throws {
        var preferences = Preferences()
        preferences.layout = .combined
        preferences.dollImportHandled = true
        preferences.apps = [
            MonitoredApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", visibility: .whenBadged, badgeStyle: .dot, iconStyle: .symbol),
            MonitoredApp(bundleID: "com.apple.mail", name: "Mail", dimWhenQuiet: true),
        ]
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == preferences)
    }

    @Test func missingKeysTakeDefaults() throws {
        let json = #"{"apps": [{"bundleID": "com.apple.mail"}]}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.layout == .separate)
        #expect(preferences.dollImportHandled == false)
        let mail = try #require(preferences.apps.first)
        #expect(mail.name == "com.apple.mail")
        #expect(mail.visibility == .always)
        #expect(mail.badgeStyle == .badge)
        #expect(mail.iconStyle == .color)
        #expect(mail.symbolName == "envelope")
    }

    @Test func valuesFromANewerVersionFallBack() throws {
        let json = #"""
        {"layout": "radial", "apps": [
            {"bundleID": "com.apple.mail", "name": "Mail", "badgeStyle": "sparkle", "visibility": "whenBadged"},
            {"name": "No bundle identifier"},
            "not even an object",
            {"bundleID": "com.apple.mail", "name": "Duplicate"},
            {"bundleID": "com.linear", "name": "Linear"}
        ]}
        """#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.layout == .separate)
        #expect(preferences.apps.map(\.bundleID) == ["com.apple.mail", "com.linear"])
        #expect(preferences.apps[0].badgeStyle == .badge)
        #expect(preferences.apps[0].visibility == .whenBadged)
        #expect(preferences.apps[0].name == "Mail")
    }

    @Test func storeSavesAndLoads() throws {
        let suite = "jolene.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        #expect(store.load() == Preferences())

        var preferences = Preferences()
        preferences.apps = [MonitoredApp(bundleID: "com.apple.MobileSMS", name: "Messages")]
        store.save(preferences)
        #expect(store.load() == preferences)
    }

    @Test func unreadablePreferencesAreKeptAside() throws {
        let suite = "jolene.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: PreferencesStore.key)
        #expect(PreferencesStore(defaults: defaults).load() == Preferences())
        #expect(defaults.data(forKey: "\(PreferencesStore.key).unreadable") == Data("not json".utf8))
    }

    @Test(arguments: [
        (MonitoredApp.Visibility.always, false, false, true),
        (.always, true, true, true),
        (.whileRunning, false, false, false),
        (.whileRunning, true, false, true),
        (.whenBadged, true, false, false),
        (.whenBadged, true, true, true),
        (.whenBadged, false, true, false),
    ])
    func visibility(_ visibility: MonitoredApp.Visibility, _ running: Bool, _ badged: Bool, _ shown: Bool) {
        let app = MonitoredApp(bundleID: "com.example", name: "Example", visibility: visibility)
        #expect(app.isShown(running: running, badge: badged ? Badge(label: "1") : nil) == shown)
    }
}
