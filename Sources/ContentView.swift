import SwiftUI
import UniformTypeIdentifiers

private enum Picker: Identifiable {
    case p12, profile, ipa
    var id: Int { hashValue }
}

struct ContentView: View {
    @EnvironmentObject var store: CertStore
    @State private var picker: Picker?

    private var types: [UTType] {
        switch picker {
        case .p12: return [UTType(filenameExtension: "p12") ?? .data]
        case .profile: return [UTType(filenameExtension: "mobileprovision") ?? .data]
        case .ipa: return [UTType(filenameExtension: "ipa") ?? .data]
        case .none: return [.data]
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Certificate (.p12)") {
                    Button(store.p12Name ?? "Import .p12") { picker = .p12 }
                    SecureField("p12 password", text: $store.p12Password)
                    Button("Save password") { store.savePassword() }
                }

                Section("Provisioning profile") {
                    Button(store.profileName ?? "Import .mobileprovision") { picker = .profile }
                    if let p = store.profile {
                        LabeledContent("Team ID", value: p.teamID)
                        LabeledContent("App ID", value: p.appID)
                        LabeledContent("Devices", value: "\(p.deviceCount)")
                        if let exp = p.expiration {
                            LabeledContent("Expires", value: exp.formatted(date: .abbreviated, time: .omitted))
                        }
                        if p.isExpired {
                            Text("This profile has expired.").foregroundColor(.red)
                        }
                    }
                }

                Section("App to sign (.ipa)") {
                    Button(store.ipa?.fileName ?? "Import .ipa") { picker = .ipa }
                    if let i = store.ipa {
                        LabeledContent("Name", value: i.appName)
                        LabeledContent("Bundle ID", value: i.bundleID)
                        LabeledContent("Version", value: i.version)
                    }
                }

                Section {
                    Button("Sign & Install") {}
                        .disabled(true)
                    Text("Signing and install come in the next stage.")
                        .font(.footnote).foregroundColor(.secondary)
                }

                if !store.message.isEmpty {
                    Section { Text(store.message).font(.footnote) }
                }
            }
            .navigationTitle("CertSigner")
        }
        .fileImporter(
            isPresented: Binding(get: { picker != nil }, set: { if !$0 { picker = nil } }),
            allowedContentTypes: types
        ) { result in
            let current = picker
            picker = nil
            guard case .success(let url) = result else { return }
            switch current {
            case .p12: store.importP12(url)
            case .profile: store.importProfile(url)
            case .ipa: store.importIPA(url)
            case .none: break
            }
        }
    }
}
