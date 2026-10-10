import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three releases of Learn's Edge Stable/Extended Stable release notes
/// (`microsoft-edge-relnote-stable-channel`), fetched 2026-10-10, in page order
/// but not contiguous: the 155 main release, a 152 Extended Stable update, and a
/// 152 Stable update, then the "See also" heading that follows the last release.
/// `class` and `data-*` attributes are elided; the rest is verbatim.
private let edgeStableFixture = #"""
<h2 id="version-1550428345-october-08-2026-stable---main-release-">Version 155.0.4283.45: October 08, 2026 (Stable) - Main Release <a id="version-1550428345-october-08-2026-stable"></a></h2>
<h3 id="release-summary">Release Summary</h3>
<table>
<thead>
<tr>
<th>Category</th>
<th>Description</th>
</tr>
</thead>
<tbody>
<tr>
<td><a href="#announcements">Announcements</a></td>
<td>Announcements about sign-in migration, Copilot URL redirects, and unload changes in Microsoft Edge.</td>
</tr>
<tr>
<td><a href="#feature-updates">Feature Updates</a></td>
<td>Updates to tab organization, video translation, and network access policies in Microsoft Edge.</td>
</tr>
<tr>
<td><a href="#fixes">Fixes</a></td>
<td>Fixes in this release of Microsoft Edge.</td>
</tr>
<tr>
<td><a href="#policy-updates">Policy Updates</a></td>
<td>New and updated policies in Microsoft Edge.</td>
</tr>
<tr>
<td>Security</td>
<td>Stable channel security updates are listed <a href="/en-us/deployedge/microsoft-edge-relnotes-security#october-08-2026">here</a>.</td>
</tr>
</tbody>
</table>
<h3 id="announcements">Announcements</h3>
<ul>
<li><p><strong>Deprecating the 'unload' event</strong>. Microsoft Edge is changing the default behavior of the web platform 'unload' event. As the rollout progresses, pages will no longer run 'unload' event handlers unless the site explicitly permits them.</p>
<ul>
<li><p>In Edge 152 and 153, unload handlers will stop firing by default for 60% of page loads unless the site explicitly enables them through Permissions Policy.</p>
</li>
<li><p>In Edge 154, the rollout will increase to 80% of page loads.</p>
</li>
<li><p>In Edge 155, the rollout will reach 100% of page loads.</p>
</li>
</ul>
<p>The 'unload' event is not a dependable way to save data, perform cleanup, or report the end of a session. Browsers and operating systems can suspend or terminate pages without firing it, and this can prevent pages from using the back/forward cache, which may make back and forward navigation slower.</p>
<p>Web developers should migrate to lifecycle events and APIs designed for these scenarios. The long-term direction of the web platform is to remove support for unload.</p>
</li>
<li><p><strong>Retiring legacy sign-in implementation on Windows</strong>. Microsoft Edge plans to retire its legacy direct-WAM sign-in implementation on Windows in version 157, completing the transition to OneAuth. OneAuth continues to use Windows Web Account Manager (WAM) internally; WAM itself is not being deprecated.</p>
<p>The vast majority of users have already transitioned automatically with no interruption. For remaining profiles that have not yet migrated, the transition will complete upon updating to version 157. In rare cases, some users may need to sign in to Microsoft Edge again.</p>
<p><strong>Action recommended for administrators:</strong></p>
<ul>
<li><p>Check <code>edge://signin-internals</code> under Edge Auth Library Information → Library to see if any managed profiles still show WAM.</p>
</li>
<li><p>Organizations wishing to validate early or test profiles that previously disabled the transition can launch <code>msedge.exe --enable-features=msForceOneAuthWAM</code> after closing all Microsoft Edge processes, including background processes, as the flag won’t take effect if Microsoft Edge is already running.</p>
</li>
<li><p>Report any sign-in issues to Microsoft Support prior to the Microsoft Edge 157 release.</p>
</li>
</ul>
</li>
</ul>
<h3 id="feature-updates">Feature Updates</h3>
<ul>
<li><p><strong>Tab organization enhancements</strong>. Microsoft Edge is expanding tab and Workspace organization capabilities to suggest groupings, names, visuals, and labels. Users can manage these experiences through the "Let Microsoft Edge help keep your tabs organized" setting under <code>edge://settings/privacy/services</code>; administrators can control them using the <a href="/en-us/deployedge/microsoft-edge-policies/tabservicesenabled">TabServicesEnabled</a> policy.</p>
</li>
<li><p><strong>Real-time video translation retirement</strong>. Real-time video translation has been retired. The <a href="/en-us/deployedge/microsoft-edge-policies/livevideotranslationenabled">LiveVideoTranslationEnabled</a> policy will be deprecated in a future update.</p>
</li>
<li><p><strong>Update for LocalNetworkAccessRestrictionsTemporaryOptOut policy</strong>. The planned removal of the <a href="/en-us/deployedge/microsoft-edge-policies/localnetworkaccessrestrictionstemporaryoptout">LocalNetworkAccessRestrictionsTemporaryOptOut</a> policy has been updated. The policy is now scheduled for removal after Microsoft Edge version 163, previously it was version 156.</p>
</li>
</ul>
<h3 id="fixes">Fixes</h3>
<ul>
<li>Fixed an issue which caused search engines configured through recommended <a href="/en-us/deployedge/microsoft-edge-policies#default-search-provider">default search provider policies</a> to become invalid after Microsoft Edge ran for a short period of time. When this occurred, address bar searches stopped working.</li>
</ul>
<h3 id="policy-updates">Policy Updates</h3>
<h4 id="deprecated-policies">Deprecated policies</h4>
<ul>
<li><strong><a href="/en-us/deployedge/microsoft-edge-policies/oneauthauthenticationenforced">OneAuthAuthenticationEnforced</a></strong> - OneAuth Authentication Flow Enforced for signin (deprecated)</li>
</ul>
<div>
<p>Note</p>
<p>For the latest web platform features and updates, see the <a href="/en-us/microsoft-edge/web-platform/release-notes/155">Microsoft Edge 155 web platform release notes (Oct. 8, 2026)</a>.</p>
</div>
<hr>
<p><a href="#microsoft-edge-release-notes-for-stable-and-extended-stable-channels">Back to top</a></p>
<hr>
<h2 id="version-15204191122-october-08-2026-extended-stable---update-9-">Version 152.0.4191.122: October 08, 2026 (Extended Stable) - Update 9 <a id="version-15204191122-october-08-2026-extended-stable"></a></h2>
<h3 id="release-summary-2">Release Summary</h3>
<table>
<thead>
<tr>
<th>Category</th>
<th>Description</th>
</tr>
</thead>
<tbody>
<tr>
<td>Fixes</td>
<td>Fixed various bugs and performance issues.</td>
</tr>
</tbody>
</table>
<h2 id="version-1520419162-september-02-2026-stable---update-1-">Version 152.0.4191.62: September 02, 2026 (Stable) - Update 1 <a id="version-1520419162-september-02-2026-stable"></a></h2>
<h3 id="release-summary-10">Release Summary</h3>
<table>
<thead>
<tr>
<th>Category</th>
<th>Description</th>
</tr>
</thead>
<tbody>
<tr>
<td>Fixes</td>
<td>Fixed various bugs and performance issues.</td>
</tr>
<tr>
<td>Security</td>
<td>Stable channel security updates are listed <a href="/en-us/deployedge/microsoft-edge-relnotes-security#september-2-2026">here</a>.</td>
</tr>
</tbody>
</table>
<hr>
<p><a href="#microsoft-edge-release-notes-for-stable-and-extended-stable-channels">Back to top</a></p>
<hr>
<h2 id="see-also">See also</h2>
"""#

/// Four consecutive releases of the Beta page
/// (`microsoft-edge-relnote-beta-channel`), fetched 2026-10-10, byte for byte,
/// and the heading of the fifth, which is what ends the fourth.
private let edgeBetaFixture = #"""
<h2 id="version-1550428339-october-5-2026">Version 155.0.4283.39: October 5, 2026</h2>
<p>Fixed various bugs and performance issues.</p>
<h2 id="version-1550428333-october-2-2026">Version 155.0.4283.33: October 2, 2026</h2>
<p>Fixed various bugs and performance issues.</p>
<h2 id="version-1550428324-september-28-2026">Version 155.0.4283.24: September 28, 2026</h2>
<p>Fixed various bugs and performance issues.</p>
<h2 id="version-1550428318-september-25-2026">Version 155.0.4283.18: September 25, 2026</h2>
<p>Fixed various bugs and performance issues.</p>
<div class="NOTE">
<p>Note</p>
<p>For the latest web platform features and updates, see the <a href="/en-us/microsoft-edge/web-platform/release-notes/155" data-linktype="absolute-path">Microsoft Edge 155 web platform release notes (Oct. 8, 2026) - Microsoft Edge Developer documentation | Microsoft Learn</a></p>
</div>

