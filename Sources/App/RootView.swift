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
    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var queue: SigningQueue
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.accent) private var accent: AccentOption = .blue

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    let selected = router.tab == tab
                    screen(for: tab)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected ? 1 : 0.985)
                        .allowsHitTesting(selected)
                        .accessibilityHidden(!selected)
                }
            }

            FloatingTabBar(selection: $router.tab, badges: [.library: signedApps.attentionCount])
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
            SignAppSheet(app: request.app, autoStart: request.quickSign, discardIfUnsigned: true)
                .roundedDesign()
        }
        .sheet(item: $queue.installRequest) { app in
            InstallSheet(app: app)
                .roundedDesign()
        }
        .onOpenURL { url in handleIncoming(url) }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
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
