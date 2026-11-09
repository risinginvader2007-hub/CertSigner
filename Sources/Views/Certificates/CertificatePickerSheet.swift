import SwiftUI

// MARK: - Display names

extension Certificate {
    /// Never the raw ID as the main title: the nickname when it reads like a name, otherwise the
    /// certificate's common name, otherwise "Development certificate" / "Distribution certificate".
    var displayName: String {
        let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty && !Self.looksLikeRawID(nick) { return nick }
        if let common = record.signingCertificate?.commonName.map(Self.personName), !common.isEmpty {
            return common
        }
        return "\(kindTitle) certificate"
    }

    /// The raw nickname, shown as small secondary text when the title is a friendlier name.
    var rawIDLine: String? {
        displayName == nickname ? nil : nickname
    }

    /// "Development" or "Distribution", from the profile type (or the certificate's common name).
    var kindTitle: String {
        switch profile?.type {
        case .development?: return "Development"
        case .adHoc?, .appStore?, .enterprise?: return "Distribution"
        case nil:
            let common = record.signingCertificate?.commonName?.lowercased() ?? ""
            return common.contains("distribution") ? "Distribution" : "Development"
        }
    }

    var kindShort: String { kindTitle == "Development" ? "Dev" : "Dist" }

    /// "Dev · Expires 7 May 2027".
    var typeAndExpiry: String {
        var parts = [kindShort]
        if let expiration = expirationDate {
            let text = expiration.formatted(.dateTime.day().month(.abbreviated).year())
            parts.append(expiration <= Date() ? "Expired \(text)" : "Expires \(text)")
        }
        return parts.joined(separator: " · ")
    }

    /// Long, space-free strings full of digits (UDIDs, "00008140-001A3C661E01801C_dev", hashes).
    static func looksLikeRawID(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        if text.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{12,}", options: .regularExpression) != nil { return true }
        let digits = text.filter(\.isNumber).count
        return text.count >= 16 && digits * 3 >= text.count
    }

    /// "Apple Development: Jane Doe (ABCDE12345)" → "Jane Doe".
    static func personName(_ commonName: String) -> String {
        var name = commonName
        if let colon = name.firstIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
        if let paren = name.lastIndex(of: "("), name.hasSuffix(")") { name = String(name[..<paren]) }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Friendly form of a stored certificate name (e.g. on a signed app whose certificate was deleted).
    static func friendlyName(_ raw: String) -> String {
        looksLikeRawID(raw) ? "Certificate \(raw.prefix(6))…" : raw
    }
}

extension View {
    /// Long identifiers (bundle IDs, UDIDs, certificate / profile names): one line, shrink a little,
    /// then truncate in the middle. Never wraps mid-word or leaves a stray character.
    func identifierText(minimumScale: CGFloat = 0.75) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minimumScale)
            .truncationMode(.middle)
    }
}

// MARK: - Certificate picker sheet

/// Bottom sheet for choosing a certificate (Home "Switch", Review & Sign, Settings). One clean row
/// per certificate; tapping a row selects it, plays a light haptic and closes the sheet.
struct CertificatePickerSheet: View {
    var title = "Switch Certificate"
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    @EnvironmentObject private var certificates: CertificateStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                // One card holding every row (clipped to the card), like grouped settings rows.
                VStack(spacing: 0) {
                    ForEach(Array(certificates.certificates.enumerated()), id: \.element.id) { index, certificate in
                        if index > 0 { SoftDivider().padding(.leading, Space.x4 + 38 + Space.x3) }
                        row(certificate)
                    }
                }
                .cardBackground()
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .padding(Theme.padding)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ certificate: Certificate) -> some View {
        let selected = certificate.id == (picked ?? selectedID)
        return Button {
            Haptics.impact(.light)
            picked = certificate.id
            onSelect(certificate.id)
            // Let the checkmark spring in before the sheet closes.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                dismiss()
            }
        } label: {
            HStack(spacing: Space.x3) {
                CertificateGlyph(seed: certificate.nickname, size: 38)
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(certificate.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .identifierText(minimumScale: 0.85)
                    Text(certificate.typeAndExpiry)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let raw = certificate.rawIDLine {
                        Text(raw)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary.opacity(0.8))
                            .identifierText()
                    }
                }
                Spacer(minLength: Space.x2)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundColor(accent)
                    .scaleEffect(selected ? 1 : 0.3)
                    .opacity(selected ? 1 : 0)
                    .animation(reduceMotion ? Motion.fade : Motion.bouncy, value: selected)
            }
            .padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(selected ? accent.opacity(0.12) : Color.clear))
            .animation(reduceMotion ? Motion.fade : Motion.selection, value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(certificate.displayName), \(certificate.typeAndExpiry)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
