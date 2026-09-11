import Foundation

/// CodeEdit (`app.codeedit.CodeEdit`) — a Sparkle app with ONE release line whose
/// every appcast item is tagged `<sparkle:channel>dev</sparkle:channel>`.
///
/// The tag is a label, not a prerelease track. CodeEdit's release workflow
/// (`.github/workflows/pre-release.yml`) generates every appcast with
/// `SPARKLE_CHANNEL: dev`, and the app's own `SPUUpdaterDelegate.allowedChannels`
/// returns `["dev"]` unconditionally — whatever its "include pre-release versions"
/// setting says, every CodeEdit install is offered exactly the `dev` items. The
/// GitHub releases those items point at are not marked prerelease.
///
/// Why a binding is needed at all: each release's appcast carries ONLY that
/// release (v0.2.0, v0.3.4, v0.3.5 and v0.3.6 checked, one item each). Without a
/// binding, `SparkleAppcastSource.allowedChannels` infers the channel from the
/// installed build's own feed item — which exists only while the install is
/// current. One release behind, the build is absent, the inference falls back to
/// the default channel, and a feed with no untagged item offers nothing: the row
/// reads unknown instead of offering the update.
///
/// `.stable`, because this is the app's only line, and
/// `channelBindingsNeedingProof` is right to treat it as having no other channel
/// to cross into.
///
/// ⚠️ Revisit when CodeEdit ships what it calls a production build. The same
/// delegate carries a commented-out branch — `if includePrereleaseVersions {
/// return ["dev"] } return []`, under "TODO: Uncomment when production build is
/// released" — i.e. an untagged stable line with `dev` becoming opt-in. From that
/// day this constant would offer `dev` builds to stable users, and the binding
/// would have to read `includePrereleaseVersions` from the app's defaults instead.
/// Reading it NOW would be wrong in the other direction: it defaults to false, so
/// every install would fall back to the default channel and see nothing.
///
/// Not in `boundBundleIDs`, same as Ghostty: nothing a user sets changes the answer.
enum CodeEditChannel {
    static let bundleID = "app.codeedit.CodeEdit"

    /// The only `<sparkle:channel>` value CodeEdit's appcasts carry.
    static let feedTag = "dev"

    static func resolveCurrent() -> ResolvedChannel {
        ResolvedChannel(channel: .stable, sparkleChannelNames: [feedTag])
    }
}
