import Foundation

enum app_chatwise {
    static let set = AppRecipeSet(
        family: "app-chatwise",
        probes: [
        // ChatWise — Squirrel releases endpoint: a newest-first array of versions, read
        // first-match (no `selectHighest`), so the first entry is the one reported.
        VendorProbeRecipe(
            bundleID: "app.chatwise",
            url: URL(string: "https://releases.chatwise.app/releases?version=0.0.0&platform=osx")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://chatwise.app/changelog"),
            // assets[] carries the arm64 zip and its SHA-512 (base64) — use both.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"([^"]*arm64\.zip)""#),
                kind: .zip,
                checksumPattern: #"arm64\.zip"\s*,\s*"sha512"\s*:\s*"([^"]+)""#)),
        ],
        changelogs: [
        // ChatWise — the public /changelog page is a SvelteKit shell (a ~4 KB
        // document with no notes in it) that hydrates from the releases JSON
        // endpoint, so we read that endpoint directly. It is a newest-first array:
        //   {"version":"26.6.0","changelog":"- new provider: cloudflare workers ai",
        //    "assets":[...],"date":"2026-06-26T16:04:26.161Z"}
        // Decoded as JSON rather than regex-scraped: the notes are a markdown
        // bullet list living inside a JSON string, so on the regex path every
        // newline is a literal `\n` escape that an item pattern must spell as
        // `\\n` — see `.chatwiseReleases` for the last-bullet bug that cost us.
        ChangelogRecipe(
            bundleID: "app.chatwise",
            source: URL(string: "https://releases.chatwise.app/releases")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .chatwiseReleases),
        ],
        changelogPages: [
        // ChatWise — the live structured notes come from the releases JSON, but
        // we still want an explicit fallback page when the lazy fetch/parser
        // misses or the update check hasn't populated a remote changelog URL yet.
        "app.chatwise": URL(string: "https://chatwise.app/changelog")!,
        ])
}
