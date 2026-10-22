import Testing
import Foundation
@testable import DuoUpdaterCore

/// `RuntimeSecurityRules`, `RuntimeInstall` and `RuntimeSecurityFeeds` — the
/// security notices for Node.js and Homebrew PHP.
///
/// Fixtures in `Fixtures/runtime-security/` are real responses fetched
/// 2026-10-22, trimmed: `nodejs-dist-index.json` keeps the v24, v25 and v26
/// entries of https://nodejs.org/dist/index.json and two of v20, verbatim;
/// `nodejs-release-schedule.json` and `php-releases-branches.json` are whole;
/// `php-src-security-advisories.json` keeps eight advisories of
/// `GET /repos/php/php-src/security-advisories?per_page=100`, with
/// `description`, `credits`, `publisher` and the CVSS fields dropped.
/// Nothing asks the host: the network is a `URLProtocol` stub and every
/// Homebrew or nvm layout a temporary directory.
///
/// Each test names the mutation it exists to catch.
@Suite(.serialized) struct RuntimeSecurityTests {

    private static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/runtime-security/\(name)"))
    }

    private static func data(
        node: Bool = true, schedule: Bool = true, branches: Bool = true, advisories: Bool = true
    ) throws -> RuntimeSecurityData {
        RuntimeSecurityData(
            nodeReleases: node ? NodeReleaseIndex(json: try fixture("nodejs-dist-index.json")) : nil,
            nodeSchedule: schedule ? NodeReleaseSchedule(json: try fixture("nodejs-release-schedule.json")) : nil,
            phpBranches: branches ? PHPBranches(json: try fixture("php-releases-branches.json")) : nil,
            phpAdvisories: advisories ? PHPAdvisories(pages: [try fixture("php-src-security-advisories.json")]) : nil)
    }

    private static let today = "2026-10-22"

    // MARK: - Node.js

    /// The spec's example: nvm's 24.13.0 against the 2026-10-22 index.
    /// Mutation: count every newer release → 9; drop `security` → the latest is
    /// 24.22.1 by accident but the count is wrong.
    @Test func newerSecurityReleasesInTheLineAreCounted() throws {
        let notices = RuntimeSecurityRules.node(version: "24.13.0", data: try Self.data(), today: Self.today)
        #expect(notices == [.nodeSecurityReleases(
            installed: "24.13.0", count: 4, latest: "24.22.1", latestDate: "2026-10-20")])
    }

    /// v25.8.2's only newer release, v25.9.0, is not a security release: no
    /// security notice — but v25 ended on 2026-06-01.
    /// Mutation: drop the `security` filter → a notice naming 25.9.0.
    @Test func newerNonSecurityReleasesGiveNoSecurityNotice() throws {
        let notices = RuntimeSecurityRules.node(version: "25.8.2", data: try Self.data(), today: Self.today)
        #expect(notices == [.nodeEndOfLife(major: "25", date: "2026-06-01")])
    }

    /// Mutation: drop the "index lists the install" guard → 24.13.5, which
    /// nodejs.org never released, gets 24.14.1's notice.
    @Test func aVersionTheIndexDoesNotListGetsNothing() throws {
        #expect(RuntimeSecurityRules.node(version: "24.13.5", data: try Self.data(), today: Self.today).isEmpty)
        #expect(RuntimeSecurityRules.node(version: "24.13", data: try Self.data(), today: Self.today).isEmpty)
    }

    /// 24.22.1 is the latest of v24; v26.12.1, a security release of another
    /// major, says nothing about it. Mutation: drop the same-major filter.
    @Test func anotherMajorsSecurityReleaseGivesNoNotice() throws {
        #expect(RuntimeSecurityRules.node(version: "24.22.1", data: try Self.data(), today: Self.today).isEmpty)
        // And v26.12.0's newer v26.12.1 is one.
        #expect(RuntimeSecurityRules.node(version: "26.12.0", data: try Self.data(), today: Self.today)
            == [.nodeSecurityReleases(installed: "26.12.0", count: 1, latest: "26.12.1", latestDate: "2026-10-21")])
    }

    /// v20 ended 2026-04-30. On the end day itself it hasn't passed.
    /// Mutation: `<=` → an end-of-life notice on the last supported day.
    @Test func aMajorPastItsEndIsEndOfLife() throws {
        let data = try Self.data()
        #expect(RuntimeSecurityRules.node(version: "20.20.2", data: data, today: Self.today)
            == [.nodeEndOfLife(major: "20", date: "2026-04-30")])
        #expect(RuntimeSecurityRules.node(version: "20.20.2", data: data, today: "2026-04-30").isEmpty)
        // A major the schedule doesn't list (no v99) gives nothing.
        #expect(RuntimeSecurityRules.node(version: "99.0.0", data: data, today: Self.today).isEmpty)
    }

    /// Both together, for an install that is behind on an ended line.
    @Test func securityAndEndOfLifeTogether() throws {
        let notices = RuntimeSecurityRules.node(version: "20.20.1", data: try Self.data(), today: Self.today)
        #expect(notices == [
            .nodeSecurityReleases(installed: "20.20.1", count: 1, latest: "20.20.2", latestDate: "2026-03-24"),
            .nodeEndOfLife(major: "20", date: "2026-04-30"),
        ])
    }

    // MARK: - PHP

    /// GHSA-w8hw-… lists `< 8.4.27` and `< 8.5.12`: 8.4.27 is the fix on its
    /// branch, and 8.5.12 is not. Mutation: drop the same-branch filter → 8.4.27
    /// is "older than 8.5.12".
    @Test func anotherBranchsFixGivesNoNotice() throws {
        #expect(RuntimeSecurityRules.php(version: "8.4.27", data: try Self.data()).isEmpty)
    }

    /// 8.4.26 is older than 8.4.27, which fixes the two critical advisories of
    /// 2026-10-21; GHSA-7875 was fixed in 8.4.26 itself.
    @Test func anOlderPatchNamesTheAdvisoriesItsFixFixes() throws {
        let notices = RuntimeSecurityRules.php(version: "8.4.26", data: try Self.data())
        let url = { (ghsa: String) in URL(string: "https://github.com/php/php-src/security/advisories/\(ghsa)")! }
        #expect(notices == [.phpAdvisories(installed: "8.4.26", fixed: "8.4.27", advisories: [
            PHPAdvisoryReference(id: "CVE-2026-109618", severity: "critical", url: url("GHSA-w8hw-w9fx-j79w")),
            PHPAdvisoryReference(id: "CVE-2026-109619", severity: "critical", url: url("GHSA-6wmf-4rv5-p3rp")),
        ])])
        #expect(notices.first?.englishSummary
            == "8.4.26 is older than 8.4.27, which fixes CVE-2026-109618 (critical), CVE-2026-109619 (critical) (php.net/GitHub advisory)")
    }

    /// An advisory without a CVE is named by its GHSA id; the fixed version is
    /// the highest needed on the branch.
    @Test func anAdvisoryWithoutACVEIsNamedByItsGHSA() throws {
        guard case .phpAdvisories(_, let fixed, let advisories)? = RuntimeSecurityRules.php(
            version: "8.4.24", data: try Self.data()).first
        else { Issue.record("no notice"); return }
        #expect(fixed == "8.4.27")
        #expect(advisories.map(\.label) == [
            "CVE-2026-109618 (critical)", "CVE-2026-109619 (critical)", "CVE-2026-93682 (medium)",
            "GHSA-ch8v-r6jh-4vvr (low)",
        ])
    }

    /// php@8.1 is `eol`, and php.net still shipped 8.1.34 for GHSA-3237 (`< 8.1.34`):
    /// an 8.1.33 hears both. GHSA-wpj3's fix (8.1.28) is older than it, so it isn't
    /// named. Mutation: return the end of life alone for an `eol` branch → the
    /// advisory is missing.
    @Test func anEndOfLifeBranchStillHearsItsOwnBranchsFix() throws {
        #expect(RuntimeSecurityRules.php(version: "8.1.33", data: try Self.data()) == [
            .phpAdvisories(installed: "8.1.33", fixed: "8.1.34", advisories: [PHPAdvisoryReference(
                id: "CVE-2025-14177", severity: "medium",
                url: URL(string: "https://github.com/php/php-src/security/advisories/GHSA-3237-qqm7-mfv7")!)]),
            .phpEndOfLife(branch: "8.1", date: "2025-12-31"),
        ])
        // At the branch's last release only the end of life is left.
        #expect(RuntimeSecurityRules.php(version: "8.1.34", data: try Self.data())
            == [.phpEndOfLife(branch: "8.1", date: "2025-12-31")])
    }

    /// Without branches.php nobody knows whether the branch is still supported:
    /// no advisory verdict either. A branch it doesn't list gets nothing.
    @Test func noBranchesNoVerdict() throws {
        #expect(RuntimeSecurityRules.php(version: "8.4.26", data: try Self.data(branches: false)).isEmpty)
        #expect(RuntimeSecurityRules.php(version: "8.9.0", data: try Self.data()).isEmpty)
        #expect(RuntimeSecurityRules.php(version: "8.4.26", data: try Self.data(advisories: false)).isEmpty)
    }

    /// GHSA-9fcc's `patched_versions` is "8.1.29, 8.2.20, 8.3.8" against a range
    /// of "8.3.6": which fix is its range's isn't written, so it is left out.
    @Test func anEntryNamingSeveralVersionsIsLeftOut() throws {
        let all = try JSONSerialization.jsonObject(with: try Self.fixture("php-src-security-advisories.json")) as! [[String: Any]]
        let page = try JSONSerialization.data(withJSONObject: all.filter { $0["ghsa_id"] as? String == "GHSA-9fcc-425m-g385" })
        var data = try Self.data()
        data.phpAdvisories = PHPAdvisories(pages: [page])
        #expect(data.phpAdvisories?.advisories.count == 1)
        #expect(RuntimeSecurityRules.php(version: "8.3.6", data: data).isEmpty)
    }

    /// A pre-release or a HEAD version is not `x.y.z`.
    @Test func onlyExactReleaseVersionsAreRead() throws {
        let data = try Self.data()
        #expect(RuntimeSecurityRules.php(version: "8.4.0RC1", data: data).isEmpty)
        #expect(RuntimeSecurityRules.php(version: "HEAD-1a2b3c4", data: data).isEmpty)
        #expect(RuntimeSecurityRules.node(version: "v24.13.0-nightly", data: data, today: Self.today).isEmpty)
        #expect(RuntimeVersionTriple("8.3.8.") == nil)
        #expect(RuntimeVersionTriple(" 8.1.28") == nil)
    }

    // MARK: - What is installed

    /// A Homebrew prefix in a temporary directory: `opt/<name>` → keg, with a
    /// receipt.
    private static func keg(
        _ root: URL, _ name: String, _ version: String, tap: String? = "homebrew/core", spec: String = "stable"
    ) throws {
        let keg = root.appendingPathComponent("Cellar/\(name)/\(version)")
        try FileManager.default.createDirectory(at: keg.appendingPathComponent("bin"), withIntermediateDirectories: true)
        var source: [String: Any] = ["spec": spec]
        source["tap"] = tap
        try JSONSerialization.data(withJSONObject: ["source": source])
            .write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("opt"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("opt/\(name)").path, withDestinationPath: "../Cellar/\(name)/\(version)")
    }

    private static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-security-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Mutation: drop the tap check → a shivammathur `php@8.4` (same rack name as
    /// homebrew/core's) gets homebrew/core's verdict; drop the spec check → a
    /// HEAD build named like a release does.
    @Test func onlyHomebrewCoreReleaseKegsAreInScope() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.keg(root, "node@24", "24.13.0_1")
        try Self.keg(root, "php@8.4", "8.4.26", tap: "shivammathur/php")
        try Self.keg(root, "php@8.3", "8.3.30", tap: nil)
        try Self.keg(root, "node", "26.12.0", spec: "head")
        try Self.keg(root, "php", "8.5.0RC1")
        try Self.keg(root, "php@8.1", "8.1.33")
        try Self.keg(root, "nodenv", "1.0.0")
        let installs = RuntimeInstall.homebrew(root: root)
        #expect(installs == [
            RuntimeInstall(kind: .node, version: "24.13.0", origin: .homebrew(
                formula: "node@24", keg: root.appendingPathComponent("Cellar/node@24/24.13.0_1").path)),
            RuntimeInstall(kind: .php, version: "8.1.33", origin: .homebrew(
                formula: "php@8.1", keg: root.appendingPathComponent("Cellar/php@8.1/8.1.33").path)),
        ])
        let report = RuntimeSecurityReport(installs: installs, data: try Self.data(), today: Self.today)
        #expect(report.notices(forFormula: "php@8.4").isEmpty)
        #expect(report.notices(forFormula: "php@8.1").last == .phpEndOfLife(branch: "8.1", date: "2025-12-31"))
        #expect(report.notices(forFormula: "node@24").count == 1)
    }

    /// nvm's version directory with a `bin/node`; one without is not a runtime.
    @Test func versionManagerNodesAreReadFromTheirLayout() throws {
        let home = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let nvm = home.appendingPathComponent(".nvm/versions/node/v24.13.0")
        try FileManager.default.createDirectory(at: nvm.appendingPathComponent("bin"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: nvm.appendingPathComponent("bin/node").path, contents: Data())
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".nvm/versions/node/v22.0.0"), withIntermediateDirectories: true)
        let installs = RuntimeInstall.installed(home: home, brewRoot: nil)
        #expect(installs == [RuntimeInstall(kind: .node, version: "24.13.0", origin: .manager(.nvm, prefix: nvm.path))])
        let report = RuntimeSecurityReport(installs: installs, data: try Self.data(), today: Self.today)
        let prefix = NodePrefix(path: nvm.path, source: .nvm, layoutNodeVersion: "24.13.0")
        #expect(report.nodeNotices(forPrefix: prefix, homebrewKeg: nil).count == 1)
        #expect(report.englishLines() == [
            "  nvm node 24.13.0: 4 security releases since (latest 24.22.1) — https://nodejs.org/en/blog/release/v24.22.1/",
            "      to update it yourself: nvm install 24.22.1 --reinstall-packages-from=24.13.0"])
    }

    // MARK: - The command to copy

    private static let security = RuntimeSecurityNotice.nodeSecurityReleases(
        installed: "24.13.0", count: 4, latest: "24.22.1", latestDate: "2026-10-20")

    /// An nvm version directory under a scratch `NVM_DIR`, with `alias/default`
    /// holding `defaultAlias` when given.
    private static func nvm(_ home: URL, defaultAlias: String?) throws -> RuntimeSecurityReport.Entry {
        let nvmDir = home.appendingPathComponent(".nvm")
        let prefix = nvmDir.appendingPathComponent("versions/node/v24.13.0")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        if let defaultAlias {
            try FileManager.default.createDirectory(at: nvmDir.appendingPathComponent("alias"), withIntermediateDirectories: true)
            try Data((defaultAlias + "\n").utf8).write(to: nvmDir.appendingPathComponent("alias/default"))
        }
        return .init(install: RuntimeInstall(kind: .node, version: "24.13.0", origin: .manager(.nvm, prefix: prefix.path)),
                     notices: [Self.security])
    }

    /// nvm moves the packages itself; the default follows only when it named
    /// the installed version — `lts/*` and `24` follow newer installs already.
    /// Mutation: always append the default → `lts/*` would be pinned to 24.22.1.
    @Test func nvmsCommandMovesPackagesAndPinsOnlyAPinnedDefault() throws {
        let base = "nvm install 24.22.1 --reinstall-packages-from=24.13.0"
        for (alias, expected) in [("v24.13.0", base + " && nvm alias default 24.22.1"),
                                  ("24.13.0", base + " && nvm alias default 24.22.1"),
                                  ("lts/*", base), ("node", base), ("24", base), ("v24.12.0", base)] {
            let home = try Self.scratch()
            defer { try? FileManager.default.removeItem(at: home) }
            let upgrade = NodeUpgradeCommand(try Self.nvm(home, defaultAlias: alias), packages: ["openclaw"])
            #expect(upgrade?.command == expected, "default \(alias)")
            #expect(upgrade?.packagesLeftBehind == [])
        }
        let home = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(NodeUpgradeCommand(try Self.nvm(home, defaultAlias: nil), packages: [])?.command == base)
    }

    /// fnm's default is a link to a version's installation directory; its
    /// packages stay behind, and are named.
    /// Mutation: drop the link comparison → a default on 22.21.1 is moved.
    @Test func fnmsCommandNamesThePackagesItLeaves() throws {
        let home = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let fnm = home.appendingPathComponent(".local/share/fnm")
        let prefix = fnm.appendingPathComponent("node-versions/v24.12.0/installation")
        let other = fnm.appendingPathComponent("node-versions/v22.21.1/installation")
        for dir in [prefix, other, fnm.appendingPathComponent("aliases")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let entry = RuntimeSecurityReport.Entry(
            install: RuntimeInstall(kind: .node, version: "24.12.0", origin: .manager(.fnm, prefix: prefix.path)),
            notices: [.nodeSecurityReleases(installed: "24.12.0", count: 5, latest: "24.22.1", latestDate: "2026-10-20")])
        let link = fnm.appendingPathComponent("aliases/default").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: prefix.path)
        let upgrade = NodeUpgradeCommand(entry, packages: ["pnpm"])
        #expect(upgrade?.command == "fnm install 24.22.1 && fnm default 24.22.1")
        #expect(upgrade?.englishPackagesLeftBehind
            == "Global packages stay with 24.12.0: pnpm. Reinstall them under 24.22.1 with npm install -g.")
        try FileManager.default.removeItem(atPath: link)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: other.path)
        #expect(NodeUpgradeCommand(entry, packages: [])?.command == "fnm install 24.22.1")
        #expect(NodeUpgradeCommand(entry, packages: [])?.englishPackagesLeftBehind == nil)
    }

    /// An end of life alone has no command (its way out is another major), nor
    /// has a node of another manager or of Homebrew (which has Update).
    @Test func onlyNvmAndFnmSecurityReleasesGetACommand() throws {
        let home = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let nvm = try Self.nvm(home, defaultAlias: "v24.13.0")
        #expect(NodeUpgradeCommand(.init(install: nvm.install, notices: [.nodeEndOfLife(major: "24", date: "2026-01-01")]),
                                   packages: []) == nil)
        for origin: RuntimeInstall.Origin in [.manager(.mise, prefix: "/x"), .manager(.asdf, prefix: "/x"),
                                              .homebrew(formula: "node@24", keg: "/k")] {
            #expect(NodeUpgradeCommand(.init(install: RuntimeInstall(kind: .node, version: "24.13.0", origin: origin),
                                             notices: [Self.security]), packages: []) == nil)
        }
        // duo's line under the notice.
        let report = RuntimeSecurityReport(entries: [nvm])
        #expect(report.englishLines().last
            == "      to update it yourself: nvm install 24.22.1 --reinstall-packages-from=24.13.0 && nvm alias default 24.22.1")
    }

    // MARK: - Fetching

    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var responses: [String: (Int, Data, [String: String])] = [:]
        nonisolated(unsafe) static var seen: [URLRequest] = []
        /// How long each answer takes, so two reports can overlap one ask.
        nonisolated(unsafe) static var delay: TimeInterval = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.seen.append(request)
            let (status, body, headers) = Self.responses[request.url!.absoluteString] ?? (500, Data(), [:])
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            let answer = { [client] in
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
            if Self.delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: answer)
            } else {
                answer()
            }
        }
        override func stopLoading() {}
    }

    private static func session() -> URLSession {
        Stub.seen = []
        Stub.delay = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    private static let node = [RuntimeInstall(kind: .node, version: "24.13.0", origin: .manager(.nvm, prefix: "/x"))]
    private static let php = [RuntimeInstall(kind: .php, version: "8.4.26", origin: .homebrew(formula: "php", keg: "/k"))]

    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_792_600_000)
    }

    /// Every report asks again — the cadence is the read that wants it — and
    /// conditionally: the first ask is unconditional, the next sends the
    /// stored validators, and a 304 confirms the copy.
    /// Mutation: drop the validators → the second ask is unconditional.
    @Test func everyReportAsksConditionally() async throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = Clock()
        Stub.responses = [
            RuntimeSecurityFeeds.Source.nodeReleases.url.absoluteString:
                (200, try Self.fixture("nodejs-dist-index.json"), ["ETag": "\"abc\""]),
            RuntimeSecurityFeeds.Source.nodeSchedule.url.absoluteString:
                (200, try Self.fixture("nodejs-release-schedule.json"), ["Last-Modified": "Wed, 21 Oct 2026 10:36:37 GMT"]),
        ]
        let feeds = RuntimeSecurityFeeds(
            fileURL: dir.appendingPathComponent("feeds.json"), session: Self.session(),
            token: { nil }, now: { clock.now })
        #expect(await feeds.report(for: Self.node).entries.count == 1)
        #expect(Stub.seen.count == 2)
        #expect(Stub.seen.allSatisfy { $0.value(forHTTPHeaderField: "If-None-Match") == nil })

        clock.now += 5 * 60
        Stub.responses = Stub.responses.mapValues { (304, Data(), $0.2) }
        #expect(await feeds.report(for: Self.node).entries.count == 1)
        #expect(Stub.seen.count == 4)
        let conditional = Stub.seen.suffix(2)
        #expect(conditional.contains { $0.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"" })
        #expect(conditional.contains { $0.value(forHTTPHeaderField: "If-Modified-Since") == "Wed, 21 Oct 2026 10:36:37 GMT" })
        // No PHP installed: GitHub was never asked.
        #expect(!Stub.seen.contains { $0.url?.host == "api.github.com" })
    }

    /// Two reports at once share one ask per source.
    /// Mutation: drop the `inFlight` check → four requests.
    @Test func overlappingReportsShareOneAsk() async throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = Self.session()
        Stub.delay = 0.3
        Stub.responses = [
            RuntimeSecurityFeeds.Source.nodeReleases.url.absoluteString: (200, try Self.fixture("nodejs-dist-index.json"), [:]),
            RuntimeSecurityFeeds.Source.nodeSchedule.url.absoluteString: (200, try Self.fixture("nodejs-release-schedule.json"), [:]),
        ]
        let feeds = RuntimeSecurityFeeds(fileURL: dir.appendingPathComponent("feeds.json"), session: session, token: { nil })
        async let first = feeds.report(for: Self.node)
        async let second = feeds.report(for: Self.node)
        let (a, b) = await (first, second)
        #expect(a.entries.count == 1 && b.entries.count == 1)
        #expect(Stub.seen.count == 2)
    }

    /// A failed ask keeps speaking from a copy confirmed within 48 hours, and
    /// from none older. Mutation: drop the age check → a 49-hour-old copy
    /// still gives the notice.
    @Test func aCopyOlderThan48HoursGivesNothing() async throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = Clock()
        Stub.responses = [
            RuntimeSecurityFeeds.Source.nodeReleases.url.absoluteString: (200, try Self.fixture("nodejs-dist-index.json"), [:]),
            RuntimeSecurityFeeds.Source.nodeSchedule.url.absoluteString: (200, try Self.fixture("nodejs-release-schedule.json"), [:]),
        ]
        let file = dir.appendingPathComponent("feeds.json")
        let first = RuntimeSecurityFeeds(fileURL: file, session: Self.session(), token: { nil }, now: { clock.now })
        #expect(await first.report(for: Self.node).entries.count == 1)

        // Every later ask fails; read by a second process, from the file.
        Stub.responses = [:]
        clock.now += 47 * 60 * 60
        let second = RuntimeSecurityFeeds(fileURL: file, session: Self.session(), token: { nil }, now: { clock.now })
        #expect(await second.report(for: Self.node).entries.count == 1)
        // It was asked, and failed: a failure is retried at the next read.
        #expect(Stub.seen.count == 2)

        clock.now += 2 * 60 * 60
        #expect(await second.report(for: Self.node).entries.isEmpty)
    }

    /// The advisories go to the API with the token, and a body that isn't the
    /// list is not stored as one.
    @Test func advisoriesAreAskedWithTheToken() async throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = Clock()
        Stub.responses = [
            RuntimeSecurityFeeds.Source.phpBranches.url.absoluteString: (200, try Self.fixture("php-releases-branches.json"), [:]),
            RuntimeSecurityFeeds.Source.phpAdvisories.url.absoluteString:
                (200, try Self.fixture("php-src-security-advisories.json"), ["ETag": "W/\"e0\""]),
        ]
        let feeds = RuntimeSecurityFeeds(
            fileURL: dir.appendingPathComponent("feeds.json"), session: Self.session(),
            token: { "zzfixture-token" }, now: { clock.now })
        let report = await feeds.report(for: Self.php)
        #expect(report.notices(forFormula: "php").count == 1)
        let api = try #require(Stub.seen.first { $0.url?.host == "api.github.com" })
        #expect(api.value(forHTTPHeaderField: "Authorization") == "Bearer zzfixture-token")
        #expect(api.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theNextPageIsReadFromTheLinkHeader() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!, statusCode: 200, httpVersion: nil,
            headerFields: ["Link": "<https://api.github.com/repositories/1/security-advisories?per_page=100&page=2>; rel=\"next\", <https://api.github.com/repositories/1/security-advisories?per_page=100&page=3>; rel=\"last\""])!
        #expect(RuntimeSecurityFeeds.nextPage(response)?.absoluteString
            == "https://api.github.com/repositories/1/security-advisories?per_page=100&page=2")
        let last = HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!, statusCode: 200, httpVersion: nil,
            headerFields: ["Link": "<https://api.github.com/x?page=1>; rel=\"prev\""])!
        #expect(RuntimeSecurityFeeds.nextPage(last) == nil)
    }
}
