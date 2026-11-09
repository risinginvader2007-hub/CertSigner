import SwiftUI

/// Review an imported IPA: options + certificate + pre-sign checks → queue the sign job.
struct SignAppSheet: View {
    let app: LibraryApp
    /// Quick Sign: queue immediately with defaults if the pre-sign checks pass.
    var autoStart: Bool = false
    /// Remove the staged IPA if the sheet closes without queuing a job.
    var discardIfUnsigned: Bool = false
    /// Install after signing regardless of the saved "Install when done" setting.
    var installWhenDone: Bool = false

    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SigningQueue
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var importer: ImportCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    @AppStorage(SettingsKeys.autoInstall) private var autoInstall = false

    @State private var certificateID: UUID?
    @State private var options = SigningOptions()
    @State private var keepOriginalBundleID = false
    @State private var prefilled = false
    @State private var installAfter = false
    @State private var showCertificatePicker = false
    /// Per-app override of the Settings signing mode.
    @State private var mode: SigningMode = SigningMode.defaultMode
    /// Passed checks start collapsed; failing / unchecked ones are always open.
    @State private var expandedChecks: Set<String> = []
    /// True once the job is queued (the staged IPA must then be kept).
    @State private var started = false
    @State private var shakes = 0
    @State private var appeared = false

    private var certificate: Certificate? {
        certificates.certificates.first { $0.id == certificateID }
    }

    private var isCompatibility: Bool { mode == .compatibility }

    private var effectiveBundleID: String {
        if isCompatibility || keepOriginalBundleID { return app.bundleID }
        return options.trimmedBundleID.isEmpty ? app.bundleID : options.trimmedBundleID
    }

    private var issues: [SigningIssue] {
        SigningValidator.validate(
            certificate: certificate,
            bundleID: effectiveBundleID,
            originalBundleID: app.bundleID,
            extensionIDs: app.extensions,
            removeExtensions: isCompatibility ? false : options.removeExtensions,
            udid: udid,
            mode: mode
        )
    }

    private var checks: [PreSignCheck] {
        SigningValidator.checks(
            certificate: certificate,
            bundleID: effectiveBundleID,
            originalBundleID: app.bundleID,
            extensionIDs: app.extensions,
            removeExtensions: isCompatibility ? false : options.removeExtensions,
            udid: udid,
            mode: mode
        )
    }

