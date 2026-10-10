import Foundation
import Testing

@testable import DuoUpdaterCore

/// Five release blocks of `docs.termius.com/changelog` (GitBook), fetched
/// 2026-10-10, in page order: the year heading and 10.1.3, 10.1.0 and 10.0.6 from
/// the top, then 9.37.3 (4) and 9.37.0, then the page's "Last updated" footer.
/// The live page is ~6.7 MB decoded, almost all of it markup around these blocks,
/// so the icon `<svg>`s, the "Ask" `<button>`s and every `class`/`style`/`data-*`/
/// `aria-*` attribute are elided; the tags, their order, the text and the
/// newlines between note lines are verbatim.
private let termiusChangelogFixture = #"""
<h2 id="id-2026"><span>2026</span><span><a href="#id-2026"></a></span></h2><div><div><div><time dateTime="2026-09-30">September 30, 2026</time></div><div><h2 id="id-10.1.3"><span>10.1.3</span><span><a href="#id-10.1.3"></a></span></h2><div><p>🛠️ Fixed an issue with the Snapcraft update.
🛠️ Fixed an issue where connections using FIDO2 security keys failed in the Mac App Store version.</p><div></div></div></div></div><div><div><time dateTime="2026-09-21">September 21, 2026</time></div><div><h2 id="id-10.1.0"><span>10.1.0</span><span><a href="#id-10.1.0"></a></span></h2><div><p>✨ Proxy, Agent Forwarding, Host chains, and Serial connections are now available for free.</p><div></div></div><div><p>
🛠️ Fixed a bug where OSC 8 hyperlinks showed a confirmation dialog but did not open the browser after confirmation.
🛠️ Improved performance.
🛠️ Other stability and UI improvements.</p><div></div></div></div></div><div><div><time dateTime="2026-09-17">September 17, 2026</time></div><div><h2 id="id-10.0.6"><span>10.0.6</span><span><a href="#id-10.0.6"></a></span></h2><div><p>🛠️  Update to Electron 43 and other stability improvements.

⚠️ These changes are not backward-compatible. 
Do not install an earlier version over the current one, as this will reset your local storage.</p><div></div></div></div></div><div><div><time dateTime="2026-03-09">March 9, 2026</time></div><div><h2 id="id-9.37.3-4"><span>9.37.3 (4)</span><span><a href="#id-9.37.3-4"></a></span></h2><div><p>✨ <strong>Terminal Emulation:</strong> Added support for specifying <strong>Linux</strong> and <strong>VT100</strong> terminal types within Terminal settings.</p><div></div></div><div><p>🛠️ Fixed a bug causing an infinite spinner in SFTP when attempting to restore a disconnected session.
🛠️ Fixed a bug that prevented users from exporting their biometric keys.
🛠️ Other stability improvements.</p><div></div></div></div></div><div><div><time dateTime="2026-02-09">February 9, 2026</time></div><div><h2 id="id-9.37.0"><span>9.37.0</span><span><a href="#id-9.37.0"></a></span></h2><div><p>✨ Added support for ML-DSA key generation and authentication (requires server-side ML-DSA support).
✨ Improved hotkey support for workspaces:
- <code>Cmd+S</code> (or <code>Ctrl+S</code>) is now used to save changes in the workspace (layout, focus mode, hosts list, tab names).
- <code>Cmd+.</code> (or <code>Ctrl+.</code>) is used for opening/closing the terminal side panel
- <code>Cmd+Shift+M</code> (or <code>Ctrl+Shift+M</code>) switches between the Focus and Split modes
- <code>Cmd+Option+arrows</code> (or <code>Ctrl+Alt+arrows</code>) switches between the terminals in the workspace in both modes
- You are open to customize it in <code>Termius &gt; Settings &gt; Shortcuts</code></p><div></div></div><div><p>🛠️ Stability and performance improvements.</p><div></div></div></div></div></div></div><p>Last updated <time dateTime="2026-09-30T21:09:41.719Z">9 days ago</time></p></main>
"""#

@Test func termiusReadsOneEntryPerDatedBlock() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.termius-dmg.mac"),
        "Termius changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: termiusChangelogFixture, using: recipe))

    // The year heading is not an entry, and "9.37.3 (4)" is read as the version
    // the feed reports, without the build suffix.
    #expect(log.entries.map(\.version) == ["10.1.3", "10.1.0", "10.0.6", "9.37.3", "9.37.0"])
    #expect(log.entries.first?.date == "September 30, 2026")
    #expect(log.entries[0].items == [
        "🛠️ Fixed an issue with the Snapcraft update.",
        "🛠️ Fixed an issue where connections using FIDO2 security keys failed in the Mac App Store version.",
    ])
}

@Test func termiusSplitsAParagraphIntoItsLines() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.termius-dmg.mac"))
    let log = try #require(ChangelogExtractor.extract(from: termiusChangelogFixture, using: recipe))

    // 10.1.0 is two `<p>` blocks, the second opening on a newline and holding
    // three lines: one item per line, none empty.
    #expect(log.entries[1].items == [
        "✨ Proxy, Agent Forwarding, Host chains, and Serial connections are now available for free.",
        "🛠️ Fixed a bug where OSC 8 hyperlinks showed a confirmation dialog but did not open the browser after confirmation.",
        "🛠️ Improved performance.",
        "🛠️ Other stability and UI improvements.",
    ])
    // A sub-point loses its "- ", inline <code> is flattened, entities decode, and
    // the next block's paragraph is still this entry's last line.
    let notes = log.entries[4].items
    #expect(notes.count == 8)
    #expect(notes.contains(
        "Cmd+S (or Ctrl+S) is now used to save changes in the workspace (layout, focus mode, hosts list, tab names)."))
    #expect(notes.contains("You are open to customize it in Termius > Settings > Shortcuts"))
    #expect(notes.last == "🛠️ Stability and performance improvements.")
    // The footer's "Last updated" paragraph never joins the last entry.
    #expect(!notes.contains { $0.contains("Last updated") })
}
