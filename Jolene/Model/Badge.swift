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
        } else if let number = Self.integer(from: trimmed) {
            kind = .count(number)
        } else {
            kind = .text
        }
    }

    /// The number this badge stands for, when it has one. "99+" counts as 99.
    var count: Int? {
        switch kind {
        case .count(let number): number
        case .dot: nil
        case .text: Self.leadingInteger(in: label)
        }
    }

    /// The text to draw inside a badge. A dot has none, and long labels are shortened.
    var displayText: String {
        switch kind {
        case .dot:
            ""
        case .count, .text:
            label.count > Self.maxDisplayLength
                ? String(label.prefix(Self.maxDisplayLength - 1)) + "…"
                : label
        }
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

    /// Reads labels made only of digits and grouping separators, such as "1,204" or "1 204",
    /// in any script's decimal digits.
    private static func integer(from text: String) -> Int? {
        var value = 0
        var digits = 0
        for character in text {
            if let digit = decimalDigit(character) {
                guard digits < 12 else { return nil }
                value = value * 10 + digit
                digits += 1
            } else if !(digits > 0 && groupingSeparators.contains(character)) {
                return nil
            }
        }
        return digits > 0 ? value : nil
    }

    private static func leadingInteger(in text: String) -> Int? {
        var value = 0
        var digits = 0
        for character in text {
            guard let digit = decimalDigit(character), digits < 12 else { break }
            value = value * 10 + digit
            digits += 1
        }
        return digits > 0 ? value : nil
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
