import Testing
import Foundation
@testable import DuoUpdaterCore

// Blender publishes one notes page per minor at
// `developer.blender.org/docs/release_notes/<major.minor>/`. The three fixtures
// are the `<h1>` … `</article>` slice of the live 5.1, 5.2 and 5.3 pages, byte for
// byte except that the run of whitespace-only lines before `</article>` is
// collapsed. They are the three shapes the recipe has to tell apart:
//
//   - 5.1, a regular release: "Blender 5.1 Release Notes", a
//     "Corrective Releases" `<h2>` after the bugfix list;
//   - 5.2, an LTS release: "LTS" in the `<h1>` AND in the "was released on"
//     sentence, and no corrective-releases `<h2>` at all;
//   - 5.3, in development: "is currently in Alpha", which must parse to nothing.

private let blender51Page = #"""
<h1 id="blender-51-release-notes">Blender 5.1 Release Notes<a class="headerlink" href="#blender-51-release-notes" title="Permanent link">&para;</a></h1>
<p>Blender 5.1 was released on March 17, 2026.</p>
<p>Check out out the final <a href="https://www.blender.org/download/releases/5-1/">release notes on
blender.org</a>.</p>
<p><a href="https://www.blender.org/news/remembering-germano-cavalcante/">In memory of Germano Cavalcante</a>.</p>
<ul>
<li><a href="animation_rigging/">Animation &amp; Rigging</a></li>
<li><a href="assets/">Assets</a></li>
<li><a href="compositor/">Compositor</a></li>
<li><a href="core/">Core</a></li>
<li><a href="cycles/">Cycles</a></li>
<li><a href="eevee/">EEVEE &amp; Viewport</a></li>
<li><a href="geometry_nodes/">Geometry Nodes</a></li>
<li><a href="grease_pencil/">Grease Pencil</a></li>
<li><a href="modeling/">Modeling &amp; UV</a></li>
<li><a href="motion_tracking/">Motion Tracking</a></li>
<li><a href="pipeline_io/">Pipeline &amp; I/O</a></li>
<li><a href="python_api/">Python API</a></li>
<li><a href="rendering/">Rendering</a></li>
<li><a href="sculpt/">Sculpt, Paint, Texture</a></li>
<li><a href="user_interface/">User Interface</a></li>
<li><a href="sequencer/">Video Sequencer</a></li>
<li><a href="virtual_reality/">Virtual Reality</a></li>
</ul>
<h2 id="compatibility">Compatibility<a class="headerlink" href="#compatibility" title="Permanent link">&para;</a></h2>
<ul>
<li>Libraries have been upgraded to match <a href="https://vfxplatform.com/">VFX platform 2026</a>, including:<ul>
<li>Python 3.13</li>
<li>OpenColorIO 2.5</li>
<li>OpenEXR 3.4</li>
<li>OpenVDB 13.0</li>
</ul>
</li>
</ul>
<ul>
<li>Node Tools now have a global unique idname requirement. This can be set automatically by opening and saving files in 5.1, or chosen manually in the node editor header.</li>
<li>Grease Pencil fills have been revamped. Blend-files are automatically converted to the new system but some procedural setups using Geometry Nodes and Grease Pencil materials might need manual adjustments. See the <a href="grease_pencil/#compatibility">Grease Pencil section</a> for more details.</li>
</ul>
<h2 id="bugfixes">Bugfixes<a class="headerlink" href="#bugfixes" title="Permanent link">&para;</a></h2>
<ul>
<li><a href="bugfixes/">Fixes for issues present in previous versions</a></li>
</ul>
<h2 id="corrective-releases"><a href="corrective_releases/">Corrective Releases</a><a class="headerlink" href="#corrective-releases" title="Permanent link">&para;</a></h2>
</article>
"""#

private let blender52LTSPage = #"""
<h1 id="blender-52-lts-release-notes">Blender 5.2 LTS Release Notes<a class="headerlink" href="#blender-52-lts-release-notes" title="Permanent link">&para;</a></h1>
<p>Blender 5.2 LTS was released on July 14, 2026.</p>
<p>Check out out the final <a href="https://www.blender.org/download/releases/5-2/">release notes on
blender.org</a>.</p>
<p>This release includes long-term support and will be maintained until July 2028, see the <a href="https://www.blender.org/download/lts/5-2/">LTS
page</a> for a list of bugfixes
included in the latest version.</p>
<ul>
<li><a href="animation_rigging/">Animation &amp; Rigging</a></li>
<li><a href="assets/">Assets</a></li>
<li><a href="compositor/">Compositor</a></li>
<li><a href="core/">Core</a></li>
<li><a href="cycles/">Cycles</a></li>
<li><a href="eevee/">EEVEE &amp; Viewport</a></li>
<li><a href="geometry_nodes/">Geometry Nodes</a></li>
<li><a href="grease_pencil/">Grease Pencil</a></li>
<li><a href="modeling/">Modeling &amp; UV</a></li>
<li><a href="motion_tracking/">Motion Tracking</a></li>
<li><a href="physics/">Physics</a></li>
<li><a href="pipeline_io/">Pipeline &amp; I/O</a></li>
<li><a href="python_api/">Python API</a></li>
<li><a href="rendering/">Rendering</a></li>
<li><a href="sculpt/">Sculpt, Paint, Texture</a></li>
<li><a href="user_interface/">User Interface</a></li>
<li><a href="sequencer/">Video Sequencer</a></li>
<li><a href="virtual_reality/">Virtual Reality</a></li>
</ul>
<h2 id="compatibility">Compatibility<a class="headerlink" href="#compatibility" title="Permanent link">&para;</a></h2>
<ul>
<li>Evaluated meshes created from scratch in Geometry Nodes will no longer end up with the same name as the object's original mesh (<a href="https://projects.blender.org/blender/blender/commit/5e1e4de9d95d">5e1e4de9d9</a>).</li>
<li>The python API for <code>paint.eraser_brush</code> and <code>paint.eraser_brush_asset_reference</code> is removed as it is no longer used (<a href="https://projects.blender.org/blender/blender/commit/8c22be8d89ec2aabcb16c153ba3aae2a816a521c">8c22be8d89</a>).</li>
<li>The Python API for accessing Geometry Nodes modifier properties has changed. For more information, see the Python API release notes (<a href="https://projects.blender.org/blender/blender/commit/1561c1ea4ab6">1561c1ea4a</a>).</li>
<li>Similar to 5.1, asset files with Geometry Nodes tools must be re-saved to be used properly in 5.2 (<a href="https://projects.blender.org/blender/blender/commit/1561c1ea4ab6">1561c1ea4a</a>).</li>
<li>Socket identifiers for the Compare and Random Value node changed (<a href="https://projects.blender.org/blender/blender/commit/3a5cd7862bc1422188cdc7e6fb9ac3209077f479">3a5cd7862b</a>).</li>
</ul>
<h2 id="bugfixes">Bugfixes<a class="headerlink" href="#bugfixes" title="Permanent link">&para;</a></h2>
<ul>
<li><a href="bugfixes/">Fixes for issues present in previous versions</a></li>
</ul>
</article>
"""#

private let blender53AlphaPage = #"""
<h1 id="blender-53-release-notes">Blender 5.3 Release Notes<a class="headerlink" href="#blender-53-release-notes" title="Permanent link">&para;</a></h1>
<p>Blender 5.3 is currently in <strong>Alpha</strong> until September 30, 2026.
<a href="https://projects.blender.org/blender/blender/milestone/34">See schedule</a>.</p>
<p>Under development in <a href="https://projects.blender.org/blender/blender/src/branch/main"><code>main</code></a>.</p>
<ul>
<li><a href="animation_rigging/">Animation &amp; Rigging</a></li>
<li><a href="assets/">Assets</a></li>
<li><a href="compositor/">Compositor</a></li>
<li><a href="core/">Core</a></li>
<li><a href="cycles/">Cycles</a></li>
<li><a href="eevee/">EEVEE &amp; Viewport</a></li>
<li><a href="geometry_nodes/">Geometry Nodes</a></li>
<li><a href="grease_pencil/">Grease Pencil</a></li>
<li><a href="modeling/">Modeling &amp; UV</a></li>
<li><a href="motion_tracking/">Motion Tracking</a></li>
<li><a href="physics/">Physics</a></li>
<li><a href="pipeline_io/">Pipeline &amp; I/O</a></li>
<li><a href="python_api/">Python API</a></li>
<li><a href="rendering/">Rendering</a></li>
<li><a href="sculpt/">Sculpt, Paint, Texture</a></li>
<li><a href="user_interface/">User Interface</a></li>
<li><a href="sequencer/">Video Sequencer</a></li>
<li><a href="virtual_reality/">Virtual Reality</a></li>
</ul>
<h2 id="compatibility">Compatibility<a class="headerlink" href="#compatibility" title="Permanent link">&para;</a></h2>
<ul>
<li><code>gpu.types.GPUBatch.draw_instanced</code> prefers to use <code>gpu_InstanceIndex</code> which has the <code>base_instance</code> baked in. This for better alignment how Metal/Vulkan internally works. (<a href="https://projects.blender.org/blender/blender/commit/6f646327165e702e12d4a32e72d8e700fb238dc2">6f64632716</a>)</li>
</ul>
</article>
"""#

@Suite struct BlenderChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.blenderfoundation.blender"))
    }

    /// Mutation: pin `source` to one minor and drop `sourceTemplate` (the recipe
    /// as it was) — every install then reads that minor's page, whatever it runs.
    @Test func thePageFollowsTheTargetMinor() throws {
        let recipe = try self.recipe()
        #expect(recipe.resolvedSource(forVersion: "5.2.1").absoluteString
            == "https://developer.blender.org/docs/release_notes/5.2/")
        #expect(recipe.resolvedSource(forVersion: "5.1.2").absoluteString
            == "https://developer.blender.org/docs/release_notes/5.1/")
        #expect(recipe.resolvedSource(forVersion: "4.5.3").absoluteString
            == "https://developer.blender.org/docs/release_notes/4.5/")
        #expect(recipe.resolvedSource(forVersion: "5.2").absoluteString
            == "https://developer.blender.org/docs/release_notes/5.2/")
        // No version to work from: the fixed `source`, which is itself a real page.
        #expect(recipe.resolvedSource(forVersion: nil) == recipe.source)
    }

    /// The regular (non-LTS) shape must keep parsing beside the LTS one.
    ///
    /// Mutation: make `LTS` required instead of optional in both halves — this
    /// goes to nil. (Which of the two stops ends the body is not observable here:
    /// nothing after the corrective-releases `<h2>` is an `<li>`.)
    @Test func aRegularReleaseParses() throws {
        let log = try #require(ChangelogExtractor.extract(from: blender51Page, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "5.1")
        #expect(entry.date == "March 17, 2026")
        #expect(entry.items.count == 24)
        #expect(entry.items.first == "Animation & Rigging")   // &amp; decoded
        #expect(entry.items.last == "Fixes for issues present in previous versions")
        #expect(!entry.items.contains("Physics"))   // a 5.2-only module
    }

    /// Mutation: take `(?:\s+LTS)?` out of either the `<h1>` or the
    /// "was released on" half, or drop the `</article>` stop — each alone gives nil.
    @Test func anLTSReleaseWithNoCorrectiveReleasesParses() throws {
        let log = try #require(ChangelogExtractor.extract(from: blender52LTSPage, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "5.2")   // not "5.2 LTS"
        #expect(entry.date == "July 14, 2026")
        #expect(entry.items.count == 24)
        #expect(entry.items.contains("Physics"))
        #expect(entry.items.last == "Fixes for issues present in previous versions")
    }

    /// A daily/alpha build shares the bundle id, so its version can resolve to an
    /// in-development page. "is currently in Alpha" must not match: zero entries
    /// sends the pane to the embedded page instead of a half-written changelog.
    ///
    /// Mutation: loosen "was released on" to any `<p>` — this parses to an entry.
    @Test func anInDevelopmentPageParsesToNothing() throws {
        #expect(ChangelogExtractor.extract(from: blender53AlphaPage, using: try recipe()) == nil)
    }
}
