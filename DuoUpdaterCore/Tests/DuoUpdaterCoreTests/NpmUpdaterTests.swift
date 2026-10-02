import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running a global npm package's one-click update: what is run, with which
/// environment, and when it counts as done.
///
/// The prefix's `bin/node` here is a `#!/bin/sh` script standing in for node
/// running npm: it prints what it was given and rewrites the package's
/// `package.json` the way `npm install -g` replaces the package. The busy check
/// and the base environment are injected — nothing reads the host's process
/// table, prefixes or network.
@Suite struct NpmUpdaterTests {

    func updater(
        busy: @escaping NpmUpdater.BusyCheck = { _ in nil }, environment: [String: String] = [:],
        deadline: ChildProcess.Deadline = NpmUpdater.defaultDeadline
    ) -> NpmUpdater {
        NpmUpdater(busy: busy, environment: { environment }, deadline: deadline)
    }

    /// mcp-remote 0.1.38 in prefix `p`, whose node runs `body`.
    func status(_ box: NpmSandbox, node body: String) async throws -> CLIToolStatus {
        try box.runtime("p", node: "#!/bin/sh\n" + body + "\n")
        try box.package("p", "mcp-remote", version: "0.1.38")
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        let packument = NpmPackument(distTags: ["latest": "0.14.3"], versions: ["0.1.38": .init(), "0.14.3": .init()])
        let status = await NpmCheck(packument: { _ in packument }).status(of: install, busy: nil)
        #expect(status.oneClick != nil)
        return status
    }

    /// What npm leaves: the package directory replaced, at the new version.
    func installing(_ box: NpmSandbox, _ version: String = "0.14.3") -> String {
        let manifest = box.path("p/lib/node_modules/mcp-remote/package.json")
        return """
            echo "PATH=$PATH"
            echo "ARGS=$*"
            printf '{"name":"mcp-remote","version":"\(version)","bin":{"mcp-remote":"cli.js"}}' > '\(manifest)'
            echo "changed 1 package in 2s"
            """
    }

    @Test func noOneClickRunsNothingAndAsksNothing() async throws {
        let box = try NpmSandbox()
        let foreign = CLIToolStatus(
            kind: .fx, path: "/ZZFixture-npm", installedVersion: "1", latestVersion: "2", channel: nil,
            state: .updateAvailable, oneClick: CLIToolCommand(executable: "/bin/echo", arguments: [], pathPrefix: nil),
            withheld: nil, note: nil, detail: .fx(FxInstall(path: "/ZZFixture-npm", version: "1")))
        #expect(!FileManager.default.fileExists(atPath: "/ZZFixture-npm"))
        let asked = NpmRecorder()
        #expect(await updater(busy: { asked.add($0.path); return nil }).update(foreign) == .notOffered)

        let offered = try await status(box, node: "touch '\(box.path("ran"))'")
        let withheld = CLIToolStatus(
            kind: .npm, path: offered.path, installedVersion: offered.installedVersion, latestVersion: offered.latestVersion,
            channel: offered.channel, state: offered.state, oneClick: nil, withheld: .busy, note: nil, detail: offered.detail)
        #expect(await updater(busy: { asked.add($0.path); return nil }).update(withheld) == .notOffered)
        #expect(asked.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: box.path("ran")))
    }

