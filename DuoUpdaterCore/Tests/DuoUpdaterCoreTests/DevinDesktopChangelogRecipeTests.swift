import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three `<Update>` blocks of `docs.devin.ai/desktop/changelog` (Mintlify),
/// fetched 2026-10-10: 3.10.48 and 3.10.35 from the top of the page, and 2.3.15,
/// an older block that uses real `<h1>`/`<h2>` headings instead of bold
/// paragraphs. Icon `<svg>`s and `class`/`style` attributes are elided; the rest
/// is verbatim, including the zero-width space in each heading's anchor.
private let devinDesktopChangelogFixture = #"""
<div id="v3-10-48"><div><div><a href="#v3-10-48" aria-label="Navigate to changelog: v3.10.48">​<div></div></a></div><button type="button" contentEditable="false" data-component-part="update-label">v3.10.48</button><span role="status"></span><div contentEditable="false" data-component-part="update-description">September 29, 2026</div></div><div><div data-component-part="update-content"><span data-as="p"><strong>Sign in with ChatGPT</strong></span><span data-as="p">You can now <a href="https://devin.ai/blog/sign-in-with-chatgpt" target="_blank" rel="noreferrer">sign in to Devin with ChatGPT</a> and use your eligible ChatGPT Plus or Pro plan for GPT model usage in Devin Desktop. Choose a GPT model and those requests are billed to your ChatGPT plan; for the best value, use Fusion with GPT-6 Astra as the lead and SWE-2 as the sidekick. See <a href="/admin/billing/chatgpt">Use your ChatGPT plan</a> for setup and eligible models.</span><span data-as="p"><strong>Devin Desktop</strong></span><ul>
<li>New commands <strong>Devin: Save Language Server Memory Profile</strong> and <strong>Devin: Save Language Server CPU Profile</strong> save a diagnostic <code>.zip</code> you can send to support.</li>
<li>Long or noisy shell commands no longer grow the Agent window’s memory with every terminal refresh, which could crash the window.</li>
<li>New Agent sessions started without a folder pick keep every folder of a converted multi-folder workspace, instead of only the first one.</li>
<li>Devin Desktop keeps a much smaller local settings file for accounts with many available models, and resolves user settings once per change instead of on every read. Typing, selecting text, and copy/paste no longer stall the extension host.</li>
<li>Session list polling backs off while Devin Desktop is unfocused or the conversation dropdown is closed.</li>
</ul><details open=""><summary aria-controls="download-3-10-48-accordion-children" aria-expanded="true" data-component-part="accordion-button"><div id="download-3-10-48"></div><div data-component-part="accordion-caret-right"></div><div contentEditable="false" data-component-part="accordion-title-container"><p id="download-3-10-48-accordion-title" data-component-part="accordion-title">Download 3.10.48</p></div></summary><div id="download-3-10-48-accordion-children" role="region" aria-labelledby="download-3-10-48-accordion-title" data-component-part="accordion-content"></div></details></div></div></div>
<div id="v3-10-35"><div><div><a href="#v3-10-35" aria-label="Navigate to changelog: v3.10.35">​<div></div></a></div><button type="button" contentEditable="false" data-component-part="update-label">v3.10.35</button><span role="status"></span><div contentEditable="false" data-component-part="update-description">September 24, 2026</div></div><div><div data-component-part="update-content"><span data-as="p"><strong>Devin Desktop</strong></span><ul>
<li>Devin Desktop no longer crashes at startup on Apple Macs using M6 chips</li>
<li>Fixed a memory leak with the agent command center</li>
<li>Choosing a folder for an agent on an SSH or WSL host now works when the side panel and a new-session welcome are both open.</li>
<li>MCP servers passed by an ACP client in <code>session/new</code> / <code>session/load</code> are now usable by the agent and listed in <code>/mcp</code>, including for HTTP and SSE MCP servers</li>
</ul><details><summary aria-controls="download-3-10-35-accordion-children" aria-expanded="false" data-component-part="accordion-button"><div id="download-3-10-35"></div><div data-component-part="accordion-caret-right"></div><div contentEditable="false" data-component-part="accordion-title-container"><p id="download-3-10-35-accordion-title" data-component-part="accordion-title">Download 3.10.35</p></div></summary><div id="download-3-10-35-accordion-children" role="region" aria-labelledby="download-3-10-35-accordion-title" data-component-part="accordion-content"></div></details></div></div></div>
<div id="v2-3-15"><div><div><a href="#v2-3-15" aria-label="Navigate to changelog: v2.3.15">​<div></div></a></div><button type="button" contentEditable="false" data-component-part="update-label">v2.3.15</button><span role="status"></span><div contentEditable="false" data-component-part="update-description">May 27, 2026</div></div><div><div data-component-part="update-content"><h1 id="bug-fixes-and-improvements"><div tabindex="-1"><a href="#bug-fixes-and-improvements" aria-label="Navigate to header">​<div></div></a></div><span>Bug fixes and improvements</span></h1><h2 id="general"><div tabindex="-1"><a href="#general" aria-label="Navigate to header">​<div></div></a></div><span>General</span></h2><ul>
<li>Increased remote server startup timeout from 2.5s to 6s.</li>
</ul><h2 id="devin-local"><div tabindex="-1"><a href="#devin-local" aria-label="Navigate to header">​<div></div></a></div><span>Devin Local</span></h2><span data-as="p">This release updates the bundled Devin Local agent to 2026.5.26. See the <a href="https://cli.devin.ai/docs/changelog/stable#2026-5-26-0" target="_blank" rel="noreferrer">changelog</a> for the full list of changes.</span><ul>
<li>Devin Local is now aware of the files you have open in the editor as part of its context.</li>
<li>When prompted for an MCP tool permission in Devin Local, two additional server-level options are now offered: approve all tools on the server for the current session, or permanently.</li>
<li>Repaired hooks for Devin Local to allow blocking user prompts.</li>
<li>Improved plan mode in Devin Local to work in the OS sandbox.</li>
<li>“Always Allow” permission grants in Devin Local now persist across sessions.</li>
<li>Image attachments in Devin Local now show the correct warning when the selected model does not support images.</li>
</ul><details><summary aria-controls="download-2-3-15-accordion-children" aria-expanded="false" data-component-part="accordion-button"><div id="download-2-3-15"></div><div data-component-part="accordion-caret-right"></div><div contentEditable="false" data-component-part="accordion-title-container"><p id="download-2-3-15-accordion-title" data-component-part="accordion-title">Download 2.3.15</p></div></summary><div id="download-2-3-15-accordion-children" role="region" aria-labelledby="download-2-3-15-accordion-title" data-component-part="accordion-content"></div></details></div></div></div>

