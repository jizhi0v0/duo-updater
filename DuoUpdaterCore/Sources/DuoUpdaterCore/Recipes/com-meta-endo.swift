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
        // runs of a minute or more, whatever the host (www/web/m), User-Agent or
        // Accept header. `SparkleAppcastSource` answers first whenever the feed
        // does come through — with the build, and the fbcdn enclosure one-click
        // installs from — and throws `SparkleError.notAFeed` when it gets the
        // login page, which is when this recipe answers instead.
        //
        // THE ENDPOINT is the Homebrew cask `muse`'s API listing, read for its
        // `version` only. The cask's own `livecheck` reads that same walled
        // appcast, but autobump runs again and again, one run that gets through
        // is enough, and `sha256 :no_check` means a bump never downloads anything
        // — so the number keeps moving, a little behind: 4.0 reached it about two
        // hours after the appcast's `pubDate`, and 3.0, which this recipe read off
        // the old endpoint that same morning, never reached it at all (2.2 → 4.0).
        // The cask is `auto_updates`, so `HomebrewCaskSource` leaves it alone;
        // this reads the number without offering a brew install.
        //
        // DETECTION ONLY, no install spec: the only link that does not expire is
        // the cask's `url`, `muse.ai/api/hatch/app-download/mac`, and since
        // 2026-09-25 it answers anyone not signed in to muse.ai with
        // `403 {"error":"not_eligible"}` (this recipe used to read its 307). The
        // dmg itself is public — only the link to it is gated. Installing goes
        // through the Sparkle source's enclosure in the rounds the feed gets
        // through, and Muse's own Sparkle updates it otherwise. The row's page is
        // muse.ai itself: signed in, it hands out the dmg (that is how the link
        // above was seen working); signed out, it sends you to sign in first.
        //
        // Marketing only: the cask names no build, so a same-marketing rebuild is
        // visible only through the Sparkle feed.
        VendorProbeRecipe(
            bundleID: "com.meta.endo",
            url: URL(string: "https://formulae.brew.sh/api/cask/muse.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://muse.ai/")),
        ])
}
