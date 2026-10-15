import AppKit
import Observation

/// Keeps the menu bar in step with the apps, their settings and their badges.
///
/// Items are only ever hidden and shown, never removed and added back, except when an app
/// leaves Jolene altogether. That's what keeps them where the person put them, including
/// across switches between the two layouts.
final class MenuBarController {
    private let model: AppModel
    private let showSettings: (SidebarItem?) -> Void
    private var appItems: [String: AppStatusItem] = [:]
    private var combinedItem: CombinedStatusItem?

    init(model: AppModel, showSettings: @escaping (SidebarItem?) -> Void) {
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
        let useCombined = Self.usesCombinedItem(preferences, snapshot)

        let wanted = Set(preferences.apps.map(\.bundleID))
        for (bundleID, item) in appItems where !wanted.contains(bundleID) {
            item.remove()
            appItems[bundleID] = nil
        }
        // New items appear to the left of existing ones, so creating them last to first puts
        // the first app leftmost, matching the order in settings.
        for app in preferences.apps.reversed() {
            let item = appItems[app.bundleID] ?? makeAppItem(for: app)
            if useCombined {
                item.hide()
            } else {
                item.update(app: app, isRunning: snapshot.running.contains(app.bundleID), badge: snapshot.badges[app.bundleID])
            }
        }

        if useCombined {
            let combined = combinedItem ?? makeCombinedItem()
            combined.update(apps: preferences.apps, snapshot: snapshot)
            combined.isShown = true
        } else {
            combinedItem?.isShown = false
        }
    }

    /// Whether the single combined item shows instead of per-app items. Besides the combined
    /// layout itself, it stands in whenever no app has an item to show (no apps yet, or each is
    /// set to show only while open or badged and none is), so Jolene's menu, with Settings and
    /// Quit, never disappears from the menu bar.
    static func usesCombinedItem(_ preferences: Preferences, _ snapshot: BadgeMonitor.Snapshot) -> Bool {
        guard preferences.layout == .separate else { return true }
        return !preferences.apps.contains { app in
            app.isShown(running: snapshot.running.contains(app.bundleID), badge: snapshot.badges[app.bundleID])
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
