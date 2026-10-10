import Testing
import Foundation
@testable import DuoUpdaterCore

/// `bombich.com/software/updates/ccc7_rn.html` as served 2026-10-10, trimmed to
/// the 7.2.1 entry (no date in its summary) and the 7.2 entry (prose paragraphs
/// under an `<h2>`, then a list), two lines each.
private let ccc7StableFixture = #"""
	<details open id="primary">
	    <summary><a name="7.2.1"></a>CCC 7.2.1 &mdash; This is a FREE update for CCC 7 license holders</span></summary>
		<ul>
			<li>
				<span class="icon"><div class="type Improved">Improved</div></span>
				<span class="description"><p>Corrected an oversight that caused the "Repeat affected tasks on login" setting to be enabled by default. That setting will be actively disabled for anyone updating from CCC 7.2 (builds 8399 or 8401). If you want that setting to be enabled, re-enable it after applying the update in CCC Settings &gt; Advanced.</p></span>
			</li>
			<li>
				<span class="icon"><div class="type Fixed">Fixed</div></span>
				<span class="description"><p>Fixed a logic issue that was preventing the export of an ad hoc verification report.</p></span>
			</li>
		</ul>
	</details>


	<details>
	    <summary><a name="7.2"></a>CCC 7.2: September 13, 2026</span></summary>
		<h2>What's new in this update</h2>
		<p><strong>Modernized the UI in CCC's Settings window</strong><br>We did a little bit of reorganizing in this window, but largely everything is where it was before.</p>

		<h2>Other improvements</h2>
			<ul>
			<li>
				<span class="icon"><div class="type Improved">Improved</div></span>
				<span class="description"><p>We made some adjustments to the collection of snapshots when a volume is selected in CCC's sidebar.</p></span>
			</li>
		</ul>
	</details>
"""#

/// `ccc7_rn_beta.html` as served 2026-10-10, trimmed to its one entry with one
/// prose paragraph and one list item. Keeps the beta-notice boilerplate, which
/// must not become a change line.
private let ccc7BetaFixture = #"""
	<details open id="primary">
	    <summary>CCC 7.2.2-b4 &mdash; <span style="color: #fff776">This is a pre-release update of CCC</span></summary>
		<div class="beta_notice_bg">
			<p class="beta_notice">If you prefer to not see beta versions of CCC, open CCC's Settings window, click on <strong>Software Update</strong>, then uncheck the box next to <strong>Inform me of beta releases</strong>.</p>
		</div>
		<h2>What we're testing in this beta cycle</h2>
		<p><strong>Quick Update is smarter and more resilient.</strong> Quick Update now recovers much better when a previous backup ran into errors.</p>
		<h2>Changes in CCC 7.2.2</h2>
		<ul>
			<li>
				<span class="icon"><div class="type Improved">Improved</div></span>
				<span class="description"><p>Improved the performance of sparsefile copying.</p></span>
			</li>
		</ul>

	</details>
"""#

/// `en/kb/ccc/6/release-notes` as served 2026-10-10: the first two releases and
/// one of the older-generation headings the page ends with.
private let ccc6Fixture = #"""
            <article><h2><a name="6.1.13"></a>CCC 6.1.13</h2>
<p>March 16, 2026</p>
<ul>
	<li>Fixed an infinite-recursion crash that could occur when loading the Task Filter window in cases where the source is a NAS volume that errantly presents a "." entry in its folder list.</li>
	<li>CCC's helper tool will no longer allow requests from older versions of CCC.</li>
</ul>

<h2><a name="6.1.12"></a>CCC 6.1.12</h2>
<p>April 7, 2025</p>
<ul>
<li>This update adjusts the ownership of the CCC System keychain entries so they will be accessible to CCC v7 (e.g. if you decided later to upgrade to CCC v7).</li>
</ul>

<h2><a name="bigsur"></a><a name="5_1_22"></a>Carbon Copy Cloner 5.1.22</h2>

<p>October 16, 2020 [macOS Big Sur qualification]</p>
</article>
"""#

/// `en/kb/ccc/5/release-notes` as served 2026-10-10: the newest release, one
/// that leads with paragraphs, and the first CCC 4 heading after 5.0.
private let ccc5Fixture = #"""
            <article><h2><a name="5_1_28"></a>Carbon Copy Cloner 5.1.28</h2>

