import Foundation
import Testing
@testable import DuoUpdaterCore

/// Mayoi: the history comes from the repo's `CHANGELOG.md`. Excerpts of the real
/// file (sorrycc/Mayoi `main`, 2026-10-19), keeping the hard wrapping and the
/// angle-bracket placeholders the notes are written with.
struct MayoiChangelogRecipeTests {
    private static let changelog = """
    # Changelog

    The update window shows the section of the version it offers. Every release
    needs a `## <version>` section here, or its build fails.

    ## Unreleased

    - A project's square dragged along the rail goes where it is dropped
      again, before the square under the pointer, not always at the end.

    ## 0.10.0

    - macOS: files and folders dropped on the Dock icon open, as `mayoi
      <path>` opens them, and Mayoi is in the Finder's **Open With** menu

    ## 0.3.2

    - Folders open from the Finder. A folder dropped on a window opens as `mayoi <dir>` opens
      it.

    ## 0.3.1

    - The disk images and Windows installers of a release are named
      `Mayoi.<version>.<arch>.dmg` and `Mayoi.Setup.<version>.<arch>.exe`.
    - Second item.
    """

    private static func entries() throws -> [String: [String]] {
        let recipe = try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == "dev.mayoi.editor" })
        let log = try #require(ChangelogService.parse(recipe, body: changelog))
        return Dictionary(uniqueKeysWithValues: log.entries.map { ($0.version, $0.items) })
    }

    @Test func oneEntryPerReleaseAndNoneForUnreleased() throws {
        let entries = try Self.entries()
        #expect(Set(entries.keys) == ["0.10.0", "0.3.2", "0.3.1"])
        #expect(entries["0.3.1"]?.count == 2)
    }

    /// The placeholders are the words these sentences are about. Mutation that
    /// turns this red: leaving `stripTags` on, whose `<[^>]+>` sweep deletes them.
    @Test func angleBracketPlaceholdersSurvive() throws {
        let entries = try Self.entries()
        let joined = entries.values.flatMap { $0 }.joined(separator: "\n")
        for placeholder in ["<version>", "<arch>", "<dir>", "<path>"] {
            #expect(joined.contains(placeholder), "lost \(placeholder)")
        }
    }

    /// A hard-wrapped item stays one item.
    @Test func wrappedItemsStayWhole() throws {
        let item = try #require(Self.entries()["0.3.1"]?.first)
        #expect(item.contains("named"))
        #expect(item.contains(".exe"))
    }

    /// 0.10.0 wraps inside a code span (`` `mayoi\n  <path>` ``). CommonMark
    /// reads that line ending as a space, so the span is still code and loses
    /// its backticks like a one-line span does.
    @Test func inlineCodeWrappedAcrossALineIsUnwrapped() throws {
        let item = try #require(Self.entries()["0.10.0"]?.first)
        #expect(item == "macOS: files and folders dropped on the Dock icon open, as mayoi <path> opens them, and Mayoi is in the Finder's **Open With** menu")
    }

    /// A blank line ends the paragraph, so a backtick before it never pairs with
    /// one after it.
    @Test func inlineCodeNeverPairsAcrossABlankLine() {
        let text = "run `a\n\nb` now"
        #expect(ChangelogExtractor.unwrapMarkdownInlineCode(text) == text)
        #expect(ChangelogExtractor.unwrapMarkdownInlineCode("run ``a\n \nb`` now") == "run ``a\n \nb`` now")
    }
}