<h2 id="version-1550428313-september-23-2026">Version 155.0.4283.13: September 23, 2026</h2>
"""#

@Test func edgeStableReadsOnlyStableLabelledReleases() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.edgemac"),
        "Edge Stable changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: edgeStableFixture, using: recipe))

    // The Extended Stable update between them is another train's.
    #expect(log.entries.map(\.version) == ["155.0.4283.45", "152.0.4191.62"])
    #expect(log.entries.map(\.date) == ["October 08, 2026", "September 02, 2026"])

    let main = log.entries[0]
    // A parent line and each nested sub-point are separate lines.
    #expect(main.items.first == "Deprecating the 'unload' event. Microsoft Edge is changing the default behavior of the "
        + "web platform 'unload' event. As the rollout progresses, pages will no longer run 'unload' event handlers "
        + "unless the site explicitly permits them.")
    #expect(main.items[1] == "In Edge 152 and 153, unload handlers will stop firing by default for 60% of page loads "
        + "unless the site explicitly enables them through Permissions Policy.")
    #expect(main.items.last
        == "OneAuthAuthenticationEnforced - OneAuth Authentication Flow Enforced for signin (deprecated)")
    #expect(!main.items.contains { $0.contains("Back to top") })
    let headings = main.content.compactMap { block -> String? in
        if case .heading(let text) = block { return text } else { return nil }
    }
    #expect(headings == ["Announcements", "Feature Updates", "Fixes", "Policy Updates", "Deprecated policies"])

    // A minor update has no list: its summary table's descriptions are the notes.
    #expect(log.entries[1].items == [
        "Fixed various bugs and performance issues.", "Stable channel security updates are listed here.",
    ])
}

@Test func edgeBetaReadsEveryReleaseHeading() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.edgemac.Beta"),
        "Edge Beta changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: edgeBetaFixture, using: recipe))

    #expect(log.entries.map(\.version)
        == ["155.0.4283.39", "155.0.4283.33", "155.0.4283.24", "155.0.4283.18"])
    #expect(log.entries.first?.date == "October 5, 2026")
    #expect(log.entries[0].items == ["Fixed various bugs and performance issues."])
    // The note box's bare "Note" label is not a line; its text is.
    let last = try #require(log.entries.last).items
    #expect(last.count == 2)
    #expect(!last.contains("Note"))
    #expect(last[1].hasPrefix("For the latest web platform features and updates"))
}
