import SwiftUI

enum SignedSort: String, CaseIterable, Identifiable {
    case date, name, expiry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "Date Signed"
        case .name: return "Name"
        case .expiry: return "Expiry"
        }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all, valid, expiring, expired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Statuses"
        case .valid: return "Valid"
        case .expiring: return "Expiring Soon"
        case .expired: return "Expired"
        }
    }

    func matches(_ status: CertificateStatus) -> Bool {
        switch (self, status) {
        case (.all, _): return true
        case (.valid, .valid): return true
        case (.expiring, .expiringSoon): return true
        case (.expired, .expired): return true
        default: return false
        }
    }
}

private struct LogTarget: Identifiable { let id: UUID }

struct LibraryView: View {
    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var queue: SigningQueue
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var importer: ImportCoordinator
    @Environment(\.themeAccent) private var accent

    @AppStorage("library.signedSort") private var sort: SignedSort = .date
    @State private var statusFilter: StatusFilter = .all
    @State private var certificateFilter: UUID?
    @State private var search = ""
    @State private var path: [UUID] = []
    @State private var installTarget: SignedApp?
    @State private var logTarget: LogTarget?
    @State private var pendingDelete: SignedApp?
    @Namespace private var zoom

    private var visibleApps: [SignedApp] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = signedApps.apps.filter { app in
            if router.attentionOnly && !app.needsAttention() { return false }
            if !statusFilter.matches(app.status()) { return false }
            if let certificateFilter, app.certificateID != certificateFilter { return false }
            if !query.isEmpty && !app.name.lowercased().contains(query) && !app.bundleID.lowercased().contains(query) { return false }
            return true
        }
        switch sort {
        case .date: return filtered.sorted { $0.signedAt > $1.signedAt }
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .expiry: return filtered.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        }
    }

    private var isFiltering: Bool {
        router.attentionOnly || statusFilter != .all || certificateFilter != nil || !search.isEmpty
    }

    private struct CertificateChoice: Identifiable {
        let id: UUID
        let name: String
    }

    /// Certificates that appear on signed apps (they may have been deleted since).
    private var certificateChoices: [CertificateChoice] {
        var seen: [UUID: String] = [:]
        for app in signedApps.apps where seen[app.certificateID] == nil {
            seen[app.certificateID] = app.certificateName
        }
        return seen.map { CertificateChoice(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        let apps = visibleApps
        NavigationStack(path: $path) {
            List {
                if queue.tasks.isEmpty && signedApps.apps.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "square.stack.3d.up",
                            title: "Your library is empty",
                            message: "Import an IPA from Home. While it signs it shows up here, then lands in Signed Apps.",
                            actionTitle: "Go to Home",
                            action: { withAnimation(Theme.spring) { router.tab = .home } }
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if !queue.tasks.isEmpty { signingSection }
                    signedSection(apps)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .animation(Theme.spring, value: queue.tasks.map(\.id))
            .animation(Theme.spring, value: apps.map(\.id))
            .librarySearchable(text: $search)
            .refreshable { await reload() }
            .navigationTitle("Library")
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in
                SignedAppDetailView(appID: id)
                    .zoomTransition(id: id, in: zoom)
            }
            .sheet(item: $installTarget) { app in
                InstallSheet(app: app).roundedDesign()
            }
            .sheet(item: $logTarget) { target in
                SigningLogSheet(taskID: target.id).roundedDesign()
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "app")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let app = pendingDelete { delete(app) }
                    pendingDelete = nil
                }
            } message: {
                Text("Removes the signed IPA from CertSigner. Installed copies on your iPhone aren't affected.")
            }
        }
    }

    private func reload() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        signedApps.load()
    }

    private func delete(_ app: SignedApp) {
        withAnimation(Theme.spring) { signedApps.delete(app) }
        Haptics.success()
        toasts.show("Deleted \(app.name)", kind: .success)
    }

    // MARK: Signing

    private var signingSection: some View {
        Section {
            ForEach(queue.tasks) { task in
                SigningTaskRow(task: task, job: queue.jobs[task.id], icon: icon(for: task))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if queue.jobs[task.id] != nil { logTarget = LogTarget(id: task.id) }
                    }
                    .swipeActions(edge: .trailing) {
                        if task.status != .running {
                            Button(role: .destructive) {
                                queue.remove(task.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        } header: {
            Text("Signing")
        }
    }

    private func icon(for task: SigningTask) -> UIImage? {
        switch task.source {
        case .library(let id): return library.icons[id]
        case .signed(let id): return signedApps.icons[id]
        }
    }

    // MARK: Signed

    private func signedSection(_ apps: [SignedApp]) -> some View {
        Section {
            if router.attentionOnly {
                Button {
                    withAnimation(Theme.spring) { router.attentionOnly = false }
                } label: {
                    Label("Showing items that need attention. Tap to show all.", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.warning)
                }
            }
            if apps.isEmpty {
                if signedApps.apps.isEmpty {
                    Text("Nothing signed yet. Finished jobs appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title2).foregroundColor(.secondary)
                        Text("No signed apps match your filters.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Clear Filters") { clearFilters() }
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                ForEach(apps) { app in
                    SignedAppListRow(
                        app: app,
                        icon: signedApps.icons[app.id],
                        fileURL: signedApps.ipaURL(for: app),
                        onOpen: { path.append(app.id) },
                        onInstall: { installTarget = app },
                        onResign: { resign(app) }
                    )
                    .zoomSource(id: app.id, in: zoom)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = app
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            resign(app)
                        } label: {
                            Label("Re-sign", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.indigo)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        } header: {
            HStack {
                Text("Signed Apps")
                Spacer()
                if !signedApps.apps.isEmpty {
                    Text("\(apps.count)")
                        .monospacedDigit()
                }
            }
        }
    }

    private func resign(_ app: SignedApp) {
        guard let active = certificates.active else {
            toasts.show("Add a certificate first.", kind: .warning)
            importer.showCertificateImport = true
            return
        }
        queue.enqueueResign(app, certificateID: active.id)
        Haptics.impact(.medium)
        toasts.show("Re-signing \(app.name) with \(active.nickname)", kind: .info)
    }

    private func clearFilters() {
        withAnimation(Theme.spring) {
            router.attentionOnly = false
            statusFilter = .all
            certificateFilter = nil
            search = ""
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sort.animation(Theme.spring)) {
                    ForEach(SignedSort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Status", selection: $statusFilter.animation(Theme.spring)) {
                    ForEach(StatusFilter.allCases) { Text($0.title).tag($0) }
                }
                if !certificateChoices.isEmpty {
                    Picker("Certificate", selection: $certificateFilter.animation(Theme.spring)) {
                        Text("All Certificates").tag(UUID?.none)
                        ForEach(certificateChoices) { choice in
                            Text(choice.name).tag(Optional(choice.id))
                        }
                    }
                }
                if isFiltering {
                    Divider()
                    Button(role: .destructive) { clearFilters() } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.body.weight(.semibold))
                    .foregroundColor(isFiltering ? .white : accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isFiltering ? accent : Color.clear))
                    .glassIconButton()
            }
            .accessibilityLabel("Sort and filter")
        }
    }
}

// MARK: - Rows

struct SigningTaskRow: View {
    let task: SigningTask
    let job: SigningJob?
    let icon: UIImage?

    var body: some View {
        if let job {
            LiveSigningRow(task: task, job: job, icon: icon)
        } else {
            StaticSigningRow(task: task, icon: icon)
        }
    }
}

private struct LiveSigningRow: View {
    let task: SigningTask
    @ObservedObject var job: SigningJob
    let icon: UIImage?

    var body: some View {
        SigningRowContent(task: task, icon: icon, step: job.step, progress: job.progress, failed: task.status == .failed)
    }
}

private struct StaticSigningRow: View {
    let task: SigningTask
    let icon: UIImage?

    var body: some View {
        SigningRowContent(task: task, icon: icon, step: nil, progress: 0, failed: task.status == .failed)
    }
}

private struct SigningRowContent: View {
    let task: SigningTask
    let icon: UIImage?
    let step: SigningStep?
    let progress: Double
    let failed: Bool

    @EnvironmentObject private var queue: SigningQueue
    @Environment(\.themeAccent) private var accent

    private var statusText: String {
        if failed { return task.errorMessage ?? "Failed" }
        switch task.status {
        case .queued: return "Waiting…"
        case .running: return step.map { "\($0.title)…" } ?? "Starting…"
        case .failed: return task.errorMessage ?? "Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppIconView(image: icon, name: task.name, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(failed ? Theme.danger : .secondary)
                        .lineLimit(failed ? 3 : 1)
                }
                Spacer(minLength: 8)
                if failed {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.title2)
                        .foregroundColor(Theme.danger)
                        .transition(.scale)
                } else if task.status == .running {
                    ProgressRing(progress: progress, lineWidth: 5, showsPercentage: false)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Text("\(Int(progress * 100))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        )
                } else {
                    Image(systemName: "clock")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            if task.status == .running {
                HStack(spacing: 6) {
                    ForEach(SigningStep.allCases) { candidate in
                        Capsule()
                            .fill(stepColor(candidate))
                            .frame(height: 4)
                    }
                }
                .animation(Theme.spring, value: step)
                .accessibilityHidden(true)
            }
            if failed {
                HStack(spacing: 10) {
                    Button {
                        queue.retry(task.id)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(accent.opacity(0.15)))
                    }
                    Button(role: .destructive) {
                        queue.remove(task.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.danger.opacity(0.12)))
                    }
                    Spacer()
                    Text("Tap for log")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.name), \(statusText)")
    }

    private func stepColor(_ candidate: SigningStep) -> Color {
        guard let step else { return Color.primary.opacity(0.1) }
        if candidate.rawValue < step.rawValue { return Theme.success }
        if candidate == step { return accent }
        return Color.primary.opacity(0.1)
    }
}

struct SignedAppListRow: View {
    let app: SignedApp
    let icon: UIImage?
    let fileURL: URL
    let onOpen: () -> Void
    let onInstall: () -> Void
    let onResign: () -> Void

    @Environment(\.themeAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppIconView(image: icon, name: app.name, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text("v\(app.version) · \(app.certificateName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        CertificateStatusBadge(status: app.status())
                        if let expires = app.expiresAt {
                            Text(expires.expiryCountdown())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows details")

            HStack(spacing: 8) {
                Button(action: onInstall) {
                    actionLabel("Install", systemImage: "arrow.down.app.fill", filled: true)
                }
                Button(action: onResign) {
                    actionLabel("Re-sign", systemImage: "arrow.triangle.2.circlepath", filled: false)
                }
                ShareLink(item: fileURL) {
                    actionLabel("Share", systemImage: "square.and.arrow.up", filled: false)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private func actionLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundColor(filled ? .white : accent)
            .background(
                Capsule().fill(filled ? AnyShapeStyle(accent) : AnyShapeStyle(accent.opacity(0.14)))
            )
    }
}

/// Live log + step progress for one signing task.
struct SigningLogSheet: View {
    let taskID: UUID

    @EnvironmentObject private var queue: SigningQueue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let job = queue.jobs[taskID] {
                        ObservedSigningProgress(job: job)
                    } else {
                        EmptyStateView(systemImage: "checkmark.circle", title: "Finished", message: "This job is done. The app is in Signed Apps.")
                    }
                    if let task = queue.tasks.first(where: { $0.id == taskID }), task.status == .failed {
                        PrimaryButton(title: "Retry", systemImage: "arrow.clockwise") {
                            queue.retry(taskID)
                        }
                    }
                }
                .padding(Theme.padding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(queue.tasks.first(where: { $0.id == taskID })?.name ?? "Signing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ObservedSigningProgress: View {
    @ObservedObject var job: SigningJob

    var body: some View {
        SigningProgressView(
            currentStep: job.step,
            progress: job.progress,
            log: job.log,
            result: job.result,
            failureMessage: job.errorMessage
        )
    }
}
