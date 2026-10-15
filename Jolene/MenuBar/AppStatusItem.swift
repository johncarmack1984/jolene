import AppKit

/// One app's menu bar item.
///
/// The item is created once and then shown or hidden with `isVisible`, never removed and added
/// back, and it keeps a stable autosave name. That keeps it where the person put it, including
/// in the section a menu bar manager such as Ice or Bartender shows or hides.
final class AppStatusItem: NSObject, NSMenuDelegate {
    let bundleID: String
    var onShowSettings: ((String?) -> Void)?

    private let statusItem: NSStatusItem
    private var app: MonitoredApp
    private var badge: Badge?
    private var isRunning = false
    private var renderedKey: RenderKey?
    private let appearanceWatcher = AppearanceWatcher()

    private struct RenderKey: Equatable {
        var artwork: StatusItemArtwork
        var appearance: NSAppearance.Name
        var label: String
    }

    init(app: MonitoredApp) {
        bundleID = app.bundleID
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "jolene.app.\(app.bundleID)"
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

    func update(app: MonitoredApp, isRunning: Bool, badge: Badge?) {
        self.app = app
        self.isRunning = isRunning
        self.badge = badge
        let shown = app.isShown(running: isRunning, badge: badge)
        if statusItem.isVisible != shown {
            statusItem.isVisible = shown
        }
        if shown { render() }
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let artwork = StatusItemArtwork(app: app, badge: badge)
        let key = RenderKey(artwork: artwork, appearance: button.effectiveAppearance.name, label: accessibilityText)
        guard key != renderedKey else { return }
        renderedKey = key
        button.image = StatusItemRenderer.image(for: artwork, appearance: button.effectiveAppearance)
        button.setAccessibilityLabel(accessibilityText)
        button.toolTip = accessibilityText
    }

    private var accessibilityText: String {
        if !isRunning { return "\(app.name), not open" }
        guard let badge else { return app.name }
        return "\(app.name), \(badge.spokenDescription)"
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else {
            AppActivator.toggle(bundleID: bundleID)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(item(isRunning ? "Show \(app.name)" : "Open \(app.name)", #selector(openApp)))
        if isRunning {
            menu.addItem(item("Hide \(app.name)", #selector(hideApp)))
        }
        menu.addItem(.separator())
        menu.addItem(item("\(app.name) Options…", #selector(showAppSettings)))
        menu.addItem(item("Jolene Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Jolene", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    private var statusLine: String {
        guard isRunning else { return "\(app.name) isn't open" }
        guard let badge else { return "\(app.name): nothing new" }
        return "\(app.name): \(badge.spokenDescription)"
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuDidClose(_ menu: NSMenu) {
        // Clear the menu so the next left click goes back to opening the app.
        statusItem.menu = nil
    }

    @objc private func openApp() {
        AppActivator.open(bundleID: bundleID)
    }

    @objc private func hideApp() {
        AppActivator.hide(bundleID: bundleID)
    }

    @objc private func showAppSettings() {
        onShowSettings?(bundleID)
    }

    @objc private func showSettings() {
        onShowSettings?(nil)
    }
}

/// A zero-size view inside a menu bar button that reports when the menu bar changes between
/// light and dark, which on recent macOS can follow the wallpaper rather than the system setting.
final class AppearanceWatcher: NSView {
    var onChange: (() -> Void)?

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onChange?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
