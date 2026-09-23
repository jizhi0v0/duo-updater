import Foundation

enum com_meta_endo {
    static let set = AppRecipeSet(
        family: "com-meta-endo",
        probes: [
        // History: docs/app-audits/com-meta-endo.md#历史与实测
        // Muse (Meta) — `com.meta.endo`, Team `V9WTTPBFK9`, notarized.
        //
        // WHY A PROBE AT ALL: the bundle ships a Sparkle `SUFeedURL`
        // (`www.facebook.com/endo/release/appcast.xml?channel=production`), and
        // facebook.com login-walls it: most anonymous requests 302 to `/login`, in
        // runs of tens of seconds, from one exit and one request shape alike.
        // `SparkleAppcastSource` answers first whenever the feed does come through
        // (it compares builds, which this probe cannot), and throws
        // `SparkleError.notAFeed` when it gets the login page — which is when this
        // recipe answers instead. The Homebrew cask `muse` is `auto_updates` and
        // not a source here (`HomebrewCaskSource`), and its own `livecheck` reads
        // that same login-walled appcast.
        //
        // THE ENDPOINT is the one the cask's `url` uses: a version-free "latest"
        // link that 307s to the fbcdn artifact, whose last path component is
        // `Muse-<marketing>.dmg`. That marketing string is the bundle's own
        // `CFBundleShortVersionString` (read from the real dmg). Anchored to the
        // whole filename so a renamed artifact fails the probe (a Failed row and a
        // `duo verify` finding) rather than yielding some other number.
        //
        // Marketing only: Meta has shipped several builds under one marketing
        // string (1.0 carried at least two), and the filename names no build, so a
        // same-marketing rebuild is visible only through the Sparkle feed.
        //
        // ONE-CLICK via `.redirect` on the same link, resolved at download time:
        // the fbcdn URL is signed (`oh=`/`oe=`), so a copy resolved at check time
        // and held on the row is not something to depend on. HEAD works here (307,
        // then 200 with the dmg's length). The dmg holds the real, self-contained
        // `Muse.app` — no helper, launch item or extension outside the bundle, only
        // Sparkle inside `Frameworks` — so `.dmg` is the right kind.
        VendorProbeRecipe(
            bundleID: "com.meta.endo",
            url: Self.latestDownload,
            mode: .redirectFilename,
            versionPattern: #"^Muse-([0-9]+(?:\.[0-9]+)+)\.dmg$"#,
            downloadURL: Self.latestDownload,
            install: VendorInstallSpec(urlSource: .redirect(Self.latestDownload), kind: .dmg)),
        ])

    /// Muse's version-free "latest" download link — the endpoint the probe reads
    /// and the one the installer fetches, declared once so the two cannot drift.
    static let latestDownload = URL(string: "https://muse.ai/api/hatch/app-download/mac")!
}
