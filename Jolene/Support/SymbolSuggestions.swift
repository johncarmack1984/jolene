import Foundation

/// SF Symbols that suit the menu bar, and a sensible pick for well-known apps.
nonisolated enum SymbolSuggestions {
    static let all: [String] = [
        "app.badge", "envelope", "tray", "paperplane", "bubble.left", "bubble.left.and.bubble.right",
        "message", "phone", "video", "bell", "megaphone", "at", "number", "person.2", "briefcase",
        "calendar", "checklist", "doc.text", "folder", "flag", "star", "cart", "gamecontroller", "music.note",
    ]

    static func symbol(for bundleID: String) -> String {
        switch bundleID.lowercased() {
        case "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac", "com.readdle.sparkdesktop",
             "com.superhuman.electron", "com.mimestream.mimestream":
            "envelope"
        case "com.apple.mobilesms":
            "message"
        case "com.tinyspeck.slackmacgap":
            "number"
        case "com.microsoft.teams", "com.microsoft.teams2":
            "person.2"
        case "com.hnc.discord", "com.facebook.archon":
            "bubble.left.and.bubble.right"
        case "net.whatsapp.whatsapp", "com.apple.facetime":
            "phone"
        case "ru.keepcoder.telegram", "org.telegram.desktop":
            "paperplane"
        case "org.whispersystems.signal-desktop":
            "bubble.left"
        case "com.apple.ical":
            "calendar"
        case "com.linear":
            "checklist"
        case "notion.id":
            "doc.text"
        default:
            "app.badge"
        }
    }
}
