import Foundation

enum com_github_CopilotForXcode {
    static let set = AppRecipeSet(
        family: "com-github-CopilotForXcode",
        changelogs: [
        // GitHub Copilot for Xcode — the Sparkle feed carries no notes on any of
        // its 12 items, and the GitHub release bodies are a single sentence
        // ("Release 0.51.0 of Copilot extension for Xcode"). The real notes are
        // the repo's Keep-a-Changelog file:
        //
        //   ## 0.51.0 - August 12, 2026
        //   ### Added
        //   - Support for Kimi K3 through the updated Copilot language server.
        //
        // `(?:^|\n)##`, not `^##` and not `\n##`: `ChangelogExtractor` compiles
        // with `.dotMatchesLineSeparators` but NOT `.anchorsMatchLines`, so `^`
        // matches ONLY the start of the document — which is why `\n` is needed for
        // the headings, and why `^` has to stay for the one case `\n` cannot see.
        // The file opens with a `# Changelog` preamble today, so every `##` does
        // follow a newline; drop that preamble and a bare `\n##` would silently
        // lose the FIRST entry — the newest release's notes — while every older
        // one kept rendering. `markdownSource` because the
        // items carry inline code (`/v1/messages`) and `[text](url)` links that a
        // plain renderer would otherwise print as punctuation. The `### Added` /
        // `### Fixed` group headings are dropped — only the `- ` bullets become
        // items. 21 entries parse from the live file (2026-08-31), head 0.51.0.
        ChangelogRecipe(
            bundleID: "com.github.copilotforxcode",
            source: URL(string: "https://raw.githubusercontent.com/github/CopilotForXcode/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##\s+(?<version>[0-9][^\s]*)\s*-\s*(?<date>[^\n]+)\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n-\s+(?<item>[^\n]+)"#],
            markdownSource: true),
        ])
}
