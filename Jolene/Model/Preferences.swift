import Foundation
import os

/// Everything Jolene remembers between launches.
nonisolated struct Preferences: Codable, Equatable, Sendable {
    enum Layout: String, Codable, CaseIterable, Sendable {
        /// One menu bar item per app, the way the Dock shows them.
        case separate
        /// One Jolene item that lists every app, for crowded menu bars and notched displays.
        case combined
    }

    var apps: [MonitoredApp] = []
    var layout: Layout = .separate
    /// Set once Doll's apps were imported or the offer was turned down, so it isn't made again.
    var dollImportHandled = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var seen = Set<String>()
        apps = container.lenientArray(MonitoredApp.self, forKey: .apps).filter { seen.insert($0.bundleID).inserted }
        layout = container.lenientValue(Layout.self, forKey: .layout) ?? .separate
        dollImportHandled = container.lenientValue(Bool.self, forKey: .dollImportHandled) ?? false
    }

    func app(_ bundleID: String) -> MonitoredApp? {
        apps.first { $0.bundleID == bundleID }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a list one entry at a time, so one bad entry can't take the rest with it.
    nonisolated func lenientArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var values: [T] = []
        while !list.isAtEnd {
            let index = list.currentIndex
            if let value = try? list.decode(type) {
                values.append(value)
            } else {
                // Step past the entry that didn't decode.
                _ = try? list.decode(DiscardedValue.self)
            }
            if list.currentIndex == index { break }
        }
        return values
    }
}

/// Decodes any JSON value without reading it, to skip past an entry.
private nonisolated struct DiscardedValue: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// Saves preferences as one JSON value in UserDefaults.
struct PreferencesStore {
    static let key = "preferences"

    let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.johncarmack.jolene", category: "preferences")

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> Preferences {
        guard let data = defaults.data(forKey: Self.key) else { return Preferences() }
        do {
            return try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            // Keep the unreadable copy rather than overwriting it on the next save.
            logger.error("Couldn't read preferences: \(error.localizedDescription, privacy: .public)")
            defaults.set(data, forKey: "\(Self.key).unreadable")
            return Preferences()
        }
    }

    func save(_ preferences: Preferences) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            defaults.set(try encoder.encode(preferences), forKey: Self.key)
        } catch {
            logger.error("Couldn't save preferences: \(error.localizedDescription, privacy: .public)")
        }
    }
}