    private var errors: [SigningIssue] { issues.filter { $0.severity == .error } }
    private var hasErrors: Bool { !errors.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.95)
                    if certificates.certificates.isEmpty {
                        noCertificateCard
                    } else {
                        certificateSection
                        checksSection
                        optionsSection
                        if !errors.isEmpty { errorsSection }
                        afterSigningSection
                        PrimaryButton(title: hasErrors ? "Fix the issues above" : "Sign", systemImage: "signature") { start() }
                            .disabled(hasErrors)
                            .shake(shakes)
                    }
                }
                .padding(Theme.padding)
                .animation(Theme.spring, value: checks)
                .animation(Theme.spring, value: keepOriginalBundleID)
                .animation(Theme.spring, value: mode)
            }
            .background(AmbientBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review & Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .modifier(ToastHost(center: toasts))
            .sheet(isPresented: $showCertificatePicker) {
                CertificatePickerSheet(title: "Certificate", selectedID: certificateID) { id in
                    withAnimation(Theme.spring) { certificateID = id }
                }
                .sheetChrome()
            }
        }
        .onAppear {
            prefill()
            withAnimation(Theme.bouncy.delay(0.05)) { appeared = true }
            if autoStart && !started {
                if hasErrors {
                    toasts.show("Quick Sign needs your attention: review the checks.", kind: .warning)
                } else {
                    start()
                }
            }
        }
        .onDisappear {
            if discardIfUnsigned && !started {
                library.delete(app)
            }
        }
        .onChange(of: certificateID) { _ in
            guard prefilled, !keepOriginalBundleID else { return }
            options.bundleID = SigningValidator.suggestedBundleID(appBundleID: app.bundleID, profile: certificate?.profile)
        }
        .onChange(of: keepOriginalBundleID) { keep in
            options.bundleID = keep ? "" : SigningValidator.suggestedBundleID(appBundleID: app.bundleID, profile: certificate?.profile)
            Haptics.selection()
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            AppIconView(image: library.icons[app.id], name: app.name, size: 88)
            Text(app.name)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(app.bundleID)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .identifierText()
            HStack(spacing: 8) {
                StatusBadge(text: "v\(app.version)", kind: .info)
                StatusBadge(text: app.size.byteString, systemImage: "internaldrive", kind: .neutral)
                if !app.extensions.isEmpty {
                    StatusBadge(text: "\(app.extensions.count) ext.", systemImage: "puzzlepiece.extension", kind: .neutral)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var noCertificateCard: some View {
        Card {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal").font(.largeTitle).foregroundColor(accent)
                Text("Add a certificate to sign").font(.headline)
                Text("Import your .p12 and matching profile, then come back to this app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Add Certificate", systemImage: "plus") {
                    dismiss()
                    importer.showCertificateImport = true
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var certificateSection: some View {
        CardSection("Certificate", systemImage: "checkmark.seal") {
            // Row 1: glyph + picker (the name may wrap; the row grows to fit).
            HStack(alignment: .center, spacing: 12) {
                CertificateGlyph(seed: certificate?.nickname ?? "?", size: 40)
                // Opens the certificate sheet (one clean row per certificate) instead of a system menu.
                Button {
                    showCertificatePicker = true
                } label: {
                    HStack(spacing: Space.x2) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(certificate?.displayName ?? "Choose a certificate")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)
                                .identifierText(minimumScale: 0.85)
                            if let certificate {
                                Text(certificate.rawIDLine ?? certificate.typeAndExpiry)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .identifierText()
                            }
                        }
                        Spacer(minLength: Space.x2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Certificate: \(certificate?.displayName ?? "none"). Change")
            }
            // Row 2: badges on their own line, never overlapping the name.
            if let certificate {
                HStack(spacing: 6) {
                    CertificateStatusBadge(status: certificate.status())
                    if let type = certificate.profile?.type {
                        StatusBadge(text: type.rawValue, kind: .neutral)
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // Row 3: App ID on a subtle tonal strip instead of a divider.
            if let profile = certificate?.profile {
                InfoRow(label: "App ID", value: profile.bundleIDPattern)
                    .padding(.horizontal, Space.x3)
                    .padding(.vertical, Space.x2 + 2)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.primary.opacity(0.045)))
                // Raw data as read from the profile, to verify the App ID / wildcard decision.
                ProfileRawDataView(profile: profile, compactEntitlements: true)
                    .padding(.horizontal, Space.x3)
                    .padding(.vertical, Space.x2 + 2)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.primary.opacity(0.03)))
            }
        }
    }

    /// Stepper-style checklist: status icons joined by a rail, rows expand to show their detail.
    private var checksSection: some View {
        CardSection("Pre-sign Checks", systemImage: "checklist") {
            let list = checks
            ForEach(Array(list.enumerated()), id: \.element.id) { index, check in
                let alwaysOpen = check.state != .pass
                let expanded = alwaysOpen || expandedChecks.contains(check.id)
                Button {
                    guard !alwaysOpen else { return }
                    Haptics.selection()
                    withAnimation(Motion.snappy) {
                        if expandedChecks.contains(check.id) { expandedChecks.remove(check.id) } else { expandedChecks.insert(check.id) }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Image(systemName: icon(for: check.state))
                                .font(.title3)
                                .foregroundColor(color(for: check.state))
                                .symbolBounce(value: check.state)
                                .ambientGlow(color(for: check.state), radius: 6, opacity: 0.45)
                                .transition(.scale.combined(with: .opacity))
                                .id("\(check.id)-\(check.state)")
                            if index < list.count - 1 {
                                Capsule()
                                    .fill(LinearGradient(colors: [color(for: check.state).opacity(0.5),
                                                                  color(for: list[index + 1].state).opacity(0.5)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: 2)
                                    .frame(minHeight: 10, maxHeight: .infinity)
                            }
                        }
                        .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(check.title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                Spacer(minLength: 4)
                                if !alwaysOpen {
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .rotationEffect(.degrees(expanded ? 180 : 0))
                                }
                            }
                            if expanded {
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.bottom, index < list.count - 1 ? 8 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityValue(label(for: check.state))
                .accessibilityHint(alwaysOpen ? "" : (expanded ? "Hides details" : "Shows details"))
            }
        }
    }

    private func icon(for state: PreSignCheck.State) -> String {
        switch state {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func color(for state: PreSignCheck.State) -> Color {
        switch state {
        case .pass: return Theme.success
        case .fail: return Theme.danger
        case .unknown: return Theme.warning
        }
    }

    private func label(for state: PreSignCheck.State) -> String {
        switch state {
        case .pass: return "Passed"
        case .fail: return "Failed"
        case .unknown: return "Not checked"
        }
    }

    private var optionsSection: some View {
        CardSection("Signing Options", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Signing mode")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                GlassSegmentedControl(
                    selection: $mode,
                    options: SigningMode.allCases.map { GlassSegmentedControl<SigningMode>.Option(value: $0, title: $0.title) }
                )
                .accessibilityLabel("Signing mode")
                Text(mode.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SoftDivider()
            labeledField("Display name", placeholder: app.name, text: $options.displayName)
            SoftDivider()
            if isCompatibility {
                Label("Keeps the original bundle ID · \(app.bundleID)", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .transition(.opacity)
            } else {
                Toggle(isOn: $keepOriginalBundleID) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep original bundle ID")
                        Text(app.bundleID).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                if !keepOriginalBundleID {
                    labeledField("Bundle ID", placeholder: app.bundleID, text: $options.bundleID)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            SoftDivider()
            labeledField("Version", placeholder: app.version, text: $options.version)
            if !app.extensions.isEmpty {
                SoftDivider()
                if isCompatibility {
                    Label("Keeps all \(app.extensions.count) app extension\(app.extensions.count == 1 ? "" : "s") and signs each one",
                          systemImage: "puzzlepiece.extension")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Toggle(isOn: $options.removeExtensions) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove app extensions")
                            Text("\(app.extensions.count) found (widgets, share extensions…)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            if app.containsWatchApp {
                SoftDivider()
                Toggle("Remove Watch app", isOn: $options.removeWatchApp)
            }
        }
    }

    private var afterSigningSection: some View {
        CardSection("After Signing", systemImage: "arrow.down.app") {
            Toggle(isOn: Binding(
                get: { installAfter },
                set: { installAfter = $0; autoInstall = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install when done")
                    Text("Opens the iOS install prompt as soon as signing finishes")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            GlowTextField(placeholder: placeholder, text: text)
        }
    }

    private var errorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(errors) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(Theme.danger)
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
                .fill(Theme.danger.opacity(0.1))
        )
    }

    // MARK: Actions

    private func prefill() {
        guard !prefilled else { return }
        mode = SigningMode.defaultMode
        certificateID = certificates.activeID ?? certificates.certificates.first?.id
        options.removeExtensions = SettingsKeys.bool(SettingsKeys.defaultRemoveExtensions, default: false) && !app.extensions.isEmpty
        let keep = SettingsKeys.bool(SettingsKeys.defaultKeepBundleID, default: false)
        keepOriginalBundleID = keep
        options.bundleID = keep ? "" : SigningValidator.suggestedBundleID(appBundleID: app.bundleID, profile: certificate?.profile)
        installAfter = autoInstall || installWhenDone
        prefilled = true
    }

    private func start() {
        guard !hasErrors, let certificate else {
            Haptics.error()
            withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            return
        }
        var finalOptions = options
        if keepOriginalBundleID || finalOptions.trimmedBundleID == app.bundleID { finalOptions.bundleID = "" }
        finalOptions.mode = mode
        if mode == .compatibility {
            // No bundle ID override and every extension kept (the worker enforces this too).
            finalOptions.bundleID = ""
            finalOptions.removeExtensions = false
        }
        started = true
        queue.enqueue(app: app, certificateID: certificate.id, options: finalOptions, installWhenDone: installAfter)
        Haptics.impact(.medium)
        toasts.show("Signing \(app.name)…", kind: .info)
        router.attentionOnly = false
        withAnimation(Theme.spring) { router.tab = .library }
        dismiss()
    }
}
