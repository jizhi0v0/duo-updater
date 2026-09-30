import Foundation
import Testing
import DuoUpdaterCore

/// How the workbench's CLI tab names a Claude Code install, and when it hands
/// out a command to copy. Every path is made up and `home` is passed in, so no
/// answer depends on the Mac running the tests.
///
/// Each case names the one-line mutation of `ClaudeCodePresentation` it fails
/// under.
struct ClaudeCodePresentationTests {

    private static let home = "/Users/ann"

    private func install(
        _ path: String, _ method: ClaudeCodeInstall.Method,
        origin: ClaudeCodeInstall.Origin = .conventional, nodePrefix: String? = nil
    ) -> ClaudeCodeInstall {
        ClaudeCodeInstall(
            path: path, method: method, origin: origin, executable: nil,
            version: "2.1.274", signature: .anthropic, problem: nil, nodePrefix: nodePrefix)
    }

    private func title(_ install: ClaudeCodeInstall) -> String {
        ClaudeCodePresentation.title(of: install, home: Self.home)
    }

    // MARK: - Titles

    @Test func nativeIsItsLauncherWithHomeAsTilde() {
        #expect(title(install("/Users/ann/.local/bin/claude", .native)) == "~/.local/bin/claude")
    }

    /// Mutation: dropping the nvm branch names it "npm · ~/.nvm/versions/node/v24.13.0".
    @Test func anNvmPrefixIsNamedByItsNodeVersion() {
        let prefix = "/Users/ann/.nvm/versions/node/v24.13.0"
        let npm = install(prefix + "/lib/node_modules/@anthropic-ai/claude-code", .npm, nodePrefix: prefix)
        #expect(title(npm) == "nvm · node v24.13.0")
    }

    /// Only a prefix directly under nvm's `versions/node` is one of nvm's. Mutation:
    /// `hasPrefix(nvm)` instead of the parent's equality calls this "node extra".
    @Test func aPrefixDeeperUnderNvmIsNotOneOfItsVersions() {
        let prefix = "/Users/ann/.nvm/versions/node/v24.13.0/extra"
        let npm = install(prefix + "/lib/node_modules/@anthropic-ai/claude-code", .npm, nodePrefix: prefix)
        #expect(title(npm) == "npm · ~/.nvm/versions/node/v24.13.0/extra")
    }

    @Test func anyOtherNodePrefixIsNamedByItsPath() {
        let brew = install("/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code", .npm, nodePrefix: "/opt/homebrew")
        let global = install("/Users/ann/.npm-global/lib/node_modules/@anthropic-ai/claude-code", .npm,
                             nodePrefix: "/Users/ann/.npm-global")
        #expect(title(brew) == "npm · /opt/homebrew")
        #expect(title(global) == "npm · ~/.npm-global")
    }

    /// The conventional pnpm and bun copies live in the package manager's global
    /// directory, and are named that. One added by hand is wherever the user put it,
    /// so it keeps its path. Mutation: `case (.pnpm, _)` names the second "pnpm global".
    @Test func onlyTheConventionalPackageManagerCopyIsItsGlobalDirectory() {
        let pnpm = install("/Users/ann/Library/pnpm/global/5/node_modules/@anthropic-ai/claude-code", .pnpm)
        let bun = install("/Users/ann/.bun/install/global/node_modules/@anthropic-ai/claude-code", .bun)
        let added = install("/Users/ann/work/.pnpm/x/node_modules/@anthropic-ai/claude-code", .pnpm, origin: .userAdded)
        #expect(title(pnpm) == "pnpm global")
        #expect(title(bun) == "bun global")
        #expect(title(added) == "~/work/.pnpm/x/node_modules/@anthropic-ai/claude-code")
    }

    // MARK: - Home as ~

    /// Mutation: `hasPrefix(home)` without the separator turns another user's
    /// `/Users/anna/…` into `~a/…`.
    @Test func homeMatchesOnlyAWholeComponent() {
        #expect(ClaudeCodePresentation.abbreviate("/Users/anna/bin/claude", home: "/Users/ann") == "/Users/anna/bin/claude")
        #expect(ClaudeCodePresentation.abbreviate("/Users/ann/bin/claude", home: "/Users/ann/") == "~/bin/claude")
        #expect(ClaudeCodePresentation.abbreviate("/Users/ann", home: "/Users/ann") == "~")
        #expect(ClaudeCodePresentation.abbreviate("/opt/claude", home: "/Users/ann") == "/opt/claude")
    }

    // MARK: - The command to copy

    /// `ClaudeCodeStatus` has no public initializer; it is `Codable`, and this is
    /// the JSON `duo claude-code --json` prints for one.
    private func status(withheld: String?, oneClick: Bool = false) throws -> ClaudeCodeStatus {
        var json: [String: Any] = [
            "channel": "latest", "state": "updateAvailable", "latestVersion": "2.1.285",
            "install": [
                "path": "/Users/ann/.local/bin/claude", "method": "native", "origin": "conventional",
                "executable": "/Users/ann/.local/share/claude/versions/2.1.274", "version": "2.1.274",
                "signature": "anthropic",
            ],
        ]
        if let withheld { json["withheld"] = withheld }
        if oneClick { json["oneClick"] = ["executable": "/Users/ann/.local/bin/claude", "arguments": ["update"]] }
        return try JSONDecoder().decode(ClaudeCodeStatus.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// With auto-update off the update is the user's to take: they get the same
    /// command a one-click update would run.
    @Test func autoUpdateOffHandsOutTheCommand() throws {
        #expect(ClaudeCodePresentation.manualCommand(try status(withheld: "autoUpdateOff"))
                == "/Users/ann/.local/bin/claude update")
    }

    /// Every other gate means the command should not be run now — or it is
    /// DuoUpdater's to run. Mutation: dropping the `withheld == .autoUpdateOff`
    /// check hands out a command beside a running update and beside the Update
    /// button.
    @Test func noOtherGateHandsOutACommand() throws {
        #expect(ClaudeCodePresentation.manualCommand(try status(withheld: "busy")) == nil)
        #expect(ClaudeCodePresentation.manualCommand(try status(withheld: "updatesDisabled")) == nil)
        #expect(ClaudeCodePresentation.manualCommand(try status(withheld: nil, oneClick: true)) == nil)
    }
}
