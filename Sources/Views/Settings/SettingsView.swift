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

    @State private var storage: [StorageItem] = []
    @State private var loadingStorage = true
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
            .task { await refreshStorage() }
            .refreshable { await refreshStorage() }
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

    private var storageSection: some View {
        Section {
            if loadingStorage && storage.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        SkeletonBlock(width: 120, height: 14)
                        Spacer()
                        SkeletonBlock(width: 50, height: 14)
                    }
                }
            } else {
                StorageBar(items: storage)
                    .padding(.vertical, Space.x2)
                ForEach(storage) { item in
                    HStack {
                        Label(item.title, systemImage: item.systemImage)
                        Spacer()
                        Text(item.bytes.byteString)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack {
                    Text("Total").fontWeight(.semibold)
                    Spacer()
                    Text(storage.reduce(0) { $0 + $1.bytes }.byteString)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            Button(role: .destructive) {
                CacheService.clear()
                toasts.show("Cache cleared", kind: .success)
                Task { await refreshStorage() }
            } label: {
                Label("Clear Cache", systemImage: "sparkles")
            }
            Button(role: .destructive) {
                Haptics.impact(.light)
                withAnimation(Motion.smooth) { removeUnusedImports() }
            } label: {
                Label("Remove Unused Imported IPAs", systemImage: "trash")
            }
        } header: {
            Text("Storage")
        }
    }

    private func refreshStorage() async {
        loadingStorage = true
        let items = await Task.detached(priority: .utility) { StorageService.usage() }.value
        withAnimation(Theme.spring) {
            storage = items
            loadingStorage = false
        }
    }

    private func removeUnusedImports() {
        let pending = Set(queue.tasks.compactMap { task -> UUID? in
            if case .library(let id) = task.source { return id }
            return nil
        })
        let unused = library.apps.filter { !pending.contains($0.id) }
        unused.forEach { library.delete($0) }
        toasts.show("Removed \(unused.count) imported IPA\(unused.count == 1 ? "" : "s")", kind: .success)
        Task { await refreshStorage() }
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
            Button(role: .destructive) {
                AppLog.clear()
                toasts.show("Log cleared", kind: .success)
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    logURL = AppLog.exportCopy()
                }
            } label: {
                Label("Clear Log", systemImage: "trash")
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

struct AccentPicker: View {
    @Binding var selection: AccentOption

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x3) {
                ForEach(AccentOption.allCases) { option in
                    Button {
                        withAnimation(Theme.bouncy) { selection = option }
                        Haptics.selection()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: option.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 32)
                            Circle()
                                .strokeBorder(option.color, lineWidth: 2.5)
                                .frame(width: 42, height: 42)
                                .opacity(selection == option ? 1 : 0)
                                .scaleEffect(selection == option ? 1 : 0.7)
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .transition(.scale)
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.85))
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(.vertical, Space.hair)
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
    @State private var current: String?

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
        .onAppear { current = UIApplication.shared.alternateIconName }
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                                      lineWidth: selected ? 3 : 0)
                                        .padding(-4)
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
            .padding(.vertical, Space.x1)
            .animation(Theme.bouncy, value: current)
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

/// Storage usage as one animated, colour-coded bar (each area's share of the total).
struct StorageBar: View {
    let items: [StorageItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private static let colors: [Color] = [Theme.violet, Theme.cyan, Theme.indigo, Theme.warning, Theme.success, .pink]

    private var total: Int64 { max(1, items.reduce(0) { $0 + $1.bytes }) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            GeometryReader { geo in
                HStack(spacing: Space.hair) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let share = CGFloat(item.bytes) / CGFloat(total)
                        if item.bytes > 0 {
                            Capsule()
                                .fill(Self.colors[index % Self.colors.count])
                                .frame(width: max(4, (geo.size.width - 12) * share * (grown ? 1 : 0)))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .clipShape(Capsule())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if item.bytes > 0 {
                            HStack(spacing: Space.x1) {
                                Circle().fill(Self.colors[index % Self.colors.count]).frame(width: 7, height: 7)
                                Text(item.title).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage breakdown")
        .onAppear {
            withAnimation(Motion.adaptive(Motion.smooth, reduceMotion: reduceMotion).delay(0.1)) { grown = true }
        }
    }
}
