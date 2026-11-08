import SwiftUI

/// iOS 26+ Search tab (rendered by the system as a separate Liquid Glass button).
/// Finds signed apps (name / bundle ID) and certificates (nickname / team).
struct SearchView: View {
    private enum Route: Hashable {
        case app(UUID)
        case certificate(UUID)
    }

    @EnvironmentObject private var signedApps: SignedAppsStore
    @EnvironmentObject private var certificates: CertificateStore
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var apps: [SignedApp] {
        guard !trimmed.isEmpty else { return [] }
        return signedApps.apps.filter {
            $0.name.lowercased().contains(trimmed) || $0.bundleID.lowercased().contains(trimmed)
        }
    }

    private var matchingCertificates: [Certificate] {
        guard !trimmed.isEmpty else { return [] }
        return certificates.certificates.filter {
            $0.nickname.lowercased().contains(trimmed)
                || ($0.profile?.teamName.lowercased().contains(trimmed) ?? false)
                || ($0.profile?.teamID.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "Search",
                            message: "Find signed apps by name or bundle ID, and certificates by nickname or team."
                        )
                        .listRowBackground(Color.clear)
                    }
                } else if apps.isEmpty && matchingCertificates.isEmpty {
                    Section {
                        Text("No results for “\(query)”.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    if !apps.isEmpty {
                        Section("Signed Apps") {
                            ForEach(apps) { app in
                                NavigationLink(value: Route.app(app.id)) {
                                    HStack(spacing: 12) {
                                        AppIconView(image: signedApps.icons[app.id], name: app.name, size: 40)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name).font(.body.weight(.semibold))
                                            Text(app.bundleID).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        CertificateStatusBadge(status: app.status())
                                    }
                                }
                            }
                        }
                    }
                    if !matchingCertificates.isEmpty {
                        Section("Certificates") {
                            ForEach(matchingCertificates) { certificate in
                                NavigationLink(value: Route.certificate(certificate.id)) {
                                    HStack(spacing: 12) {
                                        CertificateGlyph(seed: certificate.nickname, size: 36)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(certificate.nickname).font(.body.weight(.semibold))
                                            Text(certificate.profile?.teamName ?? "Unknown team")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        CertificateStatusBadge(status: certificate.status())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .animation(Theme.spring, value: trimmed)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Apps and certificates")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .app(let id): SignedAppDetailView(appID: id)
                case .certificate(let id): CertificateDetailView(certificateID: id)
                }
            }
        }
    }
}
