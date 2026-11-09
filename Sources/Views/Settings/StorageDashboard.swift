import SwiftUI

// MARK: - Model

/// Storage report shared across Settings and the category screens. Calculated off the main thread,
/// cached (shown instantly next time), refreshed on demand.
@MainActor
final class StorageModel: ObservableObject {
    static let shared = StorageModel()

    @Published private(set) var report: StorageReport?
    @Published private(set) var calculating = false
    private var generation = 0

    func refresh(signedApps: SignedAppsStore, library: LibraryStore, certificates: CertificateStore) {
        let signed = signedApps.apps.map {
            StorageEntry(category: .signed, key: $0.id.uuidString, name: $0.name, detail: "v\($0.version)",
                         date: $0.signedAt, urls: [signedApps.folder(for: $0.id)])
        }
        let imports = library.apps.map {
            StorageEntry(category: .imports, key: $0.id.uuidString, name: $0.name, detail: "v\($0.version)",
                         date: $0.dateAdded, urls: [library.folder(for: $0.id)])
        }
        var certs = certificates.certificates.map {
            StorageEntry(category: .certificates, key: $0.id.uuidString, name: $0.displayName, detail: $0.typeAndExpiry,
                         date: $0.record.dateAdded, urls: [certificates.folder(for: $0.id)])
        }
        let server = StorageService.documents.appendingPathComponent("Server", isDirectory: true)
        if FileManager.default.fileExists(atPath: server.path) {
            certs.append(StorageEntry(category: .certificates, key: "server", name: "Install server certificate",
                                      detail: "Used for local HTTPS installs", date: nil, urls: [server],
                                      deletable: false))
        }
        generation += 1
        let current = generation
        calculating = true
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) { () -> StorageReport in
                let capacity = StorageService.deviceCapacity()
                return StorageReport(
                    entries: [
                        .signed: StorageService.measure(signed),
                        .imports: StorageService.measure(imports),
                        .certificates: StorageService.measure(certs),
                        .logs: StorageService.measure(StorageService.logEntries()),
                        .cache: StorageService.measure(StorageService.cacheEntries())
                    ],
                    calculatedAt: Date(),
                    deviceAvailable: capacity.available,
                    deviceTotal: capacity.total
                )
            }.value
            guard let self, current == self.generation else { return }
            withAnimation(Motion.smooth) {
                self.report = result
                self.calculating = false
            }
        }
    }
}

// MARK: - Ring

/// Donut chart: one rounded segment per category with small gaps; segments sweep in on appear and
/// animate to new values. Tiny categories get a minimum visible sweep (the cards show real numbers).
struct StorageRing: View {
    let report: StorageReport?
    var lineWidth: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    private struct Segment: Identifiable {
        let category: StorageCategory
        let start: CGFloat
        let end: CGFloat
        var id: StorageCategory { category }
    }

