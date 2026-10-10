import Foundation
import Testing

@testable import DuoUpdaterCore

/// `shottr.cc/newversion.html`, fetched 2026-10-10: the headline release (1.9.3),
/// 1.9.2, 1.7.2 with its lists cut to one item each, 1.7.1, and the page's end of
/// content. Every line kept is verbatim.
///
/// Each kept segment is one of the page's shapes: the newest release as the `<h1>`
/// headline, an ordinary `<h3>`, a segment carrying a commented-out copy of an old
/// headline, and a release written as paragraphs. The page prints no dates.
private let shottrNewVersionFixture = #"""
<div class="content">
	<div class="segment">

		<div class="leftcol">
			<h1>Shottr v1.9.3 is out!</h1>
			<a href="/dl/Shottr-1.9.3b.dmg" class="download gaDownload gaV1-9-3" id="downloadButton">
				<b>Download</b>
				<small>v1.9.3, 2.3mb</small>
			</a>
		</div>
		<div class="rightcol">
			<b>Improvements</b>
			<ul>
				<li>Another set of improvements to accommodate macOS 27</li>
			</ul>
		</div>
	</div>


	<div class="segment">
		<div class="leftcol">
			<h3>Shottr v1.9.2</h3>	
		</div>
		<div class="rightcol">
			<b>Improvements</b>
			<ul>
				<li>Improved compatibility with macOS 27.</li>
			</ul>
		</div>
	</div>

	<div class="segment">
		<div class="leftcol">
			<h3>Shottr v1.7.2</h3>
			<!--<h1>Shottr v1.7.2 is out!</h1>
			<a href="/dl/Shottr-1.7.2.dmg" class="download gaDownload gaV1-7-2" id="downloadButton">
				<b>Download</b>
				<small>v1.7.2, 1.6mb</small>
			</a>-->
		</div>
		<div class="rightcol">
			<b>New Features</b>
			<ul>
				<li>Rasterize Image. Use menu Edit → Rasterize Image to make the entire image static (all appended screenshots and annotations will become a part of the image). Cannot be undone.</li>
			</ul>
			<br/>
			<b>Other Improvements</b>
			<ul>
				<li>[BUG FIX] On the computers that had the perpetual “Save” dialog problem, this problem should be fixed.</li>
			</ul>
		</div>
	</div>

	<div class="segment">
		<div class="leftcol">
			<h3>Shottr v1.7.1</h3>
			<!--<a href="/dl/Shottr-1.7.1.dmg" class="download gaDownload gaV1-7-1" id="downloadButton">
				<b>Download</b>
				<small>v1.7.1, 1.6mb</small>
			</a>-->
		</div>
		<div class="rightcol">
			<p><b>Changes</b></p>
			<p>Fixed bugs introduced by macOS v13.5</p>
		</div>
	</div>

</div>

<style>
"""#

@Test func shottrReadsItsNewVersionPage() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "cc.ffitch.shottr"))
    let log = try #require(ChangelogExtractor.extract(from: shottrNewVersionFixture, using: recipe))

    // The commented-out "Shottr v1.7.2 is out!" headline is not a second 1.7.2.
    #expect(log.entries.map(\.version) == ["1.9.3", "1.9.2", "1.7.2", "1.7.1"])
    try #require(log.entries.count == 4)
    #expect(log.entries.allSatisfy { $0.date == nil })
    #expect(log.entries[0].items == ["Another set of improvements to accommodate macOS 27"])
    #expect(log.entries[2].items == [
        "Rasterize Image. Use menu Edit → Rasterize Image to make the entire image static (all appended screenshots and annotations will become a part of the image). Cannot be undone.",
        "[BUG FIX] On the computers that had the perpetual “Save” dialog problem, this problem should be fixed.",
    ])
    #expect(log.entries[2].content.contains(.heading("Other Improvements")))
    // A release written as paragraphs: the bold section name is a heading, not a note.
    #expect(log.entries[3].items == ["Fixed bugs introduced by macOS v13.5"])
    #expect(log.entries[3].content.contains(.heading("Changes")))
}
