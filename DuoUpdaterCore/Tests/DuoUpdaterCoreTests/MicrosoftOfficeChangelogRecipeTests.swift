import Testing
import Foundation
@testable import DuoUpdaterCore

/// `learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac`, fetched
/// 2026-10-10 and trimmed: the whole 16.113.4 entry, the 16.113 entry with every
/// list cut to its first two items (it has all three blocks, an Office Suite
/// section, and Outlook's one `<p>` section), and the 16.103.4 entry, whose
/// version line has no "Build". Markup is verbatim.
private let officeForMacFixture = #"""
<h2 id="october-06-2026">October 06, 2026</h2>
<p><em>Version 16.113.4 (Build 26100421)</em></p>
<h3 id="resolved-issues">Resolved issues</h3>
<h3 id="excel">Excel</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="onenote">OneNote</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="outlook">Outlook</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="powerpoint">PowerPoint</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="word">Word</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h2 id="september-16-2026">September 16, 2026</h2>
<p><em>Version 16.113 (Build 26091433)</em></p>
<h3 id="feature-updates">Feature updates</h3>
<h3 id="excel-4">Excel</h3>
<ul>
<li><strong>Copilot in Excel: change history skill</strong> The change history skill helps users understand how a workbook has evolved over time. Copilot can summarize recent changes, identify who made edits, and explain how both people and AI have modified the workbook. It can also help undo specific edits or restore formulas by returning the workbook to a previous working state.</li>
<li><strong>Copilot in Excel: chat history</strong> Use the menu icon in the upper left corner of the Copilot in Excel pane to access your Copilot chat history. Conversations are listed based on recency, with your most recent chat at the top of the list. Select a conversation from the list to view it.</li>
</ul>
<h3 id="outlook-4">Outlook</h3>
<ul>
<li><strong>Calendar</strong>: Outlook Settings now let users manage work hours and work-location schedules for supported accounts.</li>
<li><strong>Calendar</strong>: Users can choose whether accepted invitations are removed from the Inbox and whether conflicting events are automatically declined on supported accounts.</li>
</ul>
<h3 id="resolved-issues-4">Resolved issues</h3>
<h3 id="excel-5">Excel</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="onenote-4">OneNote</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="outlook-5">Outlook</h3>
<p>Resolved Issues:
<strong>Mail</strong>: The unread-count badge in the Dock now initializes correctly at startup.<br>
<strong>Mail</strong>: Improved the experience for viewing and interacting with Loop components in Outlook messages.
<strong>Add-ins</strong>: Attachments added or removed by add-ins now synchronize more reliably, including during rapid or overlapping draft saves. The unread-count badge in the Dock now initializes correctly at startup.<br>
<strong>Copilot</strong>: Fixed an issue that disrupted the Copilot rewrite experience.</p>
<h3 id="powerpoint-4">PowerPoint</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="word-4">Word</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="security-updates">Security updates</h3>
<h3 id="excel-6">Excel</h3>
<ul>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-85875" data-linktype="external">CVE-2026-85875</a></li>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-81960" data-linktype="external">CVE-2026-81960</a></li>
</ul>
<h3 id="powerpoint-5">PowerPoint</h3>
<ul>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-78513" data-linktype="external">CVE-2026-78513</a></li>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-72977" data-linktype="external">CVE-2026-72977</a></li>
</ul>
<h3 id="office-suite">Office Suite</h3>
<ul>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-81955" data-linktype="external">CVE-2026-81955</a></li>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-81952" data-linktype="external">CVE-2026-81952</a></li>
</ul>
<h3 id="word-5">Word</h3>
<ul>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-80090" data-linktype="external">CVE-2026-80090</a></li>
<li><a href="https://portal.msrc.microsoft.com/security-guidance/advisory/CVE-2026-80088" data-linktype="external">CVE-2026-80088</a></li>
</ul>
<h2 id="december-09-2025">December 09, 2025</h2>
<p><em>Version 16.103.4 (25120717)</em></p>
<h3 id="excel-57">Excel</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="onenote-42">OneNote</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="outlook-52">Outlook</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="powerpoint-45">PowerPoint</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
<h3 id="word-50">Word</h3>
<ul>
<li>Quality and performance improvements.</li>
</ul>
</div>
</main>
"""#

private func officeEntries(_ bundleID: String) throws -> [Changelog.Entry] {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID))
    return try #require(ChangelogExtractor.extract(from: officeForMacFixture, using: recipe)).entries
}

private let suiteCVEs = ["CVE-2026-81955", "CVE-2026-81952"]

@Test func officeForMacExcelTakesOnlyExcelAndSuiteItems() throws {
    let entries = try officeEntries("com.microsoft.Excel")
    // Marketing versions (CFBundleShortVersionString), with or without "Build".
    #expect(entries.map(\.version) == ["16.113.4", "16.113", "16.103.4"])
    #expect(entries.map(\.date) == ["October 06, 2026", "September 16, 2026", "December 09, 2025"])
    #expect(entries[0].items == ["Quality and performance improvements."])
    #expect(entries[1].items == [
        "Copilot in Excel: change history skill The change history skill helps users understand how a workbook has evolved over time. Copilot can summarize recent changes, identify who made edits, and explain how both people and AI have modified the workbook. It can also help undo specific edits or restore formulas by returning the workbook to a previous working state.",
        "Copilot in Excel: chat history Use the menu icon in the upper left corner of the Copilot in Excel pane to access your Copilot chat history. Conversations are listed based on recency, with your most recent chat at the top of the list. Select a conversation from the list to view it.",
        "Quality and performance improvements.",
        "CVE-2026-85875", "CVE-2026-81960",
    ] + suiteCVEs)
}

@Test func officeForMacWordAndPowerPointSkipOtherAppsSections() throws {
    let word = try officeEntries("com.microsoft.Word")
    #expect(word.map(\.version) == ["16.113.4", "16.113", "16.103.4"])
    // The PowerPoint list right before the suite's, and Excel's before that,
    // contribute nothing.
    #expect(word[1].items == ["Quality and performance improvements."] + suiteCVEs
        + ["CVE-2026-80090", "CVE-2026-80088"])

    let powerPoint = try officeEntries("com.microsoft.Powerpoint")
    #expect(powerPoint[1].items == ["Quality and performance improvements.",
        "CVE-2026-78513", "CVE-2026-72977"] + suiteCVEs)
}

@Test func officeForMacOutlookKeepsItsParagraphSection() throws {
    let entries = try officeEntries("com.microsoft.Outlook")
    #expect(entries.map(\.version) == ["16.113.4", "16.113", "16.103.4"])
    let items = entries[1].items
    #expect(items.count == 5)
    #expect(items[0] == "Calendar: Outlook Settings now let users manage work hours and work-location schedules for supported accounts.")
    #expect(items[2].hasPrefix("Resolved Issues: Mail: The unread-count badge in the Dock now initializes correctly at startup."))
    #expect(items[2].hasSuffix("Copilot: Fixed an issue that disrupted the Copilot rewrite experience."))
    #expect(Array(items.suffix(2)) == suiteCVEs)
}

@Test func officeForMacOneNoteIsItsOwnLineAndTheSuite() throws {
    let entries = try officeEntries("com.microsoft.onenote.mac")
    #expect(entries.map(\.version) == ["16.113.4", "16.113", "16.103.4"])
    #expect(entries[1].items == ["Quality and performance improvements."] + suiteCVEs)
}

/// `learn.microsoft.com/en-us/sharepoint/sync-release-notes`, fetched 2026-10-10:
/// one Windows entry, two macOS Production entries (one with the nested "rolling
/// out" list) and one macOS Deferred entry, verbatim; the rest of each ring cut.
private let oneDriveSyncFixture = #"""
<h2 id="windows-production-ring">Windows Production Ring</h2>
<h4 id="2617809130006-october-2-2026">26.178.0913.0006 (October 2, 2026)</h4>
<ul>
<li>We resolved product issues to improve the reliability and performance of the OneDrive sync app.</li>
</ul>
<h2 id="windows-deferred-ring">Windows Deferred Ring</h2>
<h2 id="macos-production-ring">macOS Production Ring</h2>
<h4 id="2617309060008-september-25-2026-1">26.173.0906.0008 (September 25, 2026)</h4>
<ul>
<li>We resolved product issues to improve the reliability and performance of the OneDrive sync app.</li>
</ul>
<h4 id="2615008040011-august-21-2026-1">26.150.0804.0011 (August 21, 2026)</h4>
<ul>
<li>We resolved product issues to improve the reliability and performance of the OneDrive sync app.</li>
<li>New features gradually rolling out:
<ul>
<li><strong>Check in and check out synced files:</strong> Users with work or school accounts can now check files in and out of SharePoint document libraries that require check-out. When you check out a file, its synced copy becomes editable locally instead of read-only, and Check In and Check Out commands are available from the right-click menu in Finder. Checking a file back in restores the read-only state.</li>
</ul>
</li>
</ul>
<h2 id="macos-deferred-ring">macOS Deferred Ring</h2>
<h4 id="2612306280001-october-6-2026-1">26.123.0628.0001 (October 6, 2026)</h4>
<ul>
<li>We resolved product issues to improve the reliability and performance of the OneDrive sync app.</li>
</ul>
</div>
</main>
"""#

@Test func oneDriveTakesOnlyTheMacOSProductionRing() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.OneDrive"))
    let entries = try #require(ChangelogExtractor.extract(from: oneDriveSyncFixture, using: recipe)).entries
    // Not Windows' 26.178, not the Deferred ring's 26.123; three components, the
    // probe's scheme.
    #expect(entries.map(\.version) == ["26.173.0906", "26.150.0804"])
    #expect(entries[0].date == "September 25, 2026")
    #expect(entries[1].items == [
        "We resolved product issues to improve the reliability and performance of the OneDrive sync app.",
        "New features gradually rolling out:",
        "Check in and check out synced files: Users with work or school accounts can now check files in and out of SharePoint document libraries that require check-out. When you check out a file, its synced copy becomes editable locally instead of read-only, and Check In and Check Out commands are available from the right-click menu in Finder. Checking a file back in restores the read-only state.",
    ])
}
