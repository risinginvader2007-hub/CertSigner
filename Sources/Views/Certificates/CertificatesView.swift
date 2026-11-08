import SwiftUI

struct CertificatesView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    @State private var showImport = false
    @State private var pendingDelete: Certificate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if certificates.certificates.isEmpty {
                        EmptyStateView(
                            systemImage: "checkmark.seal",
                            title: "No certificates",
                            message: "Import your .p12 and matching .mobileprovision to start signing apps.",
                            actionTitle: "Import Certificate",
                            action: { showImport = true }
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(certificates.certificates) { certificate in
                            NavigationLink(value: certificate.id) {
                                CertificateCard(certificate: certificate, isActive: certificate.id == certificates.activeID)
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.98))
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
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
            .background(Theme.background.ignoresSafeArea())
            .refreshable { await reload() }
            .navigationTitle("Certificates")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImport = true
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
            .sheet(isPresented: $showImport) {
                ImportCertificateView()
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.nickname ?? "certificate")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let certificate = pendingDelete {
                        certificates.delete(certificate.id)
                        toasts.show("Deleted \(certificate.nickname)", kind: .success)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("The .p12, profile and saved password are removed from this device.")
            }
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
            pendingDelete = certificate
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
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(accent, lineWidth: isActive ? 2 : 0)
                .opacity(isActive ? 1 : 0)
        )
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
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}
