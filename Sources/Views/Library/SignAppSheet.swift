import SwiftUI

/// Options → validation → live signing progress → result.
struct SignAppSheet: View {
    let app: LibraryApp
    /// Quick Sign: start immediately with defaults if the pre-sign checks pass.
    var autoStart: Bool = false
    /// Remove the staged IPA if the sheet closes without a successful sign.
    var discardIfUnsigned: Bool = false

    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""

    @StateObject private var job = SigningJob()
    @State private var certificateID: UUID?
    @State private var options = SigningOptions()
    @State private var started = false
    @State private var shakes = 0
    @State private var installTarget: SignedApp?

    private var certificate: Certificate? {
        certificates.certificates.first { $0.id == certificateID }
    }

    private var effectiveBundleID: String {
        options.trimmedBundleID.isEmpty ? app.bundleID : options.trimmedBundleID
    }

    private var issues: [SigningIssue] {
        SigningValidator.validate(
            certificate: certificate,
            bundleID: effectiveBundleID,
            originalBundleID: app.bundleID,
            extensionIDs: app.extensions,
            removeExtensions: options.removeExtensions,
            udid: udid
        )
    }

    private var hasErrors: Bool { issues.contains { $0.severity == .error } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if started {
                        SigningProgressView(
                            currentStep: job.step,
                            progress: job.progress,
                            log: job.log,
                            result: job.result,
                            failureMessage: job.errorMessage
                        )
                        if job.result != nil { resultActions }
                    } else {
                        certificateSection
                        optionsSection
                        if !issues.isEmpty { issuesSection }
                        PrimaryButton(title: "Sign", systemImage: "signature") { start() }
                            .disabled(hasErrors)
                            .shake(shakes)
                    }
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: started)
                .animation(Theme.spring, value: issues)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Sign App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(job.result == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(job.isRunning)
                }
            }
            .modifier(ToastHost(center: toasts))
        }
        .interactiveDismissDisabled(job.isRunning)
        .sheet(item: $installTarget) { app in
            InstallSheet(app: app)
        }
        .onAppear {
            prefill()
            if autoStart && !started {
                if hasErrors {
                    toasts.show("Quick Sign needs your attention: review the issues below.", kind: .warning)
                } else {
                    start()
                }
            }
        }
        .onDisappear {
            if discardIfUnsigned && job.result != .success && !job.isRunning {
                library.delete(app)
            }
        }
        .onChange(of: certificateID) { _ in
            options.bundleID = SigningValidator.suggestedBundleID(appBundleID: app.bundleID, profile: certificate?.profile)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView(image: library.icons[app.id], name: app.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text("\(app.bundleID) · v\(app.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var certificateSection: some View {
        CardSection("Certificate", systemImage: "checkmark.seal") {
            Picker("Certificate", selection: $certificateID) {
                ForEach(certificates.certificates) { cert in
                    Text(cert.nickname).tag(Optional(cert.id))
                }
            }
            .pickerStyle(.menu)
            if let certificate {
                HStack(spacing: 8) {
                    CertificateStatusBadge(status: certificate.status())
                    if let type = certificate.profile?.type {
                        StatusBadge(text: type.rawValue, kind: .neutral)
                    }
                    Spacer()
                }
                if let profile = certificate.profile {
                    InfoRow(label: "App ID", value: profile.bundleIDPattern, monospaced: true)
                }
            }
        }
    }

    private var optionsSection: some View {
        CardSection("Changes (optional)", systemImage: "slider.horizontal.3") {
            labeledField("Display name", placeholder: app.name, text: $options.displayName)
            Divider()
            labeledField("Bundle ID", placeholder: app.bundleID, text: $options.bundleID, monospaced: true)
            Divider()
            labeledField("Version", placeholder: app.version, text: $options.version)
            if !app.extensions.isEmpty {
                Divider()
                Toggle(isOn: $options.removeExtensions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove app extensions")
                        Text("\(app.extensions.count) found (widgets, share extensions…)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if app.containsWatchApp {
                Divider()
                Toggle("Remove Watch app", isOn: $options.removeWatchApp)
            }
        }
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(issue.severity == .error ? Theme.danger : Theme.warning)
                    Text(issue.message)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill((hasErrors ? Theme.danger : Theme.warning).opacity(0.1))
        )
    }

    @ViewBuilder
    private var resultActions: some View {
        VStack(spacing: 12) {
            if job.result == .success, let signed = job.signedApp {
                PrimaryButton(title: "Install Now", systemImage: "arrow.down.app") {
                    installTarget = signed
                }
                ShareLink(item: signedApps.ipaURL(for: signed)) {
                    Label("Share Signed IPA", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                PrimaryButton(title: "View in Library", systemImage: "square.stack.3d.up", style: .tinted) {
                    router.attentionOnly = false
                    router.tab = .library
                    dismiss()
                }
            } else {
                PrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                    withAnimation(Theme.spring) {
                        job.reset()
                        started = false
                    }
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    private func prefill() {
        guard certificateID == nil else { return }
        certificateID = certificates.activeID ?? certificates.certificates.first?.id
        options.bundleID = SigningValidator.suggestedBundleID(appBundleID: app.bundleID, profile: certificate?.profile)
    }

    private func start() {
        guard !hasErrors, let certificate else {
            Haptics.error()
            withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            return
        }
        var finalOptions = options
        if finalOptions.trimmedBundleID == app.bundleID { finalOptions.bundleID = "" }
        let password = certificates.password(for: certificate.id) ?? ""
        withAnimation(Theme.spring) { started = true }
        Task {
            await job.run(
                app: app,
                ipaURL: library.ipaURL(for: app),
                iconURL: library.iconURL(for: app),
                certificate: certificate,
                p12URL: certificates.p12URL(for: certificate.id),
                profileURL: certificates.profileURL(for: certificate.id),
                password: password,
                options: finalOptions,
                store: signedApps
            )
            if job.result == .success {
                toasts.show("Signed \(job.signedApp?.name ?? app.name)", kind: .success)
            }
        }
    }
}
