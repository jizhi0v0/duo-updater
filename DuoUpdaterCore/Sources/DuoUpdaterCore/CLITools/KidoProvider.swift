import Foundation

public struct KidoInstall: Sendable, Equatable {
    public let path: String
    public let version: String?
}

/// kido's official script places its CLI and helpers under one prefix.
/// History: docs/app-audits/kido.md#历史与实测
public struct KidoProvider: CLIToolProvider {
    public let kind: CLIToolKind = .kido
    public let readsGitHubAPI = true

    private let prefixes: [URL]
    private let release: KidoRelease
    private let readVersion: @Sendable (URL) -> KidoScanner.Version

    public init() {
        self.init(home: FileManager.default.homeDirectoryForCurrentUser,
                  customPrefix: ProcessInfo.processInfo.environment["KIDO_PREFIX"])
    }

    init(home: URL, customPrefix: String? = nil, release: KidoRelease = KidoRelease(),
         readVersion: @escaping @Sendable (URL) -> KidoScanner.Version = KidoScanner.version(at:)) {
        var candidates = [home.appendingPathComponent(".local", isDirectory: true)]
        if let customPrefix, customPrefix.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: customPrefix, isDirectory: true))
        }
        prefixes = candidates
        self.release = release
        self.readVersion = readVersion
    }

    private func installations() -> [KidoInstall] {
        var seen: Set<String> = []
        return prefixes.compactMap { candidate in
            guard let prefix = CLIToolProcesses.realpath(candidate.path), !FlyctlScanner.isOtherOwner(prefix),
                  seen.insert(prefix).inserted
            else { return nil }
            let path = prefix + "/bin/kido"
            let helpers = prefix + "/libexec/kido"
            guard CLIToolProcesses.realpath(path) == path, CLIToolProcesses.realpath(helpers) == helpers,
                  StandaloneCLIFileStamp.read(at: path) != nil,
                  StandaloneCLIFileStamp.read(at: helpers + "/kido-agent") != nil,
                  StandaloneCLIFileStamp.read(at: helpers + "/kido-vmm") != nil
            else { return nil }
            switch readVersion(URL(fileURLWithPath: path)) {
            case .foreign: return nil
            case .unreadable: return KidoInstall(path: path, version: nil)
            case .known(let version): return KidoInstall(path: path, version: version)
            }
        }
    }

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool {
            installations().map { CLIToolSighting(kind: kind, path: $0.path, version: $0.version) }
        }
    }

    public func check() async -> CLIToolReport {
        let installs = await offCooperativePool { installations() }
        let latest: Result<NpmVersion, any Error>?
        if installs.contains(where: { $0.version != nil }) {
            do { latest = .success(try await release.latest()) }
            catch { latest = .failure(error) }
        } else {
            latest = nil
        }
        return CLIToolReport(kind: kind, statuses: installs.map { Self.status($0, latest: latest) }, context: .kido)
    }

    static func status(_ install: KidoInstall, latest: Result<NpmVersion, any Error>?) -> CLIToolStatus {
        func verdict(_ state: CLIToolState, version: NpmVersion? = nil,
                     withheld: CLIToolWithheld? = nil, command: CLIToolCommand? = nil) -> CLIToolStatus {
            CLIToolStatus(kind: .kido, path: install.path, installedVersion: install.version,
                          latestVersion: version?.description, channel: nil, state: state, oneClick: nil,
                          withheld: withheld, note: nil, manualCommand: command, detail: .kido(install))
        }
        guard let installed = install.version.flatMap(KidoRelease.stableVersion), let latest else {
            return verdict(.unknown, withheld: .versionUnreadable)
        }
        switch latest {
        case .failure(let error):
            let limited = GitHubRateLimitGate.isRefusal(error) || (error as? CLIToolReleaseNotesError) == .rateLimited
            return verdict(.unknown, withheld: limited ? .rateLimited : .channelUnreadable)
        case .success(let version):
            if installed == version { return verdict(.upToDate, version: version) }
            if installed > version { return verdict(.ahead, version: version) }
            let command = CLIToolCommand(executable: install.path, arguments: ["upgrade"], pathPrefix: nil,
                                         shellLine: NvmCheck.shellQuoted(install.path) + " upgrade")
            return verdict(.updateAvailable, version: version, withheld: .ownUpgrade, command: command)
        }
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        .notOffered
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await release.notes(force: force)
    }
}

