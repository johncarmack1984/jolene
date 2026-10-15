import Combine
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            if model.preferences.apps.isEmpty {
                Section {
                    WelcomeSection(model: model)
                }
            }

            if let doll = model.dollSettings {
                Section {
                    DollImportSection(model: model, doll: doll)
                }
            } else if model.dollIsRunning {
                Section {
                    DollStillOpenSection(model: model)
                }
            }

            Section("Menu Bar") {
                Picker("Layout", selection: layout) {
                    Text("One item for each app").tag(Preferences.Layout.separate)
                    Text("A single Jolene item").tag(Preferences.Layout.combined)
                }
                .pickerStyle(.radioGroup)
                Text(layoutExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                LoginItemToggle()
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.versionDescription)
                LabeledContent("Badges", value: model.badgeSource?.description ?? "Not available on this version of macOS")
                Text("Jolene reads the badge each app puts on its Dock icon, straight from macOS. It needs no special permissions, and it reads badges only while one of your apps is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var layout: Binding<Preferences.Layout> {
        Binding(get: { model.preferences.layout }, set: { model.setLayout($0) })
    }

    private var layoutExplanation: String {
        switch model.preferences.layout {
        case .separate:
            "Each app gets its own item. Hold Command and drag them to rearrange; Jolene keeps them where you put them."
                + (shownSummary.map { " \($0)" } ?? "")
        case .combined:
            "One item shows the apps with something new, and their total. Click it for the full list. Handy on a crowded menu bar or a notched display."
        }
    }

    /// Says what's in the menu bar now, since items that show only while their app is open or
    /// badged come and go.
    private var shownSummary: String? {
        let apps = model.preferences.apps
        guard !apps.isEmpty else { return nil }
        let shown = apps.filter { app in
            app.isShown(running: model.snapshot.running.contains(app.bundleID), badge: model.snapshot.badges[app.bundleID])
        }.count
        if shown == apps.count {
            return apps.count == 1 ? "It's in the menu bar now." : "All \(apps.count) are in the menu bar now."
        }
        if shown == 0 {
            return "None is showing right now, so a single Jolene item stands in until one is."
        }
        return "Right now \(shown) of \(apps.count) are showing; the others appear as each app's settings say."
    }
}

private struct WelcomeSection: View {
    let model: AppModel
    @State private var suggestions: [AppEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your badges, in the menu bar")
                .font(.title3.weight(.semibold))
            Text("Choose the apps you don't want to miss. Jolene puts each one's Dock badge in the menu bar, so you see what's new with the Dock hidden or a window in full screen.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Apps…") {
                model.router.addApps()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !suggestions.isEmpty {
                Divider()
                Text("Showing a badge right now")
                    .font(.headline)
                ForEach(suggestions) { entry in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(entry.name)
                        if let badge = entry.badge {
                            BadgeCapsule(badge: badge)
                        }
                        Spacer()
                        Button("Add") {
                            if let added = model.addApps([entry]).first {
                                model.router.selection = .app(added)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .task {
            suggestions = model.badgedAppsNotWatched()
        }
    }
}

private struct DollImportSection: View {
    let model: AppModel
    let doll: DollSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moving over from Doll?")
                .font(.headline)
            Text("Doll was watching \(names). Jolene can bring them over with the same settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Import from Doll") {
                    model.importFromDoll()
                }
                .buttonStyle(.borderedProminent)
                Button("No Thanks") {
                    model.dismissDollImport()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var names: String {
        ListFormatter.localizedString(byJoining: doll.bundleIDs.map(AppModel.displayName(for:)))
    }
}

private struct DollStillOpenSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Doll is still open. Quit it so you don't see two of everything. If Doll opens when you log in, you can turn that off in Login Items.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Quit Doll") {
                    model.quitDoll()
                }
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorText: String?

    var body: some View {
        Toggle("Open Jolene when you log in", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { setEnabled($0) }
        ))
        // Coming back from Login Items settings, show whatever was decided there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
        if status == .requiresApproval {
            LabeledContent {
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } label: {
                Text("macOS is waiting for your OK in Login Items.")
                    .foregroundStyle(.secondary)
            }
        }
        if let errorText {
            Text(errorText)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}

extension Bundle {
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
