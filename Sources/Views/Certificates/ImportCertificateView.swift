import SwiftUI
import UniformTypeIdentifiers

struct ImportCertificateView: View {
    private enum PickTarget { case p12, profile }
    private enum Field { case nickname, password }

    private struct PickedFile {
        let name: String
        let data: Data
    }

    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var password = ""
    @State private var revealPassword = false
    @State private var p12: PickedFile?
    @State private var profileFile: PickedFile?
    @State private var profilePreview: ProvisioningProfile?
    @State private var picking: PickTarget?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var shakes = 0
    @FocusState private var focused: Field?

    private var canImport: Bool {
        p12 != nil && profileFile != nil && !nickname.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CardSection("Nickname", systemImage: "tag") {
                        TextField("e.g. Personal Dev Cert", text: $nickname)
                            .focused($focused, equals: .nickname)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                    }

                    CardSection("Files", systemImage: "doc.on.doc") {
                        FilePickRow(
                            title: "Certificate (.p12)",
                            subtitle: p12?.name ?? "Tap to choose",
                            systemImage: "key.fill",
                            isDone: p12 != nil
                        ) { picking = .p12 }
                        Divider()
                        FilePickRow(
                            title: "Provisioning profile",
                            subtitle: profileSubtitle,
                            systemImage: "doc.badge.gearshape.fill",
                            isDone: profilePreview != nil
                        ) { picking = .profile }
                    }

                    CardSection("Password", systemImage: "lock.fill") {
                        HStack {
                            Group {
                                if revealPassword {
                                    TextField("p12 password", text: $password)
                                } else {
                                    SecureField("p12 password", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .password)
                            .submitLabel(.done)

                            Button {
                                revealPassword.toggle()
                                Haptics.selection()
                            } label: {
                                Image(systemName: revealPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
                        }
                        Text("Stored in the iOS Keychain on this device only. Leave empty if the .p12 has no password.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    PrimaryButton(title: "Import Certificate", systemImage: "square.and.arrow.down", isLoading: isImporting) {
                        Task { await runImport() }
                    }
                    .disabled(!canImport)
                    .shake(shakes)
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: errorMessage)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Import Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                allowedContentTypes: allowedTypes
            ) { result in
                let target = picking
                picking = nil
                handlePick(result, target: target)
            }
        }
        .interactiveDismissDisabled(isImporting)
    }

    private var profileSubtitle: String {
        if let profilePreview {
            var text = profilePreview.name
            if let expiry = profilePreview.expirationDate { text += " · expires \(expiry.shortDate)" }
            return text
        }
        return profileFile?.name ?? "Tap to choose"
    }

    private var allowedTypes: [UTType] {
        switch picking {
        case .p12: return [.pkcs12, .data]
        case .profile: return [UTType(filenameExtension: "mobileprovision") ?? .data, .data]
        case .none: return [.data]
        }
    }

    private func handlePick(_ result: Result<URL, Error>, target: PickTarget?) {
        guard case .success(let url) = result, let target else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            fail("Couldn't read \(url.lastPathComponent).")
            return
        }
        errorMessage = nil
        switch target {
        case .p12:
            p12 = PickedFile(name: url.lastPathComponent, data: data)
            Haptics.success()
        case .profile:
            do {
                let parsed = try ProfileParser.parse(data: data)
                profileFile = PickedFile(name: url.lastPathComponent, data: data)
                withAnimation(Theme.spring) { profilePreview = parsed }
                if nickname.isEmpty { nickname = parsed.name }
                Haptics.success()
            } catch {
                profileFile = nil
                profilePreview = nil
                fail(error.localizedDescription)
            }
        }
    }

    private func runImport() async {
        guard let p12, let profileFile else { return }
        focused = nil
        isImporting = true
        defer { isImporting = false }
        do {
            let result = try await certificates.importCertificate(
                nickname: nickname,
                p12Data: p12.data,
                profileData: profileFile.data,
                password: password
            )
            if let warning = result.warning {
                toasts.show(warning, kind: .warning)
            } else {
                toasts.show("Imported \(result.certificate.nickname)", kind: .success)
            }
            dismiss()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        Haptics.error()
        withAnimation(.linear(duration: 0.45)) { shakes += 1 }
    }
}

struct FilePickRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isDone: Bool
    let action: () -> Void

    @Environment(\.themeAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundColor(accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundColor(isDone ? Theme.success : .secondary.opacity(0.6))
                    .font(isDone ? .title3 : .footnote.weight(.semibold))
                    .animation(Theme.bouncy, value: isDone)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityLabel("\(title): \(subtitle)")
    }
}
