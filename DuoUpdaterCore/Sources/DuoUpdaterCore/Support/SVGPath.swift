import CoreGraphics
import Foundation

/// One step of a drawn outline, in the coordinate space the path was authored in.
///
/// Deliberately reduced to four cases: every SVG command that can appear in the
/// icon artwork we render is normalized into these, so the drawing side has no
/// parsing to do and no command it has not been given. Quadratics and arcs are
/// converted to cubics here rather than at the call site — there is exactly one
/// place that conversion can be got wrong, and it is covered by tests.
public enum PathSegment: Sendable, Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

/// Parses the `d` attribute of an SVG `<path>`.
///
/// This exists so the app can render real icon artwork — single-path, 24×24
/// monochrome marks — without an asset pipeline: the path data is a string
/// constant, the shape scales to any size, and it takes a tint like any other
/// vector. It lives in the core package rather than beside the view because it is
/// the kind of thing that fails silently and subtly (an off-by-one in the arc
/// conversion is a slightly wrong curve, not a crash), and the app target has no
/// tests to catch that.
///
/// Supports the full command set the artwork uses — `M L H V C S Q T A Z` in both
/// absolute and relative forms — and returns nil rather than a partial outline for
/// anything it cannot read, so a malformed path draws nothing instead of drawing
/// something wrong.
public enum SVGPath {

