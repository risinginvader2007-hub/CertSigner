import SwiftUI

@MainActor
final class TabRouter: ObservableObject {
    @Published var tab: AppTab = .home
    /// Library shows only signed apps that are expiring or expired.
    @Published var attentionOnly = false
}

struct RootView: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var certificateStore: CertificateStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SigningQueue
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    /// The selected accent's id (original accents keep their old stored value as their id).
    @AppStorage(SettingsKeys.accent) private var accent = Accent.defaultID
    /// Live theme colours: fades every view together when the accent changes.
    @StateObject private var theme = ThemeStore(accent: Accent.resolve(id: UserDefaults.standard.string(forKey: SettingsKeys.accent)))
    @Environment(\.scenePhase) private var scenePhase
    /// The animated intro plays once, on first launch.
    @AppStorage("ui.introSeen") private var introSeen = false
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        shell
            .overlay {
                if !introSeen {
                    IntroOverlay {
                        withAnimation(.easeOut(duration: Motion.standard)) { introSeen = true }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .tint(theme.accent)
            .environment(\.themeAccent, theme.accent)
            .environment(\.themeGradient, theme.gradient)
            .environment(\.themeFade, theme.fade)
            .environment(\.themeOnAccent, theme.onAccent)
            .environmentObject(theme)
            .onChange(of: accent) { newValue in theme.apply(Accent.resolve(id: newValue)) }
            .onChange(of: scenePhase) { phase in
                AuroraClock.shared.setRunning(phase == .active)
                // Back in the foreground: quiet update check (throttled to once a minute).
                if phase == .active { Task { await updates.checkIfDue() } }
            }
            .preferredColorScheme(appearance.colorScheme)
            .roundedDesign()
            .modifier(ToastHost(center: toasts))
            .sheet(isPresented: $importer.showCertificateImport) {
                ImportCertificateView()
                    .sheetChrome()
            }
            .sheet(item: $importer.review) { request in
                SignAppSheet(app: request.app, autoStart: request.quickSign, discardIfUnsigned: true,
                             installWhenDone: request.installWhenDone)
                    .sheetChrome()
            }
            .sheet(item: $queue.installRequest) { app in
                InstallSheet(app: app)
                    .sheetChrome()
            }
            .sheet(isPresented: $updates.sheetShown) {
                UpdateSheet()
                    .sheetChrome()
            }
            .onOpenURL { url in handleIncoming(url) }
            .task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                // "Updated to build N" after an in-app update, then the check for a newer one (when due).
                let updated = updates.launch(toasts: toasts)
                // Once per signature: which certificate this copy was signed with (e.g. after the web installer).
                guard let message = LaunchSignature.confirmationIfNew(LaunchSignature.current()) else { return }
                if updated { try? await Task.sleep(nanoseconds: 3_000_000_000) }
                toasts.show(message, kind: .success)
                AppLog.info("launch: \(message)")
            }
    }

    @ViewBuilder
    private var shell: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            NativeTabShell()
        } else {
            LegacyTabShell()
        }
        #else
        LegacyTabShell()
        #endif
    }

    /// Certificate hand-off from the Get CertSigner page (certsigner://import#…).
    private func importFromWeb(_ url: URL) async {
        do {
            let payload = try WebImport.parse(url)
            if let existing = certificateStore.existing(p12Data: payload.p12, profileData: payload.profile) {
                certificateStore.setActive(existing.id)
                toasts.show("\(existing.displayName) is already in CertSigner", kind: .success)
                AppLog.info("web import: already present, made active")
                return
            }
            let result = try await certificateStore.importCertificate(nickname: payload.name, p12Data: payload.p12,
                                                                      profileData: payload.profile, password: payload.password)
            certificateStore.setActive(result.certificate.id)
            Haptics.success()
            toasts.show(result.warning ?? "Imported \(result.certificate.displayName). Ready to sign.", kind: result.warning == nil ? .success : .warning)
            AppLog.info("web import: imported \(result.certificate.displayName)")
        } catch {
            toasts.show("Couldn't import the certificate. \(error.localizedDescription)", kind: .error)
            AppLog.error("web import: \(error.localizedDescription)")
        }
    }

    /// "Open in" / Share → CertSigner.
    private func handleIncoming(_ url: URL) {
        if WebImport.isImportLink(url) {
            Task { await importFromWeb(url) }
            return
        }
        guard url.isFileURL else { return }
        switch importer.handleIncoming(url) {
        case .certificateFile:
            break // the certificate import sheet opens and shows its own toast
        case .ipa(let tempURL, let name):
            Task {
                await importer.importIPA(from: tempURL, name: name, moveSource: true, quickSign: false,
                                         library: library, toasts: toasts)
            }
        case .unsupported(let name):
            toasts.show("CertSigner can't open \(name).", kind: .error)
        case .unreadable(let name, let reason):
            toasts.show("Couldn't read \(name): \(reason)", kind: .error)
        }
    }
}

@MainActor @ViewBuilder
private func tabScreen(_ tab: AppTab) -> some View {
    switch tab {
    case .home: HomeView()
    case .library: LibraryView()
    case .sources: SourcesView()
    case .settings: SettingsView()
    case .search: SearchView()
    }
}

#if compiler(>=6.2)
/// iOS 26+: native TabView → system Liquid Glass bar, correct safe areas and keyboard handling,
/// and the Search tab rendered as its own glass button.
@available(iOS 26.0, *)
private struct NativeTabShell: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var signedApps: SignedAppsStore
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        TabView(selection: $router.tab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                tabScreen(.home).environment(\.auroraActive, router.tab == .home)
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.systemImage, value: AppTab.library) {
                tabScreen(.library).environment(\.auroraActive, router.tab == .library)
            }
            .badge(signedApps.attentionCount)
            Tab(AppTab.sources.title, systemImage: AppTab.sources.systemImage, value: AppTab.sources) {
                tabScreen(.sources).environment(\.auroraActive, router.tab == .sources)
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                tabScreen(.settings).environment(\.auroraActive, router.tab == .settings)
            }
            // An empty badge: UIKit draws it as a small red dot with no number.
            .badge(updates.showsDot ? Text("") : nil)
            Tab(value: AppTab.search, role: .search) {
                tabScreen(.search)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: router.tab) { _ in Haptics.selection() }
    }
}
#endif

/// iOS 16–25: tabs stay alive and cross-fade; the custom glass bar is a bottom safe-area inset,
/// so scroll content and search fields always sit above it.
private struct LegacyTabShell: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var signedApps: SignedAppsStore
    @ObservedObject private var updates = UpdateService.shared
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            ForEach(AppTab.barTabs) { tab in
                let selected = router.tab == tab
                tabScreen(tab)
                    .environment(\.auroraActive, selected)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.985)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                FloatingTabBar(selection: $router.tab, badges: [.library: signedApps.attentionCount],
                               dots: updates.showsDot ? [.settings] : [])
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: keyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onAppear {
            if router.tab == .search { router.tab = .home }
        }
    }
}
