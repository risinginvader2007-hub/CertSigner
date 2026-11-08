import SwiftUI

@main
struct CertSignerApp: App {
    @StateObject private var certificates = CertificateStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var signedApps = SignedAppsStore()
    @StateObject private var toasts = ToastCenter()
    @StateObject private var router = TabRouter()
    @StateObject private var importer = ImportCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(certificates)
                .environmentObject(library)
                .environmentObject(signedApps)
                .environmentObject(toasts)
                .environmentObject(router)
                .environmentObject(importer)
        }
    }
}
