import Foundation

enum com_electron_wispr_flow {
    static let set = AppRecipeSet(
        family: "com-electron-wispr-flow",
        probes: [
        // (Surge needs no recipe here: it declares a Sparkle SUFeedURL, so the
        // higher-priority SparkleAppcastSource handles it, and `SurgeChannel`
        // retargets that feed to the release/beta appcast per the user's choice.)

        // MARK: - 2026-08-17 AI desktop apps

        // Wispr Flow — official RELEASES.json, the same endpoint Homebrew uses.
        // `currentRelease` is authoritative and matches both version fields in the
        // mounted app. com.electron.wispr-flow, Team C9VQZ78H85, notarized; no
        // SUFeedURL.
        //
        // ONE-CLICK via `.versionTemplate`, and the choice is forced rather than
        // preferred. The feed's 26 entries each carry their own `url`, but the
        // version is printed BEFORE the url inside every entry, and
        // `.bodyPatternHighestVersioned` requires capture group 1 to be the url and
        // group 2 the version — an order a single left-to-right regex cannot
        // produce here. The remaining body options are both ordering bets on an
        // ascending feed. `.versionTemplate` sidesteps the question: the string
        // that was compared is the string that gets downloaded.
        //
        // An earlier note here said the feed was architecture-specific and that a
        // one-click risked a cross-architecture swap. The endpoint is arm64's
        // (`/darwin/arm64/`) — it is the *probe* URL that already pins the
        // architecture, so there was never a choice to make. This app is arm64-only
        // (`App/project.yml`), so no host can ask for the Intel train.
        //
        // THE TEMPLATE DELIBERATELY DOES NOT USE THE FEED'S OWN `url`. Every entry
        // in this stable feed — all 26 — points at a `wispr-flow-beta/…` path.
        // Following it works (the artifact there is a normal notarized stable
        // build; 1.6.721 downloaded and extracted 2026-08-29:
        // `com.electron.wispr-flow`, CFBundleShortVersionString 1.6.721,
        // `Developer ID Application: Wispr AI INC (C9VQZ78H85)`, spctl "accepted /
        // Notarized Developer ID", stapled), but it makes every nightly `duo
        // verify` raise "stable recipe resolved what looks like a PRE-RELEASE
        // artifact" — a standing false positive on the one sweep whose job is to
        // be believed, and one `duo reconcile` would file as an issue.
        //
        // The same object is served from the stable path this recipe already
        // probes, `wispr-flow/darwin/arm64/`: verified 2026-08-29 by fetching both
        // and comparing — identical size (331,807,594 B) and identical SHA-256
        // (0217292d…d6a31), so the `-beta` bucket is an alias, not another build.
        // Templating the stable path is therefore the honest URL rather than a
        // suppressed warning.
        //
        // No checksum: the feed publishes none for any entry — the signature and
        // Team gates are the integrity check.
        VendorProbeRecipe(
            bundleID: "com.electron.wispr-flow",
            url: URL(string: "https://dl.wisprflow.com/wispr-flow/darwin/arm64/RELEASES.json")!,
            mode: .responseBody,
            versionPattern: #"\"currentRelease\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://wisprflow.ai/downloads"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dl.wisprflow.com/wispr-flow/darwin/arm64/"
                    + "Wispr%20Flow-darwin-arm64-{version}.zip"),
                kind: .zip)),
        ])
}
