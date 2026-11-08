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
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var queue: SigningQueue
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.accent) private var accent: AccentOption = .blue

    var body: some View {
        shell
            .tint(accent.color)
            .environment(\.themeAccent, accent.color)
            .preferredColorScheme(appearance.colorScheme)
            .roundedDesign()
            .modifier(ToastHost(center: toasts))
            .sheet(isPresented: $importer.showCertificateImport) {
                ImportCertificateView()
                    .roundedDesign()
            }
            .sheet(item: $importer.review) { request in
                SignAppSheet(app: request.app, autoStart: request.quickSign, discardIfUnsigned: true,
                             installWhenDone: request.installWhenDone)
                    .roundedDesign()
            }
            .sheet(item: $queue.installRequest) { app in
                InstallSheet(app: app)
                    .roundedDesign()
            }
            .onOpenURL { url in handleIncoming(url) }
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

    /// "Open in" / Share → CertSigner.
    private func handleIncoming(_ url: URL) {
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

    var body: some View {
        TabView(selection: $router.tab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                tabScreen(.home)
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.systemImage, value: AppTab.library) {
                tabScreen(.library)
            }
            .badge(signedApps.attentionCount)
            Tab(AppTab.sources.title, systemImage: AppTab.sources.systemImage, value: AppTab.sources) {
                tabScreen(.sources)
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                tabScreen(.settings)
            }
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
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            ForEach(AppTab.barTabs) { tab in
                let selected = router.tab == tab
                tabScreen(tab)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.985)
                    .allowsHitTesting(selected)
                    .accessibilityHidden(!selected)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                FloatingTabBar(selection: $router.tab, badges: [.library: signedApps.attentionCount])
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
