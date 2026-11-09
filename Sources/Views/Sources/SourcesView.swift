import SwiftUI

/// Sources tab: the repositories the user added and the apps they offer.
struct SourcesView: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                if store.repositories.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "shippingbox",
                            title: "No sources yet",
                            message: "Add a source URL (AltStore-style JSON) to browse its apps and sign & install them in one tap.",
                            actionTitle: "Add Source",
                            action: { showAdd = true }
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        NavigationLink {
                            AllSourceAppsView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("All Apps").font(.body.weight(.semibold))
                                    Text("\(store.allApps.count) from \(store.repositories.count) source\(store.repositories.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    Section("Sources") {
                        ForEach(store.repositories) { repo in
                            NavigationLink {
                                RepositoryView(repoID: repo.id)
                            } label: {
                                RepositoryRow(repo: repo, refreshing: store.refreshing.contains(repo.id)) {
                                    store.startRefresh(repo.id)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.remove(repo.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await store.refresh(repo.id) }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    Task { await store.refresh(repo.id) }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                Button {
                                    UIPasteboard.general.string = repo.url.absoluteString
                                } label: {
                                    Label("Copy Source URL", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    store.remove(repo.id)
                                } label: {
                                    Label("Remove Source", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { store.move(from: $0, to: $1) }
                    }
                }
                }
                .softRowSeparators()
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground(intensity: 0.55))
            .refreshable { await store.refreshAll() }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .glassIconButton()
                    }
                    .accessibilityLabel("Add Source")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAdd) {
                AddSourceSheet()
                    .sheetChrome()
            }
            // Starts store-owned refreshes; nothing here can cancel them.
            .onAppear { store.refreshIfStale() }
        }
    }
}

