import CryptoKit
import Foundation

struct MulticaRelease: Sendable {
    static let repository = "multica-ai/multica"
    static let api = URL(string: "https://api.github.com/repos/\(repository)/releases")!
    static let notesURL = URL(string: "\(api.absoluteString)?per_page=30")!
    static let versionPattern = #"v([0-9]{1,10}\.[0-9]{1,10}\.[0-9]{1,10})"#
    static let maximumArchiveBytes = 96 * 1024 * 1024

    struct Published: Sendable, Decodable {
        struct Asset: Sendable, Decodable {
            let name: String
            let digest: String?

            var sha256: String? { GitHubReleasesSource.sha256Digest(digest) }
        }

        let tag: String
        let assets: [Asset]
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case assets, draft, prerelease
        }

        var version: String { String(tag.dropFirst()) }
        var stable: Bool {
            !draft && !prerelease && tag.hasPrefix("v") && MulticaRelease.isVersion(version)
        }

        func asset(named name: String) -> Asset? {
            let matches = assets.filter { $0.name == name }
            return matches.count == 1 ? matches.first : nil
        }

        func archive(for architecture: MulticaBinary.Architecture) -> Asset? {
            let versioned = "multica-cli-\(version)-darwin-\(architecture.rawValue).tar.gz"
            if assets.contains(where: { $0.name == versioned }) { return asset(named: versioned) }
            return asset(named: "multica_darwin_\(architecture.rawValue).tar.gz")
        }

        var checksums: Asset? { asset(named: "checksums.txt") }

        func downloadURL(for asset: Asset) -> URL {
            URL(string: "https://github.com/\(MulticaRelease.repository)/releases/download")!
                .appendingPathComponent(tag)
                .appendingPathComponent(asset.name)
        }
    }

    enum Failure: LocalizedError {
        case unreadableRelease
        case missingArchive
        case invalidChecksums
        case wrongDigest

        var errorDescription: String? {
            switch self {
            case .unreadableRelease: "The Multica release could not be read."
            case .missingArchive: "The Multica release has no matching archive and checksum manifest."
            case .invalidChecksums: "The Multica archive checksum is missing, invalid, or disagrees with GitHub."
            case .wrongDigest: "The Multica download did not match its published checksum."
            }
        }
    }

    typealias Fetch = @Sendable (URL, RequestPurpose, Bool, Int) async throws -> Data
    let fetch: Fetch

    init(fetch: @escaping Fetch = CLIGitHubDownload.get) {
        self.fetch = fetch
    }

    static func isVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 10 && $0.utf8.allSatisfy { (48...57).contains($0) }
        }
    }

    func latest() async throws -> Published {
        try await release(at: Self.api.appendingPathComponent("latest"))
    }

    func tagged(_ version: String) async throws -> Published {
        guard Self.isVersion(version) else { throw Failure.unreadableRelease }
        let published = try await release(at: Self.api.appendingPathComponent("tags/v\(version)"))
        guard published.version == version else { throw Failure.unreadableRelease }
        return published
    }

    private func release(at url: URL) async throws -> Published {
        let data = try await fetch(url, .versionCheck, false, 2 * 1024 * 1024)
        guard let published = try? JSONDecoder().decode(Published.self, from: data), published.stable else {
            throw Failure.unreadableRelease
        }
        return published
    }

    func notes(force: Bool) async throws -> Changelog {
        let data = try await fetch(Self.notesURL, .changelog, force, 8 * 1024 * 1024)
        let notes = await offCooperativePool {
            StructuredChangelogDecoder.decode(
                String(decoding: data, as: UTF8.self), format: .gitHubReleases, channel: .stable,
                maxEntries: nil, tagPattern: "^\(Self.versionPattern)$")
        }
        guard let notes else { throw CLIToolReleaseNotesError.noSections }
        return notes
    }

    /// Use the vendor's exact checksum entry for this asset. Compare the two
    /// published values when GitHub also supplies asset digests.
    func verifiedArchive(_ release: Published, architecture: MulticaBinary.Architecture, into file: URL)
        async throws
    {
        guard let archive = release.archive(for: architecture), let checksums = release.checksums else {
            throw Failure.missingArchive
        }
        let manifest = try await fetch(release.downloadURL(for: checksums), .install, true, 64 * 1024)
        let manifestVerified = await offCooperativePool {
            guard let metadata = checksums.digest else { return true }
            let digest = SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined()
            return checksums.sha256 != nil
                && CLIToolTrust.matches(digest, published: metadata)
        }
        guard manifestVerified,
              let digest = Self.archiveDigest(in: manifest, name: archive.name),
              archive.digest == nil || archive.sha256 == digest
        else { throw Failure.invalidChecksums }

        let data = try await fetch(release.downloadURL(for: archive), .install, true, Self.maximumArchiveBytes)
        try await offCooperativePool {
            try data.write(to: file)
            guard CLIToolTrust.matches(CLIToolTrust.sha256(of: file), published: digest) else {
                throw Failure.wrongDigest
            }
        }
    }

    static func archiveDigest(in data: Data, name: String) -> String? {
        guard let manifest = String(data: data, encoding: .utf8) else { return nil }
        let matches = manifest.split(whereSeparator: \.isNewline).compactMap { line -> Substring? in
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count == 2 else { return nil }
            let filename = words[1].hasPrefix("*") ? words[1].dropFirst() : words[1]
            return filename == name ? words[0] : nil
        }
        guard matches.count == 1, let digest = matches.first else { return nil }
        return GitHubReleasesSource.sha256Digest("sha256:\(digest)")
    }
}
