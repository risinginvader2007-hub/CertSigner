import SwiftUI

struct SignedAppDetailView: View {
    let appID: UUID

    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var queue: SigningQueue
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var showInstall = false
    /// Delete tapped: the page fades a little while it pops back to the list.
    @State private var leaving = false
    /// Shareable copy of this app's signing log (apps signed before logs were saved have none).
    @State private var signingLog: URL?
    @State private var appeared = false

    private var app: SignedApp? { signedApps.apps.first { $0.id == appID } }

    var body: some View {
        Group {
            if let app {
                content(app)
            } else {
                EmptyStateView(systemImage: "trash", title: "App removed", message: "This signed app no longer exists.")
            }
        }
        .background(AmbientBackground())
        .navigationTitle(app?.name ?? "App")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(Theme.spring.delay(0.05)) { appeared = true }
            if let app {
                signingLog = SigningLogStore.shareableCopy(of: SigningLogStore.url(forSignedApp: app.id), appName: app.name)
            }
        }
    }

    private func content(_ app: SignedApp) -> some View {
        ScrollView {
            VStack(spacing: Space.x5) {
                VStack(spacing: Space.x3) {
                    AppIconView(image: signedApps.icons[app.id], name: app.name, size: 108)
                        .ambientGlow(.black, radius: 20, opacity: 0.25)
                        .scaleEffect(appeared ? 1 : 0.85)
                    
                    Text(app.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(app.bundleID)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .identifierText()
                    HStack(spacing: Space.x2) {
                        CertificateStatusBadge(status: app.status())
                        StatusBadge(text: "v\(app.version)", kind: .info)
                    }
                    if let expires = app.expiresAt {
                        Text(expires.expiryCountdown())
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.x3)

                CardSection("Details", systemImage: "info.circle") {
                    InfoRow(label: "Certificate", value: Certificate.friendlyName(app.certificateName))
                    SoftDivider()
                    InfoRow(label: "Signed", value: app.signedAt.formatted(date: .abbreviated, time: .shortened))
                    SoftDivider()
                    InfoRow(label: "Size", value: app.size.byteString)
                    if let expires = app.expiresAt {
                        SoftDivider()
                        InfoRow(label: "Expires", value: expires.shortDate)
                    }
                    SoftDivider()
                    InfoRow(label: "Bundle ID", value: app.bundleID, copyable: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

                VStack(spacing: Space.x3) {
                    PrimaryButton(title: "Install", systemImage: "arrow.down.app.fill") { showInstall = true }
                    HStack(spacing: Space.x3) {
                        PrimaryButton(title: "Re-sign", systemImage: "arrow.triangle.2.circlepath", style: .tinted) {
                            resign(app)
                        }
                        ShareLink(item: signedApps.ipaURL(for: app)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.app(.secondary))
                    }
                    if let signingLog {
                        ShareLink(item: signingLog) {
                            Label("Share signing log", systemImage: "doc.text")
                        }
                        .buttonStyle(.app(.secondary))
                    }
                    PrimaryButton(title: "Delete", systemImage: "trash", style: .tinted) { deleteNow(app) }
                        .environment(\.themeAccent, Theme.danger)
                }
            }
            .padding(Theme.padding)
        }
        .sheet(isPresented: $showInstall) {
            InstallSheet(app: app).sheetChrome()
        }
        .opacity(leaving ? 0.6 : 1)
        .allowsHitTesting(!leaving)
    }

    /// No confirmation: pop back to the list first (normal transition, Back stays visible), then the
    /// list plays the shared row animation and removes the app. Falls back to a plain removal if
    /// no list shows it.
    private func deleteNow(_ app: SignedApp) {
        guard !leaving else { return }
        withAnimation(.easeOut(duration: 0.2)) { leaving = true }
        dismiss()
        let store = signedApps
        let toastCenter = toasts
        RowDeleteRequests.shared.request(app.id) {
            withAnimation(DeleteMotion.collapse) {
                LibraryView.deleteWithUndo(app, signedApps: store, toasts: toastCenter)
            }
        }
    }

    private func resign(_ app: SignedApp) {
        guard let active = certificates.active else {
            toasts.show("Add a certificate first.", kind: .warning)
            return
        }
        queue.enqueueResign(app, certificateID: active.id)
        toasts.show("Re-signing \(app.name) with \(active.displayName)", kind: .info)
        dismiss()
    }
}
