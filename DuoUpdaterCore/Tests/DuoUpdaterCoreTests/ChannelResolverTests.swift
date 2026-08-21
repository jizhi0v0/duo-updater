import Testing
import Foundation
@testable import DuoUpdaterCore

/// Per-app channel resolvers turn a private preference into a `(channel, feed)`.
/// The mappings are pure; each app encodes the choice differently, so each gets
/// its own pinned-down truth. The safety invariant across all of them: an
/// unknown/absent preference resolves to the app's shipped default, never up.

// MARK: - Surge (Application Support `IncludeBetaBuilds` Bool → feed swap)

@Test func surgeBetaTrueRetargetsToBetaFeed() {
    let r = SurgeChannel.resolve(includeBeta: true)
    #expect(r.channel == .beta)
    #expect(r.feedOverride == SurgeChannel.betaFeed)
}

@Test func surgeBetaFalseStaysOnReleaseFeed() {
    let r = SurgeChannel.resolve(includeBeta: false)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == SurgeChannel.releaseFeed)
}

// MARK: - OrbStack (`updates_optinChannel` String → channel tag, no feed swap)

@Test func orbStackMapsLiteralChannelNames() {
    #expect(OrbStackChannel.resolve(channelString: "stable").channel == .stable)
    #expect(OrbStackChannel.resolve(channelString: "beta").channel == .beta)
    #expect(OrbStackChannel.resolve(channelString: "canary").channel == .canary)
    // Channel-tag app: never a feed override, the recipe picks by channel.
    #expect(OrbStackChannel.resolve(channelString: "canary").feedOverride == nil)
}

@Test func orbStackAbsentOrUnknownIsStable() {
    #expect(OrbStackChannel.resolve(channelString: nil).channel == .stable)
    #expect(OrbStackChannel.resolve(channelString: "experimental").channel == .stable)
}

// MARK: - DuoPaste (`sparkleIncludePrereleases` Bool → channel tag, no feed swap)

@Test func duoPastePrereleasesMapToBeta() {
    #expect(DuoPasteChannel.resolve(includePrereleases: true).channel == .beta)
    #expect(DuoPasteChannel.resolve(includePrereleases: false).channel == .stable)
    #expect(DuoPasteChannel.resolve(includePrereleases: true).feedOverride == nil)
}

// MARK: - TablePlus (`ViewSetting.IsReceiveBetaBuild` Bool → shared feed + header)

@Test func tablePlusBetaTrueInjectsTheUnlockHeader() {
    let r = TablePlusChannel.resolve(receiveBeta: true)
    #expect(r.channel == .beta)
    // Header-keyed app: one feed, no swap — the header is what selects beta.
    #expect(r.feedOverride == nil)
    #expect(r.feedHTTPHeaders[TablePlusChannel.betaHeaderField]
        == TablePlusChannel.betaHeaderValue)
}

@Test func tablePlusBetaFalseSendsNoHeader() {
    let r = TablePlusChannel.resolve(receiveBeta: false)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == nil)
    #expect(r.feedHTTPHeaders.isEmpty)
}

@Test func tablePlusUnlockHeaderValueIsTheLiteralServerExpects() {
    // The server treats only the exact string "true" as beta ("1"/"yes" → stable),
    // so pin the value down — a typo here silently degrades to the stable feed.
    #expect(TablePlusChannel.betaHeaderField == "X-Tiny-Beta-Update")
    #expect(TablePlusChannel.betaHeaderValue == "true")
}

// MARK: - CleanShot (`activationKey` String → personalized legit feed swap)

@Test func cleanShotFeedEmbedsTheLicenseKeyAsAQuery() {
    let url = CleanShotChannel.feed(forKey: "AAAA-BBBB-CCCC-DDDD")
    #expect(url?.scheme == "https")
    #expect(url?.host == "legit.maketheweb.io")
    #expect(url?.path == "/api/v1/appcast")
    let key = URLComponents(url: url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "key" })?.value
    #expect(key == "AAAA-BBBB-CCCC-DDDD")
}

@Test func cleanShotFeedPercentEncodesKey() {
    // The key is interpolated as a query value, so a stray reserved character
    // (defensive — real keys are hex-and-dashes) must be encoded, not break the URL.
    let url = CleanShotChannel.feed(forKey: "a b&c")
    #expect(url != nil)
    let key = URLComponents(url: url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "key" })?.value
    #expect(key == "a b&c")  // decodes back to the original
}

