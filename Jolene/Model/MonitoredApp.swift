import Foundation

/// An app Jolene watches, and how its menu bar item should look.
nonisolated struct MonitoredApp: Codable, Hashable, Identifiable, Sendable {
    enum Visibility: String, Codable, CaseIterable, Sendable {
        /// Always in the menu bar, so the item doubles as a launcher.
        case always
        /// Only while the app is open.
        case whileRunning
        /// Only while the app shows a badge.
        case whenBadged
    }

    enum BadgeStyle: String, Codable, CaseIterable, Sendable {
        /// A red badge on the icon, like the Dock's.
        case badge
        /// The number beside the icon, in the menu bar's own text color.
        case number
        /// A red dot on the icon, without the number.
        case dot
        /// Just the icon. Pair it with dimming to still see when something's new.
        case none
    }

    enum IconStyle: String, Codable, CaseIterable, Sendable {
        /// The app's own icon.
        case color
        /// The app's icon in grayscale.
        case monochrome
        /// An SF Symbol drawn like the rest of the menu bar.
        case symbol
    }

    var bundleID: String
    /// The app's name when it was added, for when it's no longer installed.
    var name: String
    var visibility: Visibility
    var badgeStyle: BadgeStyle
    var iconStyle: IconStyle
    var symbolName: String
    var dimWhenQuiet: Bool

    var id: String { bundleID }

    init(
        bundleID: String,
        name: String,
        visibility: Visibility = .always,
        badgeStyle: BadgeStyle = .badge,
        iconStyle: IconStyle = .color,
        symbolName: String? = nil,
        dimWhenQuiet: Bool = false
    ) {
        self.bundleID = bundleID
        self.name = name
        self.visibility = visibility
        self.badgeStyle = badgeStyle
        self.iconStyle = iconStyle
        self.symbolName = symbolName ?? SymbolSuggestions.symbol(for: bundleID)
        self.dimWhenQuiet = dimWhenQuiet
    }

    /// Whether the item belongs in the menu bar right now.
    func isShown(running: Bool, badge: Badge?) -> Bool {
        switch visibility {
        case .always: true
        case .whileRunning: running
        case .whenBadged: running && badge != nil
        }
    }

    // Decoding tolerates missing keys and values written by newer versions,
    // so moving between versions never throws away someone's apps.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleID = try container.decode(String.self, forKey: .bundleID)
        self.init(
            bundleID: bundleID,
            name: container.lenientValue(String.self, forKey: .name) ?? bundleID,
            visibility: container.lenientValue(Visibility.self, forKey: .visibility) ?? .always,
            badgeStyle: container.lenientValue(BadgeStyle.self, forKey: .badgeStyle) ?? .badge,
            iconStyle: container.lenientValue(IconStyle.self, forKey: .iconStyle) ?? .color,
            symbolName: container.lenientValue(String.self, forKey: .symbolName),
            dimWhenQuiet: container.lenientValue(Bool.self, forKey: .dimWhenQuiet) ?? false
        )
    }
}

extension KeyedDecodingContainer {
    /// The value for a key, or nil when it's missing or doesn't decode.
    nonisolated func lenientValue<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
