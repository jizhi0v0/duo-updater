import Foundation

/// Sparkle feed addresses for apps that ship a Sparkle updater but keep the
/// address in code instead of `Info.plist`.
///
/// `AppScanner` learns an app's feed from one key, `SUFeedURL`. An app that sets
/// it up programmatically (`SPUUpdaterDelegate.feedURLString`, or a
/// `--custom-update-server-url`-style switch) is invisible to that read, so the
/// generic `SparkleAppcastSource` never fires for it however well-formed its
/// appcast is. This table fills that one gap in.
///
/// **Fill-in only — it never overrides a feed the bundle publishes itself.** An
/// app that states an address is speaking for itself, and pointing it somewhere
/// else is a decision about which *channel* the user is on. That belongs in
/// ``ChannelBinding/feedOverride``, which exists for exactly that (Fork and Surge
/// swap feeds per channel).
///
/// **And that separation is the whole reason this type exists.** Reusing
/// `ChannelBinding` to deliver an address would have been one line — but
/// `AppScanner` sets `channelIsAuthoritative` the moment a binding resolves, and
/// `SparkleAppcastSource.allowedChannels` then stops inferring the channel from
/// the feed and takes the binding's word for it. That inference is the thing
/// worth keeping: it matches the installed build against the feed's own items, so
/// a prerelease install unlocks its train by *being* that build, with nothing
/// vendor-specific to read. Helium is the case in point — its only on-disk
/// channel signal is a `chrome://flags` entry stored as
/// `"helium-update-channel@2"`, a positional index with no label anywhere to
/// check it against, and reading the feed needs none of it. Verified against both
/// real builds on 2026-08-31: the 0.16.2.1 (default) bundle sees 8 of the feed's
/// 9 items, the 0.16.1.1 (beta-tagged) bundle sees all 9.
///
/// Deliberately NOT gated on `InstalledApp.hasSparkleUpdater`: that flag looks for
/// `Contents/Frameworks/Sparkle.framework`, and Helium's copy lives inside its
/// Chromium framework
/// (`Helium Framework.framework/Versions/<v>/Frameworks/Sparkle.framework`), so
/// the flag reads false for the one app in this table.
public enum SparkleFeedCatalog {
    /// bundleID (lowercased) → appcast. Lowercase keys only; `feed(forBundleID:)`
    /// lowercases its argument, so a key with a capital is unreachable — the same
    /// trap `ChangelogCatalog` shipped once and now guards against.
    static let feeds: [String: URL] = [
        // Helium — Chromium-based browser (imputnet/helium-macos). Ships Sparkle
        // but no `SUFeedURL`; the address is in the binary alongside a
        // `custom-update-server-url` flag. One feed PER ARCHITECTURE
        // (`appcast-x86_64.xml` is the sibling), and arm64 is pinned here because
        // DuoUpdater is arm64-only — see `App/project.yml`.
        //
        // Reading it buys two things the GitHub rule cannot: the beta train
        // (`<sparkle:channel>beta</sparkle:channel>` on one item), and the delta
        // patches every item publishes — ~40 MB against a 124 MB full download.
        // Its enclosures are RELATIVE (`assets/helium_….dmg`), which Sparkle
        // resolves against the appcast URL and we now do too; before that fix
        // this entry would have produced a schemeless, unfetchable download.
        "net.imput.helium": URL(string: "https://updates.helium.computer/mac/appcast-arm64.xml")!,
    ]

    /// The curated feed for an app that publishes none of its own, if we have one.
    /// Case-insensitive on bundle id, matching `ChangelogCatalog`'s convention.
    public static func feed(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return feeds[bundleID.lowercased()]
    }
}
