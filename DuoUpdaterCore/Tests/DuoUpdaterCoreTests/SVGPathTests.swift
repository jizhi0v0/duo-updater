import Testing
import Foundation
import CoreGraphics
@testable import DuoUpdaterCore

/// Every point a parsed outline touches — control points included, since a control
/// point flung outside the box still bends the curve outside it.
private func points(_ segments: [PathSegment]) -> [CGPoint] {
    segments.flatMap { segment -> [CGPoint] in
        switch segment {
        case .move(let p), .line(let p): return [p]
        case .curve(let to, let c1, let c2): return [to, c1, c2]
        case .close: return []
        }
    }
}

private func bounds(_ segments: [PathSegment]) -> CGRect {
    let all = points(segments)
    let xs = all.map(\.x), ys = all.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        return .null
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

@Test func readsAbsoluteAndRelativeMovesAndLines() throws {
    let absolute = try #require(SVGPath.parse("M1 2 L3 4 Z"))
    #expect(absolute == [.move(CGPoint(x: 1, y: 2)), .line(CGPoint(x: 3, y: 4)), .close])
    // Same shape, said relatively.
    let relative = try #require(SVGPath.parse("m1 2 l2 2 z"))
    #expect(relative == absolute)
}

@Test func aSecondCoordinatePairAfterAMoveIsALine() throws {
    // SVG says a repeated pair after moveto is an implicit lineto.
    let segments = try #require(SVGPath.parse("M1 1 2 2 3 3"))
    #expect(segments == [.move(CGPoint(x: 1, y: 1)),
                         .line(CGPoint(x: 2, y: 2)),
                         .line(CGPoint(x: 3, y: 3))])
}

@Test func horizontalAndVerticalLinesKeepTheOtherAxis() throws {
    let segments = try #require(SVGPath.parse("M2 3 H8 V9 h-2 v-3"))
    #expect(segments == [.move(CGPoint(x: 2, y: 3)),
                         .line(CGPoint(x: 8, y: 3)),
                         .line(CGPoint(x: 8, y: 9)),
                         .line(CGPoint(x: 6, y: 9)),
                         .line(CGPoint(x: 6, y: 6))])
}

@Test func numbersRunTogetherAreStillTwoNumbers() throws {
    // "1-2" is 1 then -2: a sign starts a new number with no separator. Real icon
    // data is minified exactly this way, so getting it wrong mangles every path.
    let segments = try #require(SVGPath.parse("M1-2L-3.5.5"))
    #expect(segments == [.move(CGPoint(x: 1, y: -2)), .line(CGPoint(x: -3.5, y: 0.5))])
}

@Test func smoothCurveMirrorsThePreviousControlPoint() throws {
    let segments = try #require(SVGPath.parse("M0 0 C1 1 2 1 3 0 S5 -1 6 0"))
    guard case .curve(_, let control1, _) = segments[2] else {
        Issue.record("expected a curve"); return
    }
    // Previous second control was (2,1) and the curve ended at (3,0), so the
    // reflection is (4,-1).
    #expect(control1 == CGPoint(x: 4, y: -1))
}

@Test func quadraticsBecomeTheEquivalentCubic() throws {
    let segments = try #require(SVGPath.parse("M0 0 Q3 3 6 0"))
    guard case .curve(let end, let c1, let c2) = segments[1] else {
        Issue.record("expected a curve"); return
    }
    #expect(end == CGPoint(x: 6, y: 0))
    #expect(c1 == CGPoint(x: 2, y: 2))   // start + 2/3 * (control - start)
    #expect(c2 == CGPoint(x: 4, y: 2))
}

@Test func anArcLandsOnItsEndpointAndStaysNearItsRadii() throws {
    // A half-circle of radius 1 from (0,0) to (2,0).
    let segments = try #require(SVGPath.parse("M0 0 A1 1 0 0 1 2 0"))
    guard case .curve(let end, _, _) = segments.last else {
        Issue.record("expected a curve"); return
    }
    #expect(abs(end.x - 2) < 0.001)
    #expect(abs(end.y) < 0.001)
    let box = bounds(segments)
    #expect(box.minX >= -0.01 && box.maxX <= 2.01)
    // Upward, not downward: a sweep flag of 1 means the positive angle direction,
    // and in SVG's y-down frame that arches the curve into negative y. (This
    // assertion was written the other way round first, which is the mistake the
    // test exists to catch.)
    #expect(box.minY >= -1.5 && box.maxY <= 0.01)
}

@Test func anArcWithAZeroRadiusIsAStraightLine() throws {
    #expect(SVGPath.parse("M0 0 A0 0 0 0 1 2 0") == [.move(.zero), .line(CGPoint(x: 2, y: 0))])
}

@Test func aNumberWhereACommandMustFollowClosepathIsRefusedRatherThanSpun() {
    // `Z` consumes nothing, so without a guard the parser re-enters the loop with
    // the cursor untouched and appends `.close` forever. This hung before the
    // guard; if it ever regresses, this test hangs rather than fails — which is
    // still the loudest possible signal.
    #expect(SVGPath.parse("M0 0 L1 1 Z 5 5") == nil)
    // A command after the closepath is the valid case and still parses.
    #expect(SVGPath.parse("M0 0 L1 1 Z M2 2") != nil)
}

@Test func malformedPathsParseToNothingRatherThanToSomethingWrong() {
    #expect(SVGPath.parse("") == nil)
    #expect(SVGPath.parse("1 2 3") == nil)          // numbers with no command
    #expect(SVGPath.parse("M1") == nil)             // half a coordinate
    #expect(SVGPath.parse("M0 0 K3 3") == nil)      // not a command
    #expect(SVGPath.parse("M0 0 A1 1 0 7 1 2 0") == nil)   // flag that isn't 0 or 1
}

// MARK: - The real artwork

@Test func everyRuntimeMarkParsesAndFitsItsBox() throws {
    for runtime in AppRuntime.allCases {
        guard let data = RuntimeArtwork.pathData(for: runtime) else { continue }
        let segments = try #require(SVGPath.parse(data), "\(runtime.rawValue) failed to parse")
        let box = bounds(segments)
        // Simple Icons authors to a 24×24 box. A path that leaves it is the
        // signature of a botched arc conversion — the shape still draws, just with
        // a piece of it somewhere off screen, which no compiler or crash reports.
        #expect(box.minX >= -0.5 && box.minY >= -0.5,
                "\(runtime.rawValue) starts outside its box at \(box.origin)")
        #expect(box.maxX <= RuntimeArtwork.viewBox + 0.5 && box.maxY <= RuntimeArtwork.viewBox + 0.5,
                "\(runtime.rawValue) runs past its box: \(box)")
        // And it should actually fill most of that box — a mark parsed down to a
        // few stray points would pass the bounds check above.
        #expect(box.width > RuntimeArtwork.viewBox * 0.5 && box.height > RuntimeArtwork.viewBox * 0.5,
                "\(runtime.rawValue) is suspiciously small: \(box)")
    }
}

@Test func theRuntimesWithoutVendorArtworkSaySoRatherThanReturningEmpty() {
    for runtime in [AppRuntime.chromium, .catalyst, .iOSApp, .native] {
        #expect(RuntimeArtwork.pathData(for: runtime) == nil)
    }
}
