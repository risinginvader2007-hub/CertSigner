import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SigningQueue
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.accent) private var accent: AccentOption = .aurora
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    @AppStorage(SettingsKeys.installMethod) private var installMethod: InstallMethod = .automatic
    @AppStorage(SettingsKeys.autoInstall) private var autoInstall = false
    @AppStorage(SettingsKeys.autoCloseInstall) private var autoCloseInstall = true
    @AppStorage(SettingsKeys.signingMode) private var signingMode: SigningMode = .compatibility
    @AppStorage(SettingsKeys.backgroundAnimation) private var backgroundAnimation = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCertificatePicker = false
    @AppStorage(SettingsKeys.deleteOriginal) private var deleteOriginal = true
    @AppStorage(SettingsKeys.defaultRemoveExtensions) private var defaultRemoveExtensions = false
    @AppStorage(SettingsKeys.defaultKeepBundleID) private var defaultKeepBundleID = false

    @EnvironmentObject private var signedApps: SignedAppsStore
    @ObservedObject private var storageModel = StorageModel.shared
    @Environment(\.themeAccent) private var accentColor
    @State private var logURL: URL?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                certificatesSection.listRowBackground(RowSurface())
                signingSection.listRowBackground(RowSurface())
                installSection.listRowBackground(RowSurface())
                deviceSection.listRowBackground(RowSurface())
                appearanceSection.listRowBackground(RowSurface())
                storageSection.listRowBackground(RowSurface())
                logSection.listRowBackground(RowSurface())
                aboutSection.listRowBackground(RowSurface())
                }
                .softRowSeparators()
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground(intensity: 0.5))
            .navigationTitle("Settings")
            .onAppear { refreshStorage() }
            .refreshable { refreshStorage() }
        }
    }

    // MARK: Certificates

    private var certificatesSection: some View {
        Section {
            NavigationLink {
                CertificatesView()
            } label: {
                HStack(spacing: Space.x3) {
                    CertificateGlyph(seed: certificates.active?.nickname ?? "none", size: 34)
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(certificates.active?.displayName ?? "No active certificate")
                            .font(.body.weight(.semibold))
                            .identifierText(minimumScale: 0.85)
                        Text("\(certificates.certificates.count) certificate\(certificates.certificates.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let active = certificates.active {
                        CertificateStatusBadge(status: active.status())
                    }
                }
            }
            if certificates.certificates.count > 1 {
                // Same bottom sheet as Home's "Switch" (long certificate names don't fit a menu).
                Button {
                    showCertificatePicker = true
                } label: {
                    HStack {
                        Text("Active")
                            .foregroundColor(.primary)
                        Spacer(minLength: Space.x3)
                        Text(certificates.active?.displayName ?? "None")
                            .foregroundColor(.secondary)
                            .identifierText()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .sheet(isPresented: $showCertificatePicker) {
                    CertificatePickerSheet(title: "Active Certificate", selectedID: certificates.activeID) { id in
                        certificates.setActive(id)
                        Haptics.success()
                    }
                    .sheetChrome()
                }
            }
            Button {
                importer.showCertificateImport = true
            } label: {
                Label("Add Certificate", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Certificates")
        } footer: {
            Text("Open Certificates to see details, rename or delete.")
        }
    }

    // MARK: Signing

    private var signingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.x2) {
                Label("Signing mode", systemImage: "signature")
                SlidingSegmentedControl(
                    selection: $signingMode,
                    options: SigningMode.allCases.map { .init(value: $0, title: $0.title) },
                    accessibilityTitle: "Signing mode"
                )
                Text(signingMode.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Space.x1)
            Toggle(isOn: $autoInstall) {
                Label("Install after signing", systemImage: "arrow.down.app")
            }
            Toggle(isOn: $deleteOriginal) {
                Label("Delete original IPA after signing", systemImage: "trash")
            }
            Toggle(isOn: $defaultRemoveExtensions) {
                Label("Remove app extensions by default", systemImage: "puzzlepiece.extension")
            }
            Toggle(isOn: $defaultKeepBundleID) {
                Label("Keep original bundle ID by default", systemImage: "number")
            }
        } header: {
            Text("Signing")
        } footer: {
            Text("Applies to every signing job (Quick Sign, Sources, re-sign); the review sheet can override it per app. The bundle-ID and extension defaults apply in Strict mode.")
        }
        .onChange(of: autoInstall) { _ in Haptics.selection() }
        .onChange(of: deleteOriginal) { _ in Haptics.selection() }
    }

    private var installSection: some View {
        Section("Install") {
            NavigationLink {
                InstallSettingsView()
            } label: {
                HStack {
                    Label("Install Method & Server", systemImage: "server.rack")
                    Spacer()
                    Text(installMethod.title)
                        .foregroundColor(.secondary)
                }
            }
            Toggle(isOn: $autoCloseInstall) {
                Label("Close install sheet automatically", systemImage: "checkmark.rectangle.stack")
            }
            .onChange(of: autoCloseInstall) { _ in Haptics.selection() }
        }
    }

    private var deviceSection: some View {
        Section {
            TextField("Paste your UDID", text: $udid)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if !udid.isEmpty {
                Button("Clear UDID", role: .destructive) { udid = "" }
            }
        } header: {
            Text("This Device")
        } footer: {
            Text("Sideloaded apps can't read the UDID. Copy it from a computer (Finder or 3uTools), then paste it here. It's only used to check this iPhone is in your profiles.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            // Sliding segmented control; the switch cross-fades the whole screen (no white / black flash).
            SlidingSegmentedControl(
                selection: Binding(
                    get: { appearance },
                    set: { newValue in
                        AppearanceCrossfade.run(reduceMotion: reduceMotion) { appearance = newValue }
                    }
                ),
                options: AppearanceOption.allCases.map { option in
                    .init(value: option, title: option.title, systemImage: option.systemImage)
                },
                accessibilityTitle: "Appearance"
            )
            .padding(.vertical, Space.x1)

            VStack(alignment: .leading, spacing: Space.x3) {
                Text("Accent colour")
                AccentPicker(selection: $accent)
            }
            .padding(.vertical, Space.x1)

            Toggle(isOn: $backgroundAnimation) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text("Background animation")
                    Text("Slowly drifting colour glows behind every screen. Pauses automatically with Reduce Motion; runs at a lower frame rate in Low Power Mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: Space.x3) {
                Text("App icon")
                AppIconPicker()
            }
            .padding(.vertical, Space.x1)
        }
    }

    // MARK: Storage

    /// Imported IPAs no signing job still needs.
    private var unusedImportIDs: Set<String> {
        let pending = Set(queue.tasks.compactMap { task -> UUID? in
            if case .library(let id) = task.source { return id }
            return nil
        })
        return Set(library.apps.filter { !pending.contains($0.id) }.map(\.id.uuidString))
    }

    private func bytes(_ entries: [StorageEntry]) -> Int64 { entries.reduce(0) { $0 + $1.bytes } }

    private var cacheBytes: Int64 { storageModel.report?.bytes(.cache) ?? 0 }
    private var unusedImportBytes: Int64 {
        let unused = unusedImportIDs
        return bytes(storageModel.report?.entries(.imports).filter { unused.contains($0.key) } ?? [])
    }
    private var appLogBytes: Int64 {
        bytes(storageModel.report?.entries(.logs).filter { $0.name == "App log" } ?? [])
    }
    /// Cache + unused imported IPAs + logs older than 30 days.
    private var reclaimableBytes: Int64 {
        cacheBytes + unusedImportBytes + bytes(storageModel.report?.oldLogs ?? [])
    }

    private var storageSection: some View {
        Section {
            StorageSummaryCard(report: storageModel.report, calculating: storageModel.calculating,
                               reclaimable: reclaimableBytes, onRefresh: refreshStorage)
            if let report = storageModel.report {
                ForEach(StorageCategory.allCases) { category in
                    NavigationLink {
                        StorageCategoryView(category: category)
                    } label: {
                        StorageCategoryRow(category: category, report: report)
                    }
                }
                storageExtras(report)
            } else {
                LoadingSkeleton(rows: 5)
                    .padding(.vertical, Space.x1)
            }
            storageAction(title: "Clear Cache", systemImage: "sparkles", bytes: cacheBytes, tint: nil) {
                let freed = cacheBytes
                CacheService.clear()
                finishStorageAction(freed: freed)
            }
            storageAction(title: "Remove Unused IPAs", systemImage: "trash", bytes: unusedImportBytes, tint: Theme.danger) {
                let freed = unusedImportBytes
                withAnimation(Motion.smooth) { removeUnusedImports() }
                finishStorageAction(freed: freed)
            }
        } header: {
            Text("Storage")
        }
    }

    /// A full-width action in the shared button style that says how much it frees.
    private func storageAction(title: String, systemImage: String, bytes: Int64, tint: Color?,
                               action: @escaping () -> Void) -> some View {
        PrimaryButton(title: bytes > 0 ? "\(title) · \(StorageService.format(bytes))" : "\(title) · Nothing to clear",
                      systemImage: systemImage, style: .tinted, action: action)
            .disabled(bytes <= 0 || storageModel.report == nil)
            .environment(\.themeAccent, tint ?? accentColor)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.x1, leading: 0, bottom: Space.x1, trailing: 0))
    }

    @ViewBuilder
    private func storageExtras(_ report: StorageReport) -> some View {
        let tips = storageTips(report)
        if !tips.isEmpty || report.oldestSignedApp != nil || report.largestItem != nil {
            VStack(alignment: .leading, spacing: Space.x2) {
                ForEach(tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb.fill")
                        .font(TypeScale.caption)
                        .foregroundColor(SemanticColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let largest = report.largestItem {
                    Label("Largest item: \(largest.name) · \(StorageService.format(largest.bytes))", systemImage: "arrow.up.circle")
                        .font(TypeScale.caption)
                        .foregroundColor(SemanticColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let oldest = report.oldestSignedApp, let date = oldest.date {
                    Label("Oldest signed app: \(oldest.name) · \(date.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "clock")
                        .font(TypeScale.caption)
                        .foregroundColor(SemanticColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, Space.x1)
        }
    }

    private func storageTips(_ report: StorageReport) -> [String] {
        var tips: [String] = []
        if report.bytes(.cache) > 50 * 1_000_000 {
            tips.append("The cache is over 50 MB. Clearing it is safe; files are recreated when needed.")
        }
        if report.bytes(.logs) > 10 * 1_000_000 {
            tips.append("Logs are over 10 MB. Export them below if you need them, then clear them.")
        }
        return tips
    }

    private func finishStorageAction(freed: Int64) {
        Haptics.impact(.light)
        toasts.show(freed > 0 ? "Freed \(StorageService.format(freed))" : "Nothing to clear", kind: .success)
        refreshStorage()
    }

    private func refreshStorage() {
        storageModel.refresh(signedApps: signedApps, library: library, certificates: certificates)
    }

    private func removeUnusedImports() {
        let pending = Set(queue.tasks.compactMap { task -> UUID? in
            if case .library(let id) = task.source { return id }
            return nil
        })
        let unused = library.apps.filter { !pending.contains($0.id) }
        unused.forEach { library.delete($0) }
    }

    // MARK: Log

    private var logSection: some View {
        Section {
            if let logURL {
                ShareLink(item: logURL) {
                    Label("Export Log File", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Preparing log…", systemImage: "doc.text")
                    .foregroundColor(.secondary)
            }
            storageAction(title: "Clear Log", systemImage: "trash", bytes: appLogBytes, tint: Theme.danger) {
                let freed = appLogBytes
                AppLog.clear()
                finishStorageAction(freed: freed)
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    logURL = AppLog.exportCopy()
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("The log records imports, signing and install events. It never contains passwords.")
        }
        .task { logURL = AppLog.exportCopy() }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundColor(.secondary)
            }
            if let url = URL(string: "https://github.com/risinginvader2007-hub/CertSigner") {
                Link(destination: url) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Built with zsign (MIT), OpenSSL and ZIPFoundation.")
                Text("CertSigner signs apps with your own certificates for your own devices.")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        } header: {
            Text("About")
        }
    }
}

/// Accent swatches. One selection ring slides from the old swatch to the new one
/// (matchedGeometryEffect follower driven by local state, so it animates with @AppStorage too).
struct AccentPicker: View {
    @Binding var selection: AccentOption

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var shown: AccentOption?

    private var current: AccentOption { shown ?? selection }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x3) {
                ForEach(AccentOption.allCases) { option in
                    let selected = current == option
                    Button {
                        guard option != selection else { return }
                        Haptics.selection()
                        withAnimation(reduceMotion ? Motion.fade : Motion.selection) {
                            shown = option
                            selection = option
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: option.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 32)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .scaleEffect(selected ? 1 : 0.4)
                                .opacity(selected ? 1 : 0)
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(Color.clear).frame(width: 42, height: 42)
                                .matchedGeometryEffect(id: option, in: namespace, properties: .frame, isSource: true)
                        )
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.85))
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .background {
                Circle()
                    .strokeBorder(current.color, lineWidth: 2.5)
                    .matchedGeometryEffect(id: current, in: namespace, properties: .frame, isSource: false)
            }
            .padding(.vertical, Space.hair)
        }
        .onChange(of: selection) { newValue in
            guard shown != newValue else { return }
            withAnimation(reduceMotion ? Motion.fade : Motion.selection) { shown = newValue }
        }
    }
}

/// Alternate app icons declared in the asset catalog (see project.yml).
struct AppIconPicker: View {
    private struct Option: Identifiable {
        let id: String
        let title: String
        /// nil = primary icon.
        let iconName: String?
        let preview: String
    }

    private let options = [
        Option(id: "default", title: "Ocean", iconName: nil, preview: "IconPreview-Default"),
        Option(id: "sunset", title: "Sunset", iconName: "AppIcon-Sunset", preview: "IconPreview-Sunset"),
        Option(id: "mint", title: "Mint", iconName: "AppIcon-Mint", preview: "IconPreview-Mint"),
        Option(id: "midnight", title: "Midnight", iconName: "AppIcon-Midnight", preview: "IconPreview-Midnight")
    ]

    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ringSpace
    @State private var current: String?
    /// The ring only animates for real changes, not when the current icon is first read.
    @State private var ready = false

    private var currentOption: Option {
        options.first { $0.iconName == current } ?? options[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            // Live preview: the chosen icon as it sits on the Home Screen.
            HStack(spacing: Space.x4) {
                Image(currentOption.preview)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.75))
                    .ambientGlow(accent, radius: 14, opacity: 0.35)
                    .id(currentOption.id)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text("CertSigner").font(.subheadline.weight(.semibold))
                    Text("\(currentOption.title) icon").font(.caption).foregroundColor(.secondary)
                }
            }
            .animation(Motion.bouncy, value: current)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current icon: \(currentOption.title)")
            picker
        }
        .onAppear {
            current = UIApplication.shared.alternateIconName
            DispatchQueue.main.async { ready = true }
        }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x4) {
                ForEach(options) { option in
                    let selected = current == option.iconName
                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: Space.x2) {
                            Image(option.preview)
                                .resizable()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                                .background(
                                    // Where the single sliding ring sits when this icon is selected.
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .fill(Color.clear)
                                        .padding(-4)
                                        .matchedGeometryEffect(id: option.id, in: ringSpace, properties: .frame, isSource: true)
                                )
                                .scaleEffect(selected ? 1.04 : 1)
                            Text(option.title)
                                .font(.caption2.weight(selected ? .bold : .regular))
                                .foregroundColor(selected ? accent : .secondary)
                        }
                        .padding(Space.x1)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.9))
                    .accessibilityLabel("\(option.title) icon")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 3)
                    .matchedGeometryEffect(id: currentOption.id, in: ringSpace, properties: .frame, isSource: false)
            }
            .padding(.vertical, Space.x1)
            .animation(ready ? (reduceMotion ? Motion.fade : Motion.selection) : nil, value: current)
        }
    }

    private func select(_ option: Option) {
        guard UIApplication.shared.supportsAlternateIcons else {
            toasts.show("This install doesn't support alternate icons.", kind: .warning)
            return
        }
        guard current != option.iconName else { return }
        UIApplication.shared.setAlternateIconName(option.iconName) { error in
            Task { @MainActor in
                if let error {
                    toasts.show("Couldn't change icon: \(error.localizedDescription)", kind: .error)
                } else {
                    current = option.iconName
                    Haptics.success()
                }
            }
        }
    }
}

