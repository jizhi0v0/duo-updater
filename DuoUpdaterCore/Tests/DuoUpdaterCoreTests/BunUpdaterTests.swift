import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running bun's one-click updates: `bun upgrade` on bun's own row, and `bun add
/// -g` (through `NpmUpdater`) on a package's.
///
/// The bun is a shell script (`BunSandbox.script`) whose `upgrade` does to the
/// sandbox what bun 1.4.1's did (2026-10-04): prints its lines, then renames a
/// new file over its own path — and records the environment it saw. Its `add -g`
/// rewrites the package's `package.json`. Nothing here reaches the network or
/// runs a real bun.
@Suite struct BunUpdaterTests {

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    /// A bun whose `upgrade` leaves `to`, signed as `signer`.
    static func upgrading(to version: String = "1.4.2", signer: String = "oven", extra: String = "") -> String {
        """
        env > "$HOME/ENV"
        \(extra)
        if [ "$1" = upgrade ]; then
          echo "Bun v\(version) is out! You're on v1.4.1"
          new="$TMPDIR/bun-new"
          # Spelled with %s, so this file holds one version literal, not two.
          printf '#!/bin/sh\\n# bun/%s+abcdef0 npm/%s node/v24.3.0\\n# %s:%s\\n' '\(version)' '?' SIGNER '\(signer)' > "$new"
          chmod +x "$new"
          mv -f "$new" "$0"
          echo "Welcome to Bun v\(version)!"
          exit 0
        fi
        if [ "$1" = add ]; then
          spec="$3"; name="${spec%@*}"; version="${spec##*@}"
          printf '{"name":"%s","version":"%s","bin":{"%s":"cli.js"}}' "$name" "$version" "$name" \\
            > "$BUN_INSTALL/install/global/node_modules/$name/package.json"
          echo "installed $spec"
          exit 0
        fi
        """
    }

