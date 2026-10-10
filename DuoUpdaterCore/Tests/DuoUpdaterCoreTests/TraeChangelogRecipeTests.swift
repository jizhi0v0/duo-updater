import Testing
import Foundation
@testable import DuoUpdaterCore

/// TRAE's docs changelog read by `.traeDocsChangelog`. The recipe comes from the
/// registry, not restated.
struct TraeChangelogRecipeTests {

    /// `https://docs.trae.ai/ide/changelog`, 2026-10-10. The ops are the page's own
    /// (re-serialized, each op's `anchor` and `grammarly-data` attributes dropped):
    /// the intro line, the two newest entries, and 3.5.51's, which has every shape
    /// the page uses — a version line split over three ops, bold, inline code,
    /// mentions, nested bullets and an indented line. The path to them is the
    /// real one with every sibling cut; `notice` is one of the page's callout
    /// boxes, also a delta, as served.
    private static let page = #"""
        <!DOCTYPE html><html><head><title>Changelog - TRAE</title></head><body><div id="root"></div>
        <script>window._ROUTER_DATA = {"loaderData":{"layout":{"docDetail":{"content":{"children":[{"children":[{"children":[{"props":{"value":{"t":{"0":{"ops":[
        {"insert":"This article records the changes to TRAE.\n"},
        {"attributes":{"heading":"h2","lmkr":"1"},"insert":"*"},
        {"insert":"October 08, 2026 (Feature Release)\n"},
        {"attributes":{"lmkr":"1"},"insert":"*"},
        {"insert":"TRAE v3.6.0 is released. Below is a summary of the updates:\n"},
        {"attributes":{"list":"bullet1","lmkr":"1"},"insert":"*"},
        {"insert":"Launched the Agent window, which is an agent-centric global workspace for orchestrating multiple agents across projects from a single window. It supports cloud tasks and scheduled tasks, with centralized management of outputs such as code, documents, presentations, images, and videos. You can switch freely between the Agent window and IDE window, with data synchronized automatically. For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"aaebb4c7-0ac6-406f-b5cf-e111e98b88c8\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Fget-started-with-the-agent-window\",\"type\":1,\"title\":\"Get started with the Agent window\",\"token\":\"6ab4dba7793c00050c7d3aae\",\"displayMode\":\"inline\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"lmkr":"1","list":"bullet1"},"insert":"*"},
        {"insert":"Supported connecting directly to a directory on a remote host from the Agent window. You can use the directory as your working directory and run tasks in the remote environment. For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"25247d33-1896-461b-b5fd-8673e2f5f242\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Fssh-remote\",\"type\":1,\"title\":\"Remote development using SSH\",\"token\":\"67ced569b5c83404a68c13ac\",\"displayMode\":\"inline\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"lmkr":"1","list":"bullet1"},"insert":"*"},
        {"insert":"Supported for mounting multiple paths to a single project. Tasks are organized by project, while the file tree and global search work across projects, making multi-repository development more convenient.\n"},
        {"attributes":{"lmkr":"1","list":"bullet1"},"insert":"*"},
        {"insert":"Added a desktop companion robot that stays on your desktop, enabling you to start tasks and track agent progress without opening the main window. For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"9de5899f-9ca5-46fc-b0d1-056336f2fc1a\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Fdesktop-companion-robot\",\"type\":1,\"title\":\"Desktop companion robot\",\"token\":\"6ab4de71dafd4c04b415a3d1\",\"displayMode\":\"inline\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"lmkr":"1","heading":"h2"},"insert":"*"},
        {"insert":"September 20, 2026 (Feature Release)\n"},
        {"attributes":{"lmkr":"1"},"insert":"*"},
        {"insert":"TraeCode v3.5.97 ~ 3.5.104 are released. Below is a summary of the updates:\n"},
        {"attributes":{"lmkr":"1","list":"bullet1","start":"2","origin-start":"2","ol-id":"ti08Djgm"},"insert":"*"},
        {"insert":"Launched the Marketplace, which offers specialized plugins for a wide range of use cases, including development tools, productivity, content creation, and more.. For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"606c4ee8-f69f-41ec-9999-c06c1a146706\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Fmarketplace\",\"type\":1,\"title\":\"Plugin marketplace\",\"token\":\"6ab4dd064c7cfa055b12814f\",\"displayMode\":\"inline\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"lmkr":"1","list":"bullet1","start":"2","origin-start":"2","ol-id":"ti08Djgm"},"insert":"*"},
        {"insert":"Fixed known issues.\n"},
        {"attributes":{"lmkr":"1","heading":"h2"},"insert":"*"},
        {"insert":"April 14, 2026 (Feature Release)\n"},
        {"attributes":{"lmkr":"1"},"insert":"*"},
        {"insert":"TRAE v3.5.51 "},
        {"insert":"is"},
        {"insert":" released. Below is a summary of the updates:\n"},
        {"attributes":{"list":"bullet1","lmkr":"1"},"insert":"*"},
        {"insert":"Optimized the execution of RunCommand tool.\n"},
        {"attributes":{"lmkr":"1","list":"bullet1","start":"1","origin-start":"1"},"insert":"*"},
        {"insert":"Optimized the rules feature:\n"},
        {"attributes":{"lmkr":"1","list":"bullet2","start":"1","origin-start":"1"},"insert":"*"},
        {"attributes":{"bold":"true"},"insert":"Supported rule nesting"},
        {"insert":": You can create subfolders in the "},
        {"attributes":{"inlineCode":"true"},"insert":".trae/rules/"},
        {"insert":" directory to categorize rules. The system automatically reads rule directories recursively up to 3 levels. For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"40b3b90a-2af4-4925-a22d-f6d881f117a4\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Frules\",\"type\":1,\"title\":\"Rules\",\"token\":\"680364db550a99048daf2eb0\",\"displayMode\":\"inline\",\"hashTitle\":\"About multi-level rule nesting\",\"hash\":\"449bd6ba\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"list":"bullet2","lmkr":"1","start":"1","origin-start":"1"},"insert":"*"},
        {"attributes":{"bold":"true"},"insert":"Supported creating rules in subdirectories"},
        {"insert":": You can create a "},
        {"attributes":{"inlineCode":"true"},"insert":".trae/rules/"},
        {"insert":" folder in any subdirectory of your project to configure rules specific to that module. The system automatically applies these rules when you mention files in that directory or when the AI reads those files. For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"7a830098-8122-47cd-b26d-8248e6b5ba95\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Frules\",\"type\":1,\"title\":\"Rules\",\"token\":\"680364db550a99048daf2eb0\",\"displayMode\":\"inline\",\"hashTitle\":\"About creating rules for subdirectories\",\"hash\":\"8ab99242\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"lmkr":"1","text-indent":"true","start":"1","origin-start":"1","list":"bullet1"},"insert":"*"},
        {"insert":"Added a button for directing you to configure Git commit message generation rules:\n"},
        {"attributes":{"lmkr":"1","list":"bullet2","start":"1","origin-start":"1"},"insert":"*"},
        {"insert":"In the drop-down menu of the Source Control panel, you can click \"Configure Commit Message Generation Rules\" to open the rule file where you can configure the rules for generating Git commit messages.\n"},
        {"attributes":{"lmkr":"1","list":"bullet2","start":"1","origin-start":"1"},"insert":"*"},
        {"insert":"When you use the AI to generate a Git commit message for the first time, the system displays a rule configuration prompt.\n"},
        {"attributes":{"list":"indent1","lmkr":"1","text-indent":"true"},"insert":"*"},
        {"insert":"For more information, refer to "},
        {"attributes":{"dataMetaBlockProps":"{\"blockId\":\"05f3261c-a70c-4828-a22c-faeaa47db978\",\"blockType\":\"mentionBlock\",\"props\":{\"link\":\"%2Fide%2Frules\",\"type\":1,\"title\":\"Rules\",\"token\":\"680364db550a99048daf2eb0\",\"displayMode\":\"inline\",\"hashTitle\":\"Set rules for Git commit messages\",\"hash\":\"495aa799\"},\"initData\":\"%7B%7D\"}"},"insert":" "},
        {"insert":".\n"},
        {"attributes":{"lmkr":"1","list":"bullet1","start":"1","origin-start":"1"},"insert":"*"},
        {"insert":"Supported the full OAuth authorization flow for MCP servers, including authorization, execution, invocation, and revocation.\n"},
        {"attributes":{"lmkr":"1","list":"bullet1","start":"1","origin-start":"1"},"insert":"*"},
        {"insert":"Supported configuring custom request URLs for custom models.\n"}
        ]}}}}}]}]}]}},"notice":{"props":{"value":{"t":{"0":{"ops":[{"insert":"Resources are currently limited, so responses may be delayed occasionally. We are working hard to scale up resources.\n"}]}}}}}}},"errors":null}</script></body></html>
        """#

    private static func decode(_ body: String = page, maxEntries: Int? = 40) -> Changelog? {
        StructuredChangelogDecoder.decode(
            body, format: .traeDocsChangelog, channel: nil, maxEntries: maxEntries)
    }

    @Test func theRecipeReadsTheDocsPage() throws {
        let matches = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == "com.trae.app" }
        try #require(matches.count == 1)
        #expect(matches[0].source.absoluteString == "https://docs.trae.ai/ide/changelog")
        #expect(matches[0].structuredFormat == .traeDocsChangelog)
    }

    /// The heading is the date, verbatim; a range is named by its last build.
    @Test func entriesAreTheDatedHeadings() throws {
        let changelog = try #require(Self.decode())
        #expect(changelog.entries.map(\.version) == ["3.6.0", "3.5.104", "3.5.51"])
        #expect(changelog.entries.map(\.date) == [
            "October 08, 2026 (Feature Release)",
            "September 20, 2026 (Feature Release)",
            "April 14, 2026 (Feature Release)",
        ])
        #expect(try #require(Self.decode(maxEntries: 1)).entries.map(\.version) == ["3.6.0"])
    }

    /// A mention reads as its title, so the sentence ends the way the page shows it.
    /// Mutation: keep the op's own insert (a space) and this reads "refer to  .".
    @Test func aMentionReadsAsItsTitle() throws {
        let newest = try #require(Self.decode()?.entries.first)
        #expect(newest.items.count == 4)
        #expect(newest.items[1] == "Supported connecting directly to a directory on a remote host from the Agent window. You can use the directory as your working directory and run tasks in the remote environment. For more information, refer to Remote development using SSH.")
    }

    /// Bold, inline code and a mention in one bullet stay one line; a nested
    /// bullet is a line of its own after its parent; the indented line is kept.
    @Test func aRunOfOpsIsOneLine() throws {
        let entry = try #require(Self.decode()?.entries.last)
        #expect(entry.items.count == 10)
        #expect(entry.items[1] == "Optimized the rules feature:")
        #expect(entry.items[2] == "Supported rule nesting: You can create subfolders in the .trae/rules/ directory to categorize rules. The system automatically reads rule directories recursively up to 3 levels. For more information, refer to Rules.")
        #expect(entry.items[7] == "For more information, refer to Rules.")
        #expect(entry.items[9] == "Supported configuring custom request URLs for custom models.")
    }

    /// Each version shape the live page uses (2026-10-10), through the decoder.
    @Test func everyRangeSpellingNamesItsLastBuild() throws {
        let lines = [
            "TRAE v3.5.80 is released. Below is a summary of the updates:": "3.5.80",
            "TRAE 3.5.73 is released. Below is a summary of the updates:": "3.5.73",
            "TraeCode v3.5.97 ~ 3.5.104 are released. Below is a summary of the updates:": "3.5.104",
            "TRAE v3.5.64 ～ 3.5.65 is released. Below is a summary of the updates:": "3.5.65",
            "TRAE v3.5.4 & v3.5.5 is released. Below is a summary of the updates:": "3.5.5",
            "TRAE v3.5.1 and 3.5.2 are released. Below is a summary of the updates:": "3.5.2",
        ]
        for (line, version) in lines {
            #expect(Self.decode(Self.document(line: line))?.entries.first?.version == version, "\(line)")
        }
    }

    /// A heading with no version line under it is left out, not given a made-up
    /// version; a page that is not this shape is nil, so the pane embeds it.
    @Test func whatCannotBeReadIsLeftOut() throws {
        let noVersion = Self.document(line: "Below is a summary of the updates:")
        #expect(Self.decode(noVersion) == nil)
        #expect(Self.decode("<html><body>Loading…</body></html>") == nil)
        #expect(Self.decode("<script>window._ROUTER_DATA = {\"loaderData\":{}}</script>") == nil)
    }

    private static func document(line: String) -> String {
        let ops: [[String: Any]] = [
            ["attributes": ["lmkr": "1", "heading": "h2"], "insert": "*"],
            ["insert": "July 23, 2026 (Hotfix)\n"],
            ["attributes": ["lmkr": "1"], "insert": "*"],
            ["insert": line + "\n"],
            ["attributes": ["lmkr": "1", "list": "bullet1"], "insert": "*"],
            ["insert": "Fixed known issues.\n"],
        ]
        let root: [String: Any] = ["loaderData": ["doc": ["ops": ops]]]
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        return "<script>window._ROUTER_DATA = \(json)</script>"
    }
}
