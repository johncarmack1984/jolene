import Foundation

/// The settings Doll left behind, read from its preferences so people moving over keep their setup.
nonisolated struct DollSettings: Equatable, Sendable {
    static let bundleID = "com.xiaogd.Doll"

    var bundleIDs: [String]
    var hideWhenNotRunning: Bool
    var hideWhenNothingNew: Bool
    var showAsRedBadge: Bool
    var showOnlyAppIcon: Bool
    var dimWhenNothingNew: Bool

    /// Returns nil when Doll was never set up with any apps.
    init?(defaults: UserDefaults?) {
        guard let defaults, let list = defaults.string(forKey: "SETTING_MONITORED_APP_IDS") else { return nil }
        var seen = Set<String>()
        bundleIDs = list
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !bundleIDs.isEmpty else { return nil }
        hideWhenNotRunning = defaults.bool(forKey: "SETTINGS_Hide_When_App_Not_Running")
        hideWhenNothingNew = defaults.bool(forKey: "SETTINGS_Hide_When_Nothing_Coming")
        showAsRedBadge = defaults.bool(forKey: "SETTINGS_Show_As_Red_Badge")
        showOnlyAppIcon = defaults.bool(forKey: "SETTINGS_Show_Only_App_Icon")
        dimWhenNothingNew = defaults.bool(forKey: "SETTINGS_Grayout_Icon_When_Nothing_Coming")
    }

    /// Doll's settings on this Mac, if it was ever used here.
    static func onThisMac() -> DollSettings? {
        DollSettings(defaults: UserDefaults(suiteName: bundleID))
    }

    /// Doll's apps as Jolene apps, with Doll's display choices carried over.
    func monitoredApps(named name: (String) -> String) -> [MonitoredApp] {
        bundleIDs.map { bundleID in
            MonitoredApp(
                bundleID: bundleID,
                name: name(bundleID),
                visibility: hideWhenNothingNew ? .whenBadged : hideWhenNotRunning ? .whileRunning : .always,
                badgeStyle: showOnlyAppIcon ? .none : showAsRedBadge ? .badge : .number,
                dimWhenQuiet: dimWhenNothingNew
            )
        }
    }
}
