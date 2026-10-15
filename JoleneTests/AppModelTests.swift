import Foundation
import Testing
@testable import Jolene

struct AppModelTests {
    private func makeModel() throws -> (AppModel, UserDefaults, String) {
        let suite = "jolene.tests.model.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = AppModel(store: PreferencesStore(defaults: defaults), monitor: BadgeMonitor(reader: nil))
        return (model, defaults, suite)
    }

    private func entry(_ bundleID: String, _ name: String) -> AppEntry {
        AppEntry(bundleID: bundleID, name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    @Test func addingSkipsAppsAlreadyWatched() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(model.addApps([entry("com.apple.mail", "Mail"), entry("com.linear", "Linear")]) == ["com.apple.mail", "com.linear"])
        #expect(model.addApps([entry("com.apple.mail", "Mail"), entry("com.tinyspeck.slackmacgap", "Slack")]) == ["com.tinyspeck.slackmacgap"])
        #expect(model.preferences.apps.map(\.name) == ["Mail", "Linear", "Slack"])
        #expect(model.monitor.watchedBundleIDs == ["com.apple.mail", "com.linear", "com.tinyspeck.slackmacgap"])
    }

    @Test func changesAreSaved() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.addApps([entry("com.apple.mail", "Mail")])
        model.updateApp("com.apple.mail") { $0.badgeStyle = .number }
        model.setLayout(.combined)

        let saved = PreferencesStore(defaults: defaults).load()
        #expect(saved.apps.first?.badgeStyle == .number)
        #expect(saved.layout == .combined)
    }

    @Test(arguments: [
        (IndexSet([0]), 3, ["B", "C", "A"]),
        (IndexSet([2]), 0, ["C", "A", "B"]),
        (IndexSet([0, 1]), 3, ["C", "A", "B"]),
        (IndexSet([1]), 1, ["A", "B", "C"]),
    ])
    func moving(_ source: IndexSet, _ destination: Int, _ expected: [String]) throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.addApps([entry("a", "A"), entry("b", "B"), entry("c", "C")])
        model.moveApps(fromOffsets: source, toOffset: destination)
        #expect(model.preferences.apps.map(\.name) == expected)
    }

    @Test func removing() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.addApps([entry("a", "A"), entry("b", "B")])
        model.removeApp("a")
        #expect(model.preferences.apps.map(\.bundleID) == ["b"])
        #expect(model.monitor.watchedBundleIDs == ["b"])
    }
}
