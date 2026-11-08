import SwiftUI

/// Exactly what CertSigner read from a provisioning profile, for verifying the App ID logic:
/// the raw application-identifier (from the Entitlements dictionary), team ID, type, wildcard
/// result and every entitlement with its full value. Values are selectable and copyable.
struct ProfileRawDataView: View {
    let profile: ProvisioningProfile
    /// Collapse the entitlements list behind a disclosure (used in the compact Review & Sign card).
    var compactEntitlements = false

    @State private var showEntitlements = false

    private var source: String {
        profile.applicationIdentifierKey.map { "Entitlements › \($0)" } ?? "Not found in Entitlements"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            rawRow("application-identifier", profile.applicationIdentifier.isEmpty ? "(missing)" : profile.applicationIdentifier,
                   note: source)
            rawRow("Team ID", profile.teamID)
            rawRow("Profile type", profile.type.rawValue)
            rawRow("App ID pattern", profile.bundleIDPattern.isEmpty ? "(empty)" : profile.bundleIDPattern,
                   note: profile.isWildcard ? "Wildcard: any matching bundle ID and extensions allowed" : "Explicit: only this bundle ID")
            if compactEntitlements {
                DisclosureGroup(isExpanded: $showEntitlements) {
                    entitlementsList.padding(.top, Space.x2)
                } label: {
                    Text("Entitlements (\(profile.entitlements.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Entitlements (\(profile.entitlements.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, Space.x1)
                entitlementsList
            }
        }
    }

    private var entitlementsList: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if profile.entitlements.isEmpty {
                Text("None").font(.caption).foregroundColor(.secondary)
            }
            ForEach(profile.fullEntitlements) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.key)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                    Text(item.value)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu { copyButton("\(item.key) = \(item.value)") }
            }
        }
    }

    private func rawRow(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let note {
                Text(note).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { copyButton(value) }
        .accessibilityElement(children: .combine)
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }
}
