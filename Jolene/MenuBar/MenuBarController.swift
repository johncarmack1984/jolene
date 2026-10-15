import AppKit
import Observation

/// Keeps the menu bar in step with the apps, their settings and their badges.
final class MenuBarController {
    private let model: AppModel
    private let showSettings: (String?) -> Void
    private var appItems: [String: AppStatusItem] = [:]
    private var combinedItem: CombinedStatusItem?

    init(model: AppModel, showSettings: @escaping (String?) -> Void) {
        self.model = model
        self.showSettings = showSettings
        observe()
    }

    /// Renders, and renders again whenever anything it read changes.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func render() {
        let preferences = model.preferences
        let snapshot = model.snapshot
        let useCombined = preferences.layout == .combined || preferences.apps.isEmpty

        if useCombined {
            for item in appItems.values { item.remove() }
            appItems.removeAll()
            let combined = combinedItem ?? makeCombinedItem()
            combined.update(apps: preferences.apps, snapshot: snapshot)
            return
        }

        combinedItem?.remove()
        combinedItem = nil

        let wanted = Set(preferences.apps.map(\.bundleID))
        for (bundleID, item) in appItems where !wanted.contains(bundleID) {
            item.remove()
            appItems[bundleID] = nil
        }
        // New items appear to the left of existing ones, so creating them last to first puts
        // the first app leftmost, matching the order in settings.
        for app in preferences.apps.reversed() {
            let item = appItems[app.bundleID] ?? makeAppItem(for: app)
            item.update(app: app, isRunning: snapshot.running.contains(app.bundleID), badge: snapshot.badges[app.bundleID])
        }
    }

    private func makeAppItem(for app: MonitoredApp) -> AppStatusItem {
        let item = AppStatusItem(app: app)
        item.onShowSettings = showSettings
        appItems[app.bundleID] = item
        return item
    }

    private func makeCombinedItem() -> CombinedStatusItem {
        let item = CombinedStatusItem()
        item.onShowSettings = showSettings
        combinedItem = item
        return item
    }
}
