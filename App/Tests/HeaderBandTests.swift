import CoreGraphics
import Testing

/// Where the long scroll reads the padding around a version header
/// (`HeaderBand.padding`). The numbers are openclaw's on macOS 27.2: the list
/// at 335, a 29.25 pt header, 4.125 pt of padding (2026-10-15).
///
/// Each case names the one-line mutation of `HeaderBand.padding` it fails under.
struct HeaderBandTests {

    private let listTop: CGFloat = 335
    private let height: CGFloat = 29.25
    private let padding: CGFloat = 4.125

    /// The header's view with its section's top `sectionTop` below the list's
    /// top, in place; floating when that is above the top.
    private func header(sectionTop: CGFloat) -> CGRect {
        CGRect(x: 347.5, y: listTop + max(sectionTop, 0) + padding, width: 1371.5, height: height)
    }

    /// Its first row, always in place.
    private func firstRow(sectionTop: CGFloat) -> CGRect {
        CGRect(x: 339.5, y: listTop + sectionTop + height + 2 * padding, width: 1388.5, height: 20)
    }

    private func read(sectionTop: CGFloat, rowBuilt: Bool = true) -> CGFloat? {
        HeaderBand.padding(header: header(sectionTop: sectionTop),
                           firstRow: rowBuilt ? firstRow(sectionTop: sectionTop) : nil,
                           listTop: listTop)
    }

    /// Floating after a jump, its first row scrolled away: the offset.
    ///
    /// Mutation: return nil whenever the first row is not built.
    @Test func floatingWithoutItsFirstRowReadsTheOffset() {
        #expect(read(sectionTop: -400, rowBuilt: false) == padding)
    }

    /// Floating over its first row, the row still built.
    ///
    /// Mutation: `below >= 0` → `below > -100` (the row under the header taken
    /// for a section in place).
    @Test func floatingOverItsFirstRowReadsTheOffset() {
        #expect(read(sectionTop: -15) == padding)
    }

    /// The review's case (#1331): in place 15 pt below the top. The offset is
    /// 19.125 there, not the padding, and must not be read as it.
    ///
    /// Mutation: drop the `abs(above - below) > 0.5` check.
    @Test func inPlaceBelowTheTopIsNotRead() {
        #expect(read(sectionTop: 15) == nil)
    }

    /// In place exactly at the top: both readings are the padding.
    ///
    /// Mutation: return nil whenever the first row is in place.
    @Test func atTheTopReadsThePadding() {
        #expect(read(sectionTop: 0) == padding)
    }

    /// A header further down, its first row not built (below the viewport):
    /// not one floating at the top.
    ///
    /// Mutation: drop `above < header.height`.
    @Test func aHeaderFarDownIsNotRead() {
        #expect(read(sectionTop: 600, rowBuilt: false) == nil)
    }

    /// A header pushed up out of the top by the next one.
    ///
    /// Mutation: drop `above >= 0`.
    @Test func aHeaderPushedOutIsNotRead() {
        let pushed = CGRect(x: 347.5, y: listTop - 10, width: 1371.5, height: height)
        #expect(HeaderBand.padding(header: pushed, firstRow: nil, listTop: listTop) == nil)
    }
}
