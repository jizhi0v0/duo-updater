import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewHeadInstall` / `BrewHeadCheck` — a formula installed from HEAD, and the
/// one request that asks its upstream for the branch tip.
///
/// `urls.head` and `linked_keg` have the shape `brew info --json=v2 --installed`
/// gave on 2026-10-08 (abseil: `{"url": "https://github.com/abseil/abseil-cpp.git",
/// "branch": "master", "using": null}`). Names are fictitious (`zzfixture-*`); the
/// network is a `URLProtocol` stub and git a script this test writes — nothing
/// asks the host (CLAUDE.md "测试不能问宿主").
///
/// Each test names the mutation it exists to catch.
@Suite(.serialized) struct BrewHeadCheckTests {

    private static func entry(
        linked: String?, installed: [String], url: String = "https://github.com/zzfixture-org/zzfixture-tool.git",
        branch: String? = "main", using: String? = nil
    ) -> [String: Any] {
        var head: [String: Any] = ["url": url]
        head["branch"] = branch
        head["using"] = using
        var f: [String: Any] = [
            "name": "zzfixture-tool", "full_name": "zzfixture-tool",
            "installed": installed.map { ["version": $0] },
            "urls": ["stable": ["url": "https://example.invalid/x.tar.gz"], "head": head],
        ]
        f["linked_keg"] = linked
        return f
    }

    // MARK: - Parsing

    /// Mutation: test `installed.last` before `linked_keg` → a HEAD keg linked
    /// beside a newer stable one (or the reverse) is misread.
    @Test func theLinkedHeadKegIsAHeadInstall() {
        let head = BrewHeadInstall.parse(Self.entry(linked: "HEAD-1a2b3c4", installed: ["2.0", "HEAD-1a2b3c4"]))
        #expect(head == BrewHeadInstall(
            name: "zzfixture-tool", version: "HEAD-1a2b3c4", commit: "1a2b3c4", branch: "main",
            upstream: .github(owner: "zzfixture-org", repo: "zzfixture-tool")))
        #expect(head?.upgradeCommand == "brew upgrade --fetch-HEAD zzfixture-tool")
        #expect(BrewHeadInstall.parse(Self.entry(linked: "2.0", installed: ["HEAD-1a2b3c4", "2.0"])) == nil)
        // Linked and newest disagree: the linked keg is the one in use.
        #expect(BrewHeadInstall.parse(Self.entry(linked: "2.0", installed: ["2.0", "HEAD-1a2b3c4"])) == nil)
        #expect(BrewHeadInstall.parse(Self.entry(linked: "HEAD-1a2b3c4", installed: ["HEAD-1a2b3c4", "2.0"]))?.commit == "1a2b3c4")
        #expect(BrewHeadInstall.parse(Self.entry(linked: nil, installed: ["2.0"])) == nil)
    }

    /// A revision suffix is not part of the commit; a bare `HEAD` names none.
    /// Mutation: take everything after `HEAD-` → `1a2b3c4_1` never prefixes a SHA.
    @Test func theCommitIsTheHexAfterHead() {
        #expect(BrewHeadInstall.commit(inVersion: "HEAD-1a2b3c4_1") == "1a2b3c4")
        #expect(BrewHeadInstall.commit(inVersion: "HEAD-ABCDEF0") == "abcdef0")
        #expect(BrewHeadInstall.commit(inVersion: "HEAD") == nil)
        #expect(BrewHeadInstall.commit(inVersion: "HEAD-xyz") == nil)
        #expect(BrewHeadInstall.parse(Self.entry(linked: "HEAD", installed: ["HEAD"]))?.commit == nil)
    }

    /// Mutation: classify by `.git` suffix alone → a codeberg URL without one is
    /// `.other` (copy only); ignore `using` → an hg repo is fed to `git ls-remote`.
    @Test func upstreamsAreClassifiedTheWayBrewFetchesThem() {
        #expect(BrewHeadInstall.upstream(url: "https://github.com/o/r.git", using: nil) == .github(owner: "o", repo: "r"))
        #expect(BrewHeadInstall.upstream(url: "https://github.com/o/r", using: "git") == .github(owner: "o", repo: "r"))
        #expect(BrewHeadInstall.upstream(url: "https://gitlab.com/o/r.git", using: nil) == .git(url: "https://gitlab.com/o/r.git"))
        #expect(BrewHeadInstall.upstream(url: "https://codeberg.org/o/r", using: nil) == .git(url: "https://codeberg.org/o/r"))
        #expect(BrewHeadInstall.upstream(url: "https://hg.example.org/r", using: "hg") == .other)
        #expect(BrewHeadInstall.upstream(url: "https://git.example.org/r", using: "hg") == .other)
        #expect(BrewHeadInstall.upstream(url: "https://svn.code.sf.net/p/x/code/trunk", using: "svn") == .other)
        #expect(BrewHeadInstall.upstream(url: "", using: nil) == .other)
    }

    // MARK: - Verdict

    /// Mutation: compare for equality → a 7-character install never matches a
    /// 40-character tip, and every check says "behind".
    @Test func theInstalledAbbreviationPrefixesTheTip() {
        let tip = "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"
        #expect(BrewHeadCheck.verdict(installed: "1a2b3c4", tip: tip) == .upToDate)
        #expect(BrewHeadCheck.verdict(installed: "1A2B3C4", tip: tip) == .upToDate)
        #expect(BrewHeadCheck.verdict(installed: "9999999", tip: tip) == .behind(latest: "1a2b3c4"))
    }

    @Test func lsRemoteOutputYieldsTheFirstSha() {
        let sha = String(repeating: "a", count: 40)
        #expect(BrewHeadCheck.parseLsRemote("\(sha)\trefs/heads/main\n") == sha)
        #expect(BrewHeadCheck.parseLsRemote("") == nil)
        #expect(BrewHeadCheck.parseLsRemote("warning: something\n") == nil)
    }

    // MARK: - GitHub

    final class StubCommits: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = ""
        nonisolated(unsafe) static var headers: [String: String] = [:]
        nonisolated(unsafe) static var seen: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.seen.append(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: Self.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static func stubSession(status: Int, body: String, headers: [String: String] = [:]) -> URLSession {
        StubCommits.status = status
        StubCommits.body = body
        StubCommits.headers = headers
        StubCommits.seen = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubCommits.self]
        return URLSession(configuration: config)
    }

    private static let github = BrewHeadInstall(
        name: "zzfixture-tool", version: "HEAD-1a2b3c4", commit: "1a2b3c4", branch: "release/2",
        upstream: .github(owner: "zzfixture-org", repo: "zzfixture-tool"))

    private static let noGit: @Sendable (String, String?) async -> Result<String, BrewHeadCheck.LsRemoteError> = { _, _ in
        Issue.record("git asked for a GitHub upstream")
        return .failure(.init(message: ""))
    }

    /// The request brew's `GitHub.last_commit` makes, with the app's token in the
    /// header. Mutation: drop the Accept header → the body is JSON, not a SHA, and
    /// the check fails; drop the token → anonymous, the budget this waits for.
    @Test func gitHubIsAskedOnceForTheBranchTipWithTheToken() async throws {
        let session = Self.stubSession(status: 200, body: "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d")
        let result = await BrewHeadCheck.check(
            Self.github, session: session, token: { "zzfixture-token" }, lsRemote: Self.noGit)
        #expect(result == .upToDate)
        let request = try #require(StubCommits.seen.first)
        #expect(StubCommits.seen.count == 1)
        #expect(request.url?.absoluteString
            == "https://api.github.com/repos/zzfixture-org/zzfixture-tool/commits/release/2")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.sha")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer zzfixture-token")
        // Mutation: drop the policy → a repeat check can be answered from the
        // first one's cached tip, with no request.
        #expect(request.cachePolicy == URLRequest.versionFeedCachePolicy)
    }

    /// The token goes in this request's header, so the session must be one whose
    /// cache never reaches disk. Mutation: `.shared` → the whole request, header
    /// included, archived under ~/Library/Caches.
    @Test func theProductionSessionIsTheDisklessOne() {
        #expect(BrewHeadCheck.productionSession === URLSession.updates)
        #expect(BrewHeadCheck.productionSession.configuration.urlCache?.diskCapacity == 0)
    }

    @Test func aMovedTipIsBehind() async {
        let session = Self.stubSession(status: 200, body: "fedcba9876543210fedcba9876543210fedcba98\n")
        let result = await BrewHeadCheck.check(Self.github, session: session, token: { nil }, lsRemote: Self.noGit)
        #expect(result == .behind(latest: "fedcba9"))
        #expect(StubCommits.seen.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// A 403 with the budget at 0 is said as the rate limit, in the words the
    /// rest of the app uses. Mutation: return `.behind` or `.upToDate` on a non-200
    /// → a rate-limited answer reads as a verdict.
    @Test func aRateLimitedAnswerFailsAsTheRateLimit() async {
        let session = Self.stubSession(
            status: 403, body: #"{"message":"API rate limit exceeded"}"#, headers: ["X-RateLimit-Remaining": "0"])
        let result = await BrewHeadCheck.check(Self.github, session: session, token: { nil }, lsRemote: Self.noGit)
        guard case .failed(let message) = result else { Issue.record("\(result)"); return }
        #expect(message.localizedCaseInsensitiveContains("rate limit"))
    }

    // MARK: - git

    /// Mutation: pass `install.branch` as nil → `ls-remote` reads HEAD, which is
    /// not the branch the formula follows.
    @Test func aGitUpstreamIsAskedWithItsBranch() async {
        let install = BrewHeadInstall(
            name: "zzfixture-tool", version: "HEAD-1a2b3c4", commit: "1a2b3c4", branch: "devel",
            upstream: .git(url: "https://gitlab.example.invalid/o/r.git"))
        let asked = Asked()
        let result = await BrewHeadCheck.check(
            install, session: .shared, token: { Issue.record("token asked for git"); return nil },
            lsRemote: { url, branch in
                asked.set(url, branch)
                return .success("1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d")
            })
        #expect(result == .upToDate)
        #expect(asked.value == ["https://gitlab.example.invalid/o/r.git", "devel"])
    }

    @Test func otherUpstreamsAndCommitlessKegsAreNotAsked() async {
        let other = BrewHeadInstall(name: "a", version: "HEAD-1a2b3c4", commit: "1a2b3c4", branch: nil, upstream: .other)
        let bare = BrewHeadInstall(name: "b", version: "HEAD", commit: nil, branch: nil, upstream: .git(url: "https://x.invalid/r.git"))
        for install in [other, bare] {
            let result = await BrewHeadCheck.check(
                install, session: .shared, token: { nil },
                lsRemote: { _, _ in Issue.record("asked"); return .failure(.init(message: "")) })
            guard case .failed = result else { Issue.record("\(result)"); continue }
        }
    }

    /// The real `lsRemote` against a stand-in git that records what it was given.
    /// Mutation: drop `-c credential.helper=` → a stored password for the host
    /// (and a Keychain prompt) is in play; drop `GIT_TERMINAL_PROMPT=0` → git may
    /// wait on a prompt nobody can answer.
    @Test func lsRemoteNeverOffersCredentials() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("log")
        let git = dir.appendingPathComponent("git")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(log.path)'
        printf 'PROMPT=%s\\n' "$GIT_TERMINAL_PROMPT" >> '\(log.path)'
        printf '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d\\trefs/heads/main\\n'
        """.write(to: git, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: git.path)

        let result = await BrewHeadCheck.lsRemote(url: "https://x.invalid/r.git", branch: "main", git: git.path)
        #expect(result == .success("1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"))
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == ["-c", "credential.helper=", "ls-remote", "--", "https://x.invalid/r.git", "refs/heads/main", "PROMPT=0"])

        let missing = await BrewHeadCheck.lsRemote(url: "https://x.invalid/r.git", branch: nil, git: nil)
        guard case .failure = missing else { Issue.record("no git, yet an answer"); return }
    }

    /// Mutation: fall back to `/usr/bin/git` → the shim's "install the command line
    /// developer tools" dialog on a Mac without them.
    @Test func gitIsNeverTheXcrunShim() {
        #expect(BrewHeadCheck.gitPath(candidates: ["/nonexistent-zzfixture/git"]) == nil)
        #expect(!BrewHeadCheck.gitCandidates.contains { $0.hasPrefix("/usr/bin/") })
    }

    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String?] = []
        func set(_ url: String, _ branch: String?) { lock.lock(); stored = [url, branch]; lock.unlock() }
        var value: [String?] { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
