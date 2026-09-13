import Testing
import Foundation
@testable import DuoUpdaterCore

/// The top of `claude.com/docs/cowork/changelog.md`, fetched 2026-09-13, verbatim:
/// a release whose General and Code are both "No user-facing changes." (only
/// Cowork changed), the 1.52386.0 release the in-app "What's new" was compared
/// against, and a "Known issue" announcement that is not a release at all.
private let claudeDesktopDocsFixture = #"""
<Update label="v1.52386.3" description="2026-09-11">
  **General**

  * No user-facing changes.

  **Code**

  * No user-facing changes.

  **Cowork**

  * Changed the automatic move of scheduled tasks to the cloud, for accounts where it has started: the app now waits about a minute after the computer wakes, and while offline checks again each minute, instead of trying at once and then waiting hours after a failed try.
  * Fixed two problems with local projects that are moving to claude.ai, for accounts where that move has started: a project could refuse new tasks for hours while part of its memory copy waited on the server (it now accepts new tasks and the copy finishes in the background), and memory files shown in a moved project's earlier tasks would not open.

  **3P**

  * No user-facing changes.
</Update>

<Update label="v1.52386.0" description="2026-09-10">
  **General**

  * Changed messages sent while Claude is still replying: they now wait in the conversation looking like sent messages, the first waiting message offers Send now, which stops the current reply and sends it next, and Cmd/Ctrl+Enter sends your message right away, interrupting the current turn.
  * Fixed Claude's clicks, scrolls, screenshots, and page scripts in the built-in browser stalling, timing out, or failing while the browser pane was hidden or the window was minimized or in the background, and fixed elements picked with "Select element" reaching Claude without their styles or with a screenshot of the wrong part of the page.
  * Fixed links that open a new tab to claude.ai or claude.com pages, like Upgrade buttons and some download links, doing nothing when clicked; they now open in your default browser.
  * Fixed sites on a private network (VPN, Tailscale, or intranet hosts) loading without their styles, scripts, or data in the built-in browser, and URLs typed into the built-in browser in cloud sessions not reaching private-network sites.
  * Fixed the app window resetting to its default size and position after an update or a display change.

  **Code**

  * Added a default transcript view setting: choose whether new sessions open in the Normal, Thinking, or Verbose view from Settings > Claude Code, or make the current view the default from a session's Transcript view menu. The choice syncs between the desktop app and claude.ai.
  * Fixed Code sessions failing to start on some Microsoft Store and MSIX installs on Windows.
  * Fixed model changes being refused with a message saying organization-managed hooks could not be checked, for some organizations that manage Claude Code plugins; the session now restarts on the chosen model.
  * Fixed sessions failing to start on Windows for accounts with many plugins installed.
  * Fixed several SSH session issues: hosts slowly accumulating leftover background processes from older Claude versions until sessions there failed, sessions from one computer being ended when a second computer's Claude app cleaned up the same host, sessions permanently losing their connection after a saved connection's host or port was edited, and history missing its newest messages soon after launch or a reconnect.
  * Fixed WSL sessions failing to start or reconnect, including background reconnects right after an app update, when WSL reported a momentary error.

  **Cowork**

  * Changed what happens on Windows PCs where a Windows update released September 8, 2026 prevents Claude's workspace from reaching your files: the app now names that cause instead of deleting and reinstalling the workspace. This does not fix the underlying problem, and the workspace still can't reach your files on those PCs.
  * Fixed a session appearing stuck running when an organization hook blocked a message; the reason the message was blocked is now shown.
  * Fixed an Office file preview sometimes showing "Failed to load PDF document" instead of the spreadsheet or document view.
  * Fixed long-running tasks failing with an authentication error after the app renewed your sign-in in the background; the running task now picks up the renewed sign-in and continues.

  **3P**

  * Added `coworkVmIpv6Enabled`, which gives the Cowork workspace VM an IPv6 address and route so the agent's tools can reach IPv6-only hosts through the device's own IPv6 connectivity. macOS and Windows; off by default. `coworkEgressAllowedHosts` still decides which hostnames the tools may reach.
  * Added `sshTransport` (beta), which chooses the SSH engine that carries Code sessions: `system-openssh` runs the OpenSSH `ssh` program on the device, so connections can use the organization's own SSH setup (for example Kerberos sign-in, including on Windows), and `builtin` uses the app's built-in SSH library. Unset or `auto` keeps the build's default.
  * Added a deprecation notice in the Setup window under any managed-configuration setting that is scheduled to stop being accepted, naming the date and what to use instead.
  * Added organization-set session retention. `chatSessionRetentionDays`, `coworkSessionRetentionDays`, and `codeSessionRetentionDays` each delete that surface's idle sessions from the device, along with their files, after the set number of days (1 to 3650) without activity; unset deletes nothing. `sessionRetentionHold` suspends all automatic deletion for the users it is set for, as a legal hold. Projects, Spaces, and memory stay, and a Code session's uncommitted work stays on disk.
  * Changed app launch to open the home composer on the last-used Chat or Cowork mode instead of always opening Cowork first.
  * Changed hooks from organization plugins to also run in Chat, matching Cowork and Code.
  * Deprecated an undocumented client-certificate fallback setting that releases from 1.49585.0 on no longer read, since the app now presents TLS client certificates natively. Deployments that still set it keep working unchanged, but their users see an in-app deprecation warning from November 3, 2026, and the setting stops being accepted on November 17, 2026; remove it once every device is on 1.49585.0 or later.
  * Improved the connection test against gateways that require a TLS client certificate the device does not have: the result now says the device did not present a certificate the gateway accepts, so the connection could not be tested, instead of reporting the model as rejected.
  * Fixed Claude Code's own settings on the device (a user's or project's settings file, or a `managed-settings.json`) being able to turn OpenTelemetry trace export back on after an administrator configured a collector with traces off; with `otlpEndpoint` set, Cowork and Code sessions now export traces only when `otlpTracesEnabled` is `true`.
  * Fixed Amazon Bedrock and Google Vertex AI sessions retrying a failed request for several minutes when the AWS or Google Cloud credential on the machine had expired; the request now stops after one retry so the credential can be refreshed.
