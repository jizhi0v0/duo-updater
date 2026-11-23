import Foundation

struct NospeakerRelease: Sendable {
    static let repository = "os6/nospeaker"
    static let api = URL(string: "https://api.github.com/repos/\(repository)/releases")!
    static let tagPattern = #"\Av([0-9]{1,9}(?:\.[0-9]{1,9}){1,2})\z"#
    static let initialDigest = "9833fb66bd273c30a929076103ec7ede48d5611ab0dbfdbf3f1e9428339e8fc5"
    static let historyPageSize = 10
    static let maximumExecutableBytes = 16 * 1024 * 1024

    struct Published: Decodable, Equatable, Sendable {
        struct Asset: Decodable, Equatable, Sendable {
            let name: String
            let digest: String?
        }

        let tag: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case draft, prerelease, assets
        }

        var version: String { String(tag.dropFirst()) }
        var isStable: Bool { !draft && !prerelease && NospeakerRelease.isStableTag(tag) }

        var digest: String? {
            let archives = assets.filter { $0.name == "nospeaker.zip" }
            guard archives.count == 1 else { return nil }
            return GitHubReleasesSource.sha256Digest(archives[0].digest)
        }

        var downloadURL: URL {
            URL(string: "https://github.com/\(NospeakerRelease.repository)/releases/download")!
                .appendingPathComponent(tag)
                .appendingPathComponent("nospeaker.zip")
        }
    }

    enum Failure: LocalizedError {
        case unreadableRelease
        case missingDigest
        case wrongDigest
        case wrongBinary

        var errorDescription: String? {
            switch self {
            case .unreadableRelease: "The stable nospeaker release could not be read."
            case .missingDigest: "The nospeaker release has no unique ZIP with a published GitHub checksum."
            case .wrongDigest: "The nospeaker download did not match its published checksum."
            case .wrongBinary: "The ZIP did not contain a valid Apple Silicon nospeaker executable from Spoken Systems."
            }
        }
    }

    typealias Fetch = @Sendable (URL, RequestPurpose, Bool, Int) async throws -> Data
    typealias Identity = @Sendable (URL) -> Bool

    var fetch: Fetch = CLIGitHubDownload.get
    var isVendorBinary: Identity = Self.isVendorBinary

    static func isVendorBinary(_ executable: URL) -> Bool {
        MachOImports.architectures(at: executable)?.contains("arm64") == true
            && CLIToolTrust.signature(of: executable, teamIdentifier: "ZST375P5XB",
                                      signingIdentifier: "nospeaker") == .vendor
    }

    static func isStableTag(_ tag: String) -> Bool {
        tag.utf8.count <= 30 && tag.range(of: tagPattern, options: .regularExpression) != nil
    }

    func latest() async throws -> Published {
        let data = try await fetch(Self.api.appendingPathComponent("latest"), .versionCheck, false, 2 * 1024 * 1024)
        guard let release = try? JSONDecoder().decode(Published.self, from: data),
              release.isStable
        else { throw Failure.unreadableRelease }
        return release
    }

    func recent() async throws -> [Published] {
        let url = URL(string: "\(Self.api.absoluteString)?per_page=\(Self.historyPageSize)")!
        let data = try await fetch(url, .versionCheck, false, 2 * 1024 * 1024)
        return try JSONDecoder().decode([Published].self, from: data)
            .prefix(Self.historyPageSize).filter { $0.isStable && $0.digest != nil }
    }

    func notes(force: Bool) async throws -> Changelog {
        let url = URL(string: "\(Self.api.absoluteString)?per_page=30")!
        let data = try await fetch(url, .changelog, force, 8 * 1024 * 1024)
        let notes = await offCooperativePool {
            StructuredChangelogDecoder.decode(
                String(decoding: data, as: UTF8.self), format: .gitHubReleases, channel: .stable,
                maxEntries: nil, tagPattern: Self.tagPattern)
        }
        guard let notes else { throw CLIToolReleaseNotesError.noSections }
        return notes
    }

    /// Put only the verified executable in caller-owned scratch space. The
    /// digest is the one observed with the version at check time.
    func verifiedExecutable(_ release: Published, at binary: URL, purpose: RequestPurpose) async throws -> String {
        guard release.isStable else { throw Failure.unreadableRelease }
        guard let digest = release.digest else { throw Failure.missingDigest }
        let data = try await fetch(release.downloadURL, purpose, purpose == .install, Self.maximumExecutableBytes)
        let archive = binary.deletingLastPathComponent().appendingPathComponent("nospeaker.zip")
        try await offCooperativePool {
            try data.write(to: archive)
            guard CLIToolTrust.matches(CLIToolTrust.sha256(of: archive), published: digest) else {
                throw Failure.wrongDigest
            }
        }
        let bytes = try await StandaloneCLIArchive.executable(
            named: "nospeaker", in: archive, limit: Self.maximumExecutableBytes)
        return try await offCooperativePool {
            try bytes.write(to: binary)
            guard isVendorBinary(binary), let fingerprint = CLIToolTrust.sha256(of: binary),
                  release.version != "1.0" || fingerprint == Self.initialDigest
            else { throw Failure.wrongBinary }
            return fingerprint
        }
    }
}
