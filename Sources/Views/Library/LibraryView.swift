import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(SettingsKeys.libraryLayout) private var layout: LibraryLayout = .grid
    @AppStorage(SettingsKeys.librarySort) private var sort: LibrarySort = .dateAdded
    @State private var search = ""
    @State private var pendingDelete: LibraryApp?
    @Namespace private var zoom

    private var apps: [LibraryApp] { library.filtered(search: search, sort: sort) }
    private let gridColumns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Theme.padding)
                    .padding(.vertical, 8)
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
                action: { toasts.show("IPA import arrives in Stage 3.", kind: .info) }
            )
            .padding(.top, 60)
        } else if apps.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: "Nothing matches “\(search)”.")
                .padding(.top, 40)
        } else if layout == .grid {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(apps) { app in
                    link(for: app) { LibraryGridCell(app: app) }
                }
            }
            .animation(Theme.spring, value: apps.map(\.id))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(apps) { app in
                    link(for: app) { LibraryListRow(app: app) }
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
                Button { toasts.show("Import from Files arrives in Stage 3.") } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                Button { toasts.show("URL download arrives in Stage 3.") } label: {
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

struct LibraryGridCell: View {
    let app: LibraryApp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconView(name: app.name, size: 60)
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

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(name: app.name, size: 52)
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
