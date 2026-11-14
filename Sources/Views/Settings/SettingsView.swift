import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SigningQueue
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.accent) private var accent = Accent.defaultID
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    @AppStorage(SettingsKeys.installMethod) private var installMethod: InstallMethod = .automatic
    @AppStorage(SettingsKeys.autoInstall) private var autoInstall = false
    @AppStorage(SettingsKeys.autoCloseInstall) private var autoCloseInstall = true
    @AppStorage(SettingsKeys.signingMode) private var signingMode: SigningMode = .compatibility
    @AppStorage(SettingsKeys.backgroundAnimation) private var backgroundAnimation = true
    @AppStorage(SettingsKeys.glowIntensityLight) private var lightGlow: GlowLevel = .normal
    @AppStorage(SettingsKeys.glowIntensityDark) private var darkGlow: GlowLevel = .normal
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(UpdateService.Keys.autoCheck) private var autoCheckUpdates = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCertificatePicker = false
    @AppStorage(SettingsKeys.deleteOriginal) private var deleteOriginal = true
    @AppStorage(SettingsKeys.defaultRemoveExtensions) private var defaultRemoveExtensions = false
    @AppStorage(SettingsKeys.defaultKeepBundleID) private var defaultKeepBundleID = false

    @EnvironmentObject private var signedApps: SignedAppsStore
    @ObservedObject private var storageModel = StorageModel.shared
    @Environment(\.themeAccent) private var accentColor
    @State private var logURL: URL?

    private var updateStatus: String {
        switch updates.checkState {
        case .idle: return updates.dotBuild.map { "Build \($0) available" } ?? "Check Now"
        case .checking: return updates.dotBuild.map { "Build \($0) available" } ?? "Checking…"
        case .upToDate: return "Up to date"
        case .available(let update): return "Build \(update.build) available"
        case .failed: return "Couldn't check"
        }
    }

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

    @ViewBuilder
    private var deviceSection: some View {
        Section {
            TextField("Paste your UDID", text: $udid)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("This Device")
        } footer: {
            Text("Sideloaded apps can't read the UDID. Copy it from a computer (Finder or 3uTools), then paste it here. It's only used to check this iPhone is in your profiles.")
        }
        if !udid.isEmpty {
            Section {
                PrimaryButton(title: "Clear UDID", systemImage: "xmark.circle", style: .tinted) {
                    withAnimation(Motion.smooth) { udid = "" }
                }
                .environment(\.themeAccent, Theme.danger)
                .buttonRow()
            }
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

            // Stored per appearance: this edits the one on screen (light or dark).
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Glow intensity")
                SlidingSegmentedControl(
                    selection: colorScheme == .dark ? $darkGlow : $lightGlow,
                    options: GlowLevel.allCases.map { .init(value: $0, title: $0.title) },
                    accessibilityTitle: "Glow intensity"
                )
                Text(colorScheme == .dark
                     ? "How bright the background glows are in dark mode. Light mode has its own setting."
                     : "How strong the background glows are in light mode. Dark mode has its own setting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, Space.x1)

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

    @ViewBuilder
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
        } header: {
            Text("Storage")
        }
        // Actions sit under the card as buttons, so the card keeps all four rounded corners.
        Section {
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
        }
    }

    /// A full-width action in the shared button style that says how much it frees.
    private func storageAction(title: String, systemImage: String, bytes: Int64, tint: Color?,
                               action: @escaping () -> Void) -> some View {
        PrimaryButton(title: bytes > 0 ? "\(title) · \(StorageService.format(bytes))" : "\(title) · Nothing to clear",
                      systemImage: systemImage, style: .tinted, action: action)
            .disabled(bytes <= 0 || storageModel.report == nil)
            .environment(\.themeAccent, tint ?? accentColor)
            .buttonRow()
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
            // Both log actions are buttons (same capsule as Clear Log), not a row next to a pill.
            if let logURL {
                ShareLink(item: logURL) {
                    Label("Export Log File", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.app(.secondary))
                .buttonRow()
            } else {
                Button {} label: {
                    Label("Preparing log…", systemImage: "doc.text")
                }
                .buttonStyle(.app(.secondary))
                .disabled(true)
                .buttonRow()
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
            Button {
                Haptics.impact(.light)
                updates.sheetShown = true
            } label: {
                HStack {
                    Label("Updates", systemImage: "arrow.down.app")
                    NotificationDot(visible: updates.showsDot)
                    Spacer()
                    Text(updateStatus)
                        .foregroundColor(updates.showsDot ? accentColor : .secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(updates.showsDot ? "Update available" : "")
            Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
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

/// Accent swatches, grouped Solid / Blended with a sliding switch. One selection ring slides from
/// the old swatch to the new one (matchedGeometryEffect follower driven by local state, so it
/// animates with @AppStorage too). Blended ends with the user's custom blends and "+".
struct AccentPicker: View {
    @Binding var selection: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var library = AccentLibrary.shared
    @Namespace private var namespace
    @State private var shown: String?
    @State private var group: Accent.Group
    @State private var showCustom = false

    init(selection: Binding<String>) {
        _selection = selection
        _group = State(initialValue: Accent.resolve(id: selection.wrappedValue).group)
    }

    private var currentID: String { shown ?? selection }
    private var current: Accent { Accent.resolve(id: currentID) }
    private var visible: [Accent] { group == .solid ? Accent.solids : Accent.blends + library.customs }
    private var animation: Animation { reduceMotion ? Motion.fade : Motion.selection }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SlidingSegmentedControl(
                selection: $group,
                options: Accent.Group.allCases.map { .init(value: $0, title: $0.title) },
                accessibilityTitle: "Accent type"
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x3) {
                    ForEach(visible) { option in
                        swatch(option)
                    }
                    if group == .blended { addButton }
                }
                .background {
                    if visible.contains(where: { $0.id == currentID }) {
                        Circle()
                            .strokeBorder(current.tint, lineWidth: 2.5)
                            .matchedGeometryEffect(id: currentID, in: namespace, properties: .frame, isSource: false)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.vertical, Space.hair)
                .padding(.horizontal, Space.hair)
            }
            .id(group)
            .transition(.opacity)
            HStack(spacing: Space.x2) {
                Capsule()
                    .fill(LinearGradient(colors: current.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 10)
                Text(current.name)
                    .font(TypeScale.caption)
                    .foregroundColor(SemanticColor.textSecondary)
                    .lineLimit(1)
                if current.isCustom {
                    Text("· hold its swatch to delete")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected accent: \(current.name)")
        }
        .animation(Motion.fade, value: group)
        .onChange(of: selection) { newValue in
            guard shown != newValue else { return }
            withAnimation(animation) { shown = newValue }
        }
        .sheet(isPresented: $showCustom) {
            CustomBlendSheet { name, hex in
                let accent = library.add(name: name, hex: hex)
                select(accent.id)
            }
            .sheetChrome()
        }
    }

    private func select(_ id: String) {
        guard id != selection else { return }
        Haptics.selection()
        withAnimation(animation) {
            shown = id
            selection = id
        }
    }

    @ViewBuilder
    private func swatch(_ option: Accent) -> some View {
        let selected = currentID == option.id
        let button = Button {
            select(option.id)
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: option.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(option.onAccent)
                    .scaleEffect(selected ? 1 : 0.4)
                    .opacity(selected ? 1 : 0)
            }
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(Color.clear).frame(width: 42, height: 42)
                    .matchedGeometryEffect(id: option.id, in: namespace, properties: .frame, isSource: true)
            )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.85))
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])

        if option.isCustom {
            // Long press: delete this custom blend.
            button.contextMenu {
                Button(role: .destructive) {
                    Haptics.impact(.light)
                    if selection == option.id { select(Accent.defaultID) }
                    withAnimation(Motion.smooth) { library.delete(option.id) }
                } label: {
                    Label("Delete \(option.name)", systemImage: "trash")
                }
            }
        } else {
            button
        }
    }

    private var addButton: some View {
        Button {
            Haptics.impact(.light)
            showCustom = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundColor(SemanticColor.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.85))
        .accessibilityLabel("Custom blend")
    }
}

/// "Custom blend": two colours, a live preview, a name, Save.
struct CustomBlendSheet: View {
    let onSave: (_ name: String, _ hex: [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var first = Color(red: 0.0, green: 0.71, blue: 0.86)
    @State private var second = Color(red: 0.77, green: 0.3, blue: 1.0)
    @State private var name = ""

    private var hex: [String] {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        return [RGBA(first, traits: traits).hex, RGBA(second, traits: traits).hex]
    }

    var body: some View {
        // Live preview: the swatch, a button and small text exactly as the app will draw them.
        let accent = Accent(id: "preview", name: name, hex: hex)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    VStack(spacing: Space.x4) {
                        Circle()
                            .fill(LinearGradient(colors: accent.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 84, height: 84)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: Border.width))
                        Text("Preview")
                            .font(.body.weight(.semibold))
                            .foregroundColor(accent.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: AppButtonStyle.height)
                            .background(Capsule().fill(LinearGradient(colors: accent.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)))
                        Label("Small text and icons use this colour", systemImage: "paintbrush.pointed.fill")
                            .font(TypeScale.caption)
                            .foregroundColor(accent.tint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Space.x4)
                    .cardBackground()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Gradient preview")

                    VStack(spacing: 0) {
                        ColorPicker("Start colour", selection: $first, supportsOpacity: false)
                            .padding(.vertical, Space.x3)
                        SoftDivider()
                        ColorPicker("End colour", selection: $second, supportsOpacity: false)
                            .padding(.vertical, Space.x3)
                        SoftDivider()
                        TextField("Name (optional)", text: $name)
                            .padding(.vertical, Space.x3)
                    }
                    .padding(.horizontal, Space.x4)
                    .cardBackground()

                    PrimaryButton(title: "Save Blend", systemImage: "checkmark") {
                        onSave(name, hex)
                        dismiss()
                    }
                }
                .padding(Theme.padding)
            }
            .navigationTitle("Custom Blend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
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
    @ObservedObject private var icons = AppIconStore.shared

    /// Space between the icon/label and the ring; the ring's radius is concentric with the icon's.
    private static let ringInset: CGFloat = 6
    private static let iconRadius = Radius.sm
    private var current: String? { icons.selected }

    private var currentOption: Option {
        options.first { $0.iconName == current } ?? options[0]
    }

    private var selectionAnimation: Animation { reduceMotion ? Motion.fade : Motion.selection }

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current icon: \(currentOption.title)")
            picker
        }
        .onAppear { icons.sync() }
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
                                .clipShape(RoundedRectangle(cornerRadius: Self.iconRadius, style: .continuous))
                            Text(option.title)
                                .font(.caption2.weight(selected ? .bold : .regular))
                                .foregroundColor(selected ? accent : .secondary)
                        }
                        .padding(Self.ringInset)
                        .background(
                            // Where the single sliding ring sits when this icon is selected.
                            RoundedRectangle(cornerRadius: Self.iconRadius + Self.ringInset, style: .continuous)
                                .fill(Color.clear)
                                .matchedGeometryEffect(id: option.id, in: ringSpace, properties: .frame, isSource: true)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Self.iconRadius + Self.ringInset, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.94))
                    .accessibilityLabel("\(option.title) icon")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Self.iconRadius + Self.ringInset, style: .continuous)
                    .strokeBorder(accent, lineWidth: 2.5)
                    .matchedGeometryEffect(id: currentOption.id, in: ringSpace, properties: .frame, isSource: false)
                    .allowsHitTesting(false)
            }
            // Room around the grid so the ring is never clipped by the scroll view or the card.
            .padding(.horizontal, Space.x1)
            .padding(.vertical, Space.x2)
        }
        .padding(.horizontal, -Space.x1)
    }

    private func select(_ option: Option) {
        guard current != option.iconName else { return }
        guard icons.supportsAlternateIcons else {
            toasts.show("This copy of CertSigner can\'t change its icon.", kind: .warning)
            return
        }
        icons.select(option.iconName, animation: selectionAnimation) { message in
            toasts.show("Couldn't change icon: \(message)", kind: .error)
        }
    }
}

