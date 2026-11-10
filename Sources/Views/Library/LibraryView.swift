import SwiftUI

enum SignedSort: String, CaseIterable, Identifiable {
    case date, name, expiry

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .date: return "Date"
        case .name: return "Name"
        case .expiry: return "Expiry"
        }
    }

    var systemImage: String {
        switch self {
        case .date: return "calendar"
        case .name: return "textformat"
        case .expiry: return "hourglass"
        }
    }

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

    /// Fits a 4-segment control.
    var shortTitle: String {
        switch self {
        case .all: return "All"
        case .valid: return "Valid"
        case .expiring: return "Expiring"
        case .expired: return "Expired"
        }
    }

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
    @State private var showFilters = false
    @State private var path: [UUID] = []
    @State private var installTarget: SignedApp?
    @State private var logTarget: LogTarget?
    /// Rows currently playing the shared delete animation.
    @State private var deletePhases: [UUID: DeletePhase] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            seen[app.certificateID] = certificates.certificates.first { $0.id == app.certificateID }?.displayName
                ?? Certificate.friendlyName(app.certificateName)
        }
        return seen.map { CertificateChoice(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        let apps = visibleApps
        NavigationStack(path: $path) {
            List {
                Group {
                if queue.tasks.isEmpty && signedApps.apps.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "square.stack.3d.up",
                            title: "Your library is empty",
                            message: "Import an IPA from Home. While it signs it shows up here, then lands in Signed Apps.",
                            actionTitle: "Go to Home",
                            action: { withAnimation(Theme.spring) { router.tab = .home } }
                        )
                        .emptyStateEntrance()
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if !queue.tasks.isEmpty { signingSection }
                    signedSection(apps)
                }
                }
                .softRowSeparators()
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AuroraBackground(intensity: 0.55))
            .animation(Theme.spring, value: queue.tasks.map(\.id))
            .animation(DeleteMotion.collapse, value: apps.map(\.id))
            .librarySearchable(text: $search)
            .refreshable { await reload() }
            .navigationTitle("Library")
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in
                SignedAppDetailView(appID: id)
                    .zoomTransition(id: id, in: zoom)
            }
            .sheet(item: $installTarget) { app in
                InstallSheet(app: app).sheetChrome()
            }
            .sheet(item: $logTarget) { target in
                SigningLogSheet(taskID: target.id).sheetChrome()
            }
            // Delete from the detail screen: it pops first, then the row leaves here.
            .onReceive(RowDeleteRequests.shared.$requested) { ids in
                for id in ids where signedApps.apps.contains(where: { $0.id == id }) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: DeleteMotion.popNanoseconds)
                        guard let app = signedApps.apps.first(where: { $0.id == id }),
                              RowDeleteRequests.shared.claim(id) else { return }
                        animatedDelete(app)
                    }
                }
            }
        }
    }

    private func reload() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        signedApps.load()
    }

    /// Removes the app from the list (inside the collapse animation) and shows "Deleted <app>" with Undo.
    static func deleteWithUndo(_ app: SignedApp, signedApps: SignedAppsStore, toasts: ToastCenter) {
        let pending = signedApps.removeForUndo(app)
        Haptics.success()
        toasts.show(
            "Deleted \(app.name)", kind: .success, actionTitle: "Undo", duration: 5,
            action: {
                guard let pending else { return }
                withAnimation(DeleteMotion.collapse) { signedApps.restore(pending) }
                Haptics.impact(.light)
            },
            onExpire: {
                if let pending { signedApps.finalizeDeletion(pending) }
            }
        )
    }

    /// No confirmation: the shared delete animation plays, then the app leaves the list.
    private func animatedDelete(_ app: SignedApp) {
        guard deletePhases[app.id] == nil else { return }
        DeleteMotion.run(reduceMotion: reduceMotion, setPhase: { deletePhases[app.id] = $0 }) {
            Self.deleteWithUndo(app, signedApps: signedApps, toasts: toasts)
        }
    }

    /// The last signed app is leaving: the "Signed Apps" header fades out with it.
    private var lastSignedAppLeaving: Bool {
        !deletePhases.isEmpty && queue.tasks.isEmpty
            && signedApps.apps.allSatisfy { deletePhases[$0.id] == .leaving }
    }

    // MARK: Signing

    private var signingSection: some View {
        Section {
            ForEach(queue.tasks) { task in
                SigningTaskRow(task: task, job: queue.jobs[task.id], icon: icon(for: task))
                    .listRowBackground(RowSurface())
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
                        .padding(.vertical, Space.x2)
                        .emptyStateEntrance()
                } else {
                    VStack(spacing: Space.x2) {
                        Image(systemName: "magnifyingglass").font(.title2).foregroundColor(.secondary)
                        Text("No signed apps match your filters.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Clear Filters") { clearFilters() }
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.x3)
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
                    .deleteExit(deletePhases[app.id])
                    .zoomSource(id: app.id, in: zoom)
                    .listRowBackground(RowSurface().deleteExit(deletePhases[app.id]))
                    .swipeActions(edge: .trailing) {
                        // Not `role: .destructive`: that makes List remove the row itself before the dissolve plays.
                        Button {
                            animatedDelete(app)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Theme.danger)
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
                        .numericTransition()
                }
            }
            .opacity(lastSignedAppLeaving ? 0 : 1)
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
        toasts.show("Re-signing \(app.name) with \(active.displayName)", kind: .info)
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
            // Sort & filter sheet (sliding segmented controls) instead of a system menu.
            Button {
                showFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.body.weight(.semibold))
                    .foregroundColor(isFiltering ? .white : accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isFiltering ? accent : Color.clear))
                    .glassIconButton()
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
            .sheet(isPresented: $showFilters) {
                LibraryFilterSheet(
                    sort: $sort,
                    statusFilter: $statusFilter,
                    certificateFilter: $certificateFilter,
                    certificates: certificateChoices.map { ($0.id, $0.name) },
                    isFiltering: isFiltering,
                    onClear: clearFilters
                )
                .sheetChrome()
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
    @Environment(\.themeGradient) private var gradient

    private var statusText: String {
        if failed { return task.errorMessage ?? "Failed" }
        switch task.status {
        case .queued: return "Waiting…"
        case .running: return step.map { "\($0.title)…" } ?? "Starting…"
        case .failed: return task.errorMessage ?? "Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                AppIconView(image: icon, name: task.name, size: 46)
                VStack(alignment: .leading, spacing: Space.x1) {
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
                        .symbolBounce(value: failed)
                        .ambientGlow(Theme.danger, radius: 8, opacity: 0.4)
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
                        .symbolPulse()
                }
            }
            if task.status == .running {
                HStack(spacing: Space.x2) {
                    ForEach(SigningStep.allCases) { candidate in
                        if candidate == step {
                            // Current step: gradient with a moving sheen.
                            Capsule()
                                .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                                .frame(height: 5)
                                .shimmering()
                                .shadow(color: accent.opacity(0.45), radius: 4)
                        } else {
                            Capsule()
                                .fill(stepColor(candidate))
                                .frame(height: 5)
                        }
                    }
                }
                .animation(Theme.spring, value: step)
                .accessibilityHidden(true)
            }
            if failed {
                HStack(spacing: Space.x3) {
                    Button {
                        queue.retry(task.id)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Space.x3)
                            .padding(.vertical, Space.x2)
                            .background(Capsule().fill(accent.opacity(0.15)))
                    }
                    Button(role: .destructive) {
                        queue.remove(task.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Space.x3)
                            .padding(.vertical, Space.x2)
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
        .padding(.vertical, Space.x1)
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
    @Environment(\.themeOnAccent) private var onAccent
    @Environment(\.themeGradient) private var gradient

    private var lifetimeRemaining: Double? {
        guard let expires = app.expiresAt, expires > app.signedAt else { return nil }
        let total = expires.timeIntervalSince(app.signedAt)
        return max(0, min(1, expires.timeIntervalSinceNow / total))
    }

    private var daysLeft: Int? {
        app.expiresAt.map { max(0, Int(ceil($0.timeIntervalSinceNow / 86_400))) }
    }

    private var ringColor: Color {
        switch app.status() {
        case .valid: return Theme.success
        case .expiringSoon: return Theme.warning
        case .expired: return Theme.danger
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                AppIconView(image: icon, name: app.name, size: 52)
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(app.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text("v\(app.version) · \(Certificate.friendlyName(app.certificateName))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .identifierText()
                    HStack(spacing: Space.x2) {
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
                ExpiryRing(remaining: lifetimeRemaining, days: daysLeft, color: ringColor)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows details")

            HStack(spacing: Space.x2) {
                Button(action: onInstall) {
                    actionLabel("Install", systemImage: "arrow.down.app.fill", filled: true)
                        .glassShine(in: Capsule(), sweep: false)
                }
                .buttonStyle(ShinePressStyle(shape: Capsule(), scale: 0.95))
                Button(action: onResign) {
                    actionLabel("Re-sign", systemImage: "arrow.triangle.2.circlepath", filled: false)
                }
                ShareLink(item: fileURL) {
                    actionLabel("Share", systemImage: "square.and.arrow.up", filled: false)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Space.x2)
    }

    private func actionLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.x2)
            .foregroundColor(filled ? onAccent : accent)
            .frame(minHeight: 36)
            .background(
                Capsule().fill(filled
                    ? AnyShapeStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(accent.opacity(0.14)))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0.3 : 0.08), lineWidth: 0.75))
    }
}

/// Live log + step progress for one signing task.
struct SigningLogSheet: View {
    let taskID: UUID

    @EnvironmentObject private var queue: SigningQueue
    @Environment(\.dismiss) private var dismiss
    /// Kept after the job leaves the queue, so the finished screen can still share the log.
    @State private var savedLog: URL?
    @State private var appName = "App"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.x5) {
                    if let job = queue.jobs[taskID] {
                        ObservedSigningProgress(job: job, onLogSaved: { savedLog = $0 })
                    } else {
                        EmptyStateView(systemImage: "checkmark.circle", title: "Finished", message: "This job is done. The app is in Signed Apps.")
                    }
                    if let savedLog, let shareURL = SigningLogStore.shareableCopy(of: savedLog, appName: appName) {
                        ShareLink(item: shareURL) {
                            Label("Share signing log", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.app(.secondary))
                        .transition(.opacity)
                    }
                    if let task = queue.tasks.first(where: { $0.id == taskID }), task.status == .failed {
                        PrimaryButton(title: "Retry", systemImage: "arrow.clockwise") {
                            queue.retry(taskID)
                        }
                    }
                }
                .padding(Theme.padding)
            }
            .background(AuroraBackground(intensity: 0.7))
            .navigationTitle(queue.tasks.first(where: { $0.id == taskID })?.name ?? "Signing")
            .onAppear { appName = queue.tasks.first(where: { $0.id == taskID })?.name ?? appName }
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
    var onLogSaved: (URL) -> Void = { _ in }

    var body: some View {
        SigningProgressView(
            currentStep: job.step,
            progress: job.progress,
            log: job.log,
            result: job.result,
            failureMessage: job.errorMessage
        )
        .onAppear { if let url = job.logFileURL { onLogSaved(url) } }
        .onChange(of: job.logFileURL) { url in if let url { onLogSaved(url) } }
    }
}


/// Library "Sort & Filter": sliding segmented controls for sort and status, a certificate list
/// whose checkmark springs in, and Clear Filters. Same bindings and stored settings as before.
struct LibraryFilterSheet: View {
    @Binding var sort: SignedSort
    @Binding var statusFilter: StatusFilter
    @Binding var certificateFilter: UUID?
    let certificates: [(id: UUID, name: String)]
    let isFiltering: Bool
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    VStack(alignment: .leading, spacing: Space.x2) {
                        SectionHeader("Sort by")
                        SlidingSegmentedControl(
                            selection: $sort,
                            options: SignedSort.allCases.map { .init(value: $0, title: $0.shortTitle, systemImage: $0.systemImage) },
                            accessibilityTitle: "Sort by"
                        )
                    }
                    VStack(alignment: .leading, spacing: Space.x2) {
                        SectionHeader("Status")
                        SlidingSegmentedControl(
                            selection: $statusFilter,
                            options: StatusFilter.allCases.map { .init(value: $0, title: $0.shortTitle) },
                            accessibilityTitle: "Status"
                        )
                    }
                    if !certificates.isEmpty {
                        VStack(alignment: .leading, spacing: Space.x2) {
                            SectionHeader("Certificate")
                            VStack(spacing: 0) {
                                certificateRow(id: nil, name: "All Certificates")
                                ForEach(certificates, id: \.id) { item in
                                    SoftDivider()
                                    certificateRow(id: item.id, name: item.name)
                                }
                            }
                            .padding(.horizontal, Space.x4)
                            .cardBackground()
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        }
                    }
                    if isFiltering {
                        PrimaryButton(title: "Clear Filters", systemImage: "xmark.circle", style: .tinted) {
                            onClear()
                            dismiss()
                        }
                    }
                }
                .padding(Theme.padding)
            }
            .navigationTitle("Sort & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func certificateRow(id: UUID?, name: String) -> some View {
        let selected = certificateFilter == id
        return Button {
            Haptics.selection()
            withAnimation(Motion.smooth) { certificateFilter = id }
        } label: {
            HStack {
                Text(name)
                    .foregroundColor(SemanticColor.textPrimary)
                    .identifierText(minimumScale: 0.85)
                Spacer(minLength: Space.x2)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundColor(accent)
                    .scaleEffect(selected ? 1 : 0.3)
                    .opacity(selected ? 1 : 0)
                    .animation(reduceMotion ? Motion.fade : Motion.bouncy, value: selected)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
