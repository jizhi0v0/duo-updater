import Testing
import Foundation
@testable import DuoUpdaterCore

/// Regression coverage for issue #112's DEFECT 1 (adversarial review of PR #120):
/// `BrewFormulaReleaseService` is the SECOND cross-launch disk cache holding a
/// `Changelog` produced by `GitHubMarkdownParser` — `ChangelogDiskCache` is the
/// other — and needed the same `Changelog.parserGeneration` stamp-and-check the
/// first PR only applied to `ChangelogDiskCache`. See both types' doc comments.
///
/// Mirrors `ChangelogDiskCacheTests`'s idiom and its use of `persist` — internal
/// here, not `private`, specifically so this file doesn't need Homebrew installed
/// or a network connection to exercise the write path; see `persist`'s doc
/// comment for why.
struct BrewFormulaReleaseServiceTests {

    private static func makeRelease(itemText: String = "Fixed a thing") -> FormulaRelease {
        FormulaRelease(
            changelog: Changelog(entries: [
                Changelog.Entry(version: "1.0", date: "2026-01-01", items: [itemText]),
            ]),
            pageURL: URL(string: "https://github.com/example/example/releases/tag/v1.0"))
    }

    /// Fresh scratch directory per test.
    private func withScratchDirectory<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewFormulaReleaseServiceTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    /// The single file `persist` wrote, so a test can corrupt/rewrite it without
    /// reimplementing the service's private filename scheme.
    private func onDiskFileURL(in dir: URL) throws -> URL {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.count == 1, "expected exactly one file after a single persist(); found \(names)")
        return dir.appendingPathComponent(names[0])
    }

    // MARK: - Same generation: hit

    /// `brew info` still answers when the lookup's task is cancelled: `release(for:)`
    /// carries on and shows the result, and a killed `brew info` would read as "no
    /// release notes". The "brew" is an invented script.
    ///
    /// Mutation: `.terminateChild` in `brewInfoOffActor` → nil.
    @Test func aCancelledBrewInfoStillAnswers() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-brewinfo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let brew = dir.appendingPathComponent("brew")
        let json = #"{"formulae":[{"homepage":"https://zzfixture.invalid","urls":{"stable":{"url":"https://github.com/zzfixture/alpha/archive/refs/tags/v1.0.tar.gz"}}}]}"#
        try Data("#!/bin/sh\nsleep 0.2\ncat <<'EOF'\n\(json)\nEOF\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let path = brew.path

        let task = Task { () async -> BrewFormulaReleaseService.Info? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await BrewFormulaReleaseService.brewInfoOffActor(name: "zzfixture-alpha", brewPath: { path })
        }
        let info = await task.value

        #expect(info?.homepage == URL(string: "https://zzfixture.invalid"))
        #expect(info?.stableURL == "https://github.com/zzfixture/alpha/archive/refs/tags/v1.0.tar.gz")
    }

    @Test func sameGenerationEntryIsServed() async {
        await withScratchDirectory { dir in
            let service = BrewFormulaReleaseService(cacheDirectory: dir)
            let release = Self.makeRelease()
            await service.persist(release, name: "azure-cli", version: "1.0")
            #expect(await service.cached(for: "azure-cli", version: "1.0") == release)
        }
    }

    /// A formula's notes go to disk through the same filter as the recipe
    /// changelog cache: a signed image URL, as a block or inline, is not written.
    ///
    /// Mutation: encode `release` instead of `onDisk` in `persist` → red.
    @Test func signedImageURLsAreNotWrittenToDisk() async throws {
        try await withScratchDirectory { dir in
            let signed = URL(string: "https://cdn.example.com/b.png?X-Signature=s3cr3t-token")!
            // The line as `GitHubMarkdownParser` stores it for a rich entry: in
            // `items` and again as a `.note`.
            let line = "Faster ![x](https://cdn.example.com/c.png?sig=s3cr3t-token) sync"
            let release = FormulaRelease(
                changelog: Changelog(entries: [Changelog.Entry(
                    version: "1.0", date: nil,
                    items: [line],
                    content: [.heading("Added"), .note(line), .image(signed)])]),
                pageURL: URL(string: "https://github.com/example/example/releases/tag/v1.0"))
            await BrewFormulaReleaseService(cacheDirectory: dir).persist(release, name: "azure-cli", version: "1.0")

            let raw = try String(contentsOf: onDiskFileURL(in: dir), encoding: .utf8)
            #expect(!raw.contains("s3cr3t-token"), "the token reached the file")
            #expect(raw.contains("Faster"))
        }
    }

    // MARK: - Older generation on disk: miss

    /// An entry written at generation N-1 must be a miss at generation N. There is
    /// no way to *produce* an N-1 file through the current build (`persist` always
    /// writes `Changelog.parserGeneration`), so this rewrites the JSON `persist`
    /// wrote, simulating a build this process was never compiled as — same
    /// technique `ChangelogDiskCacheTests.staleGenerationOnDiskIsAMiss` uses.
    @Test func staleGenerationOnDiskIsAMiss() async throws {
        try await withScratchDirectory { dir in
            let service = BrewFormulaReleaseService(cacheDirectory: dir)
            await service.persist(Self.makeRelease(), name: "azure-cli", version: "1.0")
            let fileURL = try onDiskFileURL(in: dir)

            var data = try Data(contentsOf: fileURL)
            var json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let staleGeneration = Changelog.parserGeneration - 1
            #expect(staleGeneration >= 0, "parserGeneration must start at 1 or higher for this test to mean anything")
            json["parserGeneration"] = staleGeneration
            data = try JSONSerialization.data(withJSONObject: json)
            try data.write(to: fileURL)

            // Fresh instance: there is no in-memory mirror in this actor (unlike
            // `ChangelogDiskCache`, `cached` always reads the file), so this is
            // already a real disk-level check without needing a second instance —
            // kept anyway to match the sibling test's shape and rule out any future
            // memoization being added without a matching generation check.
            let reopened = BrewFormulaReleaseService(cacheDirectory: dir)
            #expect(await reopened.cached(for: "azure-cli", version: "1.0") == nil)
        }
    }

    // MARK: - Pre-generation (old-schema) file: miss, not a crash

    /// A file written before `parserGeneration` existed at all (no such key, and
    /// the bare `FormulaRelease` shape rather than the `Stored` wrapper — what
    /// `persist` wrote before this fix) must be treated as a miss.
    @Test func preGenerationSchemaFileIsAMissNotACrash() async throws {
        try await withScratchDirectory { dir in
            let service = BrewFormulaReleaseService(cacheDirectory: dir)
            await service.persist(Self.makeRelease(), name: "azure-cli", version: "1.0")
            let fileURL = try onDiskFileURL(in: dir)

            // Old shape: `FormulaRelease` encoded bare, not wrapped in `Stored`.
            let legacy = try JSONEncoder().encode(Self.makeRelease())
            try legacy.write(to: fileURL)

            let reopened = BrewFormulaReleaseService(cacheDirectory: dir)
            #expect(await reopened.cached(for: "azure-cli", version: "1.0") == nil)
        }
    }

    // MARK: - persist() always stamps the current generation

    @Test func persistStampsRunningGeneration() async throws {
        try await withScratchDirectory { dir in
            let service = BrewFormulaReleaseService(cacheDirectory: dir)
            await service.persist(Self.makeRelease(), name: "azure-cli", version: "1.0")
            let fileURL = try onDiskFileURL(in: dir)
            let json = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
            #expect(json["parserGeneration"] as? Int == Changelog.parserGeneration)
        }
    }

    // MARK: - deriveGitHub: the release a formula's stable URL names

    /// The two GitHub forms Homebrew's stable URLs take, and the tag read off
    /// the URL rather than the formula version.
    ///
    /// Mutations: drop `(?:refs/tags/)?` (the bare `/archive/` rows); drop the
    /// `.git` strip (the `.git` row); drop one extension from the second
    /// pattern (its row).
    @Test(arguments: [
        ("https://github.com/cli/cli/releases/download/v2.60.0/gh_2.60.0_macOS_arm64.zip",
         "cli", "cli", "v2.60.0"),
        ("https://github.com/Azure/azure-cli/archive/refs/tags/azure-cli-2.87.0.tar.gz",
         "Azure", "azure-cli", "azure-cli-2.87.0"),
        ("https://github.com/zzfixture/alpha/archive/v1.2.3.tar.gz",
         "zzfixture", "alpha", "v1.2.3"),
        ("https://github.com/zzfixture/alpha/archive/refs/tags/1.0.tar.xz",
         "zzfixture", "alpha", "1.0"),
        ("https://github.com/zzfixture/alpha/archive/refs/tags/1.0.tar.bz2",
         "zzfixture", "alpha", "1.0"),
        ("https://github.com/zzfixture/alpha/archive/refs/tags/1.0.zip",
         "zzfixture", "alpha", "1.0"),
        ("https://github.com/zzfixture/alpha/archive/1.0.tgz",
         "zzfixture", "alpha", "1.0"),
        ("https://github.com/zzfixture/alpha.git/releases/download/v1.0/alpha.tar.gz",
         "zzfixture", "alpha", "v1.0"),
    ])
    func deriveGitHubReadsOwnerRepoAndTag(
        url: String, owner: String, repo: String, tag: String
    ) {
        #expect(BrewFormulaReleaseService.deriveGitHub(fromStableURL: url)
            == .init(owner: owner, repo: repo, tag: tag))
    }

    /// Anything that is not one of those two forms names no release.
    @Test(arguments: [
        nil,
        "https://zzfixture.invalid/alpha-1.0.tar.gz",
        "https://github.com/zzfixture/alpha",
        "https://github.com/zzfixture/alpha/archive/refs/tags/1.0.7z",
    ] as [String?])
    func deriveGitHubNamesNoReleaseForOtherURLs(url: String?) {
        #expect(BrewFormulaReleaseService.deriveGitHub(fromStableURL: url) == nil)
    }
}
