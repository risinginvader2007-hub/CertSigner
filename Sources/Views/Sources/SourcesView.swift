import SwiftUI

struct SourcesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                EmptyStateView(
                    systemImage: "globe",
                    title: "No sources yet",
                    message: "Add AltStore or Feather-style repo URLs to browse and download apps. Coming in Stage 6."
                )
                .padding(.top, 60)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Sources")
        }
    }
}
