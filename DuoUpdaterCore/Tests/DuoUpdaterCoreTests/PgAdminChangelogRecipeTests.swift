import Testing
import Foundation
@testable import DuoUpdaterCore

// pgAdmin 4 — two-stage. The index fixture is six lines of the real
// `docs/pgadmin4/latest/release_notes.html` sidebar toctree: two ordinary docs
// links, the current-page item, then the newest three release links. The page
// fixture is the real `release_notes_9_18.html` from its version `<section>`
// to Sphinx's `<div class="clearer">`, verbatim except that each list keeps
// only its first two rows (the live page has 92).
private let pgAdminIndex = #"""
<li class="toctree-l1"><a class="reference internal" href="pgagent.html">pgAgent</a></li>
<li class="toctree-l1"><a class="reference internal" href="contributions.html">pgAdmin Project Contributions</a></li>
<li class="toctree-l1 current"><a class="current reference internal" href="#">Release Notes</a><ul>
<li class="toctree-l2"><a class="reference internal" href="release_notes_9_18.html">Version 9.18</a></li>
<li class="toctree-l2"><a class="reference internal" href="release_notes_9_17.html">Version 9.17</a></li>
<li class="toctree-l2"><a class="reference internal" href="release_notes_9_16.html">Version 9.16</a></li>
"""#

private let pgAdmin918Page = #"""
<section id="version-9-18">
<h1>Version 9.18<a class="headerlink" href="#version-9-18" title="Link to this heading">&para;</a></h1>
<p>Release date: 2026-09-17</p>
<p>This release contains a number of bug fixes and new features since the release of pgAdmin 4 v9.17.</p>
<section id="supported-database-servers">
<h2>Supported Database Servers<a class="headerlink" href="#supported-database-servers" title="Link to this heading">&para;</a></h2>
<p><strong>PostgreSQL</strong>: 14, 15, 16, 17 and 18</p>
<p><strong>EDB Advanced Server</strong>: 14, 15, 16, 17 and 18</p>
</section>
<section id="bundled-postgresql-utilities">
<h2>Bundled PostgreSQL Utilities<a class="headerlink" href="#bundled-postgresql-utilities" title="Link to this heading">&para;</a></h2>
<p><strong>psql</strong>, <strong>pg_dump</strong>, <strong>pg_dumpall</strong>, <strong>pg_restore</strong>: 18.4</p>
</section>
<section id="new-features">
<h2>New features<a class="headerlink" href="#new-features" title="Link to this heading">&para;</a></h2>
<blockquote>
<div><div class="line-block">
<div class="line"><a class="reference external" href="https://github.com/pgadmin-org/pgadmin4/issues/9631">Issue #9631</a> -  Collapse and restore the Object Explorer by re-clicking the current workspace icon, in the manner of the VS Code side bar, remembering the choice across refreshes. A keyboard shortcut, Ctrl+Alt+B by default, does the same thing and can be changed through the new <code class="docutils literal notranslate"><span class="pre">toggle_object_explorer</span></code> preference.</div>
</div>
</div></blockquote>
</section>
<section id="housekeeping">
<h2>Housekeeping<a class="headerlink" href="#housekeeping" title="Link to this heading">&para;</a></h2>
<blockquote>
<div><div class="line-block">
<div class="line"><a class="reference external" href="https://github.com/pgadmin-org/pgadmin4/issues/10221">Issue #10221</a> -  Skip importing and initialising the kerberos, ldap, mfa, oauth2 and webserver authentication providers unless <code class="docutils literal notranslate"><span class="pre">SERVER_MODE</span></code> is set, leaving desktop mode with internal authentication alone.</div>
<div class="line"><a class="reference external" href="https://github.com/pgadmin-org/pgadmin4/issues/10247">Issue #10247</a> -  Relax the <code class="docutils literal notranslate"><span class="pre">azure-mgmt-resource</span></code> pin to allow 24.0.0, and aggregate the third-party JavaScript and Python dependency bumps for this release.</div>
</div>
</div></blockquote>
</section>
<section id="bug-fixes">
<h2>Bug fixes<a class="headerlink" href="#bug-fixes" title="Link to this heading">&para;</a></h2>
<blockquote>
<div><div class="line-block">
<div class="line"><a class="reference external" href="https://github.com/pgadmin-org/pgadmin4/issues/9226">Issue #9226</a> -  Accept <code class="docutils literal notranslate"><span class="pre">SharedUsername</span></code> when importing a shared server from a servers.json definition, instead of insisting on <code class="docutils literal notranslate"><span class="pre">Username</span></code> for every server.</div>
<div class="line"><a class="reference external" href="https://github.com/pgadmin-org/pgadmin4/issues/10155">Issue #10155</a> -  Share concurrent identical GET requests behind <code class="docutils literal notranslate"><span class="pre">getNodeAjaxOptions()</span></code> so a wide table&rsquo;s Columns tab no longer fires one duplicate <code class="docutils literal notranslate"><span class="pre">get_types</span></code> request per column row.</div>
</div>
</div></blockquote>
</section>
<section id="dependencies">
<h2>Dependencies<a class="headerlink" href="#dependencies" title="Link to this heading">&para;</a></h2>
<p>Non-breaking <code class="docutils literal notranslate"><span class="pre">dependabot</span></code> and audit-driven bumps aggregated for v9.18.</p>
<p>Python:</p>
<blockquote>
<div><div class="line-block">
<div class="line"><code class="docutils literal notranslate"><span class="pre">Authlib</span></code> 1.7.* -&gt; 1.8.*</div>
<div class="line"><code class="docutils literal notranslate"><span class="pre">azure-mgmt-resource</span></code> ==25.0.0 -&gt; &gt;=24.0.0,&lt;26.0.0</div>
</div>
</div></blockquote>
<p>JavaScript (<code class="docutils literal notranslate"><span class="pre">web/</span></code>):</p>
<blockquote>
<div><div class="line-block">
<div class="line"><code class="docutils literal notranslate"><span class="pre">@babel/*</span></code> toolchain (core, eslint-parser, eslint-plugin, plugin-syntax-jsx, plugin-transform-class-properties, plugin-transform-object-rest-spread, plugin-transform-runtime, preset-env, preset-react, preset-typescript) -&gt; 7.29.7</div>
<div class="line"><code class="docutils literal notranslate"><span class="pre">@mui/icons-material</span></code> / <code class="docutils literal notranslate"><span class="pre">@mui/material</span></code> 7.3.10 -&gt; 7.3.11</div>
</div>
</div></blockquote>
<p>JavaScript (<code class="docutils literal notranslate"><span class="pre">runtime/</span></code>):</p>
<blockquote>
<div><div class="line-block">
<div class="line"><code class="docutils literal notranslate"><span class="pre">axios</span></code> 1.18.1 -&gt; 1.19.0</div>
<div class="line"><code class="docutils literal notranslate"><span class="pre">electron</span></code> 43.1.1 -&gt; 43.4.0</div>
</div>
</div></blockquote>
</section>
</section>
<div class="clearer"></div>
"""#

@Test func pgAdminFollowsNewestReleaseNotesLink() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.pgadmin.pgadmin4"))
    let pattern = try #require(recipe.indexLinkPattern)
    let url = ChangelogService.firstLink(in: pgAdminIndex, pattern: pattern, base: recipe.source)
    #expect(url?.absoluteString
        == "https://www.pgadmin.org/docs/pgadmin4/latest/release_notes_9_18.html")
}

@Test func pgAdminReleaseNotesPageParses() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.pgadmin.pgadmin4"))
    let log = try #require(ChangelogExtractor.extract(from: pgAdmin918Page, using: recipe))
    #expect(log.entries.count == 1)
    let entry = try #require(log.entries.first)
    #expect(entry.version == "9.18")
    #expect(entry.date == "2026-09-17")
    #expect(entry.items.count == 11)
    // Entities decoded, tags stripped.
    #expect(entry.items.contains(
        "Issue #10155 - Share concurrent identical GET requests behind getNodeAjaxOptions() so a wide "
            + "table’s Columns tab no longer fires one duplicate get_types request per column row."))
    // Only sections that hold rows become headings: the two plain-paragraph
    // sections above them add none.
    let headings = entry.content.compactMap { block -> String? in
        if case .heading(let text) = block { return text }
        return nil
    }
    #expect(headings == ["New features", "Housekeeping", "Bug fixes", "Dependencies"])
}
