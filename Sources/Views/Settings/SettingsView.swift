import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var router: TabRouter
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKeys.accent) private var accent: AccentOption = .blue
    @AppStorage(SettingsKeys.deviceUDID) private var udid = ""
    @AppStorage(SettingsKeys.installMethod) private var installMethod: InstallMethod = .automatic
    @State private var cacheSize: Int64 = 0

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { _ in Haptics.selection() }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent colour")
                        AccentPicker(selection: $accent)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Paste your UDID", text: $udid)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if !udid.isEmpty {
                        Button("Clear UDID", role: .destructive) { udid = "" }
                    }
                } header: {
                    Text("This Device")
                } footer: {
                    Text("Sideloaded apps can't read the UDID. Get it from a computer (Finder, iTunes or 3uTools) or a UDID website in Safari, then paste it here. It's only used to check whether this iPhone is in your profiles.")
                }

                Section("Certificates") {
                    NavigationLink {
                        CertificatesView()
                    } label: {
                        HStack {
                            Label("Certificates", systemImage: "checkmark.seal")
                            Spacer()
                            Text(certificates.active?.nickname ?? "None")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Install") {
                    NavigationLink {
                        InstallSettingsView()
                    } label: {
                        HStack {
                            Label("Install Method & Server", systemImage: "arrow.down.app")
                            Spacer()
                            Text(installMethod.title)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Storage") {
                    Button(role: .destructive) {
                        CacheService.clear()
                        withAnimation { cacheSize = CacheService.size() }
                        toasts.show("Cache cleared", kind: .success)
                    } label: {
                        HStack {
                            Label("Clear Cache", systemImage: "trash")
                            Spacer()
                            Text(cacheSize.byteString)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                    if let url = URL(string: "https://github.com/risinginvader2007-hub/CertSigner") {
                        Link(destination: url) {
                            Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    Text("CertSigner signs apps with your own certificates for your own devices.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    Label("App icon picker and log export arrive in a later stage.", systemImage: "hammer")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .floatingTabBarInset()
            .task { cacheSize = CacheService.size() }
        }
    }
}

struct AccentPicker: View {
    @Binding var selection: AccentOption

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AccentOption.allCases) { option in
                    Button {
                        withAnimation(Theme.bouncy) { selection = option }
                        Haptics.selection()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                            Circle()
                                .strokeBorder(option.color, lineWidth: 2.5)
                                .frame(width: 42, height: 42)
                                .opacity(selection == option ? 1 : 0)
                                .scaleEffect(selection == option ? 1 : 0.7)
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .transition(.scale)
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.85))
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}
