import AppKit

/// The single Jolene item: icons of the apps with something new and their total, with a menu
/// listing every watched app. It also stands in while no apps are set up, so settings stay
/// one click away.
final class CombinedStatusItem: NSObject, NSMenuDelegate {
    var onShowSettings: ((SidebarItem?) -> Void)?
    /// An "Update Jolene" item, when an update is waiting on the person.
    var updateMenuItem: (() -> NSMenuItem?)?

    private let statusItem: NSStatusItem
    private var apps: [MonitoredApp] = []
    private var snapshot = BadgeMonitor.Snapshot()
    private var renderedKey: RenderKey?
    private let appearanceWatcher = AppearanceWatcher()

    private struct RenderKey: Equatable {
        var artwork: CombinedArtwork
        var appearance: NSAppearance.Name
        var description: String
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "jolene.combined"
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            appearanceWatcher.onChange = { [weak self] in self?.render() }
            button.addSubview(appearanceWatcher)
        }
    }

    func update(apps: [MonitoredApp], snapshot: BadgeMonitor.Snapshot) {
        self.apps = apps
        self.snapshot = snapshot
        render()
    }

    /// Hidden in place while each app has its own item, so it keeps its position too.
    var isShown: Bool {
        get { statusItem.isVisible }
        set {
            if statusItem.isVisible != newValue {
                statusItem.isVisible = newValue
            }
        }
    }

    private var badgedApps: [MonitoredApp] {
        apps.filter { snapshot.badges[$0.bundleID] != nil }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let badged = badgedApps
        let artwork = CombinedArtwork(
            icons: badged.map { StatusItemArtwork(app: $0, badge: nil).icon },
            total: Badge.total(of: badged.compactMap { snapshot.badges[$0.bundleID] })
        )
        let description = badged.isEmpty
            ? "Jolene, nothing new"
            : "Jolene, " + badged.map { "\($0.name) \(snapshot.badges[$0.bundleID]?.spokenDescription ?? "")" }.joined(separator: ", ")
        // The description is part of the key: the icons and total can stay the same while the
        // counts behind them change.
        let key = RenderKey(artwork: artwork, appearance: button.effectiveAppearance.name, description: description)
        guard key != renderedKey else { return }
        renderedKey = key
        button.image = StatusItemRenderer.image(for: artwork, appearance: button.effectiveAppearance)
        button.setAccessibilityLabel(description)
        button.toolTip = description
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        if let update = updateMenuItem?() {
            menu.addItem(update)
            menu.addItem(.separator())
        }
        if apps.isEmpty {
            let empty = NSMenuItem(title: "No apps yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            menu.addItem(item("Add Apps…", #selector(addApps)))
        } else {
            for app in apps {
                menu.addItem(appItem(for: app))
            }
            menu.addItem(.separator())
            menu.addItem(item("Jolene Settings…", #selector(showSettings), key: ","))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jolene", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func appItem(for app: MonitoredApp) -> NSMenuItem {
        let item = item(app.name, #selector(openApp(_:)))
        item.representedObject = app.bundleID
        let icon = AppIcons.shared.icon(for: app.bundleID).copy() as? NSImage
        icon?.size = NSSize(width: 16, height: 16)
        item.image = icon
        // macOS 27 hides menu item images unless asked. Here the icons are how you find your app.
        // (The compiler check keeps older Xcode versions, without the macOS 27 SDK, building.)
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            item.preferredImageVisibility = .visible
        }
        #endif
        if let badge = snapshot.badges[app.bundleID] {
            item.badge = if case .count(let count) = badge.kind {
                NSMenuItemBadge(count: count)
            } else {
                NSMenuItemBadge(string: badge.kind == .dot ? "•" : badge.displayText)
            }
        } else if !snapshot.running.contains(app.bundleID) {
            item.toolTip = "\(app.name) isn't open"
        }
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        AppActivator.open(bundleID: bundleID)
    }

    @objc private func showSettings() {
        onShowSettings?(nil)
    }

    @objc private func addApps() {
        onShowSettings?(.addApps)
    }
}
