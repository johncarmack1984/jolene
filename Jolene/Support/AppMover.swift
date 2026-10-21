import AppKit
import DiskArbitration

/// Moves Jolene into the Applications folder in the person's home folder, for when it's opened
/// straight from its disk image. Installing there needs no administrator password, and neither
/// do updates, which Sparkle can't install on a disk image at all.
enum AppMover {
    /// Whether Jolene is running from somewhere it can't stay: its disk image, or the read-only
    /// copy macOS runs an app from when it's opened where it was downloaded.
    static let isNeeded = isTemporary(Bundle.main.bundleURL)

    /// The disk image Jolene is running from, if it is, to eject once Jolene has moved.
    static let diskImage = diskImageVolume(holding: Bundle.main.bundleURL)

    /// Copies Jolene into ~/Applications, then quits so the copy can open in its place.
    static func moveToApplications() throws {
        let app = Bundle.main.bundleURL
        let applications = try FileManager.default.url(for: .applicationDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let destination = applications.appending(path: app.lastPathComponent)
        try install(app, at: destination)
        try openOnceQuit(destination, thenEject: diskImage)
        NSApp.terminate(nil)
    }

    static func isTemporary(_ app: URL) -> Bool {
        // The same two checks Sparkle makes before it refuses to update.
        app.path.contains("/AppTranslocation/")
            || (try? app.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    static func diskImageVolume(holding app: URL) -> URL? {
        guard let volume = try? app.resourceValues(forKeys: [.volumeURLKey]).volume,
              let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              description[kDADiskDescriptionDeviceModelKey as String] as? String == "Disk Image"
        else { return nil }
        return volume
    }

    /// Copies the app to `destination`, replacing whatever is there only once the copy is whole.
    static func install(_ app: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination.deletingLastPathComponent(), create: true)
        defer { try? fileManager.removeItem(at: staging) }
        let copy = staging.appending(path: destination.lastPathComponent)
        try fileManager.copyItem(at: app, to: copy)
        releaseFromQuarantine(copy)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: copy)
        } else {
            try fileManager.moveItem(at: copy, to: destination)
        }
    }

    /// A copy out of a downloaded disk image comes out quarantined, like the image. The person
    /// already chose to open this app, so release the copy, or macOS asks them all over again.
    private static func releaseFromQuarantine(_ app: URL) {
        let contents = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for item in [app] + contents {
            removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// A Jolene that opens while another is running hands over to it and quits, so the copy
    /// opens only once this one is gone. The disk image can't be ejected before then either.
    private static func openOnceQuit(_ app: URL, thenEject diskImage: URL?) throws {
        let script = """
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.1; done
            /usr/bin/open "$2"
            [ -z "$3" ] || /usr/bin/hdiutil detach -quiet "$3"
            """
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = ["-c", script, "sh", String(getpid()), app.path, diskImage?.path ?? ""]
        try shell.run()
    }
}
