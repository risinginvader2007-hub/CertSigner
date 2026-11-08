import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(SettingsKeys.libraryLayout) private var layout: LibraryLayout = .grid
    @AppStorage(SettingsKeys.librarySort) private var sort: LibrarySort = .dateAdded
    @State private var search = ""
    @State private var pendingDelete: LibraryApp?
    @State private var showPicker = false
    @State private var showURLPrompt = false
    @State private var urlText = ""
    @Namespace private var zoom

    private var apps: [LibraryApp] { library.filtered(search: search, sort: sort) }
    private let gridColumns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let transfer = library.transfer {
                        TransferCard(state: transfer)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    content
                }
                .padding(.horizontal, Theme.padding)
                .padding(.vertical, 8)
                .animation(Theme.spring, value: library.transfer)
            }
            .background(Theme.background.ignoresSafeArea())
            .refreshable { await library.refresh() }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search apps or bundle IDs")
            .toolbar { toolbar }
            .navigationDestination(for: LibraryApp.self) { app in
                LibraryAppDetailView(app: app)
                    .zoomTransition(id: app.id, in: zoom)
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "app")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let app = pendingDelete {
                        withAnimation(Theme.spring) { library.delete(app) }
                        toasts.show("Deleted \(app.name)", kind: .success)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("The IPA will be removed from your library.")
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(
                    contentTypes: [.item],
                    onPick: { url in
                        showPicker = false
                        importPicked(url)
                    },
                    onCancel: { showPicker = false }
                )
                .ignoresSafeArea()
            }
            .alert("Download IPA", isPresented: $showURLPrompt) {
                TextField("https://example.com/app.ipa", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Download") { startDownload() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paste a direct HTTPS link to an .ipa file.")
            }
        }
    }

    private func importPicked(_ url: URL) {
        guard url.pathExtension.lowercased() == "ipa" else {
            try? FileManager.default.removeItem(at: url)
            toasts.show("\(url.lastPathComponent) isn't an .ipa file.", kind: .error)
            return
        }
        Task {
            do {
                // The picker hands us a temp copy (asCopy: true), so move it.
                let app = try await library.importIPA(from: url, originalName: url.lastPathComponent, moveSource: true)
                toasts.show("Added \(app.name)", kind: .success)
            } catch {
                toasts.show("Couldn't import: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func startDownload() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            toasts.show("That doesn't look like a valid link.", kind: .error)
            return
        }
        urlText = ""
        Task {
            do {
                let app = try await library.download(from: url)
                toasts.show("Downloaded \(app.name)", kind: .success)
            } catch {
                toasts.show("Download failed: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoading {
            placeholders
        } else if library.apps.isEmpty {
            EmptyStateView(
                systemImage: "square.stack.3d.up.slash",
                title: "No apps yet",
                message: "Import an IPA from Files, the share sheet, or a URL to get started.",
                actionTitle: "Import IPA",
                action: { showPicker = true }
            )
            .padding(.top, 60)
        } else if apps.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: "Nothing matches “\(search)”.")
                .padding(.top, 40)
        } else if layout == .grid {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(apps) { app in
                    link(for: app) { LibraryGridCell(app: app, icon: library.icons[app.id]) }
                }
            }
            .animation(Theme.spring, value: apps.map(\.id))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(apps) { app in
                    link(for: app) { LibraryListRow(app: app, icon: library.icons[app.id]) }
                }
            }
            .animation(Theme.spring, value: apps.map(\.id))
        }
    }

    private func link<Cell: View>(for app: LibraryApp, @ViewBuilder label: () -> Cell) -> some View {
        NavigationLink(value: app) {
            label()
                .zoomSource(id: app.id, in: zoom)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .contextMenu {
            Button {
                UIPasteboard.general.string = app.bundleID
                toasts.show("Bundle ID copied", kind: .success)
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                pendingDelete = app
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var placeholders: some View {
        if layout == .grid {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(width: 60, height: 60, cornerRadius: 14)
                        SkeletonBlock(width: 100, height: 14)
                        SkeletonBlock(width: 70, height: 10)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 14) {
                        SkeletonBlock(width: 52, height: 52, cornerRadius: 12)
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBlock(width: 140, height: 14)
                            SkeletonBlock(width: 90, height: 10)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .cardBackground()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Picker("Sort by", selection: $sort.animation(Theme.spring)) {
                    ForEach(LibrarySort.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                Divider()
                Button {
                    withAnimation(Theme.spring) { layout = layout == .grid ? .list : .grid }
                    Haptics.selection()
                } label: {
                    Label(layout == .grid ? "Show as List" : "Show as Grid",
                          systemImage: layout == .grid ? "list.bullet" : "square.grid.2x2")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Sort and layout")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showPicker = true } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                Button { showURLPrompt = true } label: {
                    Label("Download from URL", systemImage: "link")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
            .accessibilityLabel("Add app")
        }
    }
}

struct TransferCard: View {
    let state: TransferState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let progress = state.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                if let progress = state.progress {
                    ProgressBar(progress: progress)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LibraryGridCell: View {
    let app: LibraryApp
    var icon: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconView(image: icon, name: app.name, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                StatusBadge(text: "v\(app.version)", kind: .info)
                Spacer(minLength: 0)
                Text(app.size.byteString)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), version \(app.version), \(app.size.byteString)")
    }
}

struct LibraryListRow: View {
    let app: LibraryApp
    var icon: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(image: icon, name: app.name, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("v\(app.version) · \(app.size.byteString)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(12)
        .cardBackground()
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), version \(app.version), \(app.size.byteString)")
    }
}