struct RepositoryRow: View {
    let repo: Repository
    var refreshing = false
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            RemoteIcon(url: repo.iconURL, name: repo.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(.body.weight(.semibold)).lineLimit(1)
                // Cached apps stay listed while refreshing; only real failures show a warning.
                Text(detail).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if let error = repo.lastError, !refreshing {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.warning)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if refreshing {
                ProgressView()
            } else if repo.lastError != nil, let onRetry {
                Button("Retry", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = ["\(repo.apps.count) app\(repo.apps.count == 1 ? "" : "s")"]
        if let updated = repo.lastUpdated {
            parts.append(Self.lastUpdatedText(updated))
        }
        return parts.joined(separator: " · ")
    }

    static func lastUpdatedText(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - Add source

struct AddSourceSheet: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var adding = false
    @State private var error: String?
    @State private var shakes = 0
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CardSection("Source URL", systemImage: "link") {
                        TextField("https://example.com/source.json", text: $text)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focused)
                            .onSubmit { add() }
                        SoftDivider()
                        Button {
                            if let pasted = UIPasteboard.general.string {
                                text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                Haptics.selection()
                            }
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .shake(shakes)

                    if let error {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "xmark.octagon.fill").foregroundColor(Theme.danger)
                            Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(Theme.padding)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .fill(Theme.danger.opacity(0.1))
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    PrimaryButton(title: adding ? "Checking source…" : "Add Source", systemImage: "plus", isLoading: adding) {
                        add()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

                    Text("Works with AltStore / SideStore / Feather-style sources and the older ESign and Scarlet layouts. Apps install through your own certificate, like any IPA you import.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: error)
            }
            .background(AmbientBackground())
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func add() {
        guard !adding else { return }
        focused = false
        adding = true
        error = nil
        Task {
            do {
                let repo = try await store.add(text)
                adding = false
                toasts.show("Added \(repo.name) · \(repo.apps.count) app\(repo.apps.count == 1 ? "" : "s")", kind: .success)
                dismiss()
            } catch {
                adding = false
                self.error = error.localizedDescription
                Haptics.error()
                withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            }
        }
    }
}

// MARK: - One source

struct RepositoryView: View {
    let repoID: UUID

    @EnvironmentObject private var store: RepositoryStore
    @State private var query = ""

    private var repo: Repository? { store.repository(repoID) }

    var body: some View {
        Group {
            if let repo {
                List {
                    Group {
                    if query.isEmpty {
                        Section {
                            header(repo)
                        }
                    }
                    Section(query.isEmpty ? "Apps" : "Results") {
                        let apps = filtered(repo.apps)
                        if apps.isEmpty {
                            Text("No apps match “\(query)”.").foregroundColor(.secondary)
                        }
                        ForEach(apps) { app in
                            SourceAppLink(repo: repo, app: app)
                        }
                    }
                    }
                    .softRowSeparators()
                }
                .scrollContentBackground(.hidden)
                .background(AuroraBackground(intensity: 0.45))
                .refreshable { await store.refresh(repoID) }
                .searchable(text: $query, prompt: "Search \(repo.name)")
                .navigationTitle(repo.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                EmptyStateView(systemImage: "shippingbox", title: "Source removed", message: "This source is no longer in your list.")
            }
        }
    }

    private func filtered(_ apps: [RepoApp]) -> [RepoApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
                || ($0.developer?.lowercased().contains(q) ?? false)
        }
    }

    private func header(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                RemoteIcon(url: repo.iconURL, name: repo.name, size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(repo.name).font(.title3.weight(.bold)).lineLimit(2)
                    Text(repo.url.host ?? repo.url.absoluteString)
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.refreshing.contains(repo.id) { ProgressView() }
            }
            if let subtitle = repo.subtitle {
                Text(subtitle).font(.subheadline).foregroundColor(.secondary).lineLimit(4)
            }
            if let error = repo.lastError, !store.refreshing.contains(repo.id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Last refresh failed: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { store.startRefresh(repo.id) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            if let updated = repo.lastUpdated {
                Text(RepositoryRow.lastUpdatedText(updated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                StatusBadge(text: "\(repo.apps.count) apps", systemImage: "square.grid.2x2", kind: .info)
                if let website = repo.website {
                    Link(destination: website) {
                        StatusBadge(text: "Website", systemImage: "safari", kind: .neutral)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - All apps

struct AllSourceAppsView: View {
    @EnvironmentObject private var store: RepositoryStore
    @State private var query = ""

    private var entries: [SourceEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.allApps.sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.app.name.lowercased().contains(q) || $0.app.bundleID.lowercased().contains(q)
                || $0.repo.name.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            Group {
            let items = entries
            if items.isEmpty {
                Text(query.isEmpty ? "Your sources have no apps." : "No apps match “\(query)”.")
                    .foregroundColor(.secondary)
            }
            ForEach(items) { entry in
                SourceAppLink(repo: entry.repo, app: entry.app, showsSource: true)
            }
            }
            .softRowSeparators()
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground(intensity: 0.45))
        .refreshable { await store.refreshAll() }
        .searchable(text: $query, prompt: "Search all sources")
        .navigationTitle("All Apps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Rows

/// A source app row that opens the detail page, with a GET button.
struct SourceAppLink: View {
    let repo: Repository
    let app: RepoApp
    var showsSource = false

    var body: some View {
        NavigationLink {
            SourceAppDetailView(repoID: repo.id, appID: app.id)
        } label: {
            SourceAppRow(repo: repo, app: app, showsSource: showsSource)
        }
    }
}

struct SourceAppRow: View {
    let repo: Repository
    let app: RepoApp
    var showsSource = false

    var body: some View {
        HStack(spacing: 12) {
            RemoteIcon(url: app.iconURL, name: app.name, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(secondLine).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Text(thirdLine).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            GetButton(repo: repo, app: app)
        }
        .padding(.vertical, 2)
    }

    private var secondLine: String {
        if showsSource { return repo.name }
        return app.subtitle ?? app.developer ?? app.bundleID
    }

    private var thirdLine: String {
        var parts = ["v\(app.latest.version)"]
        if let size = app.latest.size { parts.append(size.byteString) }
        if let category = app.category { parts.append(category) }
        return parts.joined(separator: " · ")
    }
}

/// App Store-style GET pill. Tap = download, sign with your defaults and show the install prompt.
/// Shows a progress ring (tap to cancel) while downloading.
struct GetButton: View {
    let repo: Repository
    let app: RepoApp

    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var certificates: CertificateStore
    @Environment(\.themeAccent) private var accent

    var body: some View {
        Group {
            if let download = store.download(repoID: repo.id, app: app) {
                Button {
                    if !download.importing { store.cancelDownload(repoID: repo.id, app: app) }
                } label: {
                    ZStack {
                        if download.importing || download.progress == nil {
                            ProgressView()
                        } else {
                            ProgressRing(progress: download.progress ?? 0, lineWidth: 3, showsPercentage: false)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accent)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .frame(width: 72)
                }
                .accessibilityLabel(download.importing ? "Importing" : "Cancel download")
            } else {
                Button {
                    SourceActions.get(app, from: repo, signAndInstall: true, store: store, importer: importer,
                                      library: library, toasts: toasts, certificates: certificates)
                } label: {
                    Text("GET")
                        .font(.subheadline.weight(.heavy))
                        .tracking(0.5)
                        .foregroundColor(accent)
                        .frame(width: 72, height: 32)
                        .background(Capsule().fill(accent.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 0.75))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Get \(app.name)")
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .animation(Theme.spring, value: store.download(repoID: repo.id, app: app)?.importing)
    }
}

enum SourceActions {
    /// Starts a download. Sign & Install needs a certificate; without one it falls back to review.
    @MainActor
    static func get(_ app: RepoApp, version: RepoVersion? = nil, from repo: Repository, signAndInstall: Bool,
                    store: RepositoryStore, importer: ImportCoordinator, library: LibraryStore,
                    toasts: ToastCenter, certificates: CertificateStore) {
        if signAndInstall && certificates.certificates.isEmpty {
            toasts.show("Add a certificate first.", kind: .warning)
            importer.showCertificateImport = true
            return
        }
        Haptics.impact(.medium)
        store.get(app, version: version, from: repo, signAndInstall: signAndInstall,
                  importer: importer, library: library, toasts: toasts)
    }
}

// MARK: - Remote images

/// Source icon cache: memory (NSCache, thread-safe) backed by Caches/SourceIcons on disk,
/// so icons show instantly on the next launch, before any network request.
final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SourceIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
        if let data = image.pngData() { try? data.write(to: fileURL(for: url), options: .atomic) }
    }

    /// Reads the on-disk copy (call off the main thread).
    func diskImage(for url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: url)), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    private func fileURL(for url: URL) -> URL {
        // Stable FNV-1a hash of the URL (String.hashValue changes every launch).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return folder.appendingPathComponent(String(hash, radix: 16) + ".png")
    }
}

/// App icon loaded from a URL, falling back to the gradient initial tile.
struct RemoteIcon: View {
    let url: URL?
    let name: String
    var size: CGFloat = 52

    @State private var image: UIImage?

    init(url: URL?, name: String, size: CGFloat = 52) {
        self.url = url
        self.name = name
        self.size = size
        _image = State(initialValue: url.flatMap { RemoteImageCache.shared.image(for: $0) })
    }

    var body: some View {
        AppIconView(image: image, name: name, size: size)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        if let cached = RemoteImageCache.shared.image(for: url) {
            image = cached
            return
        }
        if let onDisk = await Task.detached(priority: .userInitiated, operation: { RemoteImageCache.shared.diskImage(for: url) }).value {
            image = onDisk
            return
        }
        guard let result = try? await URLSession.shared.data(from: url),
              let decoded = UIImage(data: result.0) else { return }
        let small = LibraryStore.downsampled(decoded, to: 180)
        RemoteImageCache.shared.store(small, for: url)
        withAnimation(.easeInOut(duration: 0.2)) { image = small }
    }
}
