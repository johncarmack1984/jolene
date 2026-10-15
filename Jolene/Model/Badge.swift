import Foundation

/// What an app's Dock badge says right now, parsed from the label the app gave the Dock.
nonisolated struct Badge: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A plain number such as "3" or "1,204".
        case count(Int)
        /// A dot with no number, which Slack and others use for "something new".
        case dot
        /// Anything else the app wrote, such as "99+" or "New".
        case text
    }

    /// The label as the app set it, trimmed.
    let label: String
    let kind: Kind

    /// Returns nil for a missing or blank label, which is how apps clear their badge.
    init?(label raw: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        label = trimmed
        if trimmed.allSatisfy(Self.dotCharacters.contains) {
            kind = .dot
        } else if let number = Self.integer(from: Substring(trimmed)) {
            kind = .count(number)
        } else {
            kind = .text
        }
    }

    /// The number this badge stands for, when it has one. "99+" counts as 99; text such as
    /// "New" or a timer's "24:59" doesn't count at all.
    var count: Int? {
        switch kind {
        case .count(let number): number
        case .dot: nil
        case .text: label.hasSuffix("+") ? Self.integer(from: label.dropLast()) : nil
        }
    }

    /// The text to draw inside a badge. A dot has none; long counts are abbreviated rather
    /// than cut, so 1,204,567 reads "1M+", and other long labels are shortened.
    var displayText: String {
        if case .dot = kind { return "" }
        guard label.count > Self.maxDisplayLength else { return label }
        if let count { return Self.abbreviated(count) }
        return String(label.prefix(Self.maxDisplayLength - 1)) + "…"
    }

    static func abbreviated(_ count: Int) -> String {
        count >= 1_000_000 ? "\(count / 1_000_000)M+" : "\(count / 1_000)k+"
    }

    /// How the badge reads aloud and in tooltips: "3 new", "something new", "New".
    var spokenDescription: String {
        switch kind {
        case .count(let number): "\(number) new"
        case .dot: "something new"
        case .text: label
        }
    }

    static let maxDisplayLength = 6

    private static let dotCharacters: Set<Character> = ["•", "●", "·", "∙", "⋅", "◦", "⦁", "⚫", "⚬", "○", "◉"]
    private static let groupingSeparators: Set<Character> = [",", ".", " ", "\u{00A0}", "\u{202F}", "'", "’", "_"]

    /// Reads whole numbers in any script's digits, optionally grouped in threes: "1,204",
    /// "1 204" and "1.204" are counts, while "1.5" and "12,34" aren't.
    private static func integer(from text: Substring) -> Int? {
        var value = 0
        var digits = 0
        var digitsInGroup = 0
        var separators = 0
        for character in text {
            if let digit = decimalDigit(character) {
                digits += 1
                guard digits <= 15 else { return nil }
                value = value * 10 + digit
                digitsInGroup += 1
            } else if groupingSeparators.contains(character) {
                // The first group has one to three digits, every later group exactly three.
                let validGroup = separators == 0 ? (1...3).contains(digitsInGroup) : digitsInGroup == 3
                guard validGroup else { return nil }
                separators += 1
                digitsInGroup = 0
            } else {
                return nil
            }
        }
        guard digits > 0, separators == 0 || digitsInGroup == 3 else { return nil }
        return value
    }

    private static func decimalDigit(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.properties.numericType == .decimal
        else { return nil }
        return character.wholeNumberValue
    }
}

extension Badge {
    /// One badge that sums up several, for the single combined menu bar item.
    /// Numbers add up, "99+" makes the total read "N+", and dots alone stay a dot.
    static func total(of badges: some Sequence<Badge>) -> Badge? {
        var sum = 0
        var approximate = false
        var any = false
        for badge in badges {
            any = true
            guard let count = badge.count else { continue }
            sum += count
            if case .text = badge.kind { approximate = true }
        }
        guard any else { return nil }
        guard sum > 0 else { return Badge(label: "•") }
        return Badge(label: approximate ? "\(sum)+" : "\(sum)")
    }
}
