import Darwin
import Foundation

/// The LaunchServices calls that read an app's Dock badge.
///
/// macOS keeps each running app's Dock badge in its LaunchServices record, under the key
/// "StatusLabel", as a dictionary holding a "label" string. Reading it needs no permission and
/// takes about 30 microseconds. The functions are private, so they're looked up at runtime:
/// `shared` is nil on a macOS that no longer has them, and Jolene falls back to `lsappinfo`.
nonisolated final class LaunchServices: @unchecked Sendable {
    static let shared = LaunchServices()

    private typealias CreateASNWithPID = @convention(c) (CFAllocator?, pid_t) -> Unmanaged<CFTypeRef>?
    private typealias CopyInformationItem = @convention(c) (Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    /// kLSDefaultSessionID: the login session of the calling process.
    private static let defaultSession: Int32 = -2

    private let createASN: CreateASNWithPID
    private let copyInformationItem: CopyInformationItem
    private let statusLabelKey = "StatusLabel" as CFString

    private init?() {
        // RTLD_DEFAULT: search every image already loaded. AppKit loads LaunchServices.
        let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
        guard let create = dlsym(everyImage, "_LSASNCreateWithPid"),
              let copy = dlsym(everyImage, "_LSCopyApplicationInformationItem")
        else { return nil }
        createASN = unsafeBitCast(create, to: CreateASNWithPID.self)
        copyInformationItem = unsafeBitCast(copy, to: CopyInformationItem.self)
    }

    /// The handle LaunchServices uses for one running process. It stays valid until the process exits.
    func serialNumber(for pid: pid_t) -> CFTypeRef? {
        createASN(kCFAllocatorDefault, pid)?.takeRetainedValue()
    }

    /// The label an app has put on its Dock icon. Nil when it has none, including after it
    /// clears its badge, which LaunchServices records as a null label.
    func badgeLabel(for serialNumber: CFTypeRef) -> String? {
        guard let value = copyInformationItem(Self.defaultSession, serialNumber, statusLabelKey)?
            .takeRetainedValue()
        else { return nil }
        return (value as? NSDictionary)?["label"] as? String
    }
}
