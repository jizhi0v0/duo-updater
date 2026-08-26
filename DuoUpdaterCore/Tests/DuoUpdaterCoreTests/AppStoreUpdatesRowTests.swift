#if os(macOS)
import Foundation
import Testing
@testable import DuoUpdaterCore

/// Regression cover for pairing an Updates-list row label with its own offer button.
///
/// Every rectangle below is a frame read off App Store's real Updates list (mini,
/// macOS 26.6, 2026-08-26) while Word had an update pending and Excel and TestFlight
/// sat under "Updated Recently". The list is a **two-column grid**: Excel's label and
/// TestFlight's label share one horizontal band with two buttons, which is what the
/// old "every static text within ±45 px of the button's midY" rule could not tell
/// apart — both buttons collected both names, so the first row answered for every app.
struct AppStoreUpdatesRowTests {

    // "Updated Recently", the two-column band — buttons at x=723 and x=1267.
    private let excelButton = CGRect(x: 723, y: 378, width: 68, height: 64)
    private let testFlightButton = CGRect(x: 1267, y: 378, width: 68, height: 64)
    private let excelLabel = CGRect(x: 341, y: 391, width: 110, height: 16)
    private let testFlightLabel = CGRect(x: 885, y: 391, width: 72, height: 16)

    private var band: [CGRect] { [excelButton, testFlightButton] }

    /// The left cell's label belongs to the left cell's button. Under the old rule this
    /// label was also handed to the right-hand button.
    @Test func aLabelBelongsToTheButtonInItsOwnColumn() {
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: excelLabel, among: band) == excelButton)
    }

    /// The second column's label must not fall back to the first column's button just
    /// because that button is also on its row.
    @Test func theSecondColumnKeepsItsOwnButton() {
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: testFlightLabel, among: band) == testFlightButton)
    }

    /// Order of the button list must not decide the answer — the AX tree hands them over
    /// in whatever order it walks.
    @Test func theAnswerDoesNotDependOnButtonOrder() {
        let reversed = [testFlightButton, excelButton]
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: excelLabel, among: reversed) == excelButton)
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: testFlightLabel, among: reversed) == testFlightButton)
    }

    /// The single-column case still works: Word's row in the "Available" section has one
    /// button (x=723) and its label at x=341.
    @Test func aSingleColumnRowStillPairsUp() {
        let wordButton = CGRect(x: 723, y: 191, width: 68, height: 64)
        let wordLabel = CGRect(x: 341, y: 204, width: 111, height: 16)
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: wordLabel, among: [wordButton]) == wordButton)
    }

    /// Full-width section headings ("Available", "Updated Recently") span past every
    /// button, so no button owns them and they can't be mistaken for an app name.
    @Test func aFullWidthSectionHeadingBelongsToNobody() {
        let heading = CGRect(x: 228, y: 325, width: 1692, height: 22)
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: heading, among: band) == nil)
    }

    /// A label to the right of every button (App Store lays labels out to the left of
    /// their button, so this is malformed input) is dropped rather than guessed at.
    @Test func aLabelWithNoButtonToItsRightIsDropped() {
        let stray = CGRect(x: 1800, y: 391, width: 60, height: 16)
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: stray, among: band) == nil)
    }

    /// A label that merely overlaps its button horizontally is not owned by it — the
    /// rule is "the button starts at or after the label ends", which is what keeps a
    /// wide label from claiming a button sitting inside its own span.
    @Test func ownershipRequiresTheButtonToStartAfterTheLabelEnds() {
        let overlapping = CGRect(x: 700, y: 391, width: 100, height: 16)  // ends at 800 > 723
        #expect(AppStoreAXInstaller.owningButton(ofLabelAt: overlapping, among: band) == testFlightButton)
    }
}
#endif
