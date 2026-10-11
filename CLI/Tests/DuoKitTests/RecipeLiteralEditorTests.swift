import Testing
import Foundation
import DuoUpdaterCore
@testable import DuoKit

/// The literal editor is the only code that turns a model's answer into Swift, so
/// it is held to two things: it changes exactly the literal it was asked to, and
/// it refuses anything it does not fully understand. The second half is checked
/// against every real family file, not just a sample.
@Suite struct RecipeLiteralEditorTests {

    static let family = """
        enum f {
            static let set = AppRecipeSet(
                family: "f",
                probes: [
                VendorProbeRecipe(bundleID: "a.b", url: URL(string: "https://x.example/v")!,
                                  versionPattern: #"v([0-9.]+)"#),
                ],
                changelogs: [
                // First: commas, (parens) and ] in a comment must not count.
                ChangelogRecipe(
                    bundleID: "a.b",
                    source: URL(string: "https://notes.example/a")!,
                    /* a block comment, with ( and [ */
                    entryPattern: #"<h2>(?<version>[^<]+)</h2>(?<body>.*?)(?=<h2>|$)"#,
                    itemPatterns: [#"<li>(?<item>[^<]+)</li>"#, #"<p>(?<item>[^<,]+)</p>"#],
                    maxEntries: 20),
                ChangelogRecipe(
                    bundleID: "a.b.beta",
                    source: URL(string: "https://notes.example/b")!,
                    entryPattern: sharedPattern,
                    itemPatterns: [#"<li>(.+?)</li>"#],
                    channel: .beta),
                ],
                githubRules: [])
        }
        """

    typealias E = RecipeLiteralEditor

