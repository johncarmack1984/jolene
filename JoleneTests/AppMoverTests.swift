import Foundation
import Testing
@testable import Jolene

struct AppMoverTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "jolene.tests.mover.\(UUID().uuidString)")

    /// A stand-in for Jolene.app. Like Sparkle's framework it holds a symlink, which a copy has
    /// to keep as a symlink or the framework's signature breaks.
    private func makeApp(in subfolder: String, version: String) throws -> URL {
        let app = folder.appending(path: subfolder).appending(path: "Jolene.app")
        let versions = app.appending(path: "Contents/Frameworks/Sparkle.framework/Versions")
        try FileManager.default.createDirectory(at: versions.appending(path: "B"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: versions.appending(path: "Current").path, withDestinationPath: "B")
        try Data(version.utf8).write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    private func version(of app: URL) throws -> String {
        try String(contentsOf: app.appending(path: "Contents/Info.plist"), encoding: .utf8)
    }

    private func quarantine(_ item: URL) {
        let value = Array("0083;\(String(Int(Date.now.timeIntervalSince1970), radix: 16));Safari;".utf8)
        setxattr(item.path, "com.apple.quarantine", value, value.count, 0, XATTR_NOFOLLOW)
    }

    private func isQuarantined(_ item: URL) -> Bool {
        getxattr(item.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    @Test func copiesTheAppWithItsSymlinks() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try makeApp(in: "Downloads", version: "0.3.0")
        let destination = folder.appending(path: "Applications/Jolene.app")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try AppMover.install(app, at: destination)

        #expect(try version(of: destination) == "0.3.0")
        let current = destination.appending(path: "Contents/Frameworks/Sparkle.framework/Versions/Current")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: current.path) == "B")
    }

    @Test func replacesAnEarlierCopy() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try makeApp(in: "Applications", version: "0.2.0")
        let leftover = installed.appending(path: "Contents/Leftover")
        try Data().write(to: leftover)
        let app = try makeApp(in: "Downloads", version: "0.3.0")

        try AppMover.install(app, at: installed)

        #expect(try version(of: installed) == "0.3.0")
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }

    @Test func releasesTheCopyFromQuarantine() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try makeApp(in: "Downloads", version: "0.3.0")
        quarantine(app)
        quarantine(app.appending(path: "Contents/Info.plist"))
        try #require(isQuarantined(app))
        let destination = folder.appending(path: "Applications/Jolene.app")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try AppMover.install(app, at: destination)

        #expect(!isQuarantined(destination))
        #expect(!isQuarantined(destination.appending(path: "Contents/Info.plist")))
    }

    @Test func offersToMoveOnlyFromATemporaryPlace() {
        #expect(!AppMover.isNeeded)
        #expect(!AppMover.isTemporary(Bundle.main.bundleURL))
        #expect(AppMover.diskImageVolume(holding: Bundle.main.bundleURL) == nil)
        #expect(AppMover.isTemporary(URL(filePath: "/private/var/folders/xy/T/AppTranslocation/0F2A/d/Jolene.app")))
    }
}
