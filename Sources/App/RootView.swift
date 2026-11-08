import SwiftUI

enum AppTab: Hashable {
    case library, sources, certificates, signed, settings
}

@MainActor
final class TabRouter: ObservableObject {
    @Published var tab: AppTab = .library
}

struct RootView: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var importer: ImportCoordinator
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.accent) private var accent: AccentOption = .blue

    var body: some View {
        TabView(selection: $router.tab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.library)

            SourcesView()
                .tabItem { Label("Sources", systemImage: "globe") }
                .tag(AppTab.sources)

            CertificatesView()
                .tabItem { Label("Certificates", systemImage: "checkmark.seal.fill") }
                .tag(AppTab.certificates)

            SignedAppsView()
                .tabItem { Label("Signed", systemImage: "signature") }
                .tag(AppTab.signed)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(accent.color)
        .environment(\.themeAccent, accent.color)
        .preferredColorScheme(appearance.colorScheme)
        .modifier(ToastHost(center: toasts))
        .onChange(of: router.tab) { _ in Haptics.selection() }
        .onOpenURL { url in handleIncoming(url) }
    }

    /// "Open in" / Share → CertSigner.
    private func handleIncoming(_ url: URL) {
        guard url.isFileURL else { return }
        switch importer.handleIncoming(url) {
        case .certificateFile:
            router.tab = .certificates // the import sheet opens and shows its own toast
        case .ipa(let name):
            toasts.show("Received \(name). IPA import arrives in Stage 3.", kind: .info)
        case .unsupported(let name):
            toasts.show("CertSigner can't open \(name).", kind: .error)
        case .unreadable(let name, let reason):
            toasts.show("Couldn't read \(name): \(reason)", kind: .error)
        }
    }
}
