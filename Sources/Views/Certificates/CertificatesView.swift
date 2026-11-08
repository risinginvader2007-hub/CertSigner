import SwiftUI

struct CertificatesView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var importer: ImportCoordinator
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    /// Cards currently playing the delete dissolve.
    @State private var deleting: Set<UUID> = []
    @State private var appeared = false

    /// Pushed from Settings / Home, so no NavigationStack of its own.
    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 12) {
                    if certificates.certificates.isEmpty {
                        EmptyStateView(
                            systemImage: "checkmark.seal",
                            title: "No certificates",
                            message: "Import your .p12 and matching .mobileprovision to start signing apps.",
                            actionTitle: "Import Certificate",
                            action: { importer.showCertificateImport = true }
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(Array(certificates.certificates.enumerated()), id: \.element.id) { index, certificate in
                            NavigationLink(value: certificate.id) {
                                CertificateCard(certificate: certificate, isActive: certificate.id == certificates.activeID)
                            }
                            .staggeredEntrance(index, active: appeared)
                            .dissolving(deleting.contains(certificate.id))
                            .buttonStyle(PressableButtonStyle(scale: 0.98))
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .identity))
                            .contextMenu { menu(for: certificate) }
                        }
                        if udid.isEmpty {
                            hint
                        }
                    }
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: certificates.certificates.map(\.id))
                .animation(Theme.spring, value: certificates.activeID)
            }
            .background(AuroraBackground(intensity: 0.6))
            .refreshable { await reload() }
            .onAppear { appeared = true }
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        importer.showCertificateImport = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                    }
                    .accessibilityLabel("Import certificate")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CertificateDetailView(certificateID: id)
            }
        }
    }

    /// No confirmation: the card dissolves, then the unchanged delete runs and the cards below slide up.
    private func dissolveDelete(_ certificate: Certificate) {
        guard !deleting.contains(certificate.id) else { return }
        Haptics.impact(.light)
        withAnimation(DeleteMotion.dissolve) { _ = deleting.insert(certificate.id) }
        Task {
            try? await Task.sleep(nanoseconds: DeleteMotion.dissolveNanoseconds)
            withAnimation(Motion.smooth) { certificates.delete(certificate.id) }
            toasts.show("Deleted \(certificate.nickname)", kind: .success)
            deleting.remove(certificate.id)
        }
    }

    private func reload() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        certificates.reload()
    }

    @ViewBuilder
    private func menu(for certificate: Certificate) -> some View {
        if certificate.id != certificates.activeID {
            Button {
                certificates.setActive(certificate.id)
                toasts.show("\(certificate.nickname) is now active", kind: .success)
            } label: {
                Label("Set as Active", systemImage: "star")
            }
        }
        Button(role: .destructive) {
            dissolveDelete(certificate)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.gen3")
                .foregroundColor(.secondary)
            Text("Add your device UDID in Settings to check whether this iPhone is included in each profile.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct CertificateStatusBadge: View {
    let status: CertificateStatus

    var body: some View {
        StatusBadge(text: status.title, systemImage: status.systemImage, kind: kind)
    }

    private var kind: StatusBadge.Kind {
        switch status {
        case .valid: return .success
        case .expiringSoon: return .warning
        case .expired: return .danger
        case .unknown: return .neutral
        }
    }
}

struct CertificateCard: View {
    let certificate: Certificate
    let isActive: Bool

    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient

    private var lifetimeRemaining: Double? {
        guard let start = certificate.profile?.creationDate,
              let end = certificate.expirationDate, end > start else { return nil }
        let total = end.timeIntervalSince(start)
        return min(max(end.timeIntervalSinceNow / total, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CertificateGlyph(seed: certificate.nickname, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(certificate.nickname)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(certificate.profile?.teamName ?? "Profile unreadable")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        CertificateStatusBadge(status: certificate.status())
                        if let type = certificate.profile?.type {
                            StatusBadge(text: type.rawValue, kind: .neutral)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 4)
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isActive ? accent : .secondary.opacity(0.4))
                    .symbolReplace()
                    .symbolBounce(value: isActive)
                    .ambientGlow(isActive ? accent : .clear, radius: 8, opacity: 0.5)
                    .scaleEffect(isActive ? 1 : 0.85)
                    .accessibilityHidden(true)
            }

            if let expiration = certificate.expirationDate {
                VStack(alignment: .leading, spacing: 6) {
                    if let lifetimeRemaining {
                        ProgressBar(progress: lifetimeRemaining, height: 6, color: barColor)
                    }
                    Text(expiration.expiryCountdown())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(Theme.padding)
        .modifier(CardSurface(cornerRadius: Theme.corner, glow: isActive ? accent : nil))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: isActive ? 2 : 0)
                .opacity(isActive ? 1 : 0)
        )
        .background(alignment: .top) {
            // Card-stack depth: a tinted sheet peeking out behind the active card.
            if isActive {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(colors: gradient.map { $0.opacity(0.35) }, startPoint: .leading, endPoint: .trailing))
                    .padding(.horizontal, Space.x3)
                    .offset(y: 7)
                    .transition(.opacity)
            }
        }
        .scaleEffect(isActive ? 1 : 0.985)
        .padding(.bottom, isActive ? 6 : 0)
        .animation(Motion.bouncy, value: isActive)
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(certificate.nickname), \(certificate.status().title)\(isActive ? ", active" : "")")
    }

    private var barColor: Color {
        switch certificate.status() {
        case .valid: return Theme.success
        case .expiringSoon: return Theme.warning
        case .expired, .unknown: return Theme.danger
        }
    }
}

struct CertificateGlyph: View {
    let seed: String
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: Theme.palette(for: seed), startPoint: .topLeading, endPoint: .bottomTrailing))
            // Glossy top highlight
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}
