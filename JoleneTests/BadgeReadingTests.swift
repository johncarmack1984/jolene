import AppKit
import Testing
@testable import Jolene

/// These run against the real macOS, so a release that changes how badges are stored
/// fails here before anyone notices missing badges.
@Suite(.serialized)
struct BadgeReadingTests {
    @Test func launchServicesIsAvailable() {
        #expect(LaunchServices.shared != nil)
        #expect(BadgeReaders.best()?.source == .launchServices)
    }

    @Test func readsTheBadgeThisAppSets() throws {
        let launchServices = try #require(LaunchServices.shared)
        let serialNumber = try #require(launchServices.serialNumber(for: ProcessInfo.processInfo.processIdentifier))
        defer { NSApp.dockTile.badgeLabel = nil }

        for label in ["7", "12", "123", "•", "99+"] {
            NSApp.dockTile.badgeLabel = label
            #expect(launchServices.badgeLabel(for: serialNumber) == label)
        }

        NSApp.dockTile.badgeLabel = nil
        #expect(launchServices.badgeLabel(for: serialNumber) == nil)
    }

    @Test func lsappinfoReadsTheSameBadge() throws {
        let reader = try #require(LsAppInfoBadgeReader())
        defer { NSApp.dockTile.badgeLabel = nil }
        NSApp.dockTile.badgeLabel = "42"
        #expect(reader.badgeLabel(for: NSRunningApplication.current) == "42")
    }

    @Test(arguments: [
        (#""StatusLabel"={ "label"="3" }"#, "3"),
        ("\"LSASN\"=ASN:0x0-0x12004ff3:\n\"StatusLabel\"={ \"label\"=\"42\" }\n", "42"),
        (#""StatusLabel"={ "label"="\U2022" }"#, "•"),
        (#""StatusLabel"={ "label"="a \"quoted\" label" }"#, #"a "quoted" label"#),
    ])
    func parsesLsappinfoOutput(_ output: String, _ expected: String) {
        #expect(LsAppInfoBadgeReader.parse(output) == expected)
    }

    @Test(arguments: ["", #""StatusLabel"={ "label"=[ NULL ] }"#, #""LSASN"=ASN:0x0-0x1:"#])
    func clearedOrMissingLabelsParseToNil(_ output: String) {
        #expect(LsAppInfoBadgeReader.parse(output) == nil)
    }

    @Test func monitorReportsRunningAppsAndBadges() throws {
        let ownID = try #require(Bundle.main.bundleIdentifier)
        defer { NSApp.dockTile.badgeLabel = nil }
        NSApp.dockTile.badgeLabel = "5"

        let monitor = BadgeMonitor()
        var reported: BadgeMonitor.Snapshot?
        monitor.onChange = { reported = $0 }
        monitor.watchedBundleIDs = [ownID, "com.example.not-installed"]

        #expect(reported?.running == [ownID])
        #expect(reported?.badges[ownID]?.label == "5")

        NSApp.dockTile.badgeLabel = nil
        monitor.refresh()
        #expect(reported?.badges.isEmpty == true)
    }
}
