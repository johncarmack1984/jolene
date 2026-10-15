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
    private var refreshing = false
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.johncarmack.jolene", category: "badges")

    init(reader: (any BadgeReading)? = BadgeReaders.best()) {
        self.reader = reader
        super.init()
        if reader == nil {
            logger.fault("No way to read badges on this macOS")
        }
    }

    func start() {
        // Delivered on the main queue, so the handlers can safely touch the monitor.
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    if let pid { self?.reader?.forget(pid: pid) }
                    self?.refresh()
                }
            },
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displaysAsleep = true
                    self?.updateTimer()
                }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displaysAsleep = false
                    self?.refresh()
                }
            },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionInactive = true
                    self?.updateTimer()
                }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionInactive = false
                    self?.refresh()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
        refresh()
    }

    /// Reads every watched app's badge now.
    func refresh() {
        // A slow read can run the run loop, which can deliver a notification that asks for
        // another refresh. Skip it; this one is already reading.
        guard !refreshing else { return }
        refreshing = true
        defer {
            refreshing = false
            updateTimer()
        }
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
        // The timer holds the monitor weakly, so a monitor nobody keeps stops polling.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            MainActor.assumeIsolated { self.refresh() }
        }
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
}
