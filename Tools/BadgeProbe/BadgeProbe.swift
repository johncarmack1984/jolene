import AppKit

// BadgeProbe is a development tool: a Dock app whose only job is to show a badge you choose,
// so Jolene can be tried against "3", "12", "123", "•" or "99+" without waiting for mail.
//
// It reads its badge from the file named by its first argument, five times a second.
// "nil" clears the badge, "quit" quits, and anything else becomes the label.

let controlPath = CommandLine.arguments.dropFirst().first ?? "/tmp/badgeprobe.txt"

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var lastLabel: String?? = .none
    private var timer: Timer?
    private let label = NSTextField(labelWithString: "No badge")
    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BadgeProbe"
        window.isReleasedWhenClosed = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 40, width: 280, height: 40)
        window.contentView?.addSubview(label)
        window.center()
        return window
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.orderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { self.readControlFile() }
        }
    }

    // Like most apps, show the window again when the Dock icon (or Jolene) reopens the app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    private func readControlFile() {
        guard let contents = try? String(contentsOfFile: controlPath, encoding: .utf8) else { return }
        let text = contents.trimmingCharacters(in: .newlines)
        if text == "quit" {
            NSApp.terminate(nil)
            return
        }
        let badge: String? = text == "nil" ? nil : text
        if case .some(let previous) = lastLabel, previous == badge { return }
        lastLabel = .some(badge)
        NSApp.dockTile.badgeLabel = badge
        label.stringValue = badge.map { "Badge: \($0)" } ?? "No badge"
    }
}

let application = NSApplication.shared
let delegate = ProbeDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
