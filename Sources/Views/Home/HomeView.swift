import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.themeAccent) private var accent

    @State private var showPicker = false
    @State private var quickSignPick = false
    @State private var dropTargeted = false
    @State private var appeared = false

    private var attentionApps: Int { signedApps.attentionCount }
    private var certificateNeedsAttention: Bool { certificates.active?.needsAttention ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    stats
                    if attentionApps > 0 || certificateNeedsAttention {
                        attentionBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let transfer = library.transfer {
                        importingCard(transfer)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    dropZone
                    quickSignRow
                    certificateCard
                }
                .padding(Theme.padding)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(Theme.spring, value: library.transfer)
                .animation(Theme.spring, value: attentionApps)
            }
            .background(AmbientBackground())
            .refreshable { await refreshHome() }
            .navigationTitle("Home")
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
        }
        .onAppear {
            withAnimation(Theme.spring.delay(0.05)) { appeared = true }
        }
    }

    private func refreshHome() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        certificates.reload()
        signedApps.load()
        Haptics.impact(.light)
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(certificates.certificates.count)", label: "Certificates", systemImage: "checkmark.seal.fill", tint: accent)
            StatCard(value: "\(signedApps.apps.count)", label: "Signed apps", systemImage: "signature", tint: .purple)
            StatCard(
                value: certificates.active?.daysLeft.map { "\($0)" } ?? "–",
                label: "Days left",
                systemImage: "hourglass",
                tint: certificateNeedsAttention ? Theme.warning : Theme.success
            )
        }
    }

    // MARK: Attention

    private var attentionBanner: some View {
        Button {
            router.attentionOnly = attentionApps > 0
            Haptics.impact(.medium)
            withAnimation(Theme.spring) { router.tab = .library }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.warning))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs attention")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(attentionText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.secondary)
            }
            .padding(Theme.padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.warning.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.warning.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityHint("Opens Library showing these items")
    }

    private var attentionText: String {
        var parts: [String] = []
        if attentionApps > 0 {
            parts.append("\(attentionApps) signed app\(attentionApps == 1 ? "" : "s") expiring or expired")
        }
        if certificateNeedsAttention, let active = certificates.active {
            parts.append("\(active.nickname) is \(active.status().title.lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Import

    private func importingCard(_ transfer: TransferState) -> some View {
        Card {
            HStack(spacing: 12) {
                ProgressView()
                Text(transfer.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dropZone: some View {
        Button {
            quickSignPick = false
            showPicker = true
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(dropTargeted ? 0.3 : 0.15))
                        .frame(width: 76, height: 76)
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(accent)
                        .scaleEffect(dropTargeted ? 1.12 : 1)
                }
                Text("Import IPA")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                Text("Tap to browse Files, drop an .ipa here, or share one to CertSigner.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, Theme.padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner + 4, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner + 4, style: .continuous)
                    .strokeBorder(accent.opacity(dropTargeted ? 0.9 : 0.45),
                                  style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
            )
            .animation(Theme.bouncy, value: dropTargeted)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .onDrop(of: [UTType.item], isTargeted: $dropTargeted, perform: handleDrop)
        .accessibilityLabel("Import IPA")
        .accessibilityHint("Opens the Files picker")
    }

    private var quickSignRow: some View {
        Button {
            guard !certificates.certificates.isEmpty else {
                toasts.show("Add a certificate first.", kind: .warning)
                importer.showCertificateImport = true
                return
            }
            quickSignPick = true
            showPicker = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Sign")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Pick an IPA and sign it right away with your defaults")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.secondary)
            }
            .padding(Theme.padding)
            .cardBackground()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    // MARK: Certificate

    @ViewBuilder
    private var certificateCard: some View {
        if let active = certificates.active {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        CertificateGlyph(seed: active.nickname, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ACTIVE CERTIFICATE")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                            Text(active.nickname)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        Spacer()
                        CertificateStatusBadge(status: active.status())
                    }
                    if let remaining = active.lifetimeRemaining {
                        ProgressBar(progress: remaining, height: 7, color: active.needsAttention ? Theme.warning : Theme.success)
                    }
                    if let expiration = active.expirationDate {
                        Text(expiration.expiryCountdown())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 10) {
                        if certificates.certificates.count > 1 {
                            Menu {
                                Picker("Active certificate", selection: Binding(
                                    get: { certificates.activeID },
                                    set: { id in
                                        withAnimation(Theme.spring) { certificates.setActive(id) }
                                        Haptics.success()
                                    }
                                )) {
                                    ForEach(certificates.certificates) { cert in
                                        Text(cert.nickname).tag(Optional(cert.id))
                                    }
                                }
                            } label: {
                                Label("Switch", systemImage: "arrow.left.arrow.right")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(accent.opacity(0.14)))
                            }
                        }
                        NavigationLink {
                            CertificatesView()
                        } label: {
                            Label("Manage", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(accent.opacity(0.14)))
                        }
                        Spacer()
                    }
                }
            }
        } else {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No certificate yet").font(.headline)
                        Text("Import your .p12 and profile to start signing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Add") { importer.showCertificateImport = true }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
        }
    }

    // MARK: File handling

    private func importPicked(_ url: URL) {
        let quick = quickSignPick
        Task {
            await importer.importIPA(from: url, name: url.lastPathComponent, moveSource: true, quickSign: quick,
                                     library: library, toasts: toasts)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let name = provider.suggestedName.map { $0.hasSuffix(".ipa") ? $0 : $0 + ".ipa" } ?? "Dropped.ipa"
        provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
            // The provided file is deleted when this closure returns, so copy it first.
            var copied: URL?
            if let url {
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString).ipa")
                if (try? FileManager.default.copyItem(at: url, to: destination)) != nil { copied = destination }
            }
            let message = error?.localizedDescription
            Task { @MainActor in
                if let copied {
                    await importer.importIPA(from: copied, name: name, moveSource: true, quickSign: false,
                                             library: library, toasts: toasts)
                } else {
                    toasts.show("Couldn't read the dropped file\(message.map { ": \($0)" } ?? ".")", kind: .error)
                }
            }
        }
        return true
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.15)))
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .numericTransition()
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

extension View {
    /// Rolling-number animation on iOS 17+, no-op before.
    @ViewBuilder
    func numericTransition() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}