    /// Mutation: drop the click-time busy check → the command runs.
    @Test func aChangeStartedSinceTheCheckIsNotRaced() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: "touch '\(box.path("ran"))'")
        let outcome = await updater(busy: { _ in .npm("npm install", pid: 42) }).update(status)
        #expect(outcome == .busy("npm install is running in this node prefix (pid 42)"))
        #expect(!FileManager.default.fileExists(atPath: box.path("ran")))
    }

    /// The node the check trusted is asked again at the click — replaced since by
    /// one that is neither the Node.js Foundation's nor Homebrew's, nothing runs.
    ///
    /// Mutation: drop the click-time `trustsNode` guard → the command runs.
    @Test func aNodeNoLongerTrustedAtTheClickIsNotRun() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: "touch '\(box.path("ran"))'")
        let outcome = await NpmUpdater(busy: { _ in nil }, trustsNode: { _ in false }, environment: { [:] })
            .update(status)
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("not run:"))
        #expect(!FileManager.default.fileExists(atPath: box.path("ran")))
    }

    /// Two copies of one package read different notes — each only the releases
    /// above its own version — so they never share the app's cache entry.
    ///
    /// Mutation: key by the package name alone.
    @Test func eachInstalledVersionHasItsOwnReleaseNotesKey() {
        #expect(NpmChangelog.releaseNotesKey(name: "foo", installed: "1.0.0")
            != NpmChangelog.releaseNotesKey(name: "foo", installed: "2.0.0"))
        #expect(NpmChangelog.releaseNotesKey(name: "foo", installed: "1.0.0")
            == NpmChangelog.releaseNotesKey(name: "foo", installed: "1.0.0"))
    }

    /// `latest` naming a prerelease while the copy is on a release: nothing is
    /// offered, and the note says why — not that the release is deprecated.
    ///
    /// Mutation: restore the unconditional "is deprecated" note.
    @Test func aPrereleaseOnLatestIsNotCalledDeprecated() async throws {
        let box = try NpmSandbox()
        try box.runtime("p", node: "#!/bin/sh\n")
        try box.package("p", "mcp-remote", version: "1.5.0")
        let install = try #require(box.scanner([box.prefix("p")]).scan().first)
        let packument = NpmPackument(distTags: ["latest": "2.0.0-rc.1"], versions: ["1.5.0": .init(), "2.0.0-rc.1": .init()])
        let status = await NpmCheck(packument: { _ in packument }).status(of: install, busy: nil)
        #expect(status.oneClick == nil)
        #expect(status.note?.contains("prerelease") == true)
        #expect(status.note?.contains("deprecated") == false)
    }

    @Test func runsTheExactCommandWithThePrefixFirstOnPath() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: installing(box))
        let lines = NpmRecorder()
        let outcome = await updater(environment: ["PATH": "/should/not/survive", "https_proxy": "http://127.0.0.1:6152"])
            .update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "0.14.3"))
        #expect(lines.all.contains("PATH=\(box.path("p/bin")):/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(lines.all.contains(
            "ARGS=\(box.path("p/bin/npm")) install -g --prefix \(box.path("p")) --engine-strict mcp-remote@0.14.3"))
    }

    /// Exit 0 is not proof: openclaw's update exits 0 having skipped, and npm can
    /// leave another version.
    ///
    /// Mutation: return `.updated` without comparing the re-read version → green
    /// row that offers the same update again.
    @Test func exitZeroWithTheOldVersionIsAFailure() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: "echo 'Skipped: this OpenClaw install is not a git checkout'")
        let outcome = await updater().update(status)
        guard case .failed(let message, let output) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "the update finished, but mcp-remote is 0.1.38, not 0.14.3")
        #expect(output.contains("Skipped"))
    }

    @Test func aPackageLeftAsALinkIsNotUpdated() async throws {
        let box = try NpmSandbox()
        try box.write("src/mcp-remote/package.json", #"{"name":"mcp-remote","version":"0.14.3","bin":"x"}"#)
        let package = box.path("p/lib/node_modules/mcp-remote")
        let status = try await status(box, node: "rm -rf '\(package)'; ln -s '\(box.path("src/mcp-remote"))' '\(package)'")
        guard case .failed(let message, _) = await updater().update(status) else { Issue.record("not failed"); return }
        #expect(message.contains("unreadable"))
    }

    /// npm's reason is its first `npm error` line that is not a field.
    @Test func npmsReasonIsTheRowsMessage() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: """
            echo 'npm error code EBADENGINE' >&2
            echo 'npm error engine Unsupported engine' >&2
            echo 'npm error engine Not compatible with your version of node/npm: mcp-remote@0.14.3' >&2
            echo 'npm error A complete log of this run can be found in: /tmp/x.log' >&2
            exit 1
            """)
        guard case .failed(let message, let output) = await updater().update(status) else { Issue.record("not failed"); return }
        #expect(message == "npm error engine Unsupported engine")
        #expect(output.contains("A complete log"))
    }

    /// openclaw's own update ends with a summary whose last line is its timing;
    /// the row shows the summary's reason instead (output of the first real
    /// one-click, 2026-10-02, shortened).
    ///
    /// Mutation: drop the `openclawReason` line from `failureMessage`.
    @Test func openclawsReasonIsTheRowsMessage() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: """
            echo 'Updating OpenClaw...'
            echo 'Update Result: ERROR'
            echo '  Root: /x/lib/node_modules/openclaw'
            echo '  Reason: global install verify'
            echo 'Steps:'
            echo '  ✓ global update (15.13s)'
            echo '  ✗ global install verify (0ms)'
            echo 'Total time: 25.41s'
            exit 1
            """)
        guard case .failed(let message, _) = await updater().update(status) else { Issue.record("not failed"); return }
        #expect(message == "openclaw update: global install verify")
    }

    /// Variables that would move the install elsewhere are not passed on.
    ///
    /// Mutation: keep the base environment as is → the prefix override reaches npm.
    @Test func prefixOverridesAreNotPassedOn() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: """
            echo "npm_config_prefix=${npm_config_prefix:-unset} NPM_CONFIG_PREFIX=${NPM_CONFIG_PREFIX:-unset} spec=${OPENCLAW_UPDATE_PACKAGE_SPEC:-unset} proxy=${https_proxy:-unset}"
            """ + "\n" + installing(box))
        let lines = NpmRecorder()
        _ = await updater(environment: [
            "npm_config_prefix": "/elsewhere", "NPM_CONFIG_PREFIX": "/elsewhere",
            "OPENCLAW_UPDATE_PACKAGE_SPEC": "openclaw@main", "https_proxy": "http://127.0.0.1:6152",
        ]).update(status) { lines.add($0) }
        #expect(lines.all.contains("npm_config_prefix=unset NPM_CONFIG_PREFIX=unset spec=unset proxy=http://127.0.0.1:6152"))
    }

    /// openclaw asks questions only when stdin is a TTY; the child's stdin is an
    /// empty pipe, never this process's terminal.
    @Test func standardInputIsAnEmptyPipe() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: """
            if [ -p /dev/stdin ]; then echo "stdin=pipe"; else echo "stdin=other"; fi
            echo "read=$(cat | wc -c | tr -d ' ')"
            """ + "\n" + installing(box))
        let lines = NpmRecorder()
        _ = await updater().update(status) { lines.add($0) }
        #expect(lines.all.contains("stdin=pipe"))
        #expect(lines.all.contains("read=0"))
    }

    @Test func aHungChildIsStopped() async throws {
        let box = try NpmSandbox()
        let status = try await status(box, node: "sleep 30")
        let outcome = await updater(deadline: .init(terminateAfter: .seconds(1), killAfter: .seconds(2))).update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "stopped: still running after 1 s")
    }
}
