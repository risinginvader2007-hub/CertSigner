import SwiftUI

struct SignedAppsView: View {
    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @State private var pendingDelete: SignedApp?
    @State private var installTarget: SignedApp?

    private var visibleApps: [SignedApp] {
        router.attentionOnly ? signedApps.apps.filter { $0.needsAttention() } : signedApps.apps
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if router.attentionOnly {
                        HStack {
                            Label("Showing expiring and expired apps", systemImage: "line.3.horizontal.decrease.circle.fill")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                withAnimation(Theme.spring) { router.attentionOnly = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3)
                            }
                            .accessibilityLabel("Show all apps")
                        }
                        .foregroundColor(Theme.warning)
                        .padding(12)
                        .background(Capsule().fill(Theme.warning.opacity(0.12)))
                    }
                    if visibleApps.isEmpty {
                        EmptyStateView(
                            systemImage: "signature",
                            title: "Nothing signed yet",
                            message: "Open an app in your Library and tap Sign. Signed IPAs show up here with the certificate used and an expiry countdown."
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(visibleApps) { app in
                            SignedAppRow(app: app, icon: signedApps.icons[app.id], fileURL: signedApps.ipaURL(for: app)) {
                                installTarget = app
                            }
                                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                                .contextMenu {
                                    Button {
                                        installTarget = app
                                    } label: {
                                        Label("Install", systemImage: "arrow.down.app")
                                    }
                                    ShareLink(item: signedApps.ipaURL(for: app)) {
                                        Label("Share IPA", systemImage: "square.and.arrow.up")
                                    }
                                    Button {
                                        UIPasteboard.general.string = app.bundleID
                                        toasts.show("Bundle ID copied", kind: .success)
                                    } label: {
                                        Label("Copy Bundle ID", systemImage: "doc.on.doc")
                                    }
                                    Button(role: .destructive) {
                                        pendingDelete = app
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: signedApps.apps.map(\.id))
            }
            .background(Theme.background.ignoresSafeArea())
            .refreshable { await reload() }
            .navigationTitle("Library")
            .floatingTabBarInset()
            .sheet(item: $installTarget) { app in
                InstallSheet(app: app)
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "app")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let app = pendingDelete {
                        signedApps.delete(app)
                        toasts.show("Deleted \(app.name)", kind: .success)
                    }
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
}

struct SignedAppRow: View {
    let app: SignedApp
    let icon: UIImage?
    let fileURL: URL
    var onInstall: () -> Void = {}

    private var status: CertificateStatus { CertificateStatus.evaluate(expiration: app.expiresAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AppIconView(image: icon, name: app.name, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("v\(app.version) · \(app.size.byteString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 6)
                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .accessibilityLabel("Share \(app.name) IPA")
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("\(app.certificateName) · \(app.signedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                CertificateStatusBadge(status: status)
            }
            if let expires = app.expiresAt {
                Text(expires.expiryCountdown())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            PrimaryButton(title: "Install", systemImage: "arrow.down.app", style: .tinted, action: onInstall)
        }
        .padding(Theme.padding)
        .cardBackground()
        .accessibilityElement(children: .contain)
    }
}
