import SwiftUI
import UniformTypeIdentifiers

struct ImportCertificateView: View {
    private enum PickTarget: String {
        case p12, profile

        var allowedExtensions: [String] {
            switch self {
            case .p12: return ["p12", "pfx"]
            case .profile: return ["mobileprovision"]
            }
        }

        var label: String {
            switch self {
            case .p12: return ".p12 certificate"
            case .profile: return ".mobileprovision profile"
            }
        }

        static func forExtension(_ ext: String) -> PickTarget? {
            if PickTarget.p12.allowedExtensions.contains(ext) { return .p12 }
            if PickTarget.profile.allowedExtensions.contains(ext) { return .profile }
            return nil
        }
    }

    private enum Field { case nickname, password }

    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var importer: ImportCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var password = ""
    @State private var revealPassword = false
    @State private var p12: PickedFile?
    @State private var profileFile: PickedFile?
    @State private var profilePreview: ProvisioningProfile?
    @State private var showPicker = false
    @State private var pendingKind: PickTarget = .p12 // never cleared on dismiss
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
                        ) { openPicker(.p12) }
                        Divider()
                        FilePickRow(
                            title: "Provisioning profile",
                            subtitle: profileSubtitle,
                            systemImage: "doc.badge.gearshape.fill",
                            isDone: profilePreview != nil
                        ) { openPicker(.profile) }
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
            .sheet(isPresented: $showPicker) {
                DocumentPicker(
                    contentTypes: [.item],
                    onPick: { url in
                        showPicker = false
                        AppLog.info("Certificate import: [\(pendingKind.rawValue)] delegate: picked \(url.lastPathComponent)")
                        readPicked(url, target: pendingKind)
                    },
                    onCancel: {
                        showPicker = false
                        AppLog.info("Certificate import: [\(pendingKind.rawValue)] delegate: cancelled")
                    }
                )
                .ignoresSafeArea()
            }
            // The sheet covers the root toast overlay, so host toasts here too.
            .modifier(ToastHost(center: toasts))
        }
        .interactiveDismissDisabled(isImporting)
        .onAppear { consumeIncoming() }
        .onChange(of: importer.pendingCertificateFiles.count) { _ in consumeIncoming() }
    }

    private var profileSubtitle: String {
        if let profilePreview {
            var text = profilePreview.name
            if let expiry = profilePreview.expirationDate { text += " · expires \(expiry.shortDate)" }
            return text
        }
        return profileFile?.name ?? "Tap to choose"
    }

    private func openPicker(_ kind: PickTarget) {
        focused = nil
        pendingKind = kind
        AppLog.info("Certificate import: [\(kind.rawValue)] opening picker…")
        showPicker = true
    }

    /// Picker URLs are copies in tmp (asCopy: true), so read directly and clean up.
    private func readPicked(_ url: URL, target: PickTarget) {
        let name = url.lastPathComponent
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let data = try Data(contentsOf: url)
            accept(PickedFile(name: name, data: data), target: target)
        } catch {
            AppLog.info("Certificate import: [\(target.rawValue)] \(name) → read failed: \(error.localizedDescription)")
            fail("Couldn't read \(name): \(error.localizedDescription)")
        }
    }

    /// Files shared into the app via "Open in" / Share → CertSigner.
    private func consumeIncoming() {
        for file in importer.takePendingCertificateFiles() {
            AppLog.info("Certificate import: open-in received \(file.name)")
            guard let target = PickTarget.forExtension(file.pathExtension) else {
                fail("\(file.name) isn't a certificate or profile.")
                continue
            }
            accept(file, target: target)
        }
    }

    private func accept(_ file: PickedFile, target: PickTarget) {
        let ext = file.pathExtension
        guard target.allowedExtensions.contains(ext) else {
            AppLog.info("Certificate import: [\(target.rawValue)] \(file.name) → rejected (extension .\(ext))")
            fail("\(file.name) isn't a \(target.label).")
            return
        }

        errorMessage = nil
        switch target {
        case .p12:
            p12 = file
            AppLog.info("Certificate import: [p12] \(file.name) → OK, \(file.data.count) bytes")
            toasts.show("Certificate file selected", kind: .success)
        case .profile:
            do {
                let parsed = try ProfileParser.parse(data: file.data)
                profileFile = file
                withAnimation(Theme.spring) { profilePreview = parsed }
                if nickname.isEmpty { nickname = parsed.name }
                AppLog.info("Certificate import: [profile] \(file.name) → OK, \(file.data.count) bytes, \"\(parsed.name)\"")
                toasts.show("Profile loaded: \(parsed.name)", kind: .success)
            } catch {
                profileFile = nil
                profilePreview = nil
                AppLog.info("Certificate import: [profile] \(file.name) → parse failed: \(error.localizedDescription)")
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
            AppLog.info("Certificate import: import failed: \(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        toasts.show(message, kind: .error) // also plays the error haptic
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
