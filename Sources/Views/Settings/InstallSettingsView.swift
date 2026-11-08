import SwiftUI

struct InstallSettingsView: View {
    @EnvironmentObject private var serverCertificates: ServerCertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(SettingsKeys.installMethod) private var method: InstallMethod = .automatic

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: $method) {
                    ForEach(InstallMethod.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } header: {
                Text("Install Method")
            } footer: {
                Text(method.detail)
            }

            Section {
                certificateRow(serverCertificates.backloop, source: .backloop)
                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        Label("Update backloop.dev Certificate", systemImage: "arrow.down.circle")
                        if serverCertificates.isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(serverCertificates.isRefreshing)
            } header: {
                Text("Public Certificate")
            } footer: {
                Text("backloop.dev is a public domain that points to 127.0.0.1 and publishes a trusted certificate for it (Feather uses the same). It's free but run by a third party and can lapse.")
            }

            Section {
                if let custom = serverCertificates.custom {
                    certificateRow(custom, source: .custom)
                    Button("Remove My Certificate", role: .destructive) {
                        serverCertificates.removeCustom()
                        toasts.show("Removed your server certificate", kind: .success)
                    }
                }
                NavigationLink {
                    CustomServerCertificateView()
                } label: {
                    Label(serverCertificates.custom == nil ? "Add My Own Certificate" : "Replace My Certificate", systemImage: "key.horizontal")
                }
            } header: {
                Text("Your Own Domain")
            } footer: {
                Text("Most reliable long-term: a hostname you own whose DNS A record is 127.0.0.1, with a trusted certificate (e.g. Let's Encrypt via DNS challenge). Used instead of backloop.dev when valid.")
            }

            Section("If iOS says “Unable to Install”") {
                Text("• Your device UDID isn't in the profile (check Settings → This Device).\n• The certificate was revoked or has expired.\n• An app with the same bundle ID is installed from a different team: delete it first.\n• Not enough free storage.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Install")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refresh() async {
        do {
            let info = try await serverCertificates.refreshBackloop()
            toasts.show("Certificate valid until \(info.notAfter?.shortDate ?? "?")", kind: .success)
        } catch {
            toasts.show(error.localizedDescription, kind: .error)
        }
    }

    @ViewBuilder
    private func certificateRow(_ certificate: ServerCertificate?, source: ServerCertificate.Source) -> some View {
        if let certificate {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(certificate.hostname)
                        .font(.system(.subheadline, design: .monospaced))
                    Spacer()
                    StatusBadge(
                        text: certificate.isValid() ? "Valid" : "Expired",
                        systemImage: certificate.isValid() ? "checkmark.seal.fill" : "xmark.seal.fill",
                        kind: certificate.isValid() ? .success : .danger
                    )
                }
                if let notAfter = certificate.notAfter {
                    Text(notAfter.expiryCountdown())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(source == .backloop ? "Not downloaded yet" : "None")
                .foregroundColor(.secondary)
        }
    }
}

struct CustomServerCertificateView: View {
    private enum Pick { case certificate, key }

    @EnvironmentObject private var serverCertificates: ServerCertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var hostname = ""
    @State private var certificatePEM: String?
    @State private var keyPEM: String?
    @State private var certificateName = ""
    @State private var keyName = ""
    @State private var pick: Pick = .certificate
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var shakes = 0

    var body: some View {
        Form {
            Section {
                TextField("install.example.com", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Hostname")
            } footer: {
                Text("Must resolve to 127.0.0.1 (DNS A record) and be covered by the certificate.")
            }

            Section {
                Button {
                    pick = .certificate
                    showPicker = true
                } label: {
                    row("Certificate chain (PEM)", value: certificatePEM == nil ? "Choose…" : certificateName, done: certificatePEM != nil)
                }
                Button {
                    pick = .key
                    showPicker = true
                } label: {
                    row("Private key (PEM, unencrypted)", value: keyPEM == nil ? "Choose…" : keyName, done: keyPEM != nil)
                }
            } header: {
                Text("Files")
            } footer: {
                Text("Use fullchain.pem (leaf + intermediates) and privkey.pem from certbot / acme.sh. Stored only on this iPhone.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.danger)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("Save Certificate").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
                .disabled(certificatePEM == nil || keyPEM == nil || hostname.isEmpty)
                .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
            }
        }
        .navigationTitle("My Certificate")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentPicker(
                contentTypes: [.item],
                onPick: { url in
                    showPicker = false
                    load(url)
                },
                onCancel: { showPicker = false }
            )
            .ignoresSafeArea()
        }
    }

    private func row(_ title: String, value: String, done: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundColor(.primary)
                Text(value).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                .foregroundColor(done ? Theme.success : .secondary)
        }
    }

    private func load(_ url: URL) {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("-----BEGIN") else {
            fail("\(url.lastPathComponent) isn't a PEM text file.")
            return
        }
        errorMessage = nil
        switch pick {
        case .certificate:
            guard text.contains("BEGIN CERTIFICATE") else { fail("That file has no certificate in it."); return }
            certificatePEM = text
            certificateName = url.lastPathComponent
            if hostname.isEmpty,
               let leaf = TLSIdentityFactory.certificateBlocks(text).first,
               let commonName = DERCertificateParser.parse(leaf)?.commonName {
                hostname = commonName.hasPrefix("*.") ? "local." + commonName.dropFirst(2) : commonName
            }
        case .key:
            guard text.contains("PRIVATE KEY") else { fail("That file has no private key in it."); return }
            guard !text.contains("ENCRYPTED") else { fail("The key is password-protected. Export it unencrypted."); return }
            keyPEM = text
            keyName = url.lastPathComponent
        }
        Haptics.success()
    }

    private func save() {
        guard let certificatePEM, let keyPEM else { return }
        do {
            let info = try serverCertificates.importCustom(certificatePEM: certificatePEM, keyPEM: keyPEM, hostname: hostname)
            toasts.show("Saved: \(info.hostname), valid until \(info.notAfter?.shortDate ?? "?")", kind: .success)
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
