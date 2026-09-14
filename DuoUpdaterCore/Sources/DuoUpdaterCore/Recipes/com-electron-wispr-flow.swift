import Foundation

enum com_electron_wispr_flow {
    static let set = AppRecipeSet(
        family: "com-electron-wispr-flow",
        probes: [
        // History: docs/app-audits/com-electron-wispr-flow.md#历史与实测
        // Wispr Flow — official RELEASES.json, the same endpoint Homebrew uses.
        // `currentRelease` is authoritative and matches both version fields in the
        // mounted app. com.electron.wispr-flow, Team C9VQZ78H85, notarized; no
        // SUFeedURL.
        //
        // ONE-CLICK via `.versionTemplate`, and the choice is forced rather than
        // preferred. The feed's entries each carry their own `url`, but the
        // version is printed BEFORE the url inside every entry, and
        // `.bodyPatternHighestVersioned` requires capture group 1 to be the url and
        // group 2 the version — an order a single left-to-right regex cannot
        // produce here. The remaining body options are both ordering bets on an
        // ascending feed. `.versionTemplate` sidesteps the question: the string
        // that was compared is the string that gets downloaded.
        //
        // The endpoint is arm64's (`/darwin/arm64/`) — it is the *probe* URL that
        // already pins the architecture, so there is no choice to make. This app
        // is arm64-only (`App/project.yml`), so no host can ask for the Intel train.
        //
        // THE TEMPLATE DELIBERATELY DOES NOT USE THE FEED'S OWN `url`. Entries in
        // this stable feed have pointed at a `wispr-flow-beta/…` path (the older
        // ones still do; History has the counts). Following such a url works (the
        // artifact there is a normal notarized stable build), but it makes every
        // nightly `duo verify` raise "stable recipe resolved what looks like a
        // PRE-RELEASE artifact" — a standing false positive on the one sweep whose
        // job is to be believed, and one `duo reconcile` would file as an issue.
        //
        // The same build is also published under the stable path this recipe
        // already probes, `wispr-flow/darwin/arm64/`, so the `-beta` bucket was an
        // alias, not another build (History has the byte comparison).
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
