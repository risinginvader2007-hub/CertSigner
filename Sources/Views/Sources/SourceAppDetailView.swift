import SwiftUI

/// A source app: description, screenshots, versions, and Get (sign & install) / Download & Review.
struct SourceAppDetailView: View {
    let repoID: UUID
    let appID: String

    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var importer: ImportCoordinator
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var certificates: CertificateStore
    @Environment(\.themeAccent) private var accent

    @State private var expandedDescription = false
    @State private var showAllVersions = false

    private var repo: Repository? { store.repository(repoID) }
    private var app: RepoApp? { repo?.apps.first { $0.id == appID } }

    var body: some View {
        Group {
            if let repo, let app {
                ScrollView {
                    VStack(spacing: 18) {
                        header(app, repo: repo)
                        actions(app, repo: repo)
                        if let notes = app.latest.notes {
                            CardSection("What's New", systemImage: "sparkles") {
                                Text(notes).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let description = app.appDescription {
                            descriptionSection(description)
                        }
                        if !app.screenshotURLs.isEmpty {
                            screenshots(app.screenshotURLs)
                        }
                        versionsSection(app, repo: repo)
                        infoSection(app, repo: repo)
                    }
                    .padding(Theme.padding)
                    // Animate only when a download starts / starts importing / ends — never on byte counts.
                    .animation(Theme.spring, value: store.download(repoID: repo.id, app: app)?.importing)
                }
                .background(AmbientBackground())
                .navigationTitle(app.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                EmptyStateView(systemImage: "shippingbox", title: "App unavailable",
                               message: "This app is no longer listed by the source.")
            }
        }
    }

    // MARK: Sections

    private func header(_ app: RepoApp, repo: Repository) -> some View {
        VStack(spacing: 10) {
            RemoteIcon(url: app.iconURL, name: app.name, size: 96)
            Text(app.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if let line = app.subtitle ?? app.developer {
                Text(line).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                StatusBadge(text: "v\(app.latest.version)", kind: .info)
                if let size = app.latest.size {
                    StatusBadge(text: size.byteString, systemImage: "internaldrive", kind: .neutral)
                }
                if let minOS = app.latest.minOSVersion {
                    StatusBadge(text: "iOS \(minOS)+", systemImage: "iphone", kind: .neutral)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actions(_ app: RepoApp, repo: Repository) -> some View {
        if let download = store.download(repoID: repo.id, app: app) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(download.importing ? "Importing…" : "Downloading…")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if !download.importing {
                            Text(progressText(download))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .transaction { $0.animation = nil }
                    if let progress = download.progress, !download.importing {
                        ProgressBar(progress: progress)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if !download.importing {
                        Button(role: .destructive) {
                            store.cancelDownload(repoID: repo.id, app: app)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 10) {
                PrimaryButton(title: "Get", systemImage: "arrow.down.app.fill") {
                    get(app, version: nil, repo: repo, signAndInstall: true)
                }
                PrimaryButton(title: "Download & Review", systemImage: "slider.horizontal.3", style: .tinted) {
                    get(app, version: nil, repo: repo, signAndInstall: false)
                }
                Text("Get downloads the IPA, signs it with your active certificate and defaults, then shows the install prompt. Download & Review lets you change the options first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .transition(.opacity)
        }
    }

    private func descriptionSection(_ text: String) -> some View {
        CardSection("About", systemImage: "text.alignleft") {
            Text(text)
                .font(.subheadline)
                .lineLimit(expandedDescription ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
            if text.count > 220 {
                Button(expandedDescription ? "Less" : "More") {
                    withAnimation(Theme.spring) { expandedDescription.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func screenshots(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCREENSHOTS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(urls, id: \.self) { url in
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                Rectangle().fill(Theme.surface)
                                    .frame(width: 180)
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func versionsSection(_ app: RepoApp, repo: Repository) -> some View {
        let visible = showAllVersions ? app.versions : Array(app.versions.prefix(3))
        let busy = store.download(repoID: repo.id, app: app) != nil
        return CardSection("Versions", systemImage: "clock.arrow.circlepath") {
            ForEach(visible) { version in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(version.version).font(.subheadline.weight(.semibold))
                            if version.id == app.latest.id {
                                StatusBadge(text: "Latest", kind: .success)
                            }
                        }
                        Text(versionDetail(version)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button {
                            get(app, version: version, repo: repo, signAndInstall: true)
                        } label: {
                            Label("Sign & Install", systemImage: "arrow.down.app")
                        }
                        Button {
                            get(app, version: version, repo: repo, signAndInstall: false)
                        } label: {
                            Label("Download & Review", systemImage: "slider.horizontal.3")
                        }
                        Button {
                            UIPasteboard.general.string = version.downloadURL.absoluteString
                        } label: {
                            Label("Copy Download Link", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(busy ? .secondary : accent)
                    }
                    .disabled(busy)
                    .accessibilityLabel("Get version \(version.version)")
                }
                if version.id != visible.last?.id { SoftDivider() }
            }
            if app.versions.count > 3 {
                Button(showAllVersions ? "Show fewer" : "Show all \(app.versions.count) versions") {
                    withAnimation(Theme.spring) { showAllVersions.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func infoSection(_ app: RepoApp, repo: Repository) -> some View {
        CardSection("Information", systemImage: "info.circle") {
            if !app.bundleID.isEmpty {
                InfoRow(label: "Bundle ID", value: app.bundleID, copyable: true)
                SoftDivider()
            }
            if let developer = app.developer {
                InfoRow(label: "Developer", value: developer)
                SoftDivider()
            }
            if let category = app.category {
                InfoRow(label: "Category", value: category)
                SoftDivider()
            }
            InfoRow(label: "Source", value: repo.name)
        }
    }

    // MARK: Helpers

    private func get(_ app: RepoApp, version: RepoVersion?, repo: Repository, signAndInstall: Bool) {
        SourceActions.get(app, version: version, from: repo, signAndInstall: signAndInstall, store: store,
                          importer: importer, library: library, toasts: toasts, certificates: certificates)
    }

    private func versionDetail(_ version: RepoVersion) -> String {
        var parts: [String] = []
        if let build = version.buildVersion, build != version.version { parts.append("build \(build)") }
        if let date = version.date { parts.append(date.shortDate) }
        if let size = version.size { parts.append(size.byteString) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func progressText(_ download: RepoDownload) -> String {
        var text = download.received.byteString
        if let expected = download.expected, expected > 0 {
            text += " of \(expected.byteString)"
        }
        if let speed = download.bytesPerSecond {
            text += " · \(Int64(speed).byteString)/s"
        }
        return text
    }
}