</Update>

<Update label="Known issue: Cowork on Windows" description="2026-09-10">
  A Windows update released September 8, 2026 (including KB5124008) stops Cowork from reaching your files when it runs on your Windows PC, so tasks fail or the workspace does not start. This affects Cowork on third-party inference deployments and Cowork sessions that run on your computer rather than in the cloud. Cloud sessions and Claude Code, including the Code tab, are not affected. Chat cloud sessions are not affected, but Chat sessions on third-party inference deployments are affected if using advanced file analysis. The cause is a change in Windows, so restarting or reinstalling Claude does not help. We are investigating and working to resolve this as quickly as possible.
</Update>
"""#

@Suite struct ClaudeDesktopChangelogTests {

    /// What the in-app "What's new" shows for 1.52386.0 in the Code tab. Not
    /// derived from the decoder's own verb rule: each note's heading is its real
    /// `kind` from the `{surface, kind, text}` array in claude.ai's JS bundle
    /// (cached on this Mac 2026-09-13), `feat`/`improvement`/`fix` rendered as
    /// New/Improved/Fixed in that order, General and Code only. Within a heading
    /// the order is the `.md`'s, which is alphabetical per surface — the modal's
    /// own order differs, and that part is not reproduced.
    private let expected = Changelog(entries: [
        Changelog.Entry(
            version: "1.52386.0",
            date: "2026-09-10",
            items: [],
            content: [
                .heading("New"),
                .note("Added a default transcript view setting: choose whether new sessions open in the Normal, Thinking, or Verbose view from Settings > Claude Code, or make the current view the default from a session's Transcript view menu. The choice syncs between the desktop app and claude.ai."),
                .heading("Improved"),
                .note("Changed messages sent while Claude is still replying: they now wait in the conversation looking like sent messages, the first waiting message offers Send now, which stops the current reply and sends it next, and Cmd/Ctrl+Enter sends your message right away, interrupting the current turn."),
                .heading("Fixed"),
                .note("Fixed Claude's clicks, scrolls, screenshots, and page scripts in the built-in browser stalling, timing out, or failing while the browser pane was hidden or the window was minimized or in the background, and fixed elements picked with \"Select element\" reaching Claude without their styles or with a screenshot of the wrong part of the page."),
                .note("Fixed links that open a new tab to claude.ai or claude.com pages, like Upgrade buttons and some download links, doing nothing when clicked; they now open in your default browser."),
                .note("Fixed sites on a private network (VPN, Tailscale, or intranet hosts) loading without their styles, scripts, or data in the built-in browser, and URLs typed into the built-in browser in cloud sessions not reaching private-network sites."),
                .note("Fixed the app window resetting to its default size and position after an update or a display change."),
                .note("Fixed Code sessions failing to start on some Microsoft Store and MSIX installs on Windows."),
                .note("Fixed model changes being refused with a message saying organization-managed hooks could not be checked, for some organizations that manage Claude Code plugins; the session now restarts on the chosen model."),
                .note("Fixed sessions failing to start on Windows for accounts with many plugins installed."),
                .note("Fixed several SSH session issues: hosts slowly accumulating leftover background processes from older Claude versions until sessions there failed, sessions from one computer being ended when a second computer's Claude app cleaned up the same host, sessions permanently losing their connection after a saved connection's host or port was edited, and history missing its newest messages soon after launch or a reconnect."),
                .note("Fixed WSL sessions failing to start or reconnect, including background reconnects right after an app update, when WSL reported a momentary error."),
            ]),
    ])

    /// Rebuilds `expected` with `items` filled from its notes, so the list is
    /// written once.
    private var expectedWithItems: Changelog {
        Changelog(entries: expected.entries.map { entry in
            Changelog.Entry(
                version: entry.version, date: entry.date,
                items: entry.content.compactMap {
                    if case .note(let text) = $0 { return text } else { return nil }
                },
                content: entry.content)
        })
    }

    /// Through `ChangelogService.parse` with the registered recipe — the exact
    /// path the app takes — so a recipe that stopped pointing at this format
    /// fails here too.
    @Test func registeredRecipeMatchesTheInAppWhatsNew() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.anthropic.claudefordesktop"))
        #expect(recipe.structuredFormat == .claudeDesktopChangelog)
        let changelog = try #require(ChangelogService.parse(recipe, body: claudeDesktopDocsFixture))

        // One entry: 1.52386.3 has nothing outside Cowork (the modal drops such a
        // release too), and "Known issue: …" is not a `v<version>` label.
        #expect(changelog == expectedWithItems)
    }

    @Test func capStopsAtMaxEntries() throws {
        let body = (1...3).map {
            "<Update label=\"v1.0.\($0)\" description=\"\">\n  **Code**\n\n  * Fixed \($0).\n</Update>"
        }.joined(separator: "\n\n")
        let changelog = try #require(StructuredChangelogDecoder.decode(
            body, format: .claudeDesktopChangelog, channel: nil, maxEntries: 2))
        #expect(changelog.entries.map(\.version) == ["1.0.1", "1.0.2"])
        #expect(changelog.entries.first?.date == nil)
    }
}
