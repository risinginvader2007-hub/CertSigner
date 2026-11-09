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
    @State private var showCertificatePicker = false
    @State private var quickSignPick = false
    @State private var dropTargeted = false
    @State private var appeared = false
    @State private var dashPhase: CGFloat = 0
    @State private var path: [HomeRoute] = []
    @State private var attentionGlow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themeGradient) private var gradient

    private var attentionApps: Int { signedApps.attentionCount }
    private var certificateNeedsAttention: Bool { certificates.active?.needsAttention ?? false }

    var body: some View {
        // Path-based so pushed screens don't depend on the Manage link inside the certificate card
        // staying alive while the certificate store publishes changes.
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Space.x4 + 2) {
                    stats
                        .staggeredEntrance(0, active: appeared)
                    if attentionApps > 0 || certificateNeedsAttention {
                        attentionBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let transfer = library.transfer {
                        importingCard(transfer)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    dropZone
                        .staggeredEntrance(1, active: appeared)
                    quickSignRow
                        .staggeredEntrance(2, active: appeared)
                    certificateCard
                        .scrollTilt()
                        .staggeredEntrance(3, active: appeared)
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: library.transfer)
                .animation(Theme.spring, value: attentionApps)
            }
            .background(AmbientBackground())
            .refreshable { await refreshHome() }
            .navigationTitle("Home")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .certificates: CertificatesView()
                }
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
            .sheet(isPresented: $showCertificatePicker) {
                CertificatePickerSheet(selectedID: certificates.activeID) { id in
                    withAnimation(Theme.spring) { certificates.setActive(id) }
                }
                .sheetChrome()
            }
        }
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            // Marching dashed border and breathing attention glow: slow, cheap (stroke phase / opacity).
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { dashPhase = -32 }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { attentionGlow = true }
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
                    .symbolPulse()
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LinearGradient(colors: [Theme.warning, Theme.danger.opacity(0.85)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .shadow(color: Theme.warning.opacity(attentionGlow ? 0.6 : 0.2), radius: attentionGlow ? 12 : 4)
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
                    .strokeBorder(Theme.warning.opacity(attentionGlow ? 0.7 : 0.3), lineWidth: 1)
            )
            .shadow(color: Theme.warning.opacity(attentionGlow ? 0.25 : 0.05), radius: 16, y: 6)
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
                        .fill(RadialGradient(colors: [accent.opacity(dropTargeted ? 0.45 : 0.25), .clear],
                                             center: .center, startRadius: 4, endRadius: 64))
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(LinearGradient(colors: gradient.map { $0.opacity(dropTargeted ? 0.35 : 0.18) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .frame(width: 76, height: 76)
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .accentGradientForeground(gradient)
                        .symbolBounce(value: dropTargeted)
                        .scaleEffect(dropTargeted ? 1.12 : 1)
                }
                .frame(height: 96)
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
                    .strokeBorder(
                        LinearGradient(colors: gradient.map { $0.opacity(dropTargeted ? 1 : 0.6) },
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: dropTargeted ? 2.5 : 2, lineCap: .round, dash: [9, 7], dashPhase: dashPhase)
                    )
            )
            .glassShine(cornerRadius: Theme.corner + 4)
            .shadow(color: accent.opacity(dropTargeted ? 0.45 : 0), radius: 22)
            .animation(Theme.bouncy, value: dropTargeted)
        }
        .buttonStyle(ShinePressStyle(shape: RoundedRectangle(cornerRadius: Theme.corner + 4, style: .continuous), scale: 0.98))
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
                        RoundedRectangle(cornerRadius: Radius.sm + 1, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .ambientGlow(.pink, radius: 10, opacity: 0.4)
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
            .glassShine(cornerRadius: Theme.corner)
        }
        .buttonStyle(ShinePressStyle(shape: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous), scale: 0.98))
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
                            Text(active.displayName)
                                .font(.headline)
                                .identifierText(minimumScale: 0.85)
                                .id(active.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            if let raw = active.rawIDLine {
                                Text(raw)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .identifierText()
                            }
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
                            // A plain button + bottom sheet (a system Menu blurred the pill and
                            // left a square snapshot behind when it closed).
                            Button {
                                showCertificatePicker = true
                            } label: {
                                Label("Switch", systemImage: "arrow.left.arrow.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(accent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .accentPillBackground(accent)
                                    .glassShine(in: Capsule())
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.95))
                            .accessibilityLabel("Switch certificate")
                        }
                        NavigationLink(value: HomeRoute.certificates) {
                            Label("Manage", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .accentPillBackground(accent)
                                .glassShine(in: Capsule())
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(ShinePressStyle(shape: Capsule(), scale: 0.95))
                        Spacer()
                    }
                }
            }
            .glassShine(cornerRadius: Theme.corner)
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

/// Screens Home pushes, declared at Home's NavigationStack root.
enum HomeRoute: Hashable {
    case certificates
}

struct StatCard: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shown value: counts up once from 0 when the card first appears, then follows `value`.
    @State private var shown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .symbolBounce(value: value)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs + 2, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(RoundedRectangle(cornerRadius: Radius.xs + 2, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 0.75))
                .ambientGlow(tint, radius: 8, opacity: 0.35)
            Text(shown ?? value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .displayTracking()
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
        .glassShine(cornerRadius: Theme.corner)
        .onAppear {
            guard shown == nil else { return }
            guard !reduceMotion, Int(value) != nil else { shown = value; return }
            shown = "0"
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) { shown = value }
        }
        .onChange(of: value) { newValue in
            withAnimation(Motion.smooth) { shown = newValue }
        }
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
