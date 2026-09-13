import Foundation

enum com_anythingllm {
    static let set = AppRecipeSet(
        family: "com-anythingllm",
        probes: [
        // MARK: - 2026-08-30 AnythingLLM

        // AnythingLLM — private desktop AI chat (Electron). No Sparkle: the real
        // bundle (downloaded and mounted 2026-08-30) carries no `SUFeedURL`, and
        // its `app-update.yml` points at a leftover electron-vite TEMPLATE repo
        // (`electron-vite/electron-vite-react/releases/download/v0.9.9/`), not a
        // working updater. The real distribution surface is the vendor's own CDN,
        // `cdn.anythingllm.com`:
        //
        //   * `latest/version.txt` — a one-line plain-text version body
        //     (`1.16.1\n`), which is EXACTLY the endpoint Homebrew's own
        //     `anythingllm` cask names in its `livecheck` block — a third party
        //     already depends on it for the same purpose, so this is the vendor's
        //     intended version surface, not a guess. Prefer it over scraping the
        //     homepage.
        //   * `latest/AnythingLLMDesktop-Silicon.dmg` — the arm64 build, an
        //     UNVERSIONED moving pointer (no `1.16.1/…` path exists; 404). The
        //     pair is published together: on 2026-08-30 both carry the same
        //     Last-Modified minute (16:34/16:35, 73 s apart), and the mounted
        //     dmg's `CFBundleShortVersionString` equals version.txt exactly.
        //     This is the same `/latest/` + livecheck pairing the cask itself
        //     ships, so the drift risk is shared with Homebrew, not invented
        //     here. The Intel twin is `latest/AnythingLLMDesktop.dmg` (the cask
        //     selects by arch); DuoUpdater is arm64-only, so pin Silicon.
        //
        // Verified against the real artifact: `com.anythingllm`, short == build
        // == `1.16.1`, arm64-only, signed "Developer ID Application: Timothy
        // Carambat (35S2NMU3G4)", notarized. Self-contained bundle (no
        // LaunchDaemons/Agents, no `Contents/Library`), so `kind: .dmg` is
        // right — nothing outside the `.app` to go stale.
        //
        // Single channel: the vendor ships no beta/nightly surface.
        //
        // Delta/binary patch: not a Sparkle app and the CDN carries no
        // `.delta`/`.patch` artifacts — nothing to consume.
        // Notes live in the project's GitHub releases, on the SAME numbering as
        // `version.txt` (`1.16.1` ↔ `v1.16.1`, 2026-09-03) — see the
        // `ChangelogRecipe` for `com.anythingllm`, which parses them natively.
        // `docs.anythingllm.com/changelog` 404s and is not the page.
        VendorProbeRecipe(
            bundleID: "com.anythingllm",
            url: URL(string: "https://cdn.anythingllm.com/latest/version.txt")!,
            mode: .responseBody,
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)\s*$"#,
            changelogURL: URL(string: "https://github.com/Mintplex-Labs/anything-llm/releases"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://cdn.anythingllm.com/latest/AnythingLLMDesktop-Silicon.dmg")!),
                kind: .dmg)),
        ],
        changelogs: [
        // MARK: - 2026-09-03 AnythingLLM / Chatbox

        // AnythingLLM — the desktop build's version source is the vendor CDN
        // (`cdn.anythingllm.com/latest/version.txt`), which is a bare version
        // string and carries no notes at all. The notes live in the project's
        // GitHub releases, and the two are the SAME numbering: `version.txt`
        // answered `1.16.1` on 2026-09-03 and the newest release there is tagged
        // `v1.16.1` (bodies run 1.7–10.7 KB). That alignment is what makes this
        // safe to attach — a changelog keyed to a version the app never reports
        // renders an empty pane, which is worse than the web-view fallback.
        //
        // `docs.anythingllm.com/changelog` is NOT the source: it 404s (checked
        // 2026-09-03). Reuses `.gitHubReleases`, the same decoder Waku and
        // Shotbase go through.
        ChangelogRecipe(
            bundleID: "com.anythingllm",
            source: URL(
                string: "https://api.github.com/repos/Mintplex-Labs/anything-llm/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ])
}
