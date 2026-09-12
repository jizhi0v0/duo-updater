import Foundation

/// Parses a GitHub release body (GitHub-flavored Markdown) into a structured
/// `Changelog`. Handles both hand-written bodies and the auto-generated
/// "What's Changed" format GitHub produces from pull requests.
///
/// Auto-generated bodies look like:
///   ## What's Changed
///   * Fix X by @user in https://github.com/owner/repo/pull/123
///   ## New Contributors
///   * @user made their first contribution ...
///   **Full Changelog**: https://github.com/...
///
/// Hand-written bodies use arbitrary section headings and bullet styles.
/// Both go through the same pipeline — bullets are extracted, contributor-
/// noise sections are skipped, and the "by @user in URL" suffix is stripped.
///
/// If you're changing what this file extracts (not just adding support for a
/// new vendor shape), bump `Changelog.parserGeneration` — see its doc comment.
/// A `Changelog` this parser produces can be written to EITHER of the two
/// cross-launch disk caches that persist one — `ChangelogDiskCache` (via
/// `StructuredChangelogDecoder`, for the `.gitHubReleases`/`.zedGitHubReleases`
/// recipe formats) and `BrewFormulaReleaseService`'s own on-disk cache (this file
/// called directly, for Homebrew formula release notes) — and served, unre-parsed,
/// to a user on a version their notes were already cached for; without the bump,
/// this fix never reaches them.
public enum GitHubMarkdownParser {

    /// Parse a single release body into a `Changelog` with one entry, or nil
    /// when the body contains no extractable bullet items.
    ///
    /// Two passes. The strict pass (original behavior) takes only top-level
    /// `-`/`*`/`+` bullets. ONLY when that finds nothing do we retry leniently —
    /// also accepting indented bullets and numbered lists, and skipping fenced code
    /// blocks. Gating the lenient pass on an empty strict result means every body
    /// that already parsed is byte-for-byte unchanged (no regression for the GitHub
    /// apps that share this parser); the lenient pass purely rescues bodies that
    /// would otherwise fall back to a raw web view — e.g. nvm's space-indented
    /// `- ` lists, or any project that writes its notes as a numbered list.
    ///
    /// A THIRD pass, prose, runs only when both bullet passes come back empty: a
    /// release whose notes are written as sentences rather than a list. Returning
    /// nil for those was a real hole — for a multi-release source it drops that
    /// version out of the rail entirely, so a user sitting on exactly that build
    /// finds no entry for their own version (Zed's `v1.5.3-pre`, "No public-facing
    /// changes in this release.", is the live case; Waku's `v0.1.9`, "See
    /// CHANGELOG.md for details.", is another). Gated the same way the lenient pass
    /// is, so no body that already parsed changes at all.
    ///
    /// `skipSections` is the per-recipe escape hatch (`ChangelogRecipe.skipSections`)
    /// for a vendor who puts boilerplate under a heading of their own. Unlike
    /// `skippedSectionKeywords`, which is a substring rule applied to EVERY app,
    /// these are matched whole — case-insensitively, after trimming — against one
    /// app's headings, so a heading that merely resembles one is untouched. Empty
    /// by default, and an empty list is byte-for-byte the old behavior.
    ///
    /// A category heading (`### Added`, `### Fixed`, …) survives into the returned
    /// entry's `content` as a `.heading` block — but only when `qualifyingHeadings`
    /// says so (see that function's doc comment for the rule and the measurement
    /// behind it); a recipe's own `skipSections`/`skippedSectionKeywords` still
    /// name a heading as boilerplate first, same as before. Everything else is
    /// dropped exactly as it always was (never folded into `items` either way —
    /// see `Changelog.Entry.items`'s doc comment). `items` itself is completely
    /// unaffected: a heading was never one of its lines before this and still isn't.
    public static func parse(
        body: String, version: String, date: String?, skipSections: [String] = []
    ) -> Changelog? {
        var (items, content) = extractItems(from: body, lenient: false, skipSections: skipSections)
        if items.isEmpty {
            (items, content) = extractItems(from: body, lenient: true, skipSections: skipSections)
        }
        if items.isEmpty {
            (items, content) = proseItems(from: body, skipSections: skipSections)
        }
        guard !items.isEmpty else { return nil }
        let entry = Changelog.Entry(version: version, date: date, items: items, content: content)
        // The body is Markdown and the items keep their inline syntax — say so,
        // or the renderer prints `**bold**` and `[text](url)` verbatim.
        return Changelog(entries: [entry], itemSyntax: .markdown)
    }

    // MARK: - Internals

