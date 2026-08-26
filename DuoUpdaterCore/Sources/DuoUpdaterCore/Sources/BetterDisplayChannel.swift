import Foundation

/// BetterDisplay (`pro.betterdisplay.BetterDisplay`) ships THREE tracks through
/// ONE Sparkle appcast (`betterdisplay.pro/betterdisplay/sparkle/appcast.xml`),
/// selected by two toggles in Settings → Application → Updates:
///   * stable            → the untagged items (4.3.6 is the newest, 2026-08-26)
///   * "Receive pre-release updates"          → `<sparkle:channel>pre`
///   * "Receive internal pre-release updates" → `<sparkle:channel>internal`
///
/// The second toggle is only rendered once the first is on, so the GUI exposes
/// three states, not four. `internal` therefore SUBSUMES `pre`: a user with both
/// on must still be offered the plain `pre` builds when they are newer, which is
/// why this resolves to a Set of tag names rather than a single one. The vendor
/// states both halves outright, on the `pre` release itself
/// (`api.github.com/repos/waydabber/BetterDisplay/releases/tags/pre`, read
/// 2026-08-26): "Internal builds auto-update to newer internal builds until a
/// proper pre-release or stable release comes by. To keep receiving internal
/// builds even when a stable version was downloaded, enable `Receive pre-release
/// updates` and then `Receive internal pre-release updates`."
///
/// Note for anyone adding a changelog recipe here later: the internal track's
/// `<sparkle:releaseNotesLink>` is `changelog.html?tag=pre`, and that tag is a
/// ROLLING GitHub release (published 2023-06-14, 26 assets accumulated across
/// v3.0.5…v5.0.4) whose body is static boilerplate about what internal builds
/// are — there are no per-version notes on that track at all. Only `pre` and
/// stable items point at a real per-version tag.
///
/// Why a binding at all, when `SparkleAppcastSource` already infers the channel
/// from the running build: the inference cannot see an opt-in the user has not
/// yet acted on. Reproduced on this machine 2026-08-26 — BetterDisplay 4.3.6
/// (build 50119, a stable-track build) with both toggles on, the vendor's own
/// updater offering v5.0.4, and `duo check` reporting "up-to-date" because the
/// installed build matches the untagged 4.3.6 item. The vendor documents the
/// inference as the fallback, not the rule ("If you are already running a
/// pre-release version, you'll receive pre-release updates until the next stable
/// release even if this option is disabled").
///
/// The preference keys, read off `~/Library/Preferences/pro.betterdisplay.BetterDisplay.plist`
/// on 2026-08-26 while flipping the GUI toggles:
///     both off  → `preReleaseChannel` ABSENT,  `internalReleaseChannel` ABSENT
///     both on   → `preReleaseChannel` 1,       `internalReleaseChannel` 1
///     pre only  → `preReleaseChannel` 1,       `internalReleaseChannel` 0
/// So the keys are absent until first touched and thereafter written explicitly,
/// including a literal 0 on the way back down — the same behaviour Tailscale's
/// equivalent pair shows. `readBoolPref` treats absent and 0 alike, so both
/// spellings of "off" land on the same track.
///
/// ⚠️ `arm64_pre` is deliberately NOT in any allowed set. It is a real fourth tag
/// in the feed and its builds are **arm64-only**. Measured 2026-08-26 by mounting
/// every artifact in question and reading `lipo -archs`, so the tag↔architecture
/// boundary is observed on both sides rather than extrapolated from one sample:
///     5.0.0  arm64_pre  arm64            5.0.2  pre        x86_64 arm64
///     5.0.1  arm64_pre  arm64            5.0.3  pre        x86_64 arm64
///                                        5.0.4  internal   x86_64 arm64
///                                        4.3.6  untagged   x86_64 arm64
/// (2.3.9 and 3.5.6b are universal too.) Every one of those artifacts is signed
/// by Team 299YSU96J7, the same identity as the installed app — so the signature
/// gate cannot catch a cross-architecture mistake here either.
/// Why the tag exists at all is unconfirmed; the timeline reads as "the first two
/// v5 previews shipped Apple-silicon-only, and the tag kept Intel users on the
/// `pre` track from being handed one", but the vendor has not said so.
/// Nothing in the feed says so: the items declare no `<sparkle:hardwareRequirements>`
/// and the enclosure is named `BetterDisplay-v5.0.1-pre-release.dmg` with no arch
/// token, so `SparkleAppcastSource.archVerdict` would rate them `.neutral` and
/// happily offer them to an Intel Mac that cannot run them. Excluding the tag
/// costs nothing: 5.0.2+ moved to `pre` with a higher version, so an `arm64_pre`
/// item could never be the offered update anyway — only two rows of changelog
/// history are lost.
///
/// Safety: an unreadable or absent key falls back to `.stable` — the shipped
/// default — so we never push a prerelease at someone who did not opt in.
enum BetterDisplayChannel {
    static let bundleID = "pro.betterdisplay.BetterDisplay"

    /// The feed's tag for the plain pre-release track.
    static let preTag = "pre"
    /// The feed's tag for the internal track.
    static let internalTag = "internal"

    /// Map the two flags to a resolution. Pure and tested.
    ///
    /// `internalEnabled` is checked first and carries `preTag` with it, mirroring
    /// the GUI's nesting. A hypothetical on-disk state with `internalReleaseChannel`
    /// set but `preReleaseChannel` clear — not reachable through the GUI, but
    /// producible by a `defaults write` or a future vendor bug — still resolves to
    /// the internal track rather than silently downgrading, the same defensive
    /// tie-break `TailscaleChannel.resolve` documents.
    static func resolve(preEnabled: Bool, internalEnabled: Bool) -> ResolvedChannel {
        if internalEnabled {
            // `.unstable` is the closest `ReleaseChannel` case for a track the
            // vendor itself calls "unstable, may contain major bugs". The feed's
            // own spelling travels separately, in `sparkleChannelNames`.
            return ResolvedChannel(
                channel: .unstable, sparkleChannelNames: [preTag, internalTag]
            )
        }
        if preEnabled {
            return ResolvedChannel(channel: .beta, sparkleChannelNames: [preTag])
        }
        return ResolvedChannel(channel: .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(preEnabled: readBoolPref("preReleaseChannel"),
                internalEnabled: readBoolPref("internalReleaseChannel"))
    }

    private static func readBoolPref(_ key: String) -> Bool {
        // Force a fresh read from cfprefsd before each look: this menu-bar process
        // runs for days and can otherwise serve a value it cached before
        // BetterDisplay wrote the toggle — which would defeat the whole point here,
        // since the flip is exactly what `ChannelSwitchDetector` is watching for.
        // `IINAChannel` and `TablePlusChannel` both carry this call for the same
        // reason. One synchronize per key is redundant but free; the two keys are
        // read back to back and the second sync finds nothing to do.
        CFPreferencesAppSynchronize(bundleID as CFString)
        return (CFPreferencesCopyAppValue(key as CFString,
                                          bundleID as CFString) as? NSNumber)?.boolValue ?? false
    }
}
