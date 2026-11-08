import SwiftUI

@main
struct CertSignerApp: App {
    @StateObject private var certificates = CertificateStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var toasts = ToastCenter()
    @StateObject private var router = TabRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(certificates)
                .environmentObject(library)
                .environmentObject(toasts)
                .environmentObject(router)
        }
    }
}
