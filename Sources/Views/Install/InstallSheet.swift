import SwiftUI

struct InstallSheet: View {
    let app: SignedApp

    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var serverCertificates: ServerCertificateStore
    @EnvironmentObject private var router: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient
    @AppStorage(SettingsKeys.installMethod) private var method: InstallMethod = .automatic

    /// One app-wide session: if this sheet is created twice (e.g. re-presented right after automatic
    /// signing) both copies show the same install, and nothing restarts the server iOS is talking to.
    @ObservedObject private var session = InstallSession.shared
    @State private var shakes = 0
    @AppStorage(SettingsKeys.autoCloseInstall) private var autoClose = true
    @State private var autoCloseTask: Task<Void, Never>?

    private enum Stage: Int, CaseIterable {
        case server, prompt, transfer, install

        var title: String {
            switch self {
            case .server: return "Start local server"
            case .prompt: return "Confirm on the iOS prompt"
            case .transfer: return "Send app to iOS"
            case .install: return "Install"
            }
        }
    }

    private var currentStage: Stage? {
        switch session.phase {
        case .idle, .preparing: return .server
        case .waitingForPrompt, .manifestSent: return .prompt
        case .downloading: return .transfer
        case .installing: return .install
        case .failed: return nil
        }
    }

    private var failure: String? {
        if case .failed(let message) = session.phase { return message }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.x6) {
                    header
                    statusIcon
                    statusText
                    stages
                    if failure != nil { troubleshooting }
                    logView
                    actions
                }
                .padding(Theme.padding)
                // Animate stage changes only: the phase also carries the transfer percentage, and
                // springing the whole sheet on every tick made the numbers jitter.
                .animation(Theme.spring, value: currentStage)
                .animation(Theme.spring, value: failure)
            }
            .background(AuroraBackground(intensity: 0.7))
            .navigationTitle("Install")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.phase.isActive ? "Cancel" : "Done") {
                        session.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            if session.isRunning(for: app.id) {
                AppLog.info("install: sheet shown again for \(app.name); keeping the running install")
                return
            }
            await begin()
        }
        // Closing the sheet mid-install leaves the server up (iOS may still be fetching);
        // the prompt watchdog or the post-install grace period shuts it down.
        .onChange(of: failure) { newValue in
            if newValue != nil { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
        }
        // Success only (iOS took the whole app): show the checkmark ~1 s, then close.
        // Failures never auto-close. The server keeps its existing post-install grace period and stops itself.
        .onChange(of: session.phase == .installing) { installed in
            autoCloseTask?.cancel()
            guard installed, autoClose, session.appID == app.id else { return }
            autoCloseTask = Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard !Task.isCancelled, session.phase == .installing else { return }
                dismiss() // the success haptic already played when iOS took the app

            }
        }
        .onDisappear { autoCloseTask?.cancel() }
    }

    private func begin() async {
        await session.start(
            app: app,
            ipaURL: signedApps.ipaURL(for: app),
            iconURL: app.iconFileName.map { signedApps.folder(for: app.id).appendingPathComponent($0) },
            method: method,
            certificates: serverCertificates
        )
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: Space.x4) {
            AppIconView(image: signedApps.icons[app.id], name: app.name, size: 56)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(app.name).font(.headline)
                Text("\(app.bundleID) · v\(app.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .identifierText()
                if !session.methodDescription.isEmpty {
                    Text(session.methodDescription)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(accent)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            switch session.phase {
            case .installing:
                AnimatedResultIcon(result: .success, size: 120)
                    .transition(.scale.combined(with: .opacity))
            case .failed:
                AnimatedResultIcon(result: .failure, size: 120)
                    .transition(.scale.combined(with: .opacity))
            case .downloading(let progress):
                ProgressRing(progress: progress, lineWidth: 12)
                    .frame(width: 120, height: 120)
                    .transition(.opacity)
            default:
                ZStack {
                    Circle().fill(RadialGradient(colors: [accent.opacity(0.3), .clear], center: .center,
                                                 startRadius: 20, endRadius: 95))
                        .frame(width: 190, height: 190)
                    Circle()
                        .fill(LinearGradient(colors: gradient.map { $0.opacity(0.2) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        .frame(width: 120, height: 120)
                    Image(systemName: currentStage == .prompt ? "hand.tap.fill" : "server.rack")
                        .font(.system(size: 44, weight: .semibold))
                        .accentGradientForeground(gradient)
                        .symbolReplace()
                        .symbolPulse()
                }
                .frame(width: 120, height: 120)
                .transition(.opacity)
            }
        }
        .frame(height: 130)
        .shake(shakes)
    }

    private var statusText: some View {
        VStack(spacing: Space.x2) {
            Text(headline)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subheadline)
                .font(.subheadline)
                .foregroundColor(failure == nil ? .secondary : Theme.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        switch session.phase {
        case .idle, .preparing: return "Preparing…"
        case .waitingForPrompt, .manifestSent: return "Tap “Install” on the prompt"
        case .downloading: return "Sending to iOS…"
        case .installing: return "Installing"
        case .failed: return "Install failed"
        }
    }

    private var subheadline: String {
        switch session.phase {
        case .idle, .preparing: return "Starting the local install server."
        case .waitingForPrompt: return "iOS will ask whether to install \(app.name). Stay in CertSigner until the transfer finishes."
        case .manifestSent: return "iOS read the install manifest. Confirm the prompt to continue."
        case .downloading(let progress): return "\(Int(progress * 100))% of \(app.size.byteString). Keep CertSigner open."
        case .installing: return "Go to your Home Screen to watch \(app.name) install. If iOS says “Unable to Install”, see the tips in Settings → Install."
        case .failed(let message): return message
        }
    }

    private var stages: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.x4) {
                ForEach(Stage.allCases, id: \.rawValue) { stage in
                    HStack(spacing: Space.x3) {
                        stageIcon(stage).frame(width: 26, height: 26)
                        Text(stage.title)
                            .font(.subheadline.weight(stage == currentStage ? .semibold : .regular))
                            .foregroundColor(isPending(stage) ? .secondary : .primary)
                        Spacer()
                        if stage == currentStage && session.phase.isActive {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                if case .downloading(let progress) = session.phase {
                    ProgressBar(progress: progress)
                }
            }
        }
    }

    private func isPending(_ stage: Stage) -> Bool {
        guard let currentStage else { return false }
        return stage.rawValue > currentStage.rawValue
    }

    @ViewBuilder
    private func stageIcon(_ stage: Stage) -> some View {
        if session.phase == .installing || (currentStage.map { stage.rawValue < $0.rawValue } ?? false) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundColor(Theme.success)
        } else if failure != nil {
            Image(systemName: "minus.circle").font(.title3).foregroundColor(.secondary)
        } else if stage == currentStage {
            Image(systemName: "circle.dotted").font(.title3.weight(.semibold)).foregroundColor(accent)
        } else {
            Image(systemName: "circle").font(.title3).foregroundColor(.secondary.opacity(0.5))
        }
    }

    private var troubleshooting: some View {
        CardSection("Try this", systemImage: "lightbulb") {
            VStack(alignment: .leading, spacing: Space.x2) {
                tip("Fully Local failing? Switch to Semi-Local in Settings → Install (needs internet).")
                tip("Semi-Local failing? Check you're online; it uses api.palera.in for the manifest.")
                tip("“Unable to Install” from iOS usually means the device isn't in the profile, or the certificate is revoked.")
                tip("“Integrity could not be verified” means the signature is bad: re-sign with a valid certificate.")
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("LOG")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, Space.x1)
            VStack(alignment: .leading, spacing: Space.x1) {
                ForEach(session.log) { line in
                    Text(line.text)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(line.isError ? Theme.danger : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Space.x3)
            .cardBackground(cornerRadius: Theme.smallCorner)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if failure != nil {
            VStack(spacing: Space.x3) {
                PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                    Task { await begin() }
                }
                PrimaryButton(title: "Install Settings", systemImage: "gearshape", style: .tinted) {
                    session.cancel()
                    router.tab = .settings
                    dismiss()
                }
            }
        } else if session.phase == .installing {
            PrimaryButton(title: "Done", systemImage: "checkmark") {
                dismiss()
            }
        }
    }
}