    public static func parse(_ d: String) -> [PathSegment]? {
        var scanner = Scanner(d)
        var segments: [PathSegment] = []

        var current = CGPoint.zero        // the point the next command starts from
        var subpathStart = CGPoint.zero   // where `Z` returns to
        var lastCubicControl: CGPoint?    // for `S`, the reflection source
        var lastQuadControl: CGPoint?     // for `T`
        var command: Character?

        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { break }

            if let letter = scanner.peekCommand() {
                command = letter
                scanner.advance()
            } else if command == nil {
                return nil   // numbers before any command
            } else if command == "M" || command == "m" {
                // A repeated coordinate pair after a moveto is an implicit lineto.
                command = command == "M" ? "L" : "l"
            }

            guard let cmd = command else { return nil }
            let relative = cmd.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch Character(cmd.uppercased()) {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y)
                subpathStart = current
                segments.append(.move(current))
                lastCubicControl = nil; lastQuadControl = nil
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y)
                segments.append(.line(current))
                lastCubicControl = nil; lastQuadControl = nil
            case "H":
                guard let x = scanner.number() else { return nil }
                current = relative ? CGPoint(x: current.x + x, y: current.y) : CGPoint(x: x, y: current.y)
                segments.append(.line(current))
                lastCubicControl = nil; lastQuadControl = nil
            case "V":
                guard let y = scanner.number() else { return nil }
                current = relative ? CGPoint(x: current.x, y: current.y + y) : CGPoint(x: current.x, y: y)
                segments.append(.line(current))
                lastCubicControl = nil; lastQuadControl = nil
            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c1 = point(x1, y1), c2 = point(x2, y2), end = point(x, y)
                segments.append(.curve(to: end, control1: c1, control2: c2))
                current = end; lastCubicControl = c2; lastQuadControl = nil
            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                // The first control point mirrors the previous curve's second one;
                // with no previous curve it coincides with the current point.
                let c1 = lastCubicControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let c2 = point(x2, y2), end = point(x, y)
                segments.append(.curve(to: end, control1: c1, control2: c2))
                current = end; lastCubicControl = c2; lastQuadControl = nil
            case "Q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let q = point(x1, y1), end = point(x, y)
                segments.append(cubic(from: current, quadControl: q, to: end))
                current = end; lastQuadControl = q; lastCubicControl = nil
            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                let q = lastQuadControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let end = point(x, y)
                segments.append(cubic(from: current, quadControl: q, to: end))
                current = end; lastQuadControl = q; lastCubicControl = nil
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let end = point(x, y)
                segments.append(contentsOf: arc(from: current, to: end, rx: rx, ry: ry,
                                                rotation: rotation, largeArc: largeArc, sweep: sweep))
                current = end; lastCubicControl = nil; lastQuadControl = nil
            case "Z":
                segments.append(.close)
                current = subpathStart
                lastCubicControl = nil; lastQuadControl = nil
                // `Z` is the one command that consumes nothing, so it is also the
                // one that can spin: with a number after it — invalid SVG, since a
                // command must follow a closepath — the loop would re-enter with
                // the cursor untouched and append `.close` until it ran out of
                // memory. Verified before this guard existed: `M0 0 L1 1 Z 5 5`
                // hung. Every other command either consumes its operands or bails.
                scanner.skipSeparators()
                if !scanner.isAtEnd, scanner.peekCommand() == nil { return nil }
            default:
                return nil
            }
        }
        return segments.isEmpty ? nil : segments
    }

    /// A quadratic expressed as the cubic with the same shape.
    private static func cubic(from start: CGPoint, quadControl q: CGPoint, to end: CGPoint) -> PathSegment {
        .curve(to: end,
               control1: CGPoint(x: start.x + 2.0 / 3 * (q.x - start.x),
                                 y: start.y + 2.0 / 3 * (q.y - start.y)),
               control2: CGPoint(x: end.x + 2.0 / 3 * (q.x - end.x),
                                 y: end.y + 2.0 / 3 * (q.y - end.y)))
    }

    /// An elliptical arc as up to four cubics, per the SVG spec's endpoint-to-centre
    /// conversion (implementation notes F.6.5). Degenerate cases — zero-length arc,
    /// a zero radius — fall back to a straight line, which is what the spec says to
    /// do rather than something to guard against.
    private static func arc(from start: CGPoint, to end: CGPoint,
                            rx: CGFloat, ry: CGFloat, rotation: CGFloat,
                            largeArc: Bool, sweep: Bool) -> [PathSegment] {
        guard start != end else { return [] }
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0 else { return [.line(end)] }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Radii too small to span the chord are scaled up until they exactly do.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale; ry *= scale
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard len > 0 else { return 0 }
            let a = acos(min(1, max(-1, dot / len)))
            return (ux * vy - uy * vx < 0) ? -a : a
        }

        let startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        // A cubic tracks an elliptical arc well up to a quarter turn; past that the
        // error becomes visible, so the sweep is split.
        let count = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(count)
        let k = 4.0 / 3 * tan(step / 4)

        var segments: [PathSegment] = []
        var theta = startAngle
        func onArc(_ t: CGFloat) -> CGPoint {
            let x = rx * cos(t), y = ry * sin(t)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            let x = -rx * sin(t), y = ry * cos(t)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }
        for _ in 0..<count {
            let next = theta + step
            let p0 = onArc(theta), p1 = onArc(next)
            let d0 = derivative(theta), d1 = derivative(next)
            segments.append(.curve(
                to: p1,
                control1: CGPoint(x: p0.x + k * d0.x, y: p0.y + k * d0.y),
                control2: CGPoint(x: p1.x - k * d1.x, y: p1.y - k * d1.y)))
            theta = next
        }
        return segments
    }

    /// A forward-only scanner over the `d` string.
    ///
    /// Hand-written rather than `Foundation.Scanner` because SVG number syntax is
    /// its own thing: separators are optional, a sign starts a new number without
    /// any separator at all (`1-2` is two numbers), and the flags in an arc
    /// command are single digits that may be run together with what follows
    /// (`a1 1 0 011 1`).
    private struct Scanner {
        private let characters: [Character]
        private var index = 0

        init(_ string: String) { characters = Array(string) }

        var isAtEnd: Bool { index >= characters.count }

        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while index < characters.count, characters[index] == "," || characters[index].isWhitespace {
                index += 1
            }
        }

        func peekCommand() -> Character? {
            guard index < characters.count else { return nil }
            let c = characters[index]
            return "MmLlHhVvCcSsQqTtAaZz".contains(c) ? c : nil
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var digits = ""
            if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                digits.append(characters[index]); index += 1
            }
            // At most one decimal point: in minified path data ".5.5" is two
            // numbers, and swallowing the second dot turns the whole path into an
            // unparseable token. This is the single most common shape in real
            // artwork, so getting it wrong fails every icon at once.
            var sawDot = false
            while index < characters.count {
                let c = characters[index]
                if c.isNumber {
                    digits.append(c); index += 1
                } else if c == ".", !sawDot {
                    sawDot = true; digits.append(c); index += 1
                } else {
                    break
                }
            }
            if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                digits.append(characters[index]); index += 1
                if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                    digits.append(characters[index]); index += 1
                }
                while index < characters.count, characters[index].isNumber {
                    digits.append(characters[index]); index += 1
                }
            }
            guard let value = Double(digits) else { return nil }
            return CGFloat(value)
        }

        /// An arc flag: exactly one character, `0` or `1`.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let c = characters[index]
            guard c == "0" || c == "1" else { return nil }
            index += 1
            return c == "1"
        }
    }
}
