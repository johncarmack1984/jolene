import SwiftUI

/// One app's page: how its menu bar item looks, and when it shows.
struct AppSettingsView: View {
    let model: AppModel
    let app: MonitoredApp

    var body: some View {
        Form {
            Section {
                AppHeader(app: app, status: model.status(of: app))
            }

            Section("Preview") {
                MenuBarPreview(app: app)
            }

            Section("Show in the Menu Bar") {
                Picker("Show in the menu bar", selection: binding(\.visibility)) {
                    Text("Always").tag(MonitoredApp.Visibility.always)
                    Text("While \(app.name) is open").tag(MonitoredApp.Visibility.whileRunning)
                    Text("Only when \(app.name) has a badge").tag(MonitoredApp.Visibility.whenBadged)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("Badge") {
                Picker("Style", selection: binding(\.badgeStyle)) {
                    Text("Red badge").tag(MonitoredApp.BadgeStyle.badge)
                    Text("Number").tag(MonitoredApp.BadgeStyle.number)
                    Text("Red dot").tag(MonitoredApp.BadgeStyle.dot)
                    Text("None").tag(MonitoredApp.BadgeStyle.none)
                }
                Toggle("Dim the icon when there's nothing new", isOn: binding(\.dimWhenQuiet))
            }

            Section("Icon") {
                Picker("Icon", selection: binding(\.iconStyle)) {
                    Text("App icon").tag(MonitoredApp.IconStyle.color)
                    Text("App icon in gray").tag(MonitoredApp.IconStyle.monochrome)
                    Text("Symbol").tag(MonitoredApp.IconStyle.symbol)
                }
                if app.iconStyle == .symbol {
                    SymbolPicker(selection: binding(\.symbolName))
                }
            }

            Section {
                LabeledContent {
                    Button("Open Notification Settings") {
                        openNotificationSettings()
                    }
                } label: {
                    Text("Not seeing badges?")
                    Text("Jolene shows what \(app.name) puts on its Dock icon. If the Dock shows no badge either, turn on Badge application icon for \(app.name) in Notifications settings.")
                }
            }

            Section {
                Button("Remove \(app.name) from Jolene", role: .destructive) {
                    model.removeApp(app.bundleID)
                    model.router.selection = .general
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.name)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MonitoredApp, Value>) -> Binding<Value> {
        Binding(
            get: { model.app(app.bundleID)?[keyPath: keyPath] ?? app[keyPath: keyPath] },
            set: { value in model.updateApp(app.bundleID) { $0[keyPath: keyPath] = value } }
        )
    }

    private func openNotificationSettings() {
        let address = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(app.bundleID)"
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AppHeader: View {
    let app: MonitoredApp
    let status: AppStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppIcons.shared.icon(for: app.bundleID))
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Text(status.summary)
                        .foregroundStyle(.secondary)
                    if case .running(let badge?) = status {
                        BadgeCapsule(badge: badge)
                    }
                }
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            if status != .notInstalled {
                Button(status.isRunning ? "Show" : "Open") {
                    AppActivator.open(bundleID: app.bundleID)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The app's menu bar item as it will look, on a light and a dark menu bar.
struct MenuBarPreview: View {
    let app: MonitoredApp

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Text("Light").font(.caption).foregroundStyle(.secondary)
                Text("Dark").font(.caption).foregroundStyle(.secondary)
            }
            GridRow {
                Text("Nothing new")
                strip(badge: nil, dark: false)
                strip(badge: nil, dark: true)
            }
            GridRow {
                Text("Something new")
                strip(badge: Badge(label: "3"), dark: false)
                strip(badge: Badge(label: "3"), dark: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(app.name) in the menu bar")
    }

    private func strip(badge: Badge?, dark: Bool) -> some View {
        let artwork = StatusItemArtwork(app: app, badge: badge)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        let image = StatusItemRenderer.image(for: artwork, appearance: appearance)
        return Image(nsImage: image)
            .renderingMode(artwork.isTemplate ? .template : .original)
            .foregroundStyle(dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
            .frame(minWidth: 56, minHeight: 28)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(dark ? Color(white: 0.13) : Color(white: 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
    }
}

/// A grid of SF Symbols that suit the menu bar, plus a field for any other symbol name.
struct SymbolPicker: View {
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(SymbolSuggestions.all, id: \.self) { name in
                    Button {
                        selection = name
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 15))
                            .frame(width: 34, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selection == name ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(selection == name ? Color.accentColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(name)
                    .accessibilityLabel(name)
                }
            }
            HStack {
                TextField("Symbol name", text: $selection)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                if NSImage(systemSymbolName: selection, accessibilityDescription: nil) == nil {
                    Label("No symbol has that name", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