enum KidoScanner {
    static let module = "github.com/kido-sh/kido"

    // The first tag was built before it was published, so its Go module version is a pseudo-version.
    static let firstModuleVersion = "0.0.0-20261123171353-ad7c104e3b48"
    static let firstExecutableDigest = "aa328f25277c572b2752721b2c74dd0d4e83d956b3bfb21d33f06648dec8fd98"

    enum Version: Sendable, Equatable {
        case foreign
        case unreadable
        case known(String)
    }

    static func version(at url: URL) -> Version {
        guard ClaudeCodeRelease.platform(of: url) == "darwin-arm64", let info = GoBuildInfo.read(at: url) else {
            return .foreign
        }
        return version(info) { CLIToolTrust.sha256(of: url) }
    }

    static func version(_ info: GoBuildInfo, digest: () -> String?) -> Version {
        guard info.packagePath == module + "/cmd/kido", let main = info.main, main.path == module,
              main.replacement == nil
        else { return .foreign }
        guard let version = main.builtVersion else { return .unreadable }
        if KidoRelease.stableVersion(version) != nil { return .known(version) }
        if version == firstModuleVersion, CLIToolTrust.matches(digest(), published: firstExecutableDigest) {
            return .known("0.1.0")
        }
        return .unreadable
    }
}

struct KidoRelease: Sendable {
    static let repository = "kido-sh/kido"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let notesURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!
    static let tagPattern = #"^v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))$"#

    typealias Fetch = @Sendable (URL, RequestPurpose, Bool, Int) async throws -> Data
    var fetch: Fetch = CLIGitHubDownload.get

    private struct Published: Decodable {
        struct Asset: Decodable {
            let name: String
        }

        let tag: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case draft, prerelease, assets
        }
    }

    enum Failure: LocalizedError {
        case invalidRelease

        var errorDescription: String? {
            "The latest kido release has no signed Apple Silicon archive."
        }
    }

    static func stableVersion(_ text: String) -> NpmVersion? {
        guard text.utf8.count <= 59, let version = NpmVersion(text),
              !version.isPrerelease, version.description == text
        else { return nil }
        return version
    }

    func latest() async throws -> NpmVersion {
        let data = try await fetch(Self.latestURL, .versionCheck, false, 2 * 1024 * 1024)
        guard let published = try? JSONDecoder().decode(Published.self, from: data),
              !published.draft, !published.prerelease, published.tag.hasPrefix("v"),
              let version = Self.stableVersion(String(published.tag.dropFirst()))
        else { throw Failure.invalidRelease }

        let names = published.assets.map(\.name)
        let required = ["kido-\(version)-darwin-arm64.tar.gz", "SHA256SUMS", "SHA256SUMS.sig"]
        guard required.allSatisfy({ name in names.filter { $0 == name }.count == 1 }) else {
            throw Failure.invalidRelease
        }
        return version
    }

    func notes(force: Bool) async throws -> Changelog {
        let data = try await fetch(Self.notesURL, .changelog, force, 8 * 1024 * 1024)
        let notes = await offCooperativePool {
            StructuredChangelogDecoder.decode(
                String(decoding: data, as: UTF8.self), format: .gitHubReleases, channel: .stable,
                maxEntries: nil, tagPattern: Self.tagPattern)
        }
        guard let notes else { throw CLIToolReleaseNotesError.noSections }
        return notes
    }
}
