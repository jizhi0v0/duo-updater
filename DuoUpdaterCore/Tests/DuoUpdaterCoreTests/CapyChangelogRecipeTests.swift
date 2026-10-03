import Testing
import Foundation
@testable import DuoUpdaterCore

/// `capy.ai/changelog`, fetched 2026-10-04 and trimmed: the start of 0.4.3 (lead
/// image, intro paragraph, two `<h3>` sections, one inline screenshot), the whole
/// 0.2.1 entry (no headings), and the versionless `Capy Beta` launch post the
/// page ends with. Long class lists are cut down; the attributes the patterns
/// read (`id`, the `font-inter` class, `src`) are verbatim.
private let capyChangelogFixture = #"""
<main><div class="container"><nav><ol><li class="relative"><a aria-label="Capy 0.4.3, Oct 3, 2026" href="#v0-4-3"></a></li><li class="relative"><a aria-label="Capy Beta, Aug 11, 2026" href="#vbeta"></a></li></ol></nav><article class="scroll-mt-[calc(var(--header-height)+1.25rem)] outline-none" id="v0-4-3" tabindex="-1"><time class="font-dm-mono text-black-600 text-sm" dateTime="2026-10-03">Oct 3, 2026</time><h2 class="leading-trim-heading mt-3 text-black md:text-5xl"><a class="focus-ring hover:text-black-700" href="/changelog/0.4.3">Capy 0.4.3</a></h2><p class="text-black-700 mt-2 text-[1.125rem] leading-[140%] md:text-lg">Subagents and the full GPT-6 context on Codex</p><div class="block aspect-video w-full overflow-hidden bg-black-50 mt-6"><img alt="Subagents and the full GPT-6 context on Codex" width="1792" height="1008" decoding="async" data-nimg="1" class="block size-full object-contain" style="color:transparent" src="https://downloads.capy.ai/stable/changelog/0.4.3-memory.webp"/></div><div class="prose-sm md:prose mt-6 max-w-none min-w-0 [&amp;&gt;*:first-child]:mt-0"><p class="font-inter text-secondary-foreground">Tasks are now called subagents, and on a Codex subscription the GPT-6 models use their full 1.05M-token context window.</p>
<h3 class="font-heading text-[1.75rem] leading-none font-normal text-black uppercase">Subagents</h3>
<p class="font-inter text-secondary-foreground">A thread&#x27;s child agents are now called subagents in the app, the CLI, Slack, and the docs. Prompts and automations that say task keep working, and the API still calls them tasks.</p>
<h3 class="font-heading text-[1.75rem] leading-none font-normal text-black uppercase">Where new messages scroll</h3>
<span class="block aspect-video w-full overflow-hidden bg-black-50 not-prose my-8"><img alt="The Chat section on the Appearance page with Scroll new messages to top" loading="lazy" width="1792" height="1008" decoding="async" data-nimg="1" class="block size-full object-contain" style="color:transparent" src="https://downloads.capy.ai/stable/changelog/0.4.3-scroll.webp"/></span>
<p class="font-inter text-secondary-foreground">The <strong class="font-semibold text-black" node="[object Object]">Appearance</strong> page has a new <strong class="font-semibold text-black" node="[object Object]">Chat</strong> section with <strong class="font-semibold text-black" node="[object Object]">Scroll new messages to top</strong>.</p></div></article><article class="scroll-mt-[calc(var(--header-height)+1.25rem)] outline-none mt-14 border-t-2 border-black pt-14" id="v0-2-1" tabindex="-1"><time class="font-dm-mono text-black-600 text-sm" dateTime="2026-09-12">Sep 12, 2026</time><h2 class="leading-trim-heading mt-3 text-black md:text-5xl"><a class="focus-ring hover:text-black-700" href="/changelog/0.2.1">Capy 0.2.1</a></h2><p class="text-black-700 mt-2 text-[1.125rem] leading-[140%] md:text-lg">Linux fixes</p><div class="prose-sm md:prose mt-6 max-w-none min-w-0 [&amp;&gt;*:first-child]:mt-0"><p class="font-inter text-secondary-foreground">Fixes for Linux: the dock shows the Capy icon and name, the window opens under Wayland, sign-in persists without a keyring, and the app relaunches after an update.</p></div></article><article class="scroll-mt-[calc(var(--header-height)+1.25rem)] outline-none mt-14 border-t-2 border-black pt-14" id="vbeta" tabindex="-1"><time class="font-dm-mono text-black-600 text-sm" dateTime="2026-08-11">Aug 11, 2026</time><h2 class="leading-trim-heading mt-3 text-black md:text-5xl"><a class="focus-ring hover:text-black-700" href="/changelog/beta">Capy Beta</a></h2><p class="text-black-700 mt-2 text-[1.125rem] leading-[140%] md:text-lg">Threads on cloud machines</p><div class="prose-sm md:prose mt-6 max-w-none min-w-0 [&amp;&gt;*:first-child]:mt-0"><p class="font-inter text-secondary-foreground">Capy&#x27;s first release: a coding agent that takes a task, works on a cloud machine with your repositories cloned, and opens the pull request.</p></div></article></div></main>
"""#

@Test func capyChangelogParsesEachVersionedArticle() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.capy.desktop"))
    let log = try #require(ChangelogExtractor.extract(from: capyChangelogFixture, using: recipe))

    // The versionless `Capy Beta` post is not an entry.
    #expect(log.entries.map(\.version) == ["0.4.3", "0.2.1"])

    let newest = try #require(log.entries.first)
    #expect(newest.date == "Oct 3, 2026")
    #expect(newest.title == "Subagents and the full GPT-6 context on Codex")
    // The subtitle `<p>` is the title, not a note; inline tags are stripped and
    // `&#x27;` decoded.
    #expect(newest.items == [
        "Tasks are now called subagents, and on a Codex subscription the GPT-6 models use their full 1.05M-token context window.",
        "A thread's child agents are now called subagents in the app, the CLI, Slack, and the docs. Prompts and automations that say task keep working, and the API still calls them tasks.",
        "The Appearance page has a new Chat section with Scroll new messages to top.",
    ])
    // Headings and screenshots interleave with the notes in page order.
    #expect(newest.content == [
        .image(URL(string: "https://downloads.capy.ai/stable/changelog/0.4.3-memory.webp")!),
        .note(newest.items[0]),
        .heading("Subagents"),
        .note(newest.items[1]),
        .heading("Where new messages scroll"),
        .image(URL(string: "https://downloads.capy.ai/stable/changelog/0.4.3-scroll.webp")!),
        .note(newest.items[2]),
    ])

    let plain = log.entries[1]
    #expect(plain.title == "Linux fixes")
    #expect(plain.items.count == 1)
    #expect(plain.content.isEmpty)
}

/// Not a captured page: the two shapes the live page doesn't have yet, built
/// from its own markup. An article with no subtitle must keep its first note
/// as a note, and a list mixed into the paragraphs must not be dropped (the
/// extractor keeps only the first item pattern that yields anything).
@Test func capyChangelogKeepsNotesWithoutASubtitleAndAlongsideAList() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.capy.desktop"))
    let page = #"""
        <article class="outline-none" id="v0-5-0" tabindex="-1"><time class="font-dm-mono text-sm" dateTime="2026-10-09">Oct 9, 2026</time><h2 class="mt-3"><a href="/changelog/0.5.0">Capy 0.5.0</a></h2><div class="prose-sm mt-6"><p class="font-inter text-secondary-foreground">Intro paragraph.</p>
        <ul><li>First list item</li><li><p class="font-inter text-secondary-foreground">Loose list item</p></li></ul>
        <p class="font-inter text-secondary-foreground">Closing paragraph.</p></div></article>
        """#
    let entry = try #require(ChangelogExtractor.extract(from: page, using: recipe)?.entries.first)
    #expect(entry.version == "0.5.0")
    #expect(entry.title == nil)
    #expect(entry.items == [
        "Intro paragraph.", "First list item", "Loose list item", "Closing paragraph.",
    ])
}
