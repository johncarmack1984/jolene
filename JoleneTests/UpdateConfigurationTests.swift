import Foundation
import Testing

/// Every installed copy finds and checks its next version with these keys, and a release can't
/// fix them for copies already out there, so a build that loses one stops updating for good.
struct UpdateConfigurationTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func feedIsServedOverHTTPS() throws {
        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(URL(string: feed)?.scheme == "https")
    }

    @Test func updateKeyIsAnEd25519PublicKey() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
    }

    @Test func updatesInstallOnTheirOwn() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    }

    /// Sparkle compares build numbers to tell which release is newer, so the build number has
    /// to follow the version that release-please sets.
    @Test func buildNumberIsTheVersion() throws {
        let version = try #require(info["CFBundleShortVersionString"] as? String)
        #expect(info["CFBundleVersion"] as? String == version)
    }
}