    private static let skippedSectionKeywords = [
        "new contributors", "contributors", "full changelog",
    ]

    /// The heading text of a `## Heading` / `### Heading` line, verbatim (original
    /// case) and trimmed — nil for any other line. One place, so every caller
    /// (the bullet passes, the prose pass, and `qualifyingHeadings`) agrees on
    /// what counts as a heading; each lowercases the result itself where a
    /// case-insensitive comparison is what it needs.
    private static func headingRawText(of trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix("#") else { return nil }
        return trimmedLine
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)
    }

    /// A heading that contains a digit reads as restating a version or build
    /// number rather than naming a change category, and styling it draws a
    /// second "version" next to the rail that already shows one — confusing,
    /// not informative. Real, measured examples (fetched 2026-09-12, 30 releases
    /// each across the 10 repos already routed through this parser): UTM's
    /// `Changes (v5.0.4)` (a DIFFERENT release folded into this one's body),
    /// Rockxy's `Rockxy 0.38.3 (build 58)` (this release's own version, restated),
    /// AnythingLLM's `AnythingLLM v1.8.0 | MCP tools & a fresh new look!`, and
    /// CotEditor's `Changes in 7.0.8 (unreleased)`. None of the ~90 distinct real
    /// category headings the same sweep found (`Added`, `Fixed`, `Improvements`,
    /// `Bug Fixes`, `Known Issues`, dozens of vendor-specific ones like `Model
    /// Router: The First Consumer Hybrid AI Experience`) contain a digit, so this
    /// single rule separates the two groups cleanly on every body sampled — see
    /// `Changelog.parserGeneration`'s generation-3 entry.
    private static func isVersionLikeHeading(_ heading: String) -> Bool {
        heading.range(of: #"[0-9]"#, options: .regularExpression) != nil
    }

    /// This release body's headings worth styling as `.heading` blocks: not
    /// boilerplate (`skippedSectionKeywords`/`extraSkipKeywords`/a recipe's own
    /// `skipSections`), not version-like (`isVersionLikeHeading`), AND — because a
    /// GitHub release body is not Keep a Changelog and ranges from real categories
    /// (CotEditor's `Improvements`/`Fixes`) to one heading restating the pane
    /// (Shotbase's "What's new", measured always exactly 0 or 1 per release across
    /// 13 fetched) to 38 headings in one body (Headlamp, though it never reaches
    /// this parser — its recipe reads raw JSON with its own regexes) — only when
    /// there are at least 2 such headings in this one body. Below that threshold a
    /// heading is exactly as invisible as it always was: dropped, never folded
    /// into `items`, not shown at all.
    ///
    /// Returns the qualifying headings' raw (non-lowercased) text, since that's
    /// what a `.heading` block displays and membership only needs a set. A
    /// heading repeated in one body (CotEditor's beta releases list an
    /// "unreleased" sub-range with its own `Improvements`/`Fixes`) qualifies at
    /// every occurrence once its text is in the set — each occurrence still
    /// counts toward the ≥2 threshold too, because this counts total headings
    /// found, not distinct names.
    ///
    /// Mostly independent of the strict/lenient/prose split below: all three
    /// encounter the same `#`-prefixed lines the same way, EXCEPT that the strict
    /// bullet pass (`extractItems(lenient: false, …)`) never tracks fenced code
    /// blocks at all — its own `inCodeBlock` toggle is gated on `lenient` — so a
    /// heading-shaped line inside a fence is a heading to it. `tracksCodeFences`
    /// mirrors that per-pass rule so this scan's candidate count and code-fence
    /// state can never disagree with the pass that actually wins.
    private static func qualifyingHeadings(
        in body: String, skipSections: [String], extraSkipKeywords: [String] = [],
        tracksCodeFences: Bool = true
    ) -> Set<String> {
        var candidates: [String] = []
        var inCodeBlock = false
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if tracksCodeFences, trimmed.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if tracksCodeFences, inCodeBlock { continue }
            guard let raw = headingRawText(of: trimmed) else { continue }
            let lowered = raw.lowercased()
            if skippedSectionKeywords.contains(where: { lowered.contains($0) }) { continue }
            if extraSkipKeywords.contains(where: { lowered.contains($0) }) { continue }
            if isSkipped(lowered, by: skipSections) { continue }
            if isVersionLikeHeading(raw) { continue }
            candidates.append(raw)
        }
        return candidates.count >= 2 ? Set(candidates) : []
    }

    /// Whole-heading, case-insensitive match against a recipe's own `skipSections`.
    /// Deliberately NOT a substring test: BetterDisplay's roster headings
    /// ("Included Localizations", "Localizations included in this release") sit one
    /// release away from "Localization Improvements", which carries real changes —
    /// a substring rule wide enough to catch the first two eats the third.
    private static func isSkipped(_ heading: String, by skipSections: [String]) -> Bool {
        guard !skipSections.isEmpty else { return false }
        return skipSections.contains {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == heading
        }
    }

    /// Extra headings the lenient pass skips: release bodies that aren't bullet
    /// changelogs often still carry a checksum/hash block, which we never want as
    /// "change items".
    private static let lenientExtraSkipKeywords = [
        "sha256", "sha-256", "sha1", "md5", "checksum", "hashes", "artifacts",
    ]

    /// Sentences from a release body that contains no list at all, in document
    /// order. Deliberately conservative about what it drops, because at this point
    /// the alternative is showing the user nothing:
    ///
    ///   - headings and fenced code blocks (same as the bullet passes);
    ///   - a line that is only an image or a badge — LuLu opens its notes with a
    ///     `[![](shields.io/...)](...)` sponsor banner, which as an "item" is a URL
    ///     the reader cannot use;
    ///   - a checksum: both the `🔐 Disk Image Hash (SHA256):` label line and the
    ///     `file.dmg: <64 hex>` line under it. Neither is a change.
    ///
    /// Everything else is kept verbatim, including Markdown links — the entry is
    /// emitted with `.markdown` syntax, so they render rather than showing as raw
    /// brackets.
    ///
    /// Two hard bails, both of which mean "this is a shape I don't understand, and
    /// showing part of it as bullets is worse than not converting at all":
    ///
    ///   - a Markdown TABLE. Headlamp writes its whole changelog as tables — 142
    ///     table rows in v0.45.0 — and line-by-line that renders as bullets reading
    ///     `|:--|--:|` and `| <img src="…">`, next to download links for other
    ///     platforms. Verified against the live release before this guard existed.
    ///   - more than `proseItemCap` lines. Prose notes are a sentence or a handful;
    ///     dozens of lines means real structure this pass is misreading. Not a
    ///     display limit — the entry is abandoned, not truncated, so the caller
    ///     falls back to the renderer that shows the body whole.
    private static let proseItemCap = 12

    private static func proseItems(
        from body: String, skipSections: [String] = []
    ) -> (items: [String], content: [Changelog.Entry.Block]) {
        guard body.range(of: #"(?m)^\s*\|"#, options: .regularExpression) == nil
        else { return ([], []) }
        let qualifying = qualifyingHeadings(in: body, skipSections: skipSections)
        var items: [String] = []
        var content: [Changelog.Entry.Block] = []
        var inCodeBlock = false
        var inSkippedSection = false
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCodeBlock.toggle(); continue }
            // A recipe-declared section is skipped here too, so a vendor who writes
            // their boilerplate as prose is handled the same as one who bullets it.
            // Gated on a non-empty list, so the default path is unchanged.
            if !inCodeBlock, let raw = headingRawText(of: trimmed) {
                inSkippedSection = isSkipped(raw.lowercased(), by: skipSections)
                if !inSkippedSection, !qualifying.isEmpty, qualifying.contains(raw) {
                    content.append(.heading(raw))
                }
                continue
            }
            if inCodeBlock || inSkippedSection || trimmed.isEmpty { continue }
            if isImageOnly(trimmed) || isBareURL(trimmed) || isChecksum(trimmed) { continue }
            if skippedSectionKeywords.contains(where: {
                trimmed.lowercased().hasPrefix("**\($0)")
            }) { continue }
            items.append(trimmed)
            if !qualifying.isEmpty { content.append(.note(trimmed)) }
            if items.count > proseItemCap { return ([], []) }
        }
        return (items, qualifying.isEmpty ? [] : content)
    }

    /// A line that is nothing but a URL. Not a change description — the same
    /// reasoning as the image-only skip. Caught by an existing test: an
    /// azure-cli-style body of "a bare link, a SHA256 heading, a hash code block"
    /// must still yield nothing, and without this the bare link became its one
    /// "change". A sentence that merely CONTAINS a URL is untouched (kitty's notes
    /// are exactly that), because the whole line has to be the URL.
    private static func isBareURL(_ line: String) -> Bool {
        line.range(of: #"^<?https?://\S+>?$"#, options: .regularExpression) != nil
    }

    /// A line whose entire content is one image, optionally wrapped in a link —
    /// in either spelling. GitHub release bodies are Markdown but accept raw HTML,
    /// and vendors use both: LuLu opens with a Markdown `[![](shields.io/…)](…)`
    /// sponsor banner, BetterDisplay closes every release with an HTML
    /// `<a href="…dmg"><img src="…" alt="Download for macOS"/></a>` button. Neither
    /// is a change, and as an "item" both are markup the reader cannot use — the
    /// HTML one worse, since it reaches the pane as literal angle brackets.
    private static func isImageOnly(_ line: String) -> Bool {
        line.range(
            of: #"^\[?!\[[^\]]*\]\([^)]*\)\]?(\([^)]*\))?$"#,
            options: .regularExpression) != nil
        || line.range(
            of: #"^(?:<a\b[^>]*>\s*)?<img\b[^>]*/?>(?:\s*</a>)?$"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A checksum label (`… SHA256 …:`) or a line carrying a 32+ character hex run.
    private static func isChecksum(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasSuffix(":"),
           lenientExtraSkipKeywords.contains(where: { lower.contains($0) }) {
            return true
        }
        return line.range(of: #"\b[0-9a-fA-F]{32,}\b"#, options: .regularExpression) != nil
    }

    private static func extractItems(
        from body: String, lenient: Bool, skipSections: [String] = []
    ) -> (items: [String], content: [Changelog.Entry.Block]) {
        let lines = body.components(separatedBy: .newlines)
        let skipKeywords = lenient ? skippedSectionKeywords + lenientExtraSkipKeywords
                                   : skippedSectionKeywords
        let qualifying = lenient
            ? qualifyingHeadings(in: body, skipSections: skipSections, extraSkipKeywords: lenientExtraSkipKeywords)
            : qualifyingHeadings(in: body, skipSections: skipSections, tracksCodeFences: false)
        var items: [String] = []
        var content: [Changelog.Entry.Block] = []
        var inSkippedSection = false
        var inCodeBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block (lenient only): skip its contents so a release's
            // SHA256 table or example snippet isn't mistaken for change items.
            if lenient, trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }

            // Section heading: ## Title or ### Title
            if let raw = headingRawText(of: trimmed) {
                let heading = raw.lowercased()
                inSkippedSection = skipKeywords.contains(where: { heading.contains($0) })
                    || isSkipped(heading, by: skipSections)
                if !inSkippedSection, !qualifying.isEmpty, qualifying.contains(raw) {
                    content.append(.heading(raw))
                }
                continue
            }

            if inSkippedSection { continue }

            if lenient {
                // Indented bullets and numbered lists count too. Safe here because
                // the strict pass already came up empty, so there are no top-level
                // items for an indented line to be a duplicate sub-detail of.
                if let raw = bulletContent(from: trimmed) ?? numberedContent(from: trimmed) {
                    let cleaned = cleanItem(raw)
                    if cleaned.count >= 6 {
                        items.append(cleaned)
                        if !qualifying.isEmpty { content.append(.note(cleaned)) }
                    }
                }
            } else {
                // Bullet: `- text`, `* text`, `+ text`.
                // Skip any indented sub-bullet — a leading space or tab marks PR-body
                // detail that usually duplicates the top-level item. (Checked on the
                // raw line; `trimmed` below has the indentation stripped.)
                guard let first = line.first, first != " ", first != "\t" else { continue }

                if let raw = bulletContent(from: trimmed) {
                    let cleaned = cleanItem(raw)
                    // Drop very short items (emoji-only, single-word, link-only lines).
                    if cleaned.count >= 6 {
                        items.append(cleaned)
                        if !qualifying.isEmpty { content.append(.note(cleaned)) }
                    }
                }
            }
        }

        return (items, qualifying.isEmpty ? [] : content)
    }

    /// A numbered-list item's text: "1. text" / "12) text" → "text". nil otherwise.
    private static func numberedContent(from line: String) -> String? {
        guard let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else { return nil }
        return String(line[r.upperBound...])
    }

    private static func bulletContent(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] {
            if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
        }
        return nil
    }

    /// Strip the "by @user in https://..." suffix GitHub appends to auto-generated
    /// PR-merge entries so only the human-readable change title remains.
    private static func cleanItem(_ item: String) -> String {
        var s = item

        // "Something by @user in https://github.com/owner/repo/pull/123"
        if let r = s.range(of: #"\s+by\s+@\S+\s+in\s+https?://\S+"#, options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }

        // Trailing bare PR reference: " (#1234)"
        if let r = s.range(of: #"\s+\(#\d+\)\s*$"#, options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }

        return s.trimmingCharacters(in: .whitespaces)
    }
}
