import Foundation

/// The ordered list of update sources a check runs an app through, and the one
/// place that order is decided.
///
/// Order is load-bearing, not alphabetical: `UpdateChecker` takes the first
/// source that answers, so a source placed too early silently shadows a better
/// one for every app it happens to match. Keeping the list here means the CLI
/// and the menu bar cannot answer differently for the same app — which is the
/// only way `duo check` is worth trusting.
public enum SourceStack {

    /// - Parameters:
    ///   - githubToken: raises the rate limit from 60/hour to 5000 and is what
    ///     makes short check intervals viable; nil is supported and just means
    ///     the unauthenticated budget.
    ///   - alcove: the user's Alcove licence, when they have entered one.
    ///   - channelStore: where a source may remember a channel it PROVED
    ///     remotely, so it survives a failed check and costs one request rather
    ///     than one per check. Pass the same instance to `UpdateChecker`.
    public static func make(
        githubToken: String?,
        alcove: AlcoveUpdateSource.Credentials? = nil,
        channelStore: ResolvedChannelStore? = nil
    ) -> [any UpdateSource] {
        var sources: [any UpdateSource] = [
            MacAppStoreSource(),
            // Xcode, right after the App Store: a store-installed Xcode is answered
            // above (the store can actually update it), and everything else — every
            // beta and RC, which only exist behind an Apple ID — lands here.
            XcodeReleasesSource(),
            SparkleAppcastSource(),
            HomebrewCaskSource(),
            // GitHub Releases for apps distributed that way (detection only unless
            // a rule names an installable asset).
            GitHubReleasesSource(
                token: githubToken, channelStore: channelStore,
                validatorCache: GitHubConditionalCache.shared),
        ]
        // Alcove's licensed update channel, ahead of the vendor probe: it's the only
        // surface carrying release notes, an exact publish time and an installable
        // (licensed) download, so when the user's credentials are present it answers
        // first. Otherwise it's omitted and the public VendorProbe recipe handles
        // Alcove — same version, but detection-only and without notes.
        if let alcove {
            sources.append(AlcoveUpdateSource(credentials: alcove))
        }
        // Last resort: bespoke per-vendor version endpoints. Only fires when
        // the earlier sources all miss and a recipe exists.
        sources.append(VendorProbeSource())
        // AFTER the bespoke recipes, not before. Eight of the nine Electron apps
        // on the development machine already have a recipe whose install spec
        // picks a particular asset, and moving this ahead of them would swap the
        // artifact those installs fetch without anyone deciding to. Last, it can
        // only ADD coverage where nothing else answered; a recipe is retired by
        // deleting it once this source is shown to resolve that app.
        sources.append(ElectronManifestSource())
        return sources
    }
}
