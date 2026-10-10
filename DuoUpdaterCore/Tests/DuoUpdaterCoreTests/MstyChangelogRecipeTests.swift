import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two slices of `msty.ai/resources/changelog/studio/`, fetched 2026-10-10, byte
/// for byte: 3.0.0 Beta 13, 2.9.11, 3.0.0 Beta 12 and 2.9.10 as they interleave at
/// the top of the page, then 2.1.0, one of the two stable ids written with a stray
/// trailing dot (`msty-2.1.0.`).
private let mstyChangelogFixture = #"""
<h2 id="msty-3.0.0-beta.13">Amazon Bedrock API keys and Anthropic provider fixes<a href="#msty-3.0.0-beta.13" class="copy-link" title="Copy link">🔗</a></h2>
<p><small>2026-09-15</small><br>
<small><strong>Msty Studio 3.0.0 Beta 13</strong></small></p>
<p>Msty Studio 3.0 Beta 13 expands Amazon Bedrock authentication options and fixes an Anthropic provider error.</p>
<h3 id="features-2">Features</h3>
<ul>
<li>Added API-key authentication for Amazon Bedrock alongside AWS credentials</li>
</ul>
<h3 id="fixes-2">Fixes</h3>
<ul>
<li>Fixed an Anthropic provider error</li>
</ul>
<hr>
<h2 id="msty-2.9.11">Amazon Bedrock API keys and Anthropic provider fixes<a href="#msty-2.9.11" class="copy-link" title="Copy link">🔗</a></h2>
<p><small>2026-09-15</small><br>
<small><strong>Msty Studio 2.9.11</strong></small></p>
<p>Msty Studio 2.9.11 expands Amazon Bedrock authentication options and fixes an Anthropic provider error.</p>
<h3 id="features-3">Features</h3>
<ul>
<li>Added API-key authentication for Amazon Bedrock alongside AWS credentials</li>
</ul>
<h3 id="fixes-3">Fixes</h3>
<ul>
<li>Fixed an Anthropic provider error</li>
</ul>
<hr>
<h2 id="msty-3.0.0-beta.12">MCP OAuth feedback, model reasoning, and Studio workflow refinements<a href="#msty-3.0.0-beta.12" class="copy-link" title="Copy link">🔗</a></h2>
<p><small>2026-09-13</small><br>
<small><strong>Msty Studio 3.0.0 Beta 12</strong></small></p>
<p>Msty Studio 3.0 Beta 12 improves MCP setup feedback, model reasoning controls, folder workflows, localization, and Context Studio search.</p>
<h3 id="features-4">Features</h3>
<ul>
<li>Added Llama.cpp CUDA support on Windows ARM64</li>
</ul>
<h3 id="enhancements">Enhancements</h3>
<ul>
<li>Improved MCP OAuth authorization status and feedback</li>
<li>Improved supported thinking-effort controls and model reasoning capabilities</li>
<li>Improved Studio folder workflows, Context Studio search, and localized UI fallbacks</li>
</ul>
<h3 id="fixes-4">Fixes</h3>
<ul>
<li>Improved compatibility with MCP tools in Claude</li>
<li>Added security fixes for imported content</li>
</ul>
<hr>
<h2 id="msty-2.9.10">Claude MCP compatibility and imported-content stability<a href="#msty-2.9.10" class="copy-link" title="Copy link">🔗</a></h2>
<p><small>2026-09-13</small><br>
<small><strong>Msty Studio 2.9.10</strong></small></p>
<p>Msty Studio 2.9.10 improves compatibility with MCP tools in Claude and includes security fixes for imported content.</p>
<h3 id="fixes-5">Fixes</h3>
<ul>
<li>Added support for MCP tools that use top-level union input schemas in Claude</li>
<li>Added security fixes for imported content across the interface</li>
</ul>
<hr>
<h2 id="msty-2.1.0.">Llama.cpp, Shadow Persona, and more!<a href="#msty-2.1.0." class="copy-link" title="Copy link">🔗</a></h2>
<p><small>2025-11-24</small><br>
<small><strong>Msty Studio 2.1.0.</strong></small></p>
<p>Msty Studio 2.1.0 is jam-packed with new features and enhancements, including support for Llama.cpp as a local inference engine and a new conversation assistant that we call Shadow Persona.</p>
<p>Check out this video to see an overview of the new features.</p>
<div class="video-embed"><iframe src="https://www.youtube.com/embed/dOeF5JUvJBs" title="Msty Studio Changelog video" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></div>
<p>Watch this video for instructions on how to setup a new Shadow Persona and to see 5 powerful ways that Shadow Personas can help enrich your experience.</p>
<div class="video-embed"><iframe src="https://www.youtube.com/embed/MCx0DYnyi1A" title="Msty Studio Changelog video" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></div>
<h3 id="features-24">Features</h3>
<ul>
<li>Llama.cpp is now supported as a local inference engine, bringing additional flexibility and powerful options for running local models</li>
<li>Shadow Personas (Aurum) observe the main conversations and provide their own responses away from the main conversation. They can help you analyze outputs from multiple split chats, synthesize the results to form an optimal response, leverage Knowledge Stacks, toolbox, and real-time data, and more, to perform various tasks and act as the ultimate conversation companion.</li>
<li>Workspace lock and secrets encryption is an experimental feature that lets you lock your workspace with a passphrase, adding more privacy and protection</li>
<li>Auto-archive old conversations to get them out of view - view the Archive folder to view archived conversations</li>
<li>Lost &amp; Found scans for orphaned Workspaces that you can re-import into Msty Studio</li>
<li>Project &amp; conversation sort, order, and display settings allow you to better customize the project folders tree</li>
<li>Model list selection sort order is also available with similar options to the above</li>
</ul>
<h3 id="enhancements-24">Enhancements</h3>
<ul>
<li>Language support for UK English 🇬🇧, Spanish 🇪🇸, and Russian 🇷🇺</li>
<li>Model fuzzy search helps you find models quickly when adding new models from a provider or when selecting a model for a convo</li>
<li>MLX remote access improvements</li>
</ul>
<h3 id="fixes-41">Fixes</h3>
<ul>
<li>Not being able to drag and drop convos to another folder</li>
<li>MLX popover not displaying text in Model Hub &gt; MLX</li>
<li>Fixed Google and Brave RTD options (though, looks like Google released a breaking change as we pushed the fix… 😢)</li>
<li>Fixed project folders not including project titles and descriptions when include project context switch is enabled</li>
</ul>
<hr>

"""#

@Test func mstyReadsStableReleasesAndSkipsTheBetaTrain() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "MstyStudio"),
        "Msty Studio changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: mstyChangelogFixture, using: recipe))

    // The beta blocks share the page and even the notes, but not the train.
    #expect(log.entries.map(\.version) == ["2.9.11", "2.9.10", "2.1.0"])
    #expect(log.entries.map(\.date) == ["2026-09-15", "2026-09-13", "2025-11-24"])
    #expect(log.entries[0].items == [
        "Added API-key authentication for Amazon Bedrock alongside AWS credentials",
        "Fixed an Anthropic provider error",
    ])
    // Category headings render as headings, not as notes.
    let headings = log.entries[0].content.compactMap { block -> String? in
        if case .heading(let text) = block { return text } else { return nil }
    }
    #expect(headings == ["Features", "Fixes"])
    // Entities decode inside a list line.
    #expect(log.entries[2].items.contains(
        "Lost & Found scans for orphaned Workspaces that you can re-import into Msty Studio"))
}
