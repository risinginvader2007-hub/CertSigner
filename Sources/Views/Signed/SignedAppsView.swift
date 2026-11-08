import SwiftUI

struct SignedAppsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                EmptyStateView(
                    systemImage: "signature",
                    title: "Nothing signed yet",
                    message: "Apps you sign show up here with the certificate used and an expiry countdown."
                )
                .padding(.top, 60)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Signed")
        }
    }
}