    @Test func rewritesOnlyTheNamedLiteralsOfTheNamedRecipe() throws {
        let out = try E.apply(
            .init(source: URL(string: "https://notes.example/a2")!, entryPattern: "NEW",
                  itemPatterns: ["ONE", "TWO"]),
            toChangelogAt: 0, count: 2, bundleID: "a.b", in: Self.family)
        var expected = Self.family
        expected = expected.replacingOccurrences(
            of: #"source: URL(string: "https://notes.example/a")!"#,
            with: #"source: URL(string: "https://notes.example/a2")!"#)
        expected = expected.replacingOccurrences(
            of: ##"entryPattern: #"<h2>(?<version>[^<]+)</h2>(?<body>.*?)(?=<h2>|$)"#"##,
            with: ##"entryPattern: #"NEW"#"##)
        expected = expected.replacingOccurrences(
            of: ##"itemPatterns: [#"<li>(?<item>[^<]+)</li>"#, #"<p>(?<item>[^<,]+)</p>"#]"##,
            with: ##"itemPatterns: [#"ONE"#, #"TWO"#]"##)
        #expect(out == expected)
    }

    @Test func refusesWhatItCannotEditInPlace() {
        // A pattern held in a constant is shared; editing it would change others.
        #expect(throws: E.Failure.self) {
            try E.apply(.init(entryPattern: "x"), toChangelogAt: 1, count: 2,
                        bundleID: "a.b.beta", in: Self.family)
        }
        // The registry and the file disagree about which element is which.
        #expect(throws: E.Failure.self) {
            try E.apply(.init(entryPattern: "x"), toChangelogAt: 0, count: 3,
                        bundleID: "a.b", in: Self.family)
        }
        #expect(throws: E.Failure.self) {
            try E.apply(.init(entryPattern: "x"), toChangelogAt: 0, count: 2,
                        bundleID: "a.b.beta", in: Self.family)
        }
        // A comment inside a concatenation would be deleted by the rewrite.
        let commented = Self.family.replacingOccurrences(
            of: ##"entryPattern: #"<h2>(?<version>[^<]+)</h2>(?<body>.*?)(?=<h2>|$)"#"##,
            with: ##"entryPattern: #"<h2>(?<version>[^<]+)</h2>"# // the heading"## + "\n"
                + ##"                + #"(?<body>.*?)(?=<h2>|$)"#"##)
        #expect(commented != Self.family)
        #expect(throws: E.Failure.self) {
            try E.apply(.init(entryPattern: "x"), toChangelogAt: 0, count: 2,
                        bundleID: "a.b", in: commented)
        }
        // Without the comment the same concatenation is edited.
        #expect(throws: Never.self) {
            try E.apply(.init(entryPattern: "x"), toChangelogAt: 0, count: 2, bundleID: "a.b",
                        in: commented.replacingOccurrences(of: " // the heading", with: ""))
        }
        // A value that cannot be one line, or a URL that would need escaping.
        #expect(throws: E.Failure.self) {
            try E.apply(.init(entryPattern: "a\nb"), toChangelogAt: 0, count: 2,
                        bundleID: "a.b", in: Self.family)
        }
        #expect(throws: E.Failure.self) { try E.plainLiteralBody(#"https://x.example/a"b"#) }
        #expect(throws: E.Failure.self) { try E.plainLiteralBody(#"https://x.example/\(x)"#) }
        #expect(throws: E.Failure.self) { try E.plainLiteralBody("https://x.example/a b") }
    }

    /// The delimiter is the one place a value could break out of its literal:
    /// `"#` would end a `#"…"#` string early, and `\#(` would interpolate.
    @Test func picksADelimiterTheValueCannotEscape() throws {
        #expect(try E.rawLiteral("plain") == ##"#"plain"#"##)
        #expect(try E.rawLiteral(##"a"#b"##) == ###"##"a"#b"##"###)
        #expect(try E.rawLiteral(##"\#(boom)"##) == ###"##"\#(boom)"##"###)
        #expect(try E.rawLiteral(###"x"##y\#z"###) == ####"###"x"##y\#z"###"####)
        for value in [##"a"#b"##, ##"\#(boom)"##, ###"x"##y\#z"###, #"\d+ "quoted""#] {
            let literal = try E.rawLiteral(value)
            let scalars = Array(literal.unicodeScalars)
            #expect(E.stringLiteralValue(scalars, 0..<scalars.count) == value)
        }
    }

    /// Layout only, but a reviewer reads it: VMPal's pattern as the 2026-10-11
    /// dry run on the mini wrote it cut `(?<body>` in two.
    @Test func aLongPatternBreaksBeforeATagOrGroup() {
        let vmpal = #"<li[^>]*class="vp-release"[^>]*>.*?<h2[^>]*>\s*VMPal (?<version>\d+\.\d+(?:\.\d+)?)\s*</h2>(?:(?:(?!</li>).)*?<time[^>]*datetime="(?<date>[^"]+)")?.*?<div[^>]*class="vp-release-body"[^>]*>(?<body>.*?)</div>"#
        let pieces = E.chunks(of: vmpal)
        #expect(pieces.joined() == vmpal)
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.count <= E.chunkLength })
        for piece in pieces.dropFirst() {
            #expect(piece.hasPrefix("<") || piece.hasPrefix("("), "\(piece)")
        }
        for piece in pieces { #expect(!piece.hasSuffix("\\")) }
        // No natural break in reach: still cut, still whole.
        let flat = String(repeating: "a", count: 200)
        #expect(E.chunks(of: flat).joined() == flat)
        #expect(E.chunks(of: flat).allSatisfy { $0.count <= E.chunkLength })
    }

    /// Every changelog recipe in the repository, edited for real: either the edit
    /// lands exactly on the literal that holds the compiled value, or it is
    /// refused. Never a different place, never a silent partial edit.
    @Test func everyRealFamilyFileIsEditedExactlyOrRefused() throws {
        let recipes = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes")
        let probe = ##"PROBE"#\#(x)"##
        let longProbe = String(repeating: ##"<h2 class="x">(?<version>[0-9.]+)\\"#</h2>"##, count: 6)
        var edited = 0
        var refused: [String] = []
        for set in AppRecipeIndex.all {
            let text = try String(
                contentsOf: recipes.appendingPathComponent("\(set.family).swift"), encoding: .utf8)
            for (index, recipe) in set.changelogs.enumerated() where recipe.structuredFormat == nil {
                let out: String
                do {
                    out = try E.apply(
                        .init(entryPattern: probe), toChangelogAt: index,
                        count: set.changelogs.count, bundleID: recipe.bundleID, in: text)
                } catch {
                    refused.append("\(set.family)[\(index)]: \(error)")
                    continue
                }
                // Everything outside one literal is byte-identical, and that
                // literal held exactly the compiled value.
                let a = Array(text.unicodeScalars), b = Array(out.unicodeScalars)
                let written = Array(try E.rawLiteral(probe).unicodeScalars)
                // A concatenation is rewritten as one; the probe is short enough
                // to be a single piece either way.
                guard let at = (0...(b.count - written.count)).first(where: {
                    Array(b[$0..<($0 + written.count)]) == written
                }) else {
                    Issue.record("\(set.family)[\(index)]: the new literal is not in the output")
                    continue
                }
                let tail = b.count - (at + written.count)
                #expect(Array(a[..<at]) == Array(b[..<at]), "\(set.family)[\(index)]")
                #expect(Array(a[(a.count - tail)...]) == Array(b[(b.count - tail)...]), "\(set.family)[\(index)]")
                #expect(E.concatenatedValue(a, at..<(a.count - tail), code: try E.Scanner(a).kinds())
                        == recipe.entryPattern,
                        "\(set.family)[\(index)] replaced something other than its pattern")
                // A pattern long enough to be written as a concatenation, in the
                // same place, reads back whole.
                let long = try E.apply(
                    .init(entryPattern: longProbe), toChangelogAt: index,
                    count: set.changelogs.count, bundleID: recipe.bundleID, in: text)
                let c = Array(long.unicodeScalars)
                #expect(Array(c[..<at]) == Array(a[..<at]), "\(set.family)[\(index)]")
                #expect(E.concatenatedValue(c, at..<(c.count - tail), code: try E.Scanner(c).kinds())
                        == longProbe, "\(set.family)[\(index)]")
                edited += 1
            }
        }
        // 92 of 111 `entryPattern:` arguments were literals when this was written
        // (2026-10-11); the rest are shared constants. A collapse in this count
        // means the scanner stopped understanding the files, not that they moved.
        #expect(edited >= 85, "edited \(edited); refused:\n\(refused.joined(separator: "\n"))")
        // Each a shape the editor declines on purpose: a shared or composed
        // pattern, an element built by a helper (Cindy), a bundle id held in a
        // constant (Alfred).
        #expect(refused.allSatisfy {
            $0.contains("not a string literal") || $0.contains("is not a `ChangelogRecipe(…)` call")
                || $0.hasSuffix("'s")
        }, "\(refused)")
        print("RecipeLiteralEditorTests: \(edited) edited, \(refused.count) refused")
    }
}
