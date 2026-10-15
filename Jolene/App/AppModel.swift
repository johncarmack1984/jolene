import AppKit
import Observation

/// Where a watched app stands right now.
enum AppStatus: Equatable {
    case notInstalled
    case notRunning
    case running(Badge?)

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    var summary: String {
        switch self {
        case .notInstalled: "Not installed"
        case .notRunning: "Not open"
        case .running(nil): "Nothing new"
        case .running(let badge?): badge.spokenDescription.capitalizedFirstLetter
        }
    }
}

/// Which page the settings window shows.
enum SidebarItem: Hashable {
    case general
    case addApps
    case app(String)
}

@Observable
final class SettingsRouter {
    var selection: SidebarItem? = .general
    /// Where to go back to if adding apps is canceled.
    @ObservationIgnored private var beforeAdding: SidebarItem?

    func addApps() {
        if selection != .addApps {
            beforeAdding = selection
        }
        selection = .addApps
    }

    func cancelAddingApps() {
        selection = beforeAdding ?? .general
    }
}

/// Jolene's state: the watched apps and their settings, and what their badges say.
@Observable
final class AppModel {
    private(set) var preferences: Preferences
    private(set) var snapshot = BadgeMonitor.Snapshot()
    /// Doll's settings, while there's an import to offer.
    private(set) var dollSettings: DollSettings?
    private(set) var dollIsRunning = false

    let router = SettingsRouter()
    let monitor: BadgeMonitor
    private let store: PreferencesStore
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    init(store: PreferencesStore, monitor: BadgeMonitor) {
        self.store = store
        self.monitor = monitor
        let preferences = store.load()
        self.preferences = preferences
        dollSettings = preferences.dollImportHandled ? nil : DollSettings.onThisMac()
        monitor.onChange = { [weak self] snapshot in self?.receive(snapshot) }
    }

    func start() {
        monitor.watchedBundleIDs = Set(preferences.apps.map(\.bundleID))
        monitor.start()
        refreshDollIsRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDollIsRunning() }
            })
        }
    }

    var badgeSource: BadgeSource? { monitor.source }

    func app(_ bundleID: String) -> MonitoredApp? {
        preferences.app(bundleID)
    }

    func badge(for bundleID: String) -> Badge? {
        snapshot.badges[bundleID]
    }

    func status(of app: MonitoredApp) -> AppStatus {
        if snapshot.running.contains(app.bundleID) {
            return .running(snapshot.badges[app.bundleID])
        }
        return AppActivator.isInstalled(app.bundleID) ? .notRunning : .notInstalled
    }

    // MARK: Changing the list

    /// Adds apps that aren't already watched and returns the bundle identifiers it added.
    @discardableResult
    func addApps(_ entries: [AppEntry]) -> [String] {
        var added: [String] = []
        commit { preferences in
            for entry in entries where preferences.app(entry.bundleID) == nil {
                preferences.apps.append(MonitoredApp(bundleID: entry.bundleID, name: entry.name))
                added.append(entry.bundleID)
            }
        }
        return added
    }

    func removeApp(_ bundleID: String) {
        commit { $0.apps.removeAll { $0.bundleID == bundleID } }
    }

    func moveApps(fromOffsets source: IndexSet, toOffset destination: Int) {
        commit { preferences in
            let moving = source.map { preferences.apps[$0] }
            let insertAt = destination - source.count { $0 < destination }
            for index in source.sorted(by: >) {
                preferences.apps.remove(at: index)
            }
            preferences.apps.insert(contentsOf: moving, at: insertAt)
        }
    }

    func updateApp(_ bundleID: String, _ change: (inout MonitoredApp) -> Void) {
        commit { preferences in
            guard let index = preferences.apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
            change(&preferences.apps[index])
        }
    }

    func setLayout(_ layout: Preferences.Layout) {
        commit { $0.layout = layout }
    }

    // MARK: Doll

    func importFromDoll() {
        guard let dollSettings else { return }
        let apps = dollSettings.monitoredApps(named: Self.displayName(for:))
        commit { preferences in
            for app in apps where preferences.app(app.bundleID) == nil {
                preferences.apps.append(app)
            }
            preferences.dollImportHandled = true
        }
        self.dollSettings = nil
    }

    func dismissDollImport() {
        commit { $0.dollImportHandled = true }
        dollSettings = nil
    }

    func quitDoll() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: DollSettings.bundleID) {
            app.terminate()
        }
    }

    private func refreshDollIsRunning() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: DollSettings.bundleID).isEmpty
        if running != dollIsRunning { dollIsRunning = running }
    }

    // MARK: Suggestions

    /// Open apps showing a badge right now that Jolene doesn't watch yet.
    func badgedAppsNotWatched() -> [AppEntry] {
        guard let reader = BadgeReaders.best() else { return [] }
        let watched = Set(preferences.apps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppEntry? in
                guard let bundleID = app.bundleIdentifier, !watched.contains(bundleID),
                      bundleID != Bundle.main.bundleIdentifier,
                      let label = reader.badgeLabel(for: app), let badge = Badge(label: label),
                      let url = app.bundleURL
                else { return nil }
                return AppEntry(bundleID: bundleID, name: app.localizedName ?? Self.displayName(for: bundleID), url: url, badge: badge)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The app's name as the Dock shows it, in the person's language.
    static func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return AppNames.name(of: url)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
    }

    // MARK: Internals

    private func receive(_ snapshot: BadgeMonitor.Snapshot) {
        // An app that just opened may have been updated; pick up its current icon.
        for bundleID in snapshot.running.subtracting(self.snapshot.running) {
            AppIcons.shared.forget(bundleID)
        }
        self.snapshot = snapshot
    }

    private func commit(_ change: (inout Preferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        preferences = next
        store.save(next)
        monitor.watchedBundleIDs = Set(next.apps.map(\.bundleID))
    }
}

extension String {
    var capitalizedFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
