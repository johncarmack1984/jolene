import AppKit
import os

/// Where badge labels come from.
enum BadgeSource: Sendable {
    /// LaunchServices, called directly. Fast enough to read every second.
    case launchServices
    /// The `lsappinfo` tool, for a macOS where the direct calls are gone. Slower, so read less often.
    case lsappinfo

    var description: String {
        switch self {
        case .launchServices: "Read directly from macOS"
        case .lsappinfo: "Read through lsappinfo (slower fallback)"
        }
    }

    /// How often to read while a watched app is running.
    var interval: TimeInterval {
        switch self {
        case .launchServices: 1
        case .lsappinfo: 3
        }
    }
}

protocol BadgeReading: AnyObject {
    var source: BadgeSource { get }
    /// The label on the app's Dock icon, or nil when there's no badge.
    func badgeLabel(for app: NSRunningApplication) -> String?
    /// Drops anything cached for a process that has exited.
    func forget(pid: pid_t)
}

/// Picks the best reader this macOS supports.
enum BadgeReaders {
    static func best() -> (any BadgeReading)? {
        LaunchServicesBadgeReader() ?? LsAppInfoBadgeReader()
    }
}

final class LaunchServicesBadgeReader: BadgeReading {
    let source = BadgeSource.launchServices
    private let launchServices: LaunchServices
    private var serialNumbers: [pid_t: CFTypeRef] = [:]

    init?(launchServices: LaunchServices? = .shared) {
        guard let launchServices else { return nil }
        self.launchServices = launchServices
    }

    func badgeLabel(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        guard let serialNumber = serialNumbers[pid] ?? launchServices.serialNumber(for: pid) else { return nil }
        serialNumbers[pid] = serialNumber
        return launchServices.badgeLabel(for: serialNumber)
    }

    func forget(pid: pid_t) {
        serialNumbers[pid] = nil
    }
}

/// Reads badges by running `lsappinfo info -only StatusLabel -long <pid>`, which prints
/// `"StatusLabel"={ "label"="3" }`.
final class LsAppInfoBadgeReader: BadgeReading {
    static let toolURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")

    let source = BadgeSource.lsappinfo
    private let logger = Logger(subsystem: "com.johncarmack.jolene", category: "lsappinfo")

    init?() {
        guard FileManager.default.isExecutableFile(atPath: Self.toolURL.path) else { return nil }
    }

    func badgeLabel(for app: NSRunningApplication) -> String? {
        let process = Process()
        process.executableURL = Self.toolURL
        process.arguments = ["info", "-only", "StatusLabel", "-long", String(app.processIdentifier)]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("lsappinfo didn't run: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // Reading to the end waits for lsappinfo to finish without running the run loop, which
        // waitUntilExit would, letting other work cut in.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return Self.parse(String(decoding: data, as: UTF8.self))
    }

    func forget(pid: pid_t) {}

    /// Pulls the label out of lsappinfo's output. A cleared badge prints no quoted label.
    nonisolated static func parse(_ output: String) -> String? {
        guard let line = output.split(whereSeparator: \.isNewline).first(where: { $0.contains("\"StatusLabel\"") }),
              let keyRange = line.range(of: "\"label\"=\"")
        else { return nil }
        var label = ""
        var escaping = false
        var unicodeDigits: String?
        for character in line[keyRange.upperBound...] {
            if var digits = unicodeDigits {
                digits.append(character)
                if digits.count == 4 {
                    if let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                        label.unicodeScalars.append(scalar)
                    }
                    unicodeDigits = nil
                } else {
                    unicodeDigits = digits
                }
            } else if escaping {
                escaping = false
                switch character {
                case "U", "u": unicodeDigits = ""
                case "n": label.append("\n")
                case "t": label.append("\t")
                default: label.append(character)
                }
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                return label
            } else {
                label.append(character)
            }
        }
        return nil
    }
}
