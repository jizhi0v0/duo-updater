import Foundation

enum com_philandro_anydesk {
    static let set = AppRecipeSet(
        family: "com-philandro-anydesk",
        probes: [
        // AnyDesk — the plain-text changelog its own Homebrew cask reads for
        // livecheck, and the one thing on that host a script can fetch: the
        // download page and `anydesk.com/en/changelog/mac-os` both answer 403 with
        // a Cloudflare challenge even under a full Safari UA, which is why an
        // earlier sweep wrote this app off entirely. `changelog.txt` answers 200.
        //
        // Every platform's releases share the file, newest first, as
        // `22.07.2026 - 9.7.3 (macOS)`. The `(macOS)` anchor is load-bearing and
        // `selectHighest` must stay off: Windows is on a HIGHER number (9.7.14 the
        // day this was written), so an unanchored or highest-wins pattern reports
        // a version this app will never install.
        //
        // Verified 2026-08-16 on the downloaded dmg: AnyDesk.app 9.7.3,
        // com.philandro.anydesk, Developer ID `AnyDesk Software GmbH (KHRWM533LU)`
        // — the same Team as the installed copy — notarized and accepted by
        // `spctl`. The dmg URL carries no version, but it does not need to: it
        // always serves the release this file names first (its `Last-Modified`,
        // 2026-07-22, matches that entry's date).
        VendorProbeRecipe(
            bundleID: "com.philandro.anydesk",
            url: URL(string: "https://download.anydesk.com/changelog.txt")!,
            mode: .responseBody,
            versionPattern: #"([0-9]+(?:\.[0-9]+)+)\s+\(macOS\)"#,
            downloadURL: URL(string: "https://anydesk.com/en/downloads/mac-os"),
            changelogURL: URL(string: "https://anydesk.com/en/changelog/mac-os"),
            install: VendorInstallSpec(
                urlSource: .fixed(URL(string: "https://download.anydesk.com/anydesk.dmg")!),
                kind: .dmg)),
        ],
        changelogs: [
        // AnyDesk — the same plain-text changelog its `VendorProbeRecipe` already
        // reads for version detection. The vendor's HTML changelog
        // (`anydesk.com/en/changelog/mac-os`) answers 403 behind a Cloudflare
        // challenge even under a full Safari UA, so the pane's web-view fallback
        // renders a challenge page rather than notes; `changelog.txt` answers 200.
        //
        // Every platform shares the file, newest first:
        //
        //   22.07.2026 - 9.7.3 (macOS)
        //   ------------------
        //   New Features:
        //   - Visibility and online status for AnyDesk One Chat can be set manually
        //
        // The `(macOS)` anchor is load-bearing for exactly the reason the probe's
        // is: Windows runs on a HIGHER number (9.7.15 the day this was written), so
        // an unanchored pattern lists another platform's releases under this app.
        // 80 macOS entries on the live file (2026-09-03), newest 9.7.3.
        //
        // `[^\n]` in the item pattern, not `.`: every pattern is compiled with
        // dot-matches-newline, so `^-\s+(?<item>.+)$` would swallow the whole
        // section as one item. Tags and entities are left alone because the body is
        // plain text — there is no markup to strip and an `&` is just an `&`.
        //
        // The section labels ("New Features:", "Fixed Bugs:", "Other Changes:") are
        // not captured: items are flat here as everywhere else.
        ChangelogRecipe(
            bundleID: "com.philandro.anydesk",
            source: URL(string: "https://download.anydesk.com/changelog.txt")!,
            entryPattern:
                #"(?<date>\d{2}\.\d{2}\.\d{4}) - (?<version>\d+(?:\.\d+)+) \(macOS\)[ \t]*\n-+\n"#
                + #"(?<body>.*?)(?=\n\d{2}\.\d{2}\.\d{4} - |\z)"#,
            itemPatterns: [#"(?m)^-\s+(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false),
        ])
}
