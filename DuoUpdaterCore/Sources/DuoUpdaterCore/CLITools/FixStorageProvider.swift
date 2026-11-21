import Foundation

public struct FixStorageInstall: Sendable, Equatable {
    public let path: String
    public let version: String

    public init(path: String, version: String) {
        self.path = path
        self.version = version
    }
}

/// The default install owned by govijr's shell installer. npm links its
/// package into ~/.fix-storage; the installer links ~/.local/bin to that
/// copy. The first public release has no --version switch.
public struct FixStorageProvider: CLIToolProvider {
    // History: docs/app-audits/fix-storage.md#历史与实测
    public let kind: CLIToolKind = .fixStorage

    private static let repository = "govijr/fix-storage"
    private static let installer = "https://raw.githubusercontent.com/\(repository)/main/install.sh"
    private let home: URL
    private let session: URLSession

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, session: URLSession = .updates) {
        self.home = home
        self.session = session
    }

    public func scan() async -> [CLIToolSighting] {
        guard let install = await offCooperativePool({ Self.installed(in: home) }) else { return [] }
        return [sighting(install)]
    }

    public func check() async -> CLIToolReport {
        guard let install = await offCooperativePool({ Self.installed(in: home) }) else {
            return CLIToolReport(kind: kind, statuses: [], context: .fixStorage)
        }
        let url = URL(string: "https://github.com/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 20
        let response = try? await session.countedData(for: request, purpose: .versionCheck)
        let http = response?.1 as? HTTPURLResponse
        let latest = http?.statusCode == 200 ? http?.url.flatMap(Self.releaseVersion) : nil
        let status = Self.status(install, latest: latest)
        return CLIToolReport(kind: kind, statuses: [status], context: .fixStorage, sightings: [sighting(install)])
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        .notOffered
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard let version = status.latestVersion ?? status.installedVersion, Self.stableVersion(version) != nil
        else { throw CLIToolReleaseNotesError.noSections }
        let url = URL(string: "https://raw.githubusercontent.com/\(Self.repository)/v\(version)/CHANGELOG.md")!
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 20
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CLIToolReleaseNotesError.status(http, url: url)
        }
        let notes = await offCooperativePool { Self.parseNotes(data, source: url) }
        guard let notes else { throw CLIToolReleaseNotesError.noSections }
        return notes
    }

    static func parseNotes(_ data: Data, source: URL) -> Changelog? {
        let recipe = ChangelogRecipe(
            bundleID: "fix-storage", source: source,
            entryPattern: #"(?:^|\n)## \[(?<version>[0-9]+\.[0-9]+\.[0-9]+)\] - (?<date>[^\n]+)\n(?<body>.*?)(?=\n## |\z)"#,
            itemPatterns: [#"(?:^|\n)-\s+(?<item>.+?)(?=\n-\s|\n### |\n\[|\z)"#],
            markdownSource: true, headingPattern: #"(?:^|\n)### (?<heading>[^\n]+)"#)
        return ChangelogExtractor.extract(from: String(decoding: data, as: UTF8.self), using: recipe)
    }

    static func installed(in home: URL) -> FixStorageInstall? {
        let fm = FileManager.default
        let root = home.resolvingSymlinksInPath()
        let launcher = root.appendingPathComponent(".local/bin/fix-storage")
        let modules = root.appendingPathComponent(".fix-storage/node_modules")
        let npmLink = modules.appendingPathComponent(".bin/fix-storage")
        let package = modules.appendingPathComponent("fix-storage")
        let manifest = package.appendingPathComponent("package.json")
        // Recognize the two links the installer and npm create. A PATH-only
        // wrapper or an npm-global install is not this installer's copy.
        guard let target = try? fm.destinationOfSymbolicLink(atPath: launcher.path),
              URL(fileURLWithPath: target, relativeTo: launcher.deletingLastPathComponent())
                  .standardizedFileURL.path == npmLink.path,
              (try? fm.destinationOfSymbolicLink(atPath: npmLink.path)) != nil,
              manifest.resolvingSymlinksInPath().path == manifest.path,
              let metadata = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              metadata.isRegularFile == true, metadata.isSymbolicLink != true, let size = metadata.fileSize, size < 65_536,
              let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == "fix-storage",
              let version = json["version"] as? String, stableVersion(version) != nil,
              let bin = (json["bin"] as? [String: String])?["fix-storage"], !bin.hasPrefix("/")
        else { return nil }
        let binary = package.appendingPathComponent(bin).standardizedFileURL
        guard binary.path.hasPrefix(package.path + "/"),
              binary.resolvingSymlinksInPath().path == binary.path,
              launcher.resolvingSymlinksInPath().path == binary.path,
              (try? binary.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              fm.isExecutableFile(atPath: binary.path)
        else { return nil }
        return FixStorageInstall(path: launcher.path, version: version)
    }

    static func releaseVersion(_ url: URL) -> NpmVersion? {
        let prefix = "/\(repository)/releases/tag/v"
        guard url.scheme == "https", url.host == "github.com", url.path.hasPrefix(prefix) else { return nil }
        return stableVersion(String(url.path.dropFirst(prefix.count)))
    }

    private static func stableVersion(_ text: String) -> NpmVersion? {
        guard text.utf8.count <= 32, let version = NpmVersion(text),
              !version.isPrerelease, text == version.description else { return nil }
        return version
    }

    static func status(_ install: FixStorageInstall, latest: NpmVersion?) -> CLIToolStatus {
        var state: CLIToolState = .unknown
        var manualCommand: CLIToolCommand?
        var withheld: CLIToolWithheld? = .channelUnreadable
        if let installed = stableVersion(install.version), let latest {
            withheld = nil
            if installed < latest {
                state = .updateAvailable
                // The vendor script removes the old directory before the
                // final move and has no lock. Leave its invocation to the user.
                withheld = .unsupportedInstaller
                manualCommand = CLIToolCommand(
                    executable: "curl",
                    arguments: ["-fsSL", installer, "|", "/usr/bin/env", "-u", "FIX_STORAGE_TARBALL",
                                "-u", "FIX_STORAGE_REPO", "-u", "FIX_STORAGE_HOME", "-u", "FIX_STORAGE_BIN",
                                "/bin/sh", "-s", "--", "--version", latest.description],
                    pathPrefix: nil)
            } else {
                state = installed == latest ? .upToDate : .ahead
            }
        }
        return CLIToolStatus(kind: .fixStorage, path: install.path, installedVersion: install.version,
                             latestVersion: latest?.description, channel: nil, state: state, oneClick: nil,
                             withheld: withheld, note: nil, manualCommand: manualCommand, detail: .fixStorage(install))
    }

    private func sighting(_ install: FixStorageInstall) -> CLIToolSighting {
        CLIToolSighting(kind: kind, path: install.path, version: install.version)
    }
}
