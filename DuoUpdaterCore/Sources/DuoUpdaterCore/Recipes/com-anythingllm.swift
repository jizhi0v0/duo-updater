import Foundation

enum com_anythingllm {
    static let set = AppRecipeSet(
        family: "com-anythingllm",
        probes: [
        // MARK: - 2026-08-30 AnythingLLM

        // History: docs/app-audits/com-anythingllm.md#历史与实测
        // AnythingLLM — private desktop AI chat (Electron). No Sparkle: the real
        // bundle carries no `SUFeedURL`, and
        // its `app-update.yml` points at a leftover electron-vite TEMPLATE repo
        // (`electron-vite/electron-vite-react/releases/download/v0.9.9/`), not a
        // working updater. The real distribution surface is the vendor's own CDN,
        // `cdn.anythingllm.com`:
        //
        //   * `latest/version.txt` — a one-line plain-text version body
        //     (e.g. `1.16.1\n`), which is EXACTLY the endpoint Homebrew's own
        //     `anythingllm` cask names in its `livecheck` block — a third party
        //     already depends on it for the same purpose, so this is the vendor's
        //     intended version surface, not a guess. Prefer it over scraping the
        //     homepage.
        //   * `latest/AnythingLLMDesktop-Silicon.dmg` — the arm64 build, an
        //     UNVERSIONED moving pointer (no versioned path, e.g. `1.16.1/…`, exists;
        //     404). The
        //     pair is published together.
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
        // Notes: see the `ChangelogRecipe` for `com.anythingllm` below, which parses the
        // project's GitHub releases natively.
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
        // AnythingLLM — the desktop build's version source is the vendor CDN
        // (`cdn.anythingllm.com/latest/version.txt`), which is a bare version
        // string and carries no notes at all. The notes live in the project's
        // GitHub releases, and the two are the SAME numbering. That alignment is
        // what makes this
        // safe to attach — a changelog keyed to a version the app never reports
        // renders an empty pane, which is worse than the web-view fallback.
        //
        // `docs.anythingllm.com/changelog` is NOT the source: it 404s. Reuses
        // `.gitHubReleases`, the same decoder Waku and
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
