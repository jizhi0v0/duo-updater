import Foundation
import Testing
import DuoUpdaterCore

/// How the workbench's CLI tab words an install of a tool without wording of its
/// own (bub, fx), from `CLIToolStatus`'s shared fields alone. Every path is made
/// up and `home` is passed in, so no answer depends on the Mac running the tests.
///
/// Each case names the one-line mutation of `CLIToolPresentation` it fails under.
struct CLIToolPresentationTests {

    private static let home = "/Users/ann"

    private func fx(
        _ path: String = "/Users/ann/.fx/bin/fx", version: String? = "0.4.0", latest: String? = "0.5.0",
        state: CLIToolState = .updateAvailable, channel: String? = "stable",
        oneClick: Bool = true, withheld: CLIToolWithheld? = nil, manual: Bool = false
    ) -> CLIToolStatus {
        let command = CLIToolCommand(executable: path, arguments: ["upgrade"], pathPrefix: nil)
        return CLIToolStatus(
            kind: .fx, path: path, installedVersion: version, latestVersion: latest, channel: channel,
            state: state, oneClick: oneClick ? command : nil,
            withheld: withheld, note: nil, manualCommand: manual ? command : nil,
            detail: .fx(FxInstall(path: path, version: version)))
    }

    /// The command to copy only beside an update withheld because the user turned
    /// the tool's auto-update off. Mutation: dropping the `withheld` check hands it
    /// out beside a running update.
    /// bub's first update creates its project and may rebuild the venv on
    /// another Python (measured on the user's Mac, 2026-10-01): said beside the
    /// click, only then. Mutation: dropping the `.absent` check says it beside
    /// every bub update.
    @Test func onlyBubsFirstUpdateCarriesTheCaution() {
        func bub(_ project: BubInstall.Project?, oneClick: Bool = true) -> CLIToolStatus {
            let path = "/Users/ann/.bub/.venv"
            return CLIToolStatus(
                kind: .bub, path: path, installedVersion: "0.4.4", latestVersion: "0.5.0", channel: nil,
                state: .updateAvailable,
                oneClick: oneClick ? CLIToolCommand(executable: path + "/bin/bub", arguments: ["update", "bub"], pathPrefix: nil) : nil,
                withheld: oneClick ? nil : .updaterMissing, note: nil,
                detail: .bub(BubInstall(path: path, method: .installer, executable: path + "/bin/bub",
                                        version: "0.4.4", project: project)))
        }
        #expect(CLIToolPresentation.caution(bub(.absent)) != nil)
        #expect(CLIToolPresentation.caution(bub(.listsBub)) == nil)
        #expect(CLIToolPresentation.caution(bub(.absent, oneClick: false)) == nil)
        #expect(CLIToolPresentation.caution(fx()) == nil)
    }

    @Test func onlyAutoUpdateOffHandsOutTheCommand() {
        #expect(CLIToolPresentation.manualCommand(fx(oneClick: false, withheld: .autoUpdateOff, manual: true))
                == "/Users/ann/.fx/bin/fx upgrade")
        #expect(CLIToolPresentation.manualCommand(fx(oneClick: false, withheld: .busy, manual: true)) == nil)
        #expect(CLIToolPresentation.manualCommand(
            fx(state: .upToDate, oneClick: false, withheld: .autoUpdateOff, manual: true)) == nil)
    }

    /// Mutation: drop the `.claudeCode` branch from `title(of:home:)` — an nvm
    /// copy of Claude Code would then be named by its whole package path.
    @Test func theTitleIsThePathWithHomeAsTildeAndClaudeCodeKeepsItsOwn() {
        #expect(CLIToolPresentation.title(of: fx(), home: Self.home) == "~/.fx/bin/fx")

        let prefix = "/Users/ann/.nvm/versions/node/v24.13.0"
        let path = prefix + "/lib/node_modules/@anthropic-ai/claude-code"
        let json: [String: Any] = [
            "install": ["path": path, "method": "npm", "origin": "conventional", "nodePrefix": prefix],
            "channel": "latest", "state": "upToDate",
        ]
        let claudeCode = try! JSONDecoder().decode(
            ClaudeCodeStatus.self, from: try! JSONSerialization.data(withJSONObject: json))
        let status = CLIToolStatus(
            kind: .claudeCode, path: path, installedVersion: nil, latestVersion: nil, channel: "latest",
            state: .upToDate, oneClick: nil, withheld: nil, note: nil, detail: .claudeCode(claudeCode))
        #expect(CLIToolPresentation.title(of: status, home: Self.home) == "nvm · node v24.13.0")
    }

    /// An update shows both versions; otherwise the version alone.
    ///
    /// Mutation: drop `status.state == .updateAvailable,` from `versionCaption`.
    @Test func theCaptionShowsTheUpdateOnlyWhenThereIsOne() {
        #expect(CLIToolPresentation.versionCaption(fx()) == "0.4.0 → 0.5.0")
        #expect(CLIToolPresentation.versionCaption(fx(state: .ahead)) == "0.4.0")
    }

    /// The row's warning replaces the versions only when there is no verdict. An
    /// outdated copy that is only held back keeps its versions on the row; why it
    /// is held back is the pane's (and the tooltip's) to say.
    ///
    /// Mutation: drop `status.state == .unknown,` from `rowWarning`.
    @Test func onlyAnUncheckedCopyWarnsOnTheRow() {
        let heldBack = fx(oneClick: false, withheld: .autoUpdateOff)
        #expect(CLIToolPresentation.rowWarning(heldBack) == nil)
        #expect(CLIToolPresentation.explanation(heldBack) == "Auto-update is off in fx’s settings")

        let unchecked = fx(latest: nil, state: .unknown, oneClick: false, withheld: .wrongSigner)
        #expect(CLIToolPresentation.rowWarning(unchecked) == "Not signed by Vercel")
    }

    /// The group header names a channel once however many copies are on it, and
    /// each when they differ.
    ///
    /// Mutation: drop `where !seen.contains(channel)` from `channels(of:)`.
    @Test func theHeaderNamesEachChannelOnce() {
        #expect(CLIToolPresentation.channels(of: [fx(), fx("/opt/homebrew/bin/fx")]) == "stable")
        #expect(CLIToolPresentation.channels(of: [fx(), fx("/opt/homebrew/bin/fx", channel: "canary")])
            == "stable, canary")
        #expect(CLIToolPresentation.channels(of: [fx(channel: nil)]) == nil)
    }
}