<p>September 16, 2021</p>
<ul>
	<li>Fixed a logistical issue that was leading to the SafetyNet Pruning settings not being visible for HFS+ formatted volumes.</li>
	<li>Fixed a crasher affecting Mojave and older clients while using the Task Filter window.</li>
</ul>

<h2><a name="5_1_27"></a>Carbon Copy Cloner 5.1.27</h2>

<p>May 13, 2021</p>

<p>CCC still supports making bootable backups on Intel Macs running Big Sur too, that functionality has been available since 5.1.23 released in November.</p>

<ul>
	<li>Fixed an issue in which the task filter was inaccessible when the destination is the current startup disk.</li>
</ul>

<h2>Carbon Copy Cloner 4.1.24</h2>

<p>October 30, 2018</p>
</article>
"""#

struct CarbonCopyClonerChangelogRecipeTests {
    private func recipe(_ channel: ReleaseChannel, _ version: String) throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.bombich.ccc", channel: channel, version: version))
    }

    /// Each generation's install lands on its own page, and a beta copy on the
    /// beta page — the same split the probes make with `installedVersionPattern`.
    @Test func eachGenerationAndChannelGetsItsOwnPage() throws {
        #expect(try recipe(.stable, "7.2.1").source.absoluteString
                == "https://bombich.com/software/updates/ccc7_rn.html")
        #expect(try recipe(.beta, "7.2.2-b4").source.absoluteString
                == "https://bombich.com/software/updates/ccc7_rn_beta.html")
        #expect(try recipe(.stable, "6.1.13").source.absoluteString
                == "https://bombich.com/en/kb/ccc/6/release-notes")
        #expect(try recipe(.stable, "5.1.28").source.absoluteString
                == "https://bombich.com/en/kb/ccc/5/release-notes")
    }

    @Test func ccc7StablePage() throws {
        let cl = try #require(ChangelogExtractor.extract(
            from: ccc7StableFixture, using: try recipe(.stable, "7.2.1")))
        #expect(cl.entries.map(\.version) == ["7.2.1", "7.2"])
        #expect(cl.entries[0].date == nil)
        #expect(cl.entries[1].date == "September 13, 2026")
        #expect(cl.entries[0].items == [
            "Corrected an oversight that caused the \"Repeat affected tasks on login\" setting to be enabled by default. That setting will be actively disabled for anyone updating from CCC 7.2 (builds 8399 or 8401). If you want that setting to be enabled, re-enable it after applying the update in CCC Settings > Advanced.",
            "Fixed a logic issue that was preventing the export of an ad hoc verification report.",
        ])
        // The prose paragraph AND the list item both survive.
        #expect(cl.entries[1].items.count == 2)
        #expect(cl.entries[1].items.last
                == "We made some adjustments to the collection of snapshots when a volume is selected in CCC's sidebar.")
    }

    @Test func ccc7BetaPage() throws {
        let cl = try #require(ChangelogExtractor.extract(
            from: ccc7BetaFixture, using: try recipe(.beta, "7.2.2-b4")))
        #expect(cl.entries.map(\.version) == ["7.2.2-b4"])
        #expect(cl.entries[0].items == [
            "Quick Update is smarter and more resilient. Quick Update now recovers much better when a previous backup ran into errors.",
            "Improved the performance of sparsefile copying.",
        ])
    }

    @Test func ccc6PageStopsAtItsOwnGeneration() throws {
        let cl = try #require(ChangelogExtractor.extract(
            from: ccc6Fixture, using: try recipe(.stable, "6.1.13")))
        #expect(cl.entries.map(\.version) == ["6.1.13", "6.1.12"])
        #expect(cl.entries[0].date == "March 16, 2026")
        #expect(cl.entries[0].items.last == "CCC's helper tool will no longer allow requests from older versions of CCC.")
        #expect(cl.entries[1].items.count == 1)
    }

    @Test func ccc5PageStopsAtItsOwnGeneration() throws {
        let cl = try #require(ChangelogExtractor.extract(
            from: ccc5Fixture, using: try recipe(.stable, "5.1.28")))
        #expect(cl.entries.map(\.version) == ["5.1.28", "5.1.27"])
        #expect(cl.entries[0].date == "September 16, 2021")
        #expect(cl.entries[0].items.count == 2)
        #expect(cl.entries[1].items == [
            "CCC still supports making bootable backups on Intel Macs running Big Sur too, that functionality has been available since 5.1.23 released in November.",
            "Fixed an issue in which the task filter was inaccessible when the destination is the current startup disk.",
        ])
    }
}