    static func environment(_ box: BunSandbox) -> [String: String] {
        let text = (try? String(contentsOf: box.home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    static func updater(
        _ box: BunSandbox, latest: String = "1.4.2", busy: @escaping BunUpdater.BusyCheck = { _ in nil },
        environment: [String: String] = [:], token: String? = nil
    ) -> BunUpdater {
        BunUpdater(busy: busy, scanner: box.scanner, check: BunTests.check(latest), environment: { environment },
                   token: { token })
    }

    // MARK: - bun upgrade

    /// The app's GitHub token reaches `bun upgrade` as `GITHUB_ACCESS_TOKEN`, the
    /// name every bun from 1.0.0 reads, so its release lookup is not held to the
    /// anonymous 60 an hour. No token, no variable; a `GITHUB_TOKEN` or
    /// `GITHUB_ACCESS_TOKEN` already in the environment wins.
    ///
    /// The third case is an injected environment only: the one `BunUpdater()`
    /// builds (`childEnvironmentWithSystemProxy`) has had `GH_TOKEN` and
    /// `GITHUB_TOKEN` taken out, so a token exported for `gh` never reaches
    /// `bun upgrade` by that name, and the app's own arrives as
    /// `GITHUB_ACCESS_TOKEN`. The check on `GITHUB_TOKEN` is left in place.
    /// Kills: not setting it; setting it from a nil token; overwriting either of
    /// the ones already there.
    @Test func theAppsGitHubTokenReachesBunUpgrade() async throws {
        for (token, exported, expected) in [
            ("ZZFixture-token", [:], ["GITHUB_ACCESS_TOKEN": "ZZFixture-token"]),
            (nil, [:], [:]),
            ("ZZFixture-token", ["GITHUB_TOKEN": "ZZFixture-users-own"], ["GITHUB_TOKEN": "ZZFixture-users-own"]),
            ("ZZFixture-token", ["GITHUB_ACCESS_TOKEN": "ZZFixture-users-own"], ["GITHUB_ACCESS_TOKEN": "ZZFixture-users-own"]),
        ] as [(String?, [String: String], [String: String])] {
            let box = try BunSandbox()
            try box.installBun(body: Self.upgrading())
            let status = try await BunTests.status(box)
            #expect(await Self.updater(box, environment: exported, token: token).update(status) == .updated(version: "1.4.2"))
            let env = Self.environment(box)
            #expect(env.filter { $0.key == "GITHUB_TOKEN" || $0.key == "GITHUB_ACCESS_TOKEN" } == expected)
        }
    }

    /// bun's lookup failed on the token it was handed — any status bun has no
    /// name for, as 1.4.2 printed for a bogus token (2026-10-11): run once more
    /// without it. Not for another failure (`HTTPForbidden` is the anonymous
    /// rate limit), and not for a token the user exported, which is theirs to fix.
    /// Kills: no retry; retrying every failure; retrying the user's token;
    /// retrying with the token still set.
    @Test func aRejectedTokenIsRetriedOnceWithout() async throws {
        let rejected = "echo 'Bun upgrade failed with error: HTTPError'; exit 1"
        for (token, exported, failure, runs, updated) in [
            ("ZZFixture-token", nil, rejected, 2, true),
            ("ZZFixture-token", nil, "echo 'Bun upgrade failed with error: HTTPForbidden'; exit 1", 1, false),
            (nil, "ZZFixture-users-own", rejected, 1, false),
        ] as [(String?, String?, String, Int, Bool)] {
            let box = try BunSandbox()
            let extra = "echo run >> \"$HOME/RUNS\"\n"
                + "if [ -n \"$GITHUB_ACCESS_TOKEN\" ]; then \(failure); fi"
            try box.installBun(body: Self.upgrading(extra: extra))
            let status = try await BunTests.status(box)
            var environment: [String: String] = [:]
            environment["GITHUB_ACCESS_TOKEN"] = exported
            let outcome = await Self.updater(box, environment: environment, token: token).update(status)
            let ran = try String(contentsOf: box.home.appendingPathComponent("RUNS"), encoding: .utf8)
            #expect(ran.split(separator: "\n").count == runs)
            if updated {
                #expect(outcome == .updated(version: "1.4.2"))
                #expect(Self.environment(box)["GITHUB_ACCESS_TOKEN"] == nil)
            } else {
                #expect(outcome != .updated(version: "1.4.2"))
            }
        }
    }

    @Test func upgradesAndChecksWhatItLeft() async throws {
        let box = try BunSandbox()
        try box.installBun(body: Self.upgrading())
        let status = try await BunTests.status(box)
        let lines = Lines()
        let outcome = await Self.updater(
            box, environment: ["HOME": "/elsewhere", "PATH": "/x", "BUN_CANARY": "1", "GITHUB_API_DOMAIN": "mirror.example",
                               "https_proxy": "http://127.0.0.1:9"]
        ).update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "1.4.2"))
        let env = Self.environment(box)
        #expect(env["HOME"] == box.home.path)
        #expect(env["BUN_INSTALL"] == box.home.appendingPathComponent(".bun").path)
        #expect(env["PATH"] == CLIToolCommandRunner.systemPath)
        // A canary or another API host would install something else.
        #expect(env["BUN_CANARY"] == nil)
        #expect(env["GITHUB_API_DOMAIN"] == nil)
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        let tmp = try #require(env["TMPDIR"])
        #expect(tmp.contains("duo-bun-"))
        #expect(!FileManager.default.fileExists(atPath: tmp))
        #expect(lines.all.contains("Welcome to Bun v1.4.2!"))
    }

    /// Mutation: dropping the signature guard in `verdict` reports `.updated`.
    @Test func aNewBunNotSignedByOvenIsAFailure() async throws {
        let box = try BunSandbox()
        try box.installBun(body: Self.upgrading(signer: "adhoc"))
        let outcome = await Self.updater(box).update(try await BunTests.status(box))
        #expect(outcome == .failed(message: "bun 1.4.2 is not signed by Oven (Team 7FRXF46ZSN): adHoc", output: outcome.output))
    }

    /// `bun upgrade` exits 0 having done nothing when the channel names the
    /// running version. Mutation: dropping the newer-version guard reports `.updated("1.4.1")`.
    @Test func anUpgradeThatChangedNothingIsAFailure() async throws {
        let box = try BunSandbox()
        try box.installBun(body: "echo \"Congrats! You're already on the latest version of Bun\"; exit 0")
        let outcome = await Self.updater(box).update(try await BunTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "bun upgrade finished, but bun is still 1.4.1")
    }

    @Test func aFailedUpgradeSaysWhy() async throws {
        let box = try BunSandbox()
        try box.installBun(body: "echo 'Fetching version tags'; echo 'error: Failed to download the latest version of Bun. Received empty content' >&2; exit 1")
        let outcome = await Self.updater(box).update(try await BunTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "Failed to download the latest version of Bun. Received empty content")
        #expect(box.scanner.scan()?.version == "1.4.1")
    }

    /// Mutation: dropping the click-time channel read runs an upgrade that
    /// installs whatever the channel names.
    @Test func aChannelThatNoLongerNamesANewerVersionRunsNothing() async throws {
        let box = try BunSandbox()
        try box.installBun(body: Self.upgrading())
        let status = try await BunTests.status(box)
        #expect(await Self.updater(box, latest: "1.4.1").update(status) == .failed(
            message: "not run: bun's channel now names 1.4.1, not a version newer than 1.4.1", output: ""))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }

    @Test func clickTimeGates() async throws {
        let box = try BunSandbox()
        try box.installBun(body: Self.upgrading())
        let status = try await BunTests.status(box)
        #expect(await Self.updater(box, busy: { _ in .bun("bun upgrade", pid: 4) }).update(status)
            == .busy("bun upgrade is running (pid 4)"))
        // Replaced since the check.
        try box.installBun("1.4.0", body: Self.upgrading())
        #expect(await Self.updater(box).update(status) == .failed(
            message: "not run: \(box.bun.path) is no longer the bun that was checked", output: ""))
        // Re-signed since the check.
        try box.installBun("1.4.1", signer: "adhoc", body: Self.upgrading())
        #expect(await Self.updater(box).update(status) == .failed(
            message: "not run: \(box.bun.path) is not signed by Oven (Team 7FRXF46ZSN)", output: ""))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }

    // MARK: - A package: bun add -g

    static func packageUpdater(
        _ box: BunSandbox, trustsBun: Bool = true, trustsNode: Bool = false, environment: [String: String] = [:]
    ) -> NpmUpdater {
        NpmUpdater(
            busy: { _ in nil }, trustsNode: { _ in trustsNode }, trustsBun: { _ in trustsBun },
            environment: { environment })
    }

    static func cowsayStatus(_ box: BunSandbox, body: String = upgrading()) async throws -> CLIToolStatus {
        try box.installBun(body: body)
        try box.homebrewNode()
        try box.add([("cowsay", "1.5.0")])
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        let install = try #require(box.packages.scan(bun: bun).first)
        let status = await NpmCheck(packument: { _ in
            NpmPackument(distTags: ["latest": "1.6.0"], versions: ["1.5.0": .init(), "1.6.0": .init()])
        }).status(of: install, busy: nil)
        _ = try #require(status.oneClick)
        return status
    }

    /// `bun add -g` runs no node: its trust is not asked; the bun's is, and the
    /// child gets the `BUN_INSTALL` that was scanned. Mutations: ask the node
    /// for a bun command; drop `BUN_INSTALL`.
    @Test func aPackageUpdatesThroughItsBun() async throws {
        let box = try BunSandbox()
        let status = try await Self.cowsayStatus(box)
        let outcome = await Self.packageUpdater(box, environment: ["HOME": box.home.path, "BUN_INSTALL": "/elsewhere"])
            .update(status)
        #expect(outcome == .updated(version: "1.6.0"))
        let env = Self.environment(box)
        #expect(env["BUN_INSTALL"] == box.home.appendingPathComponent(".bun").path)
        #expect(env["PATH"] == box.bun.deletingLastPathComponent().path + ":" + CLIToolCommandRunner.systemPath)
    }

    /// What bun 1.4.3's `add -g <name>@<version>` does to the global
    /// `package.json` (measured 2026-10-13): the user's specifier becomes the
    /// exact version.
    static let bunWritesExactSpecifier = #"""
        if [ "$1" = add ]; then
          spec="$3"; name="${spec%@*}"; version="${spec##*@}"
          sed -i '' -E "s|(\"$name\": )\"[^\"]*\"|\\1\"$version\"|" "$BUN_INSTALL/install/global/package.json"
        fi
        """#

    static func manifest(_ cowsay: String) -> String {
        "{\n  \"dependencies\": {\n    \"cowsay\": \"\(cowsay)\",\n    \"terser\": \"~5.46.0\"\n  }\n}\n"
    }

    /// One click must not pin the package against the user's own `bun update -g`,
    /// which holds an exact specifier where it is: their `^` comes back on the new
    /// version, and the rest of the file stays as bun left it. Mutation: dropping
    /// the restore leaves `"1.6.0"`.
    @Test func aCaretSpecifierSurvivesTheUpdate() async throws {
        let box = try BunSandbox()
        let status = try await Self.cowsayStatus(box, body: Self.upgrading(extra: Self.bunWritesExactSpecifier))
        let manifest = try box.write(box.global.appendingPathComponent("package.json"), Self.manifest("^1.5.0"))
        #expect(await Self.packageUpdater(box).update(status) == .updated(version: "1.6.0"))
        #expect(try String(contentsOf: manifest, encoding: .utf8) == Self.manifest("^1.6.0"))
    }

    /// A range the new version is outside of is not left exact: the next check
    /// would read that as the user's pin and offer nothing again. Mutation:
    /// leave bun's exact version for an unsatisfied range (the row reads pinned).
    @Test func aRangeTheUpdateLeftIsNotReadAsAPin() async throws {
        let box = try BunSandbox()
        let status = try await Self.cowsayStatus(box, body: Self.upgrading(extra: Self.bunWritesExactSpecifier))
        let manifest = try box.write(box.global.appendingPathComponent("package.json"), Self.manifest("1.5.x"))
        #expect(await Self.packageUpdater(box).update(status) == .updated(version: "1.6.0"))
        #expect(try String(contentsOf: manifest, encoding: .utf8) == Self.manifest("^1.6.0"))
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        let after = try #require(box.packages.scan(bun: bun).first { $0.name == "cowsay" })
        let recheck = await NpmCheck(packument: { _ in
            NpmPackument(distTags: ["latest": "1.7.0"], versions: ["1.5.0": .init(), "1.6.0": .init(), "1.7.0": .init()])
        }).status(of: after, busy: nil)
        #expect(recheck.state == .updateAvailable)
    }

    /// An exact specifier was the user's own pin: it stays exact, at the new version.
    @Test func anExactSpecifierStaysExact() async throws {
        let box = try BunSandbox()
        let status = try await Self.cowsayStatus(box, body: Self.upgrading(extra: Self.bunWritesExactSpecifier))
        let manifest = try box.write(box.global.appendingPathComponent("package.json"), Self.manifest("1.5.0"))
        #expect(await Self.packageUpdater(box).update(status) == .updated(version: "1.6.0"))
        #expect(try String(contentsOf: manifest, encoding: .utf8) == Self.manifest("1.6.0"))
    }

    /// A `dependencies` entry that does not read the version just installed is
    /// not bun's rewrite, and nothing is touched — not even the one other place
    /// the file names that version. Mutation: dropping that guard rewrites the
    /// `overrides` entry.
    @Test func anEntryBunDidNotRewriteIsLeftAlone() async throws {
        let box = try BunSandbox()
        let status = try await Self.cowsayStatus(box)
        let text = "{\n  \"dependencies\": {\n    \"cowsay\": \"^1.5.0\"\n  },\n  \"overrides\": {\n    \"cowsay\": \"1.6.0\"\n  }\n}\n"
        let manifest = try box.write(box.global.appendingPathComponent("package.json"), text)
        #expect(await Self.packageUpdater(box).update(status) == .updated(version: "1.6.0"))
        #expect(try String(contentsOf: manifest, encoding: .utf8) == text)
    }

    @Test(arguments: [
        ("^6.0.0", "7.0.0", "^7.0.0"), ("~6.1.0", "6.2.0", "~6.2.0"), ("^7", "7.1.0", "^7.1.0"),
        ("6.0.0", "7.0.0", nil), ("=6.0.0", "7.0.0", nil), ("7.0.0", "7.0.0", nil),
        ("*", "7.0.0", "*"), (">=6", "7.0.0", ">=6"),
        // Outside the range, or a dist-tag: never left exact, which would read as a pin.
        ("6.x", "7.0.0", "^7.0.0"), ("latest", "7.0.0", "^7.0.0"), ("1.5.x", "1.6.0", "^1.6.0"),
    ] as [(String, String, String?)])
    func restoredSpecifier(specifier: String, version: String, expected: String?) {
        #expect(NpmUpdater.restoredSpecifier(specifier, at: version) == expected)
    }

    /// Mutation: dropping the click-time bun check runs it.
    @Test func aBunNoLongerTrustedRunsNothing() async throws {
        let box = try BunSandbox()
        let status = try await Self.cowsayStatus(box)
        #expect(await Self.packageUpdater(box, trustsBun: false).update(status) == .failed(
            message: "not run: \(box.bun.path) is no longer a bun DuoUpdater may run", output: ""))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }
}

private extension CLIToolUpdateOutcome {
    var output: String {
        if case .failed(_, let output) = self { return output }
        return ""
    }
}
