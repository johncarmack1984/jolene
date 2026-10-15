import Foundation

nonisolated enum AppNames {
    /// The app's name as the Dock shows it: in the person's language, and without ".app"
    /// even when Finder is set to show every filename extension.
    static func name(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
