import SwiftUI

struct InstallSheet: View {
    let app: SignedApp

    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var serverCertificates: ServerCertificateStore
    @EnvironmentObject private var router: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @AppStorage(SettingsKeys.installMethod) private var method: InstallMethod = .automatic

    @StateObject private var session = InstallSession()
    @State private var shakes = 0

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
                VStack(spacing: 22) {
                    header
                    statusIcon
                    statusText
                    stages
                    if failure != nil { troubleshooting }
                    logView
                    actions
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: session.phase)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Install")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.phase.isActive ? "Cancel" : "Done") {
                        session.stop()
                        dismiss()
                    }
                }
            }
        }
        .task { await begin() }
        .onDisappear { session.stop() }
        .onChange(of: failure) { newValue in
            if newValue != nil { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
        }
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
        HStack(spacing: 14) {
            AppIconView(image: signedApps.icons[app.id], name: app.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text("\(app.bundleID) · v\(app.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
                    Circle().fill(accent.opacity(0.12))
                    Image(systemName: currentStage == .prompt ? "hand.tap.fill" : "server.rack")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(accent)
                }
                .frame(width: 120, height: 120)
                .transition(.opacity)
            }
        }
        .frame(height: 130)
        .shake(shakes)
    }

    private var statusText: some View {
        VStack(spacing: 6) {
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
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Stage.allCases, id: \.rawValue) { stage in
                    HStack(spacing: 12) {
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
            VStack(alignment: .leading, spacing: 8) {
                tip("Fully Local failing? Switch to Semi-Local in Settings → Install (needs internet).")
                tip("Semi-Local failing? Check you're online; it uses api.palera.in for the manifest.")
                tip("“Unable to Install” from iOS usually means the device isn't in the profile, or the certificate is revoked.")
                tip("“Integrity could not be verified” means the signature is bad: re-sign with a valid certificate.")
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOG")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.log) { line in
                    Text(line.text)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(line.isError ? Theme.danger : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .cardBackground(cornerRadius: Theme.smallCorner)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if failure != nil {
            VStack(spacing: 12) {
                PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                    Task { await begin() }
                }
                PrimaryButton(title: "Install Settings", systemImage: "gearshape", style: .tinted) {
                    session.stop()
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
