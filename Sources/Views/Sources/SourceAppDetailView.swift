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
                    VStack(spacing: Space.x4) {
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
                    .animation(Theme.spring, value: store.anyDownload(repoID: repo.id, app: app)?.state.importing)
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
        VStack(spacing: Space.x3) {
            RemoteIcon(url: app.iconURL, name: app.name, size: 96)
            Text(app.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if let line = app.subtitle ?? app.developer {
                Text(line).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: Space.x2) {
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
        .padding(.vertical, Space.x2)
    }

    @ViewBuilder
    private func actions(_ app: RepoApp, repo: Repository) -> some View {
        if let running = store.anyDownload(repoID: repo.id, app: app) {
            let download = running.state
            Card {
                VStack(alignment: .leading, spacing: Space.x3) {
                    HStack {
                        Text("\(download.importing ? "Importing" : "Downloading") \(running.version.version)…")
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
                            store.cancelDownload(repoID: repo.id, app: app, version: running.version)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .transition(.opacity)
        } else {
            let reason = store.unavailableReason(app.latest)
            VStack(spacing: Space.x3) {
                PrimaryButton(title: "Get", systemImage: "arrow.down.app.fill") {
                    get(app, version: nil, repo: repo, signAndInstall: true)
                }
                .disabled(reason != nil)
                PrimaryButton(title: "Download & Review", systemImage: "slider.horizontal.3", style: .tinted) {
                    get(app, version: nil, repo: repo, signAndInstall: false)
                }
                .disabled(reason != nil)
                Text(reason.map { "Version \(app.latest.version): \($0) Pick another version below." }
                     ?? "Get downloads the IPA, signs it with your active certificate and defaults, then shows the install prompt. Download & Review lets you change the options first.")
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
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("SCREENSHOTS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, Space.x1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x3) {
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
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                }
                .padding(.horizontal, Space.x1)
            }
        }
    }

    /// Every version, newest first: version, size, date, minimum iOS, "Latest" on the top one, its
    /// own GET (that exact version) and a menu with Download & Review / Copy Download Link.
    private func versionsSection(_ app: RepoApp, repo: Repository) -> some View {
        let visible = showAllVersions ? app.versions : Array(app.versions.prefix(Self.collapsedVersions))
        return CardSection(app.versions.count > 1 ? "Versions (\(app.versions.count))" : "Version",
                           systemImage: "clock.arrow.circlepath") {
            LazyVStack(alignment: .leading, spacing: Space.x2) {
                ForEach(visible) { version in
                    versionRow(version, app: app, repo: repo)
                    if version.id != visible.last?.id { SoftDivider() }
                }
            }
            if app.versions.count > Self.collapsedVersions {
                Button(showAllVersions ? "Show fewer" : "Show all \(app.versions.count) versions") {
                    withAnimation(Theme.spring) { showAllVersions.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private static let collapsedVersions = 5

    private func versionRow(_ version: RepoVersion, app: RepoApp, repo: Repository) -> some View {
        let reason = store.unavailableReason(version)
        return HStack(spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.x2) {
                    Text(version.version).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if version.id == app.latest.id {
                        StatusBadge(text: "Latest", kind: .success)
                    }
                }
                Text(versionDetail(version)).font(.caption).foregroundColor(.secondary)
                if let reason {
                    Text(reason).font(.caption).foregroundColor(Theme.warning)
                }
            }
            Spacer(minLength: Space.x2)
            Menu {
                Button {
                    get(app, version: version, repo: repo, signAndInstall: true)
                } label: {
                    Label("Sign & Install", systemImage: "arrow.down.app")
                }
                .disabled(reason != nil)
                Button {
                    get(app, version: version, repo: repo, signAndInstall: false)
                } label: {
                    Label("Download & Review", systemImage: "slider.horizontal.3")
                }
                .disabled(reason != nil)
                if let link = version.downloadURL {
                    Button {
                        UIPasteboard.general.string = link.absoluteString
                    } label: {
                        Label("Copy Download Link", systemImage: "doc.on.doc")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for version \(version.version)")
            GetButton(repo: repo, app: app, version: version)
        }
        .accessibilityElement(children: .contain)
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
        if let minOS = version.minOSVersion { parts.append("iOS \(minOS)+") }
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
