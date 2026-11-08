import SwiftUI

struct CertificateDetailView: View {
    let certificateID: UUID

    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeAccent) private var accent
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""

    @State private var showRename = false
    @State private var showPassword = false
    @State private var dissolvingOut = false
    @State private var draft = ""

    private var certificate: Certificate? {
        certificates.certificates.first { $0.id == certificateID }
    }

    var body: some View {
        Group {
            if let certificate {
                content(certificate)
            } else {
                EmptyStateView(
                    systemImage: "questionmark.folder",
                    title: "Certificate not found",
                    message: "This certificate isn't on this device any more. It may have been deleted.",
                    actionTitle: "Back",
                    actionSystemImage: "chevron.left",
                    action: { dismiss() }
                )
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(certificate?.nickname ?? "Certificate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ certificate: Certificate) -> some View {
        let isActive = certificate.id == certificates.activeID
        return ScrollView {
            VStack(spacing: 20) {
                header(certificate, isActive: isActive)
                deviceSection(certificate.profile)
                if let profile = certificate.profile {
                    profileSection(profile)
                    CardSection("Raw Profile Data", systemImage: "curlybraces") {
                        ProfileRawDataView(profile: profile)
                    }
                } else {
                    CardSection("Profile", systemImage: "doc.badge.gearshape") {
                        Label("The provisioning profile couldn't be read.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.danger)
                            .font(.subheadline)
                    }
                }
                signingSection(certificate)
                if let profile = certificate.profile {
                    devicesSection(profile)
                    entitlementsSection(profile)
                }
                actions
            }
            .padding(Theme.padding)
        }
        .alert("Rename Certificate", isPresented: $showRename) {
            TextField("Nickname", text: $draft)
            Button("Save") {
                certificates.rename(certificate.id, to: draft)
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Change Password", isPresented: $showPassword) {
            SecureField("p12 password", text: $draft)
            Button("Save") { savePassword(draft, for: certificate) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The password is verified against the .p12 and stored in the Keychain.")
        }
        .dissolving(dissolvingOut)
    }

    /// No confirmation: the page dissolves, then the unchanged delete runs and the view pops.
    private func deleteNow() {
        guard let certificate, !dissolvingOut else { return }
        Haptics.impact(.light)
        withAnimation(DeleteMotion.dissolve) { dissolvingOut = true }
        Task {
            try? await Task.sleep(nanoseconds: DeleteMotion.dissolveNanoseconds)
            certificates.delete(certificate.id)
            toasts.show("Deleted \(certificate.nickname)", kind: .success)
            dismiss()
        }
    }

    // MARK: Sections

    private func header(_ certificate: Certificate, isActive: Bool) -> some View {
        VStack(spacing: 14) {
            CertificateGlyph(seed: certificate.nickname, size: 84)
            VStack(spacing: 4) {
                Text(certificate.nickname)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(certificate.profile?.teamName ?? "Unknown team")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                CertificateStatusBadge(status: certificate.status())
                if let type = certificate.profile?.type {
                    StatusBadge(text: type.rawValue, kind: .neutral)
                }
            }
            if let expiration = certificate.expirationDate {
                Text(expiration.expiryCountdown())
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if isActive {
                StatusBadge(text: "Active certificate", systemImage: "star.fill", kind: .info)
                    .transition(.scale.combined(with: .opacity))
            } else {
                PrimaryButton(title: "Set as Active", systemImage: "star") {
                    withAnimation(Theme.bouncy) { certificates.setActive(certificate.id) }
                    toasts.show("\(certificate.nickname) is now active", kind: .success)
                }
                .frame(maxWidth: 240)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .animation(Theme.bouncy, value: isActive)
    }

    @ViewBuilder
    private func deviceSection(_ profile: ProvisioningProfile?) -> some View {
        CardSection("This Device", systemImage: "iphone.gen3") {
            if udid.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("iOS doesn't let sideloaded apps read the UDID. Add it in Settings to check this profile.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button {
                        router.tab = .settings
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            } else if let included = profile?.containsDevice(udid) {
                if included {
                    Label(profile?.provisionsAllDevices == true ? "Enterprise profile: all devices allowed" : "This device is in the profile",
                          systemImage: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                        .font(.subheadline.weight(.medium))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("This device is NOT in the profile", systemImage: "xmark.octagon.fill")
                            .foregroundColor(Theme.danger)
                            .font(.subheadline.weight(.semibold))
                        Text("Apps signed with it won't install. Register your UDID with the certificate provider, then re-import the new profile.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Can't check without a readable profile.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func profileSection(_ profile: ProvisioningProfile) -> some View {
        CardSection("Provisioning Profile", systemImage: "doc.badge.gearshape") {
            InfoRow(label: "Name", value: profile.name)
            SoftDivider()
            InfoRow(label: "Type", value: profile.type.rawValue)
            SoftDivider()
            InfoRow(label: "Team ID", value: profile.teamID, monospaced: true, copyable: true)
            SoftDivider()
            InfoRow(label: "App ID", value: profile.bundleIDPattern, monospaced: true, copyable: true)
            if !profile.appIDName.isEmpty {
                SoftDivider()
                InfoRow(label: "App ID name", value: profile.appIDName)
            }
            if let created = profile.creationDate {
                SoftDivider()
                InfoRow(label: "Created", value: created.shortDate)
            }
            if let expires = profile.expirationDate {
                SoftDivider()
                InfoRow(label: "Expires", value: expires.shortDate)
            }
            SoftDivider()
            InfoRow(label: "UUID", value: profile.uuid, monospaced: true, copyable: true)
        }
    }

    private func signingSection(_ certificate: Certificate) -> some View {
        CardSection("Signing Certificate", systemImage: "key.fill") {
            if let summary = certificate.record.signingCertificate {
                if let name = summary.commonName {
                    InfoRow(label: "Name", value: name)
                    SoftDivider()
                }
                if let unit = summary.organizationalUnit {
                    InfoRow(label: "Team", value: unit, monospaced: true)
                    SoftDivider()
                }
                if let notAfter = summary.notAfter {
                    InfoRow(label: "Expires", value: notAfter.shortDate)
                    SoftDivider()
                }
            } else {
                Text("Details unavailable: iOS couldn't open the .p12 with the saved password.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                SoftDivider()
            }
            if let matches = certificate.record.matchesProfile {
                HStack {
                    Text("Matches profile").foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(matches ? Theme.success : Theme.danger)
                    Text(matches ? "Yes" : "No")
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                SoftDivider()
            }
            HStack {
                Text("Password").foregroundColor(.secondary)
                Spacer()
                Text(certificate.hasPassword ? "Saved in Keychain" : "Missing")
                    .foregroundColor(certificate.hasPassword ? .primary : Theme.danger)
            }
            .font(.subheadline)
            Button {
                draft = ""
                showPassword = true
            } label: {
                Label("Change Password", systemImage: "lock.rotation")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 2)
        }
    }

    private func devicesSection(_ profile: ProvisioningProfile) -> some View {
        CardSection("Devices", systemImage: "iphone") {
            if profile.provisionsAllDevices {
                Text("All devices (enterprise profile)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if profile.devices.isEmpty {
                Text("No devices listed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                DisclosureGroup("\(profile.devices.count) device\(profile.devices.count == 1 ? "" : "s")") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(profile.devices, id: \.self) { device in
                            let isMine = !udid.isEmpty && ProvisioningProfile.normalize(device) == ProvisioningProfile.normalize(udid)
                            HStack {
                                Text(device)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(isMine ? accent : .primary)
                                    .textSelection(.enabled)
                                if isMine {
                                    Spacer()
                                    StatusBadge(text: "This iPhone", kind: .info)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
    }

    private func entitlementsSection(_ profile: ProvisioningProfile) -> some View {
        CardSection("Entitlements", systemImage: "list.bullet.rectangle") {
            let items = profile.sortedEntitlements
            if items.isEmpty {
                Text("None").font(.subheadline).foregroundColor(.secondary)
            } else {
                DisclosureGroup("\(items.count) entitlement\(items.count == 1 ? "" : "s")") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.key)
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                Text(item.value)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Rename", systemImage: "pencil", style: .tinted) {
                draft = certificate?.nickname ?? ""
                showRename = true
            }
            PrimaryButton(title: "Delete Certificate", systemImage: "trash", style: .tinted) {
                deleteNow()
            }
            .environment(\.themeAccent, Theme.danger)
        }
    }

    private func savePassword(_ password: String, for certificate: Certificate) {
        Task {
            do {
                try await certificates.updatePassword(password, for: certificate.id)
                toasts.show("Password updated", kind: .success)
            } catch {
                toasts.show(error.localizedDescription, kind: .error)
            }
        }
    }
}
