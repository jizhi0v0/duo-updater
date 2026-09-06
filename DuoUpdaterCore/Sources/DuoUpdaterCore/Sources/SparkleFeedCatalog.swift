import Foundation

/// Sparkle feed addresses the bundle's own `Info.plist` does not give us: the
/// app keeps the address in code (``feeds``), or it states one the vendor has
/// stopped publishing to (``supersededFeeds``).
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
///
/// ``supersededFeeds`` is the second, narrower gap: a bundle that *does* state an
/// address, at a feed the vendor has abandoned. Everything above says a stated
/// address is the app speaking for itself and must be honoured — that still
/// holds, which is why replacing one is not a lookup by bundle id but a match
/// against the exact dead address, recorded here beside its replacement. The
/// moment the vendor edits `SUFeedURL` to anything else, the match fails and the
/// bundle's own word wins again.
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

    /// A feed the bundle still declares, paired with the one its vendor actually
    /// ships from. Both halves are load-bearing: `declared` is the match key, not
    /// documentation.
    struct SupersededFeed: Sendable, Equatable {
        /// The `SUFeedURL` the bundle states verbatim today.
        let declared: URL
        /// The appcast the vendor's own updater reads instead.
        let live: URL
    }

    /// bundleID (lowercased) → the dead feed it declares and the live one to use.
    /// Same lowercase-key rule as `feeds`.
    static let supersededFeeds: [String: SupersededFeed] = [
        // PDF Expert (Readdle). Its `SUFeedURL` points at `/release/appcast.xml`,
        // which the vendor froze on 2022-07-12: four items, newest build 764
        // (2.5.22, July 2022). Three of them cap out at `maximumSystemVersion`
        // 10.10–10.12, but the fourth does NOT, so on a current Mac the generic
        // source resolves that feed, picks 2.5.22 as "latest", finds it older than
        // the installed 3.13.2 and reports the app up to date — forever, with no
        // error anywhere. Nothing else picks the app up either: the `pdf-expert`
        // cask is `auto_updates: true`, which `HomebrewCaskSource` skips by design.
        // The live feed is `/pem3/release/appcast.xml`.
        //
        // Why this address and not merely a newer-looking one. The pem3 item for
        // build 1172 links a zip whose `.app` is Developer ID-signed by Team
        // 3L68KQB4HG and notarized (`spctl` accepts it) — Apple's attestation that
        // Readdle produced it, which no operator of that CDN path could forge — and
        // Homebrew's `pdf-expert` cask, maintained by nobody here, points at the
        // same tree and the same build. The zip's own `SUPublicEDKey`
        // (`K5sdt9UTWp/TcP48oRVycKUqWUbi0Tp37zrWtFYCCfw=`) does verify that item's
        // `sparkle:edSignature` over the exact 128 MB payload (Ed25519, checked
        // 2026-09-04), but note what that is and is not: the key and the payload
        // both come from the pem3 tree, so it proves the feed is internally
        // consistent, NOT that this key is the one the app in front of a user
        // holds. It cannot be made independent — 764, 936 and 964, the builds the
        // DEAD feed serves, carry no `SUPublicEDKey` at all (range-read from their
        // zips, 2026-09-04), and all four builds declare the same dead address.
        // The signature that actually gates the install for a stuck user is
        // therefore the Developer ID / Team check, not EdDSA (see
        // `UpdatePolicy`'s unsigned-feed branch).
        "com.readdle.pdfexpert-mac": SupersededFeed(
            declared: URL(string: "https://downloads.pdfexpert.com/release/appcast.xml")!,
            live: URL(string: "https://downloads.pdfexpert.com/pem3/release/appcast.xml")!),
    ]

    /// One catalog entry, in the shape `duo verify` sweeps registries in.
    ///
    /// The catalog is not a recipe registry — there is no pattern to re-derive
    /// and no version to parse out of a page. What it publishes is an ADDRESS,
    /// and the thing that rots is whether that address still answers with a
    /// feed a default-channel install can use. So a case carries the address
    /// and how we came to hand it out, and nothing else.
    public struct VerificationCase: Sendable, Equatable {
        public enum Kind: String, Sendable {
            /// From ``feeds``: an address the bundle never states.
            case fillIn = "fill-in"
            /// From ``supersededFeeds``: an address that overrides one the
            /// bundle does state.
            case superseded
        }
        public let bundleID: String
        public let kind: Kind
        /// The address `AppScanner` would write onto the row.
        public let feed: URL
        /// Superseded entries only: the dead address the entry matches on, and
        /// whose being dead is the entry's whole justification. Nil for a
        /// fill-in, which overrides nothing.
        public let declared: URL?

        /// Stable sweep key, same shape as every other registry's, so the
        /// baseline and the issue history key on it the same way.
        public var recipeID: String { "feed:\(bundleID)" }
    }

    /// Every entry, both halves, sorted so a run's output and the baseline it
    /// writes do not reorder themselves with the dictionaries' hashing.
    ///
    /// Derived from the tables rather than written out again beside them: a
    /// second list is a list that can be short by one, and a catalog entry
    /// nothing sweeps is precisely the state #324 was filed about.
    public static var verificationCases: [VerificationCase] {
        let fillIns = feeds.map {
            VerificationCase(bundleID: $0.key, kind: .fillIn, feed: $0.value, declared: nil)
        }
        let superseded = supersededFeeds.map {
            VerificationCase(bundleID: $0.key, kind: .superseded,
                             feed: $0.value.live, declared: $0.value.declared)
        }
        return (fillIns + superseded).sorted { $0.recipeID < $1.recipeID }
    }

    /// The curated feed for an app that publishes none of its own, if we have one.
    /// Case-insensitive on bundle id, matching `ChangelogCatalog`'s convention.
    public static func feed(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return feeds[bundleID.lowercased()]
    }

    /// The live feed to use in place of `declaredFeed`, when that is an address we
    /// have recorded as abandoned for this app.
    ///
    /// Nil unless `declaredFeed` matches the recorded dead address exactly. A
    /// bundle-id-only lookup would pin the app to our copy of the truth and keep
    /// pinning it after the vendor fixes their plist; matching the address means
    /// the entry expires by itself the moment the app stops naming the dead feed.
    public static func replacement(forBundleID bundleID: String?, declaredFeed: URL?) -> URL? {
        guard let bundleID, let declaredFeed,
              let entry = supersededFeeds[bundleID.lowercased()],
              entry.declared.absoluteString == declaredFeed.absoluteString
        else { return nil }
        return entry.live
    }
}