"""#

private func headings(_ entry: Changelog.Entry) -> [String] {
    entry.content.compactMap { block -> String? in
        if case .heading(let text) = block { return text } else { return nil }
    }
}

@Test func devinDesktopReadsUpdateBlocks() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.exafunction.windsurf"),
        "Devin Desktop (Windsurf) changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: devinDesktopChangelogFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["3.10.48", "3.10.35", "2.3.15"])
    #expect(log.entries.map(\.date) == ["September 29, 2026", "September 24, 2026", "May 27, 2026"])
    // A paragraph and the list under it, in page order; the bold-only paragraphs
    // are headings, not notes.
    let top = log.entries[0]
    #expect(top.items.count == 6)
    #expect(top.items.first?.hasPrefix("You can now sign in to Devin with ChatGPT") == true)
    #expect(top.items[1]
        == "New commands Devin: Save Language Server Memory Profile and Devin: Save Language Server CPU Profile save a diagnostic .zip you can send to support.")
    #expect(headings(top) == ["Sign in with ChatGPT", "Devin Desktop"])
    // The "Download 3.10.48" accordion is not a note.
    #expect(!top.items.contains { $0.hasPrefix("Download") })
}

@Test func devinDesktopKeepsOldStyleHeadingsWithoutTheAnchorSpace() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.exafunction.windsurf"))
    let log = try #require(ChangelogExtractor.extract(from: devinDesktopChangelogFixture, using: recipe))
    let old = log.entries[2]
    #expect(headings(old) == ["Bug fixes and improvements", "General", "Devin Local"])
    #expect(old.items.count == 8)
    #expect(old.items.first == "Increased remote server startup timeout from 2.5s to 6s.")
}
