import SwiftUI

/// "Update CertSigner": what's new, which certificate signs it, the pre-update checks, then
/// Download → Verify → Sign → Install with progress. Installing goes through the same install
/// session as every app: iOS asks to confirm and closes CertSigner while it updates it.
struct UpdateSheet: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var serverCertificates: ServerCertificateStore
    @ObservedObject private var updates = UpdateService.shared
    @ObservedObject private var install = InstallSession.shared
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    @AppStorage(SettingsKeys.installMethod) private var method: InstallMethod = .automatic
    @AppStorage(SettingsKeys.installPaleraFallback) private var paleraFallback = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent

    @State private var plan: UpdatePlan?
    @State private var showAllNotes = false
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    switch updates.checkState {
                    case .available(let update):
                        header(update)
                        if updates.runState == .idle {
                            notes(update)
                            signing
                        } else {
                            progress(update)
                        }
                    case .checking:
                        LoadingSkeleton()
                    case .failed(let message):
                        ErrorState(title: "Couldn't check for updates", message: message,
                                   onRetry: { Task { await updates.check() } })
                    case .idle, .upToDate:
                        upToDate
                    }
                }
                .padding(Theme.padding)
            }
            .background(AuroraBackground(intensity: 0.6))
            .navigationTitle("Update CertSigner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if updates.isRunning { updates.cancel() }
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actions.padding(Theme.padding) }
        }
        .task {
            if updates.checkState == .idle { await updates.check() }
            plan = await updates.plan(certificates: certificates, udid: udid)
        }
    }

    // MARK: Pieces

    private func header(_ update: AvailableUpdate) -> some View {
        HStack(spacing: Space.x4) {
            IconTile(systemImage: "arrow.down.app.fill", color: accent, size: 52)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text("Build \(update.build)")
                    .font(TypeScale.title)
                Text(subtitle(update))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ update: AvailableUpdate) -> String {
        var parts = ["You have build \(UpdateRules.installedBuild)", update.manifest.ipa.size.byteString]
        if let date = update.manifest.publishedDate { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func notes(_ update: AvailableUpdate) -> some View {
        if !update.manifest.notes.isEmpty {
            CardSection("What's new", systemImage: "sparkles") {
                let shown = showAllNotes ? update.manifest.notes : Array(update.manifest.notes.prefix(5))
                ForEach(Array(shown.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                        Text("•").foregroundColor(.secondary)
                        Text(note).font(.subheadline)
                    }
                }
                if update.manifest.notes.count > 5 {
                    Button(showAllNotes ? "Show Less" : "Show All \(update.manifest.notes.count)") {
                        withAnimation(Motion.smooth) { showAllNotes.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var signing: some View {
        if let plan {
            CardSection("Signs with", systemImage: "signature") {
                if let certificate = plan.certificate {
                    InfoRow(label: "Certificate", value: certificate.nickname)
                    if let team = certificate.profile?.teamID { InfoRow(label: "Team", value: team, monospaced: true) }
                    if let expiry = certificate.expirationDate {
                        InfoRow(label: "Expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                InfoRow(label: "Bundle ID kept", value: plan.running.bundleID, monospaced: true)
            }
            CardSection("Checks", systemImage: "checklist") {
                ForEach(plan.checks) { check in
                    HStack(alignment: .top, spacing: Space.x3) {
                        Image(systemName: check.passed == true ? "checkmark.circle.fill"
                                          : check.passed == false ? "xmark.octagon.fill" : "questionmark.circle")
                            .foregroundColor(check.passed == true ? Theme.success : check.passed == false ? Theme.danger : .secondary)
                            .font(.body.weight(.semibold))
                        VStack(alignment: .leading, spacing: Space.hair) {
                            Text(check.title).font(.subheadline.weight(.semibold))
                            Text(check.detail).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text("iOS shows an install prompt: tap Install. CertSigner closes while iOS updates it; open it again from the Home Screen. Your certificates, apps and settings stay.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            LoadingSkeleton()
        }
    }

    private func progress(_ update: AvailableUpdate) -> some View {
        CardSection("Updating to build \(update.build)", systemImage: "arrow.triangle.2.circlepath") {
            ForEach(UpdateService.Stage.allCases) { stage in
                stageRow(stage)
            }
            if updates.runState == .installing {
                Text(installHeadline)
                    .font(.subheadline.weight(.semibold))
                Text(installDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if case .failed(_, let message) = updates.runState {
                ErrorState(title: "Update didn't finish", message: message,
                           details: updates.log.suffix(12).map(\.text).joined(separator: "\n"), compact: true)
            }
            if case .failed(let message) = install.phase, updates.runState == .installing {
                ErrorState(title: "Install didn't finish", message: message, compact: true)
            }
        }
    }

    private func stageRow(_ stage: UpdateService.Stage) -> some View {
        let state = stageState(stage)
        return HStack(spacing: Space.x3) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.success)
                case .active: ProgressView().controlSize(.small)
                case .failed: Image(systemName: "xmark.octagon.fill").foregroundColor(Theme.danger)
                case .waiting: Image(systemName: "circle").foregroundColor(.secondary)
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(stage.title).font(.subheadline)
                if case .running(stage, let value) = updates.runState, stage != .verify {
                    ProgressView(value: value).tint(accent)
                }
                if stage == .install, case .downloading(let value) = install.phase {
                    ProgressView(value: value).tint(accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private enum StageState { case waiting, active, done, failed }

    private func stageState(_ stage: UpdateService.Stage) -> StageState {
        switch updates.runState {
        case .idle: return .waiting
        case .running(let current, _):
            return stage.rawValue < current.rawValue ? .done : stage == current ? .active : .waiting
        case .installing:
            if stage != .install { return .done }
            if case .failed = install.phase { return .failed }
            return install.phase.isSuccess ? .done : .active
        case .failed(let current, _):
            return stage.rawValue < current.rawValue ? .done : stage == current ? .failed : .waiting
        }
    }

    private var installHeadline: String {
        switch install.phase {
        case .idle, .preparing: return "Preparing the install…"
        case .waitingForPrompt, .manifestSent: return "Tap “Install” on the iOS prompt"
        case .stalled(.noManifest): return "iOS hasn't asked for the update yet"
        case .stalled(.noPayload): return "Waiting for iOS to download the update"
        case .downloading: return "Sending the update to iOS…"
        case .installing, .installed: return "iOS is installing the update"
        case .failed: return "Install didn't finish"
        }
    }

    private var installDetail: String {
        switch install.phase {
        case .installing, .installed:
            return "CertSigner closes now. Open it again from the Home Screen to finish."
        case .stalled:
            return "If you dismissed the prompt, reopen it. Keep CertSigner open until the transfer finishes."
        default:
            return "Keep CertSigner open until the transfer finishes."
        }
    }

    private var upToDate: some View {
        VStack(spacing: Space.x3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.success)
            Text("CertSigner is up to date").font(.headline)
            Text("Build \(UpdateRules.installedBuild)").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.x8)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if let update = updates.available {
            VStack(spacing: Space.x2) {
                switch updates.runState {
                case .idle:
                    PrimaryButton(title: "Update", systemImage: "arrow.down.circle.fill") { start(update) }
                        .disabled(!(plan?.canUpdate ?? false))
                    if updates.skippedBuild != update.build {
                        PrimaryButton(title: "Skip This Build", style: .tinted) {
                            updates.skip(update)
                            dismiss()
                        }
                    }
                case .running:
                    PrimaryButton(title: "Cancel", style: .tinted) { updates.cancel() }
                case .installing:
                    if case .stalled = install.phase {
                        PrimaryButton(title: "Reopen Prompt", systemImage: "hand.tap") { install.reopenPrompt() }
                    }
                    if case .failed = install.phase {
                        PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") { updates.resetRun(); start(update) }
                    }
                case .failed:
                    PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                        updates.resetRun()
                        start(update)
                    }
                }
            }
        }
    }

    private func start(_ update: AvailableUpdate) {
        Task {
            let fresh = await updates.plan(certificates: certificates, udid: udid)
            plan = fresh
            guard fresh.canUpdate else {
                Haptics.warning()
                return
            }
            Haptics.impact(.medium)
            updates.start(update, plan: fresh, certificates: certificates, serverCertificates: serverCertificates,
                          method: method, paleraFallback: paleraFallback)
        }
    }
}
