import Foundation

enum com_postmanlabs_mac {
    static let set = AppRecipeSet(
        family: "com-postmanlabs-mac",
        probes: [
        // Postman — CDN JSON that also powers the ChangelogRecipe. The "notes"
        // array is sorted newest-first, so the first "version" field is always
        // the latest release. We install in place: `dl.pstmn.io/download/version/
        // <ver>/osx_arm64` serves the official notarized zip (Postman.app, Team
        // H7H8Q7M5CK — the same Team the installed app verifies against), with no
        // WAF. Postman self-updates via Squirrel too, but we fetch the *same*
        // latest build from its own CDN, so this never crosses channels or
        // downgrades. If the URL can't be built, it degrades to the downloads
        // page. arm64-only, matching the other recipes' Apple-silicon endpoints.
        VendorProbeRecipe(
            bundleID: "com.postmanlabs.mac",
            url: URL(string: "https://mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json")!,
            mode: .responseBody,
            versionPattern: #""notes"\s*:\s*\[\s*\{[^}]*"version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.postman.com/downloads/"),
            changelogURL: URL(string: "https://www.postman.com/release-notes/postman-app/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dl.pstmn.io/download/version/{0}/osx_arm64",
                    fields: [#""notes"\s*:\s*\[\s*\{[^}]*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#]),
                kind: .zip)),
        ],
        changelogs: [
        // Postman — CDN-hosted JSON array under the "notes" key (newest-first).
        // Each element has "version", "content" (Markdown; `\r\n` line separators in
        // recent entries, bare `\n` in older ones) and "createdAt" (ISO-8601).
        // Structured decode (StructuredChangelogDecoder.decodePostman): split
        // `content` on real newlines, strip the `#### ` feature-heading prefix
        // (keeping the heading text as an item), skip `##`/`###` section headers and
        // the "August 21, 2026"-style date line, drop lines under 10 chars, keep
        // everything else (including markdown syntax like `**bold**` / `[t](url)`
        // verbatim — nothing downstream strips it for this recipe). This replaces a
        // regex itemPattern that only recognized the escaped `\\r\\n` form and, on
        // top of that, truncated any line containing an escaped quote at the
        // backslash (`[^\\]{10,}` stops there) — confirmed against the live feed:
        // 2 of the 30 most recent releases had a mid-sentence truncation the old
        // path produced silently.
        ChangelogRecipe(
            bundleID: "com.postmanlabs.mac",
            source: URL(string: "https://mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json")!,
            mode: .json,
            maxEntries: 30,
            structuredFormat: .postmanReleaseNotes),
        ])
}