// MARK: - Tailscale (`UnstableUpdatesEnabled` / `RCUpdatesEnabled` Bools → channel
// tag, no feed swap — three-way resolve, see `TailscaleChannel`)

@Test func tailscaleUnstableEnabledMapsToUnstable() {
    let r = TailscaleChannel.resolve(unstableEnabled: true, rcEnabled: false)
    #expect(r.channel == .unstable)
    // Channel-tag app: never a feed override, the channel gate picks the recipe.
    #expect(r.feedOverride == nil)
}

@Test func tailscaleRCEnabledMapsToRC() {
    let r = TailscaleChannel.resolve(unstableEnabled: false, rcEnabled: true)
    #expect(r.channel == .rc)
    #expect(r.feedOverride == nil)
}

@Test func tailscaleBothDisabledStaysStable() {
    let r = TailscaleChannel.resolve(unstableEnabled: false, rcEnabled: false)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == nil)
}

// `resolve` takes plain Bools, so a key that is ABSENT from the plist and one
// that is explicitly written `0` are indistinguishable once `readBoolPref`
// has collapsed them (`?? false`) — both real shapes are confirmed on-disk
// (Stable: RCUpdatesEnabled absent; Unstable: RCUpdatesEnabled explicitly 0,
// read back with `defaults read` 2026-08-21/22), and both must resolve the
// same way, which this pins at the `resolve` level.
@Test func tailscaleBothKeysMissingOrExplicitlyZeroStaysStable() {
    let r = TailscaleChannel.resolve(unstableEnabled: false, rcEnabled: false)
    #expect(r.channel == .stable)
}

// Empirically, the GUI dropdown is exclusive — verified 2026-08-21/22 by
// reading the plist through all three positions back to back, including that
// leaving RC writes `RCUpdatesEnabled` back to 0 rather than removing it — so
// this combination has not been observed from normal use. But the two keys
// are still independent Bools on disk, not one tri-state enum enforced by
// anything on our side, so pin the defensive tie-break anyway: unstable wins
// (see the reasoning in `TailscaleChannel.resolve`).
@Test func tailscaleBothEnabledPrefersUnstable() {
    let r = TailscaleChannel.resolve(unstableEnabled: true, rcEnabled: true)
    #expect(r.channel == .unstable)
}

// MARK: - IINA (`receiveBetaUpdate` Bool → feed swap)

@Test func iinaBetaTrueRetargetsToBetaFeed() {
    let r = IINAChannel.resolve(receiveBeta: true)
    #expect(r.channel == .beta)
    #expect(r.feedOverride == IINAChannel.betaFeed)
}

@Test func iinaBetaFalseStaysOnStableFeed() {
    let r = IINAChannel.resolve(receiveBeta: false)
    #expect(r.channel == .stable)
    #expect(r.feedOverride == IINAChannel.stableFeed)
}

// MARK: - Registry dispatch

@Test func channelBindingDispatchesKnownAppsAndIgnoresOthers() {
    // Unknown / nil bundles get no bespoke resolver → generic detection stays.
    #expect(ChannelBinding.resolve(bundleID: "com.google.Chrome") == nil)
    #expect(ChannelBinding.resolve(bundleID: nil) == nil)
    // Known apps resolve to *something* (live pref read; value machine-dependent).
    #expect(ChannelBinding.resolve(bundleID: ForkChannel.bundleID) != nil)
    #expect(ChannelBinding.resolve(bundleID: OrbStackChannel.bundleID) != nil)
    #expect(ChannelBinding.resolve(bundleID: TailscaleChannel.bundleID) != nil)
    #expect(ChannelBinding.resolve(bundleID: IINAChannel.bundleID) != nil)
}

@Test func channelBindingMatchesBundleIDCaseInsensitively() {
    // TablePlus's real CFBundleIdentifier is `com.tinyapp.TablePlus` (capital T)
    // while our constant / its prefs domain are lower-cased — a case-sensitive
    // switch silently failed to bind and served the stable feed. Dispatch must
    // match regardless of case (matching ChangelogRecipe's convention).
    #expect(ChannelBinding.resolve(bundleID: "com.tinyapp.TablePlus") != nil)
    #expect(ChannelBinding.resolve(bundleID: "COM.DanPristupov.FORK") != nil)
}
