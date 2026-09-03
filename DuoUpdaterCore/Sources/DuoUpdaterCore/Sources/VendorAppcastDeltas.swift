import Foundation

/// Pulls Sparkle binary patches out of a vendor probe's response body.
///
/// Some vendors answer a probe with a plain Sparkle appcast even though we reach
/// them through `VendorProbeRecipe` rather than an `SUFeedURL` — ChatGPT is the
/// case that matters (its feed lives inside the asar, so `SparkleAppcastSource`
/// never sees the app, and every one of its installs is served by `Vendor`).
/// The patches are right there in the body we already parsed for a version; this
/// is what stops the delta route from being blind to the app it was built for.
///
/// Reuses `SparkleAppcastParser` rather than adding regexes: the nesting rule
/// (`<enclosure>` means two different things inside and outside
/// `<sparkle:deltas>`) has already cost this repo one silent outage, and a second
/// implementation of it would be a second chance to get it wrong.
enum VendorAppcastDeltas {

    /// Patches published for exactly `version`, or empty when the body is not an
    /// appcast, publishes none, or does not agree with the version we resolved.
    ///
    /// The version match is the whole safety story. A vendor probe finds its
    /// version with a recipe-supplied regex, which is free to pick a different
    /// item than a feed reader would — first match rather than highest, a title
    /// rather than a `sparkle:version`. Taking "the newest item's patches" would
    /// then hand the installer a patch for a release it is not installing, and the
    /// bytes would be authentic, correctly signed, and for the wrong build. So a
    /// patch is only ever returned from the item that names the same version the
    /// probe resolved, matched against either the build or the marketing string
    /// because a recipe may key on either.
    ///
    /// Ambiguity is refused rather than guessed: if two items claim the version,
    /// there is no single right answer and the full archive is always correct.
    ///
    /// `feedURL` is the endpoint the body came from, and it is passed for the same
    /// reason `SparkleAppcastSource` passes its own: Sparkle resolves every URL in
    /// an appcast against the appcast's address, so a vendor writing
    /// `assets/App-1.2-1.1.delta` yields a schemeless, unfetchable patch without
    /// it. No vendor appcast we read publishes relative patches today — this is
    /// here so the two Sparkle-parsing paths cannot drift, which is exactly how
    /// the first one came to be wrong.
    static func patches(
        inBody body: String, forVersion version: String, feedURL: URL? = nil
    ) -> [DeltaPatch] {
        guard body.contains("sparkle:deltas") else { return [] }
        let items = SparkleAppcastParser.parse(Data(body.utf8), relativeTo: feedURL)
        let matching = items.filter {
            $0.version == version || $0.shortVersionString == version
        }
        guard matching.count == 1, let item = matching.first else { return [] }
        return item.deltas
    }
}
