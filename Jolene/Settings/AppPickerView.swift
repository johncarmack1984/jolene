import SwiftUI
import UniformTypeIdentifiers

/// An app that could be added to Jolene.
nonisolated struct AppEntry: Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var url: URL
    /// The badge it shows right now, if it's open and has one.
    var badge: Badge?

    var id: String { bundleID }
}

/// The apps on this Mac, grouped the way the picker shows them.
@Observable
final class AppCatalog {
    private(set) var badged: [AppEntry] = []
    private(set) var running: [AppEntry] = []
    private(set) var installed: [AppEntry] = []
    private(set) var isLoadingInstalled = true

    /// Each app appears once, in the first group it fits: showing a badge, open, or installed.
    func load(excluding watched: Set<String>) async {
        var seen = watched
        if let ownID = Bundle.main.bundleIdentifier {
            seen.insert(ownID)
        }

        // Through lsappinfo each read starts a process; one per open app would stall the window.
        let reader = BadgeReaders.best().flatMap { $0.source == .launchServices ? $0 : nil }
        var badged: [AppEntry] = []
        var running: [AppEntry] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, let url = app.bundleURL, seen.insert(bundleID).inserted else { continue }
            let badge = reader?.badgeLabel(for: app).flatMap(Badge.init(label:))
            let name = app.localizedName ?? AppNames.name(of: url)
            let entry = AppEntry(bundleID: bundleID, name: name, url: url, badge: badge)
            if badge != nil {
                badged.append(entry)
            } else {
                running.append(entry)
            }
        }
        self.badged = badged.sortedByName()
        self.running = running.sortedByName()

        let scanned = await Task.detached(priority: .userInitiated) { AppCatalog.installedApps() }.value
        installed = scanned.filter { seen.insert($0.bundleID).inserted }
        isLoadingInstalled = false
    }

    /// Apps in /Applications and its folders, the system's apps, and ~/Applications.
    nonisolated static func installedApps() -> [AppEntry] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var entries: [String: AppEntry] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "app",
                      let bundleID = Bundle(url: url)?.bundleIdentifier,
                      entries[bundleID] == nil
                else { continue }
                entries[bundleID] = AppEntry(bundleID: bundleID, name: AppNames.name(of: url), url: url)
            }
        }
        return Array(entries.values).sortedByName()
    }
}

extension Array where Element == AppEntry {
    nonisolated func sortedByName() -> [AppEntry] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// The Add Apps page: open apps first, those showing a badge right now at the top.
struct AppPickerView: View {
    let model: AppModel

    @State private var catalog = AppCatalog()
    @State private var query = ""
    @State private var selection = Set<String>()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)

            List(selection: $selection) {
                group("Showing a badge now", catalog.badged)
                group("Open", catalog.running)
                group("All Apps", catalog.installed)
                if catalog.isLoadingInstalled {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Finding apps…").foregroundStyle(.secondary)
                    }
                } else if nothingMatches {
                    Text("No apps match “\(query)”.")
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: String.self) { _ in
                EmptyView()
            } primaryAction: { bundleIDs in
                add(bundleIDs)
            }

            Divider()
            HStack {
                Button("Choose Another App…") {
                    chooseInFinder()
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.router.cancelAddingApps()
                }
                .keyboardShortcut(.cancelAction)
                Button(selection.count > 1 ? "Add \(selection.count) Apps" : "Add") {
                    add(selection)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(16)
        }
        .navigationTitle("Add Apps")
        .task {
            await catalog.load(excluding: Set(model.preferences.apps.map(\.bundleID)))
        }
        .onAppear {
            searchFocused = true
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [AppEntry]) -> some View {
        let matches = filtered(entries)
        if !matches.isEmpty {
            Section(title) {
                ForEach(matches) { entry in
                    PickerRow(entry: entry)
                        .tag(entry.bundleID)
                }
            }
        }
    }

    private func filtered(_ entries: [AppEntry]) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.bundleID.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var nothingMatches: Bool {
        !query.isEmpty && [catalog.badged, catalog.running, catalog.installed].allSatisfy { filtered($0).isEmpty }
    }

    private func add(_ bundleIDs: Set<String>) {
        let everything = catalog.badged + catalog.running + catalog.installed
        finish(adding: everything.filter { bundleIDs.contains($0.bundleID) })
    }

    private func finish(adding entries: [AppEntry]) {
        guard !entries.isEmpty else { return }
        if let first = model.addApps(entries).first {
            model.router.selection = .app(first)
        } else if let watched = entries.first(where: { model.app($0.bundleID) != nil }) {
            // Already watched: show its page rather than doing nothing.
            model.router.selection = .app(watched.bundleID)
        } else {
            // Only Jolene itself was picked, which it doesn't watch.
            NSSound.beep()
        }
    }

    /// For apps outside the usual folders.
    private func chooseInFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose apps for Jolene to watch."
        guard panel.runModal() == .OK else { return }
        let entries = panel.urls.compactMap { url -> AppEntry? in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
            return AppEntry(bundleID: bundleID, name: AppNames.name(of: url), url: url)
        }
        finish(adding: entries)
    }
}

private struct PickerRow: View {
    let entry: AppEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                if let folder {
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let badge = entry.badge {
                BadgeCapsule(badge: badge)
            }
        }
        .padding(.vertical, 2)
    }

    /// Where the app lives, unless it's in /Applications, to tell apart apps that share a name.
    private var folder: String? {
        let path = entry.url.deletingLastPathComponent().path(percentEncoded: false)
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed == "/Applications" ? nil : trimmed
    }
}
