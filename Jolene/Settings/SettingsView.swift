import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var router = model.router
        NavigationSplitView {
            Sidebar(model: model, selection: $router.selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            detail(for: router.selection)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder
    private func detail(for selection: SidebarItem?) -> some View {
        if case .app(let bundleID)? = selection, let app = model.app(bundleID) {
            AppSettingsView(model: model, app: app)
                .id(bundleID)
        } else if selection == .addApps {
            // A page rather than a sheet: a sheet would stop Jolene from quitting while it's open.
            AppPickerView(model: model)
        } else {
            GeneralSettingsView(model: model)
        }
    }
}

private struct Sidebar: View {
    let model: AppModel
    @Binding var selection: SidebarItem?
    @FocusState private var listFocused: Bool

    var body: some View {
        List(selection: $selection) {
            Label("General", systemImage: "gearshape")
                .tag(SidebarItem.general)

            Section("Apps") {
                ForEach(model.preferences.apps) { app in
                    AppRow(app: app, status: model.status(of: app))
                        .tag(SidebarItem.app(app.bundleID))
                        .contextMenu {
                            Button("Open \(app.name)") { AppActivator.open(bundleID: app.bundleID) }
                            Divider()
                            Button("Remove from Jolene", role: .destructive) { remove(app.bundleID) }
                        }
                }
                .onMove { model.moveApps(fromOffsets: $0, toOffset: $1) }

                Label("Add Apps…", systemImage: "plus")
                    .foregroundStyle(.secondary)
                    .tag(SidebarItem.addApps)
            }
        }
        // Start with the keyboard in the list, so arrow keys move between pages and a stray
        // keypress can't edit a field on the page.
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onDeleteCommand {
            if case .app(let bundleID)? = selection { remove(bundleID) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 2) {
                Button {
                    model.router.addApps()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 22)
                }
                .help("Add apps")
                .accessibilityLabel("Add Apps")

                Button {
                    if case .app(let bundleID)? = selection { remove(bundleID) }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 22)
                }
                .help("Remove the selected app")
                .accessibilityLabel("Remove App")
                .disabled(selectedBundleID == nil)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var selectedBundleID: String? {
        if case .app(let bundleID)? = selection { bundleID } else { nil }
    }

    /// Removes an app and selects its neighbor, so the list stays easy to work through.
    private func remove(_ bundleID: String) {
        let apps = model.preferences.apps
        let index = apps.firstIndex { $0.bundleID == bundleID }
        model.removeApp(bundleID)
        let remaining = model.preferences.apps
        if let index, !remaining.isEmpty {
            selection = .app(remaining[min(index, remaining.count - 1)].bundleID)
        } else {
            selection = .general
        }
    }
}

private struct AppRow: View {
    let app: MonitoredApp
    let status: AppStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIcons.shared.icon(for: app.bundleID))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                Text(status.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if case .running(let badge?) = status {
                BadgeCapsule(badge: badge)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A Dock-style red badge for use in settings.
struct BadgeCapsule: View {
    let badge: Badge

    var body: some View {
        Group {
            if badge.kind == .dot {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
            } else {
                Text(badge.displayText)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(.red))
            }
        }
        .accessibilityLabel(badge.spokenDescription)
    }
}
