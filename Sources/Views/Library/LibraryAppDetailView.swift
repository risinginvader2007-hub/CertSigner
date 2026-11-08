import SwiftUI

struct LibraryAppDetailView: View {
    let app: LibraryApp

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent

    @State private var showSigning = false
    @State private var confirmDelete = false
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                CardSection("Information", systemImage: "info.circle") {
                    InfoRow(label: "Bundle ID", value: app.bundleID, copyable: true)
                    Divider()
                    InfoRow(label: "Version", value: app.version)
                    Divider()
                    InfoRow(label: "Build", value: app.build)
                    Divider()
                    InfoRow(label: "Size", value: app.size.byteString)
                    if let minimumOS = app.minimumOS {
                        Divider()
                        InfoRow(label: "Minimum iOS", value: minimumOS)
                    }
                    Divider()
                    InfoRow(label: "Added", value: app.dateAdded.shortDate)
                }

                CardSection("Signing", systemImage: "signature") {
                    if let active = certificates.active {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundColor(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(active.nickname).font(.subheadline.weight(.semibold))
                                Text(active.profile?.teamName ?? "Unknown team")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            CertificateStatusBadge(status: active.status())
                        }
                    } else {
                        Button {
                            router.tab = .certificates
                        } label: {
                            Label("Add a certificate to sign apps", systemImage: "plus.circle")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }

                VStack(spacing: 12) {
                    PrimaryButton(title: "Sign App", systemImage: "signature") {
                        showSigning = true
                    }
                    PrimaryButton(title: "Delete from Library", systemImage: "trash", style: .tinted) {
                        confirmDelete = true
                    }
                    .tint(Theme.danger)
                    .environment(\.themeAccent, Theme.danger)
                }
                .padding(.top, 4)
            }
            .padding(Theme.padding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSigning) {
            SigningPreviewSheet(app: app)
        }
        .confirmationDialog("Delete \(app.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.delete(app)
                toasts.show("Deleted \(app.name)", kind: .success)
                dismiss()
            }
        }
        .onAppear {
            withAnimation(Theme.spring.delay(0.05)) { appeared = true }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            AppIconView(name: app.name, size: 104)
            VStack(spacing: 4) {
                Text(app.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(app.bundleID)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                StatusBadge(text: "v\(app.version)", kind: .info)
                StatusBadge(text: app.size.byteString, systemImage: "internaldrive", kind: .neutral)
                if app.isSample {
                    StatusBadge(text: "Demo", systemImage: "sparkles", kind: .warning)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            LinearGradient(colors: Theme.palette(for: app.name).map { $0.opacity(0.18) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner + 4, style: .continuous))
        )
    }
}
