import SwiftUI

struct SignedAppDetailView: View {
    let appID: UUID

    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var queue: SigningQueue
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var showInstall = false
    @State private var dissolvingOut = false
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
        .onAppear { withAnimation(Theme.spring.delay(0.05)) { appeared = true } }
    }

    private func content(_ app: SignedApp) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    AppIconView(image: signedApps.icons[app.id], name: app.name, size: 108)
                        .ambientGlow(.black, radius: 20, opacity: 0.25)
                        .scaleEffect(appeared ? 1 : 0.85)
                    
                    Text(app.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(app.bundleID)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
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
                .padding(.vertical, 12)

                CardSection("Details", systemImage: "info.circle") {
                    InfoRow(label: "Certificate", value: app.certificateName)
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

                VStack(spacing: 12) {
                    PrimaryButton(title: "Install", systemImage: "arrow.down.app.fill") { showInstall = true }
                    HStack(spacing: 12) {
                        PrimaryButton(title: "Re-sign", systemImage: "arrow.triangle.2.circlepath", style: .tinted) {
                            resign(app)
                        }
                        ShareLink(item: signedApps.ipaURL(for: app)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
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
        .dissolving(dissolvingOut)
    }

    /// No confirmation: the page dissolves, then the unchanged delete runs and the view pops.
    private func deleteNow(_ app: SignedApp) {
        guard !dissolvingOut else { return }
        Haptics.impact(.light)
        withAnimation(DeleteMotion.dissolve) { dissolvingOut = true }
        Task {
            try? await Task.sleep(nanoseconds: DeleteMotion.dissolveNanoseconds)
            signedApps.delete(app)
            toasts.show("Deleted \(app.name)", kind: .success)
            dismiss()
        }
    }

    private func resign(_ app: SignedApp) {
        guard let active = certificates.active else {
            toasts.show("Add a certificate first.", kind: .warning)
            return
        }
        queue.enqueueResign(app, certificateID: active.id)
        toasts.show("Re-signing \(app.name) with \(active.nickname)", kind: .info)
        dismiss()
    }
}