    private func segments(capFraction: CGFloat) -> [Segment] {
        guard let report, report.total > 0 else { return [] }
        let present = StorageCategory.allCases.filter { report.bytes($0) > 0 }
        let gap = capFraction * 2 + 0.012
        let minimum = gap + 0.025
        var shares = present.map { max(CGFloat(report.share($0)), minimum) }
        let sum = shares.reduce(0, +)
        shares = shares.map { $0 / sum }
        var cursor: CGFloat = 0
        return zip(present, shares).map { category, share in
            defer { cursor += share }
            let inset = present.count > 1 ? gap / 2 : 0
            return Segment(category: category, start: cursor + inset, end: max(cursor + inset, cursor + share - inset))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - lineWidth / 2
            let capFraction = (lineWidth / 2) / max(1, 2 * .pi * radius)
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
                ForEach(segments(capFraction: capFraction)) { segment in
                    Circle()
                        .trim(from: segment.start * sweep, to: segment.end * sweep)
                        .stroke(segment.category.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(reduceMotion ? Motion.fade : Motion.smooth, value: report?.total)
        .onAppear {
            withAnimation(reduceMotion ? Motion.fade : .easeOut(duration: 0.45).delay(0.05)) { sweep = 1 }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Summary card

struct StorageSummaryCard: View {
    let report: StorageReport?
    let calculating: Bool
    let reclaimable: Int64
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            HStack(alignment: .center, spacing: Space.x4) {
                ZStack {
                    StorageRing(report: report)
                    VStack(spacing: Space.hair) {
                        Text(report.map { StorageService.format($0.total) } ?? "–")
                            .font(TypeScale.headline.monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .numericTransition()
                        Text("CertSigner\nstorage")
                            .font(.caption2)
                            .foregroundColor(SemanticColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Space.x4)
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: Space.x2) {
                    if let available = report?.deviceAvailable {
                        Text("\(StorageService.format(available)) free")
                            .font(TypeScale.headline)
                            .numericTransition()
                        if let total = report?.deviceTotal {
                            Text("of \(StorageService.format(total)) on this iPhone")
                                .font(TypeScale.caption)
                                .foregroundColor(SemanticColor.textSecondary)
                        }
                    }
                    if let share = appShareText {
                        Text(share)
                            .font(TypeScale.caption)
                            .foregroundColor(SemanticColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if report != nil {
                        Pill(text: reclaimable > 0 ? "Reclaim \(StorageService.format(reclaimable))" : "Nothing to reclaim",
                             systemImage: reclaimable > 0 ? "sparkles" : "checkmark",
                             kind: reclaimable > 0 ? .success : .neutral)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Space.x2) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(lastCalculatedText)
                        .font(TypeScale.caption)
                        .foregroundColor(SemanticColor.textSecondary)
                }
                Spacer()
                Button(action: onRefresh) {
                    Group {
                        if calculating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.footnote.weight(.semibold))
                        }
                    }
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
                .disabled(calculating)
                .accessibilityLabel("Recalculate storage")
            }
        }
        .padding(.vertical, Space.x1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(report.map { "CertSigner uses \(StorageService.format($0.total))" } ?? "Calculating storage")
    }

    private var appShareText: String? {
        guard let report, let total = report.deviceTotal, total > 0 else { return nil }
        let share = Double(report.total) / Double(total)
        let formatted = share < 0.001 ? "less than 0.1%" : share.formatted(.percent.precision(.fractionLength(1)))
        return "CertSigner uses \(formatted) of this iPhone"
    }

    private var lastCalculatedText: String {
        guard let date = report?.calculatedAt else { return "Calculating…" }
        if Date().timeIntervalSince(date) < 60 { return "Last calculated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last calculated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - Category card

struct StorageCategoryRow: View {
    let category: StorageCategory
    let report: StorageReport

    var body: some View {
        let bytes = report.bytes(category)
        let share = report.share(category)
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x3) {
                IconTile(systemImage: category.systemImage, color: category.color, size: 34)
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(category.title)
                        .font(TypeScale.body.weight(.semibold))
                        .foregroundColor(SemanticColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("\(category.countText(report.entries(category).count)) · \(share.formatted(.percent.precision(.fractionLength(0))))")
                        .font(TypeScale.caption)
                        .foregroundColor(SemanticColor.textSecondary)
                        .numericTransition()
                }
                Spacer(minLength: Space.x2)
                Text(StorageService.format(bytes))
                    .font(TypeScale.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(bytes > 0 ? SemanticColor.textPrimary : SemanticColor.textSecondary)
                    .numericTransition()
            }
            ProgressBar(progress: share, height: 4, color: category.color)
        }
        .padding(.vertical, Space.x1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.title), \(StorageService.format(bytes)), \(category.countText(report.entries(category).count))")
    }
}

// MARK: - Category detail

/// Every item in one storage area, sorted by size (or name / date), with swipe to delete (shared
/// delete animation) and Delete All. Deletions go through the same store calls as everywhere else.
struct StorageCategoryView: View {
    let category: StorageCategory

    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var model = StorageModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Sort: Hashable { case size, name, date }
    @State private var sort: Sort = .size
    @State private var deletePhases: [String: DeletePhase] = [:]
    @State private var confirmDeleteAll = false

    private var entries: [StorageEntry] {
        let list = model.report?.entries(category) ?? []
        switch sort {
        case .size: return list.sorted { $0.bytes > $1.bytes }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .date: return list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }

    private var deletableEntries: [StorageEntry] { entries.filter(\.deletable) }
    private var needsConfirmation: Bool { [.signed, .imports, .certificates].contains(category) }

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        HStack(spacing: Space.x3) {
                            IconTile(systemImage: category.systemImage, color: category.color, size: 44)
                            VStack(alignment: .leading, spacing: Space.hair) {
                                Text(StorageService.format(model.report?.bytes(category) ?? 0))
                                    .font(TypeScale.title.monospacedDigit())
                                    .numericTransition()
                                Text(category.countText(entries.count))
                                    .font(TypeScale.caption)
                                    .foregroundColor(SemanticColor.textSecondary)
                                    .numericTransition()
                            }
                        }
                        SlidingSegmentedControl(
                            selection: $sort,
                            options: [.init(value: Sort.size, title: "Size", systemImage: "arrow.down"),
                                      .init(value: Sort.name, title: "Name", systemImage: "textformat"),
                                      .init(value: Sort.date, title: "Date", systemImage: "calendar")],
                            accessibilityTitle: "Sort by"
                        )
                    }
                    .padding(.vertical, Space.x1)
                }

                Section {
                    if model.report == nil {
                        LoadingSkeleton(rows: 4)
                    } else if entries.isEmpty {
                        EmptyStateView(systemImage: category.systemImage, title: "Nothing here",
                                       message: "\(category.title) don't use any space right now.")
                            .emptyStateEntrance()
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(entries) { entry in
                            row(entry)
                                .deleteExit(deletePhases[entry.id])
                                .listRowBackground(RowSurface().deleteExit(deletePhases[entry.id]))
                                .swipeActions(edge: .trailing) {
                                    if entry.deletable {
                                        Button { animatedDelete(entry) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(Theme.danger)
                                    }
                                }
                        }
                    }
                } footer: {
                    if category == .cache {
                        Text("Temporary files and downloads. Clearing them is safe; they're recreated when needed.")
                    } else if category == .signed {
                        Text("Deleting a signed app shows Undo for 5 seconds.")
                    }
                }

                if !deletableEntries.isEmpty {
                    Section {
                        PrimaryButton(title: "Delete All · \(StorageService.format(deletableEntries.reduce(0) { $0 + $1.bytes }))",
                                      systemImage: "trash", style: .tinted) {
                            if needsConfirmation { confirmDeleteAll = true } else { deleteAll() }
                        }
                        .environment(\.themeAccent, Theme.danger)
                        .buttonRow()
                    }
                }
            }
            .softRowSeparators()
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground(intensity: 0.45))
        .animation(DeleteMotion.collapse, value: entries.map(\.id))
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { refresh() }
        .onAppear { refresh() }
        .confirmationDialog("Delete all \(category.title.lowercased())?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete \(category.countText(deletableEntries.count))", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(StorageService.format(deletableEntries.reduce(0) { $0 + $1.bytes })). It can't be undone.")
        }
    }

    private func row(_ entry: StorageEntry) -> some View {
        HStack(spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(entry.name)
                    .font(TypeScale.body)
                    .identifierText(minimumScale: 0.85)
                Text(subtitle(entry))
                    .font(TypeScale.caption)
                    .foregroundColor(SemanticColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.x2)
            Text(StorageService.format(entry.bytes))
                .font(TypeScale.subheadline.monospacedDigit())
                .foregroundColor(SemanticColor.textSecondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ entry: StorageEntry) -> String {
        [entry.detail, entry.date.map { $0.formatted(date: .abbreviated, time: .omitted) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func refresh() {
        model.refresh(signedApps: signedApps, library: library, certificates: certificates)
    }

    private func animatedDelete(_ entry: StorageEntry) {
        guard deletePhases[entry.id] == nil else { return }
        DeleteMotion.run(reduceMotion: reduceMotion, setPhase: { deletePhases[entry.id] = $0 }) {
            let freed = entry.bytes
            remove(entry)
            if entry.category != .signed && entry.category != .certificates && entry.category != .imports {
                toasts.show("Freed \(StorageService.format(freed))", kind: .success)
            }
            refresh()
        }
    }

    private func deleteAll() {
        let items = deletableEntries
        let freed = items.reduce(0) { $0 + $1.bytes }
        withAnimation(DeleteMotion.collapse) {
            for entry in items { remove(entry, quiet: true) }
        }
        Haptics.impact(.light)
        toasts.show("Freed \(StorageService.format(freed))", kind: .success)
        refresh()
    }

    /// The same removal each store already uses elsewhere in the app.
    private func remove(_ entry: StorageEntry, quiet: Bool = false) {
        switch entry.category {
        case .signed:
            guard let app = signedApps.apps.first(where: { $0.id.uuidString == entry.key }) else { return }
            if quiet {
                signedApps.delete(app)
            } else {
                LibraryView.deleteWithUndo(app, signedApps: signedApps, toasts: toasts)
            }
        case .imports:
            guard let app = library.apps.first(where: { $0.id.uuidString == entry.key }) else { return }
            library.delete(app)
            if !quiet { toasts.show("Deleted \(app.name)", kind: .success) }
        case .certificates:
            guard let id = UUID(uuidString: entry.key) else { return }
            let name = certificates.certificates.first { $0.id == id }?.displayName ?? entry.name
            certificates.delete(id)
            if !quiet { toasts.show("Deleted \(name)", kind: .success) }
        case .logs:
            if entry.urls.first?.standardizedFileURL == AppLog.fileURL.standardizedFileURL {
                AppLog.clear()
            } else {
                entry.urls.forEach { try? FileManager.default.removeItem(at: $0) }
            }
        case .cache:
            entry.urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}
