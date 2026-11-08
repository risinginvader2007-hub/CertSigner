import SwiftUI

@main
struct CertSignerApp: App {
    @StateObject private var certificates: CertificateStore
    @StateObject private var library: LibraryStore
    @StateObject private var signedApps: SignedAppsStore
    @StateObject private var signingQueue: SigningQueue
    @StateObject private var serverCertificates = ServerCertificateStore()
    @StateObject private var toasts: ToastCenter
    @StateObject private var router = TabRouter()
    @StateObject private var importer = ImportCoordinator()
    @StateObject private var repositories = RepositoryStore()

    init() {
        let certificates = CertificateStore()
        let library = LibraryStore()
        let signedApps = SignedAppsStore()
        let toasts = ToastCenter()
        _certificates = StateObject(wrappedValue: certificates)
        _library = StateObject(wrappedValue: library)
        _signedApps = StateObject(wrappedValue: signedApps)
        _toasts = StateObject(wrappedValue: toasts)
        _signingQueue = StateObject(wrappedValue: SigningQueue(
            certificates: certificates, library: library, signedApps: signedApps, toasts: toasts
        ))
        AppLog.info("CertSigner launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(certificates)
                .environmentObject(library)
                .environmentObject(signedApps)
                .environmentObject(signingQueue)
                .environmentObject(serverCertificates)
                .environmentObject(toasts)
                .environmentObject(router)
                .environmentObject(importer)
                .environmentObject(repositories)
        }
    }
}
