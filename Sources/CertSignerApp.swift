import SwiftUI

@main
struct CertSignerApp: App {
    @StateObject private var store = CertStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
