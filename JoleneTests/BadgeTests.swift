import Testing
@testable import Jolene

struct BadgeTests {
    @Test(arguments: [nil, "", " ", "\n", "\t "] as [String?])
    func blankLabelsMeanNoBadge(_ label: String?) {
        #expect(Badge(label: label) == nil)
    }

    @Test(arguments: [("3", 3), ("12", 12), ("123", 123), (" 7 ", 7), ("1,204", 1204), ("1 204", 1204), ("١٢", 12)])
    func numbersAreCounts(_ label: String, _ expected: Int) {
        let badge = Badge(label: label)
        #expect(badge?.kind == .count(expected))
        #expect(badge?.count == expected)
    }

    @Test(arguments: ["•", "●", "··"])
    func bulletsAreDots(_ label: String) {
        let badge = Badge(label: label)
        #expect(badge?.kind == .dot)
        #expect(badge?.count == nil)
        #expect(badge?.displayText == "")
    }

    @Test func textKeepsItsLabelAndLeadingNumber() {
        let plus = Badge(label: "99+")
        #expect(plus?.kind == .text)
        #expect(plus?.count == 99)
        #expect(plus?.displayText == "99+")

        let word = Badge(label: "New")
        #expect(word?.kind == .text)
        #expect(word?.count == nil)
    }

    @Test(arguments: ["1.5", "3.0", "12,34", "24:59", "1,2345", ",123", "123,"])
    func onlyThreeDigitGroupsMakeACount(_ label: String) {
        let badge = Badge(label: label)
        #expect(badge?.kind == .text)
        #expect(badge?.count == nil)
    }

    @Test(arguments: [("1,204,567", "1M+"), ("1000000", "1M+"), ("123,456", "123k+"), ("1,000,000+", "1M+"), ("123456", "123456")])
    func longCountsAreAbbreviatedNotCut(_ label: String, _ shown: String) {
        #expect(Badge(label: label)?.displayText == shown)
    }

    @Test func timersDontAddToTheTotal() {
        let badges = ["24:59", "2"].compactMap { Badge(label: $0) }
        #expect(Badge.total(of: badges)?.label == "2")
    }

    @Test func longLabelsAreShortened() {
        let badge = Badge(label: "Offline now")
        #expect(badge?.displayText == "Offli…")
        #expect(badge?.label == "Offline now")
    }

    @Test func spokenDescriptions() {
        #expect(Badge(label: "3")?.spokenDescription == "3 new")
        #expect(Badge(label: "•")?.spokenDescription == "something new")
        #expect(Badge(label: "New")?.spokenDescription == "New")
    }

    @Test func totalsAddUp() {
        let badges = ["3", "12"].compactMap { Badge(label: $0) }
        #expect(Badge.total(of: badges)?.label == "15")
    }

    @Test func totalsWithPlusAreApproximate() {
        let badges = ["99+", "2"].compactMap { Badge(label: $0) }
        #expect(Badge.total(of: badges)?.label == "101+")
    }

    @Test func dotsAloneTotalToADot() {
        let badges = ["•", "New"].compactMap { Badge(label: $0) }
        #expect(Badge.total(of: badges)?.kind == .dot)
    }

    @Test func noBadgesTotalToNothing() {
        #expect(Badge.total(of: [Badge]()) == nil)
    }
}
