import AppKit
import os

/// Keeps track of which watched apps are running and what their badges say.
///
/// macOS tells only the Dock when a badge changes, so the monitor reads each watched app's
/// badge once a second, about 30 microseconds of work per app. While none of the watched apps
/// is open it only checks every ten seconds, in case it missed one opening. It stops completely
/// while the displays sleep or another user has the screen, and it reads right away when an
/// app opens or quits or the Mac wakes.
final class BadgeMonitor: NSObject {
    /// How often to look again while none of the watched apps is open.
    static let idleInterval: TimeInterval = 10

    struct Snapshot: Equatable {
        /// Watched apps that are open.
        var running: Set<String> = []
        /// Badges on watched apps that have one.
        var badges: [String: Badge] = [:]
    }

    private(set) var snapshot = Snapshot()
    var onChange: ((Snapshot) -> Void)?

    /// The bundle identifiers to watch.
    var watchedBundleIDs: Set<String> = [] {
        didSet {
            if watchedBundleIDs != oldValue { refresh() }
        }
    }

    var source: BadgeSource? { reader?.source }

    private let reader: (any BadgeReading)?
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var displaysAsleep = false
    private var sessionInactive = false
    private let logger = Logger(subsystem: "com.johncarmack.jolene", category: "badges")

    init(reader: (any BadgeReading)? = BadgeReaders.best()) {
        self.reader = reader
        super.init()
        if reader == nil {
            logger.fault("No way to read badges on this macOS")
        }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationsChanged(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationsChanged(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
    }

    /// Reads every watched app's badge now.
    func refresh() {
        defer { updateTimer() }
        guard !watchedBundleIDs.isEmpty else {
            publish(Snapshot())
            return
        }
        // The Dock runs for as long as someone is logged in. If LaunchServices can't find it,
        // it isn't answering right now, and this read would wrongly say every app has quit.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").isEmpty else {
            logger.notice("LaunchServices didn't answer; keeping the last badges")
            return
        }

        var next = Snapshot()
        for bundleID in watchedBundleIDs {
            let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { !$0.isTerminated }
            guard !instances.isEmpty else { continue }
            next.running.insert(bundleID)
            let badges = instances.compactMap { reader?.badgeLabel(for: $0) }.compactMap(Badge.init(label:))
            // Two copies of one app is rare; show whichever has more to say.
            if let badge = badges.max(by: { ($0.count ?? 0) < ($1.count ?? 0) }) {
                next.badges[bundleID] = badge
            }
        }
        publish(next)
    }

    private func publish(_ next: Snapshot) {
        guard next != snapshot else { return }
        logBadgeChanges(from: snapshot, to: next)
        snapshot = next
        onChange?(next)
    }

    private func updateTimer() {
        let interval: TimeInterval? = if let reader, !displaysAsleep, !sessionInactive, !watchedBundleIDs.isEmpty {
            snapshot.running.isEmpty ? Self.idleInterval : reader.source.interval
        } else {
            nil
        }
        guard interval != timerInterval else { return }
        timer?.invalidate()
        timer = nil
        timerInterval = interval
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        // Let macOS line this up with other wakeups.
        timer.tolerance = interval / 4
        // Common modes keep it firing while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func logBadgeChanges(from old: Snapshot, to new: Snapshot) {
        for bundleID in Set(old.badges.keys).union(new.badges.keys) where old.badges[bundleID] != new.badges[bundleID] {
            let label = new.badges[bundleID]?.label ?? "none"
            logger.debug("\(bundleID, privacy: .public) badge: \(label, privacy: .public)")
        }
    }

    @objc private func timerFired() {
        refresh()
    }

    @objc private func applicationsChanged(_ notification: Notification) {
        if notification.name == NSWorkspace.didTerminateApplicationNotification,
           let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            reader?.forget(pid: app.processIdentifier)
        }
        refresh()
    }

    @objc private func displaysDidSleep() {
        displaysAsleep = true
        updateTimer()
    }

    @objc private func displaysDidWake() {
        displaysAsleep = false
        refresh()
    }

    @objc private func sessionDidResign() {
        sessionInactive = true
        updateTimer()
    }

    @objc private func sessionDidBecomeActive() {
        sessionInactive = false
        refresh()
    }

    @objc private func systemDidWake() {
        refresh()
    }
}
