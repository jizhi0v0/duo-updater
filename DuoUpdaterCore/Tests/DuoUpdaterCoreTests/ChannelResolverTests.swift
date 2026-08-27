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

// MARK: - CapCut (`joinBeta` in an INI outside the sandbox container)

@Test func capCutJoinBetaMapsToTheBetaTrack() {
    let stableBuild = "capcutpc_0"
    #expect(CapCutChannel.resolve(joinBeta: true, packageChannel: stableBuild).channel == .beta)
    #expect(CapCutChannel.resolve(joinBeta: false, packageChannel: stableBuild).channel == .stable)
    // A recorded choice wins over the build, in BOTH directions: opting out on a
    // beta build is how a user asks to be moved back to stable.
    #expect(CapCutChannel.resolve(joinBeta: false, packageChannel: "capcutpc_beta").channel
        == .stable)
    #expect(CapCutChannel.resolve(joinBeta: true, packageChannel: nil).channel == .beta)
    // Channel-gated recipes, not a feed swap: CapCut has no appcast to point at.
    let r = CapCutChannel.resolve(joinBeta: true, packageChannel: stableBuild)
    #expect(r.feedOverride == nil)
    #expect(r.feedHTTPHeaders.isEmpty)
    #expect(r.sparkleChannelNames.isEmpty)
}

/// The distinction this resolver exists to keep: "no record" is not "opted out".
///
/// `ChannelBinding` is authoritative — it REPLACES `ReleaseChannel.detect()` —
/// and `updateInfo` is written by the update window, so a beta install that has
/// never opened that window has no record at all. Collapsing that into `.stable`
/// would label it Stable and pin it to a stable recipe reporting an older version
/// than the build it is running. It would also overwrite detect()'s own answer in
/// the case where the beta bundle's version keeps its `-betaN` suffix, which
/// detect() step 4 resolves to `.beta`.
@Test func capCutWithNoRecordedChoiceMirrorsTheInstalledBuild() {
    #expect(CapCutChannel.resolve(joinBeta: nil, packageChannel: "capcutpc_beta").channel
        == .beta)
    #expect(CapCutChannel.resolve(joinBeta: nil, packageChannel: "capcutpc_0").channel
        == .stable)
    // Never escalates when the build says nothing, or says something unfamiliar.
    #expect(CapCutChannel.resolve(joinBeta: nil, packageChannel: nil).channel == .stable)
    #expect(CapCutChannel.resolve(joinBeta: nil, packageChannel: "").channel == .stable)
    #expect(CapCutChannel.resolve(joinBeta: nil, packageChannel: "capcutpc_7").channel
        == .stable)
    // `capcutpc_beta` is the token in the vendor's own beta package name, so a
    // typo here would silently pin every beta build to stable.
    #expect(CapCutChannel.betaPackageToken == "capcutpc_beta")
}

/// The two filenames, pinned.
///
/// Nothing else in the suite would catch a typo in either: the INI parsers are
/// tested against strings, and the watch-root test derives its expectation from
/// `configDirectoryURL`, so it agrees with whatever these say. A wrong filename
/// makes both reads return nil, which resolves to `.stable` — every CapCut
/// install silently pinned to the stable track, with nothing anywhere reading as
/// broken. Same reason `tablePlusUnlockHeaderValueIsTheLiteralServerExpects`
/// exists.
@Test func capCutReadsTheTwoFilesCapCutActuallyWrites() {
    #expect(CapCutChannel.updateInfoFileURL.lastPathComponent == "updateInfo")
    #expect(CapCutChannel.packageChannelFileURL.lastPathComponent == "channel")
    let dir = CapCutChannel.configDirectoryURL.standardizedFileURL.path
    #expect(dir.hasSuffix("/Movies/CapCut/User Data/Config"))
    // Outside the sandbox container on purpose — the container path is the trap
    // this resolver exists to record.
    #expect(!dir.contains("Library/Containers"))
    for file in [CapCutChannel.updateInfoFileURL, CapCutChannel.packageChannelFileURL] {
        #expect(file.deletingLastPathComponent().standardizedFileURL.path == dir)
    }
}

/// The `channel` INI CapCut writes beside `updateInfo`, verbatim from this
/// machine 2026-08-27. It is CapCut's own copy of the bundle's
/// `Contents/Resources/PackageConfig.plist` → `Channel Name`.
@Test func capCutReadsTheBuildChannelOutOfTheRealINI() {
    #expect(CapCutChannel.packageChannel(inINI: "[General]\ntea_channel=capcutpc_0")
        == "capcutpc_0")
    #expect(CapCutChannel.packageChannel(inINI: "[General]\ntea_channel=capcutpc_beta")
        == "capcutpc_beta")
    #expect(CapCutChannel.packageChannel(inINI: "[General]\njoinBeta=true") == nil)
    #expect(CapCutChannel.packageChannel(inINI: "[Other]\ntea_channel=capcutpc_beta") == nil)
    // QSettings quotes values it thinks need it, and CapCut's `looki_settings` in
    // this same directory is full of quoted ones. A quoted token that kept its
    // quotes would stop matching and read as a stable build.
    #expect(CapCutChannel.packageChannel(inINI: "[General]\ntea_channel=\"capcutpc_beta\"")
        == "capcutpc_beta")
    #expect(CapCutChannel.resolve(joinBeta: nil, packageChannel:
        CapCutChannel.packageChannel(inINI: "[General]\ntea_channel=\"capcutpc_beta\"")).channel
        == .beta)
    #expect(CapCutChannel.joinBeta(inINI: "[General]\njoinBeta=\"true\"") == true)
}

/// The exact bytes CapCut writes after the "Get early access to beta features"
/// checkbox is ticked (`~/Movies/CapCut/User Data/Config/updateInfo`, read off
/// this machine 2026-08-27), plus the sibling key that must not be mistaken for
/// it — `need_show_automatic_updates_popup` is about the OTHER settings control.
@Test func capCutReadsJoinBetaOutOfTheRealINI() {
    let on = """
        [General]
        joinBeta=true
        need_show_automatic_updates_popup=false
        """
    let off = """
        [General]
        joinBeta=false
        need_show_automatic_updates_popup=false
        """
    #expect(CapCutChannel.joinBeta(inINI: on) == true)
    #expect(CapCutChannel.joinBeta(inINI: off) == false)
}

/// Everything that is not a value we understand reads as "no record" (nil), which
/// hands the decision to the installed build rather than asserting stable — the
/// distinction `capCutWithNoRecordedChoiceMirrorsTheInstalledBuild` covers. What
/// none of these may do is come back `true`.
@Test func capCutReportsNoChoiceRatherThanGuessingOne() {
    #expect(CapCutChannel.joinBeta(inINI: "") == nil)
    #expect(CapCutChannel.joinBeta(inINI: "[General]") == nil)
    #expect(CapCutChannel.joinBeta(inINI: "[General]\njoinBeta=") == nil)
    #expect(CapCutChannel.joinBeta(inINI: "[General]\njoinBeta=maybe") == nil)
    #expect(CapCutChannel.joinBeta(inINI: "joinBeta=true") == nil, "no section header")
    // The key under a DIFFERENT section is the one a naive substring scan would
    // get wrong, and it would get it wrong in the escalating direction.
    #expect(CapCutChannel.joinBeta(inINI: "[Other]\njoinBeta=true") == nil)
    // ...and a `[General]` section that comes after it still works.
    #expect(CapCutChannel.joinBeta(inINI: "[Other]\njoinBeta=false\n[General]\njoinBeta=true")
        == true)
}

/// Tolerated spellings, so a vendor writing the flag the way its other INIs
/// store booleans doesn't silently pin every user to stable.
@Test func capCutAcceptsTheBooleanSpellingsQtWrites() {
    #expect(CapCutChannel.joinBeta(inINI: "[General]\njoinBeta=1") == true)
    #expect(CapCutChannel.joinBeta(inINI: "[general]\nJoinBeta = TRUE") == true)
    #expect(CapCutChannel.joinBeta(inINI: "[General]\njoinBeta=0") == false)
    // Windows line endings: CapCut is a cross-platform Qt app and `updateInfo` is
    // the same file on both. A parser that split on "\n" alone would leave a
    // trailing "\r" on the value and read every choice as unrecognized.
    #expect(CapCutChannel.joinBeta(inINI: "[General]\r\njoinBeta=true\r\n") == true)
}

// MARK: - Registry dispatch

/// Derived from `boundBundleIDs` rather than hand-listed, because the two halves
/// of a binding are registered in two different places: an id added to
/// `boundBundleIDs` but forgotten in `resolve` would make the menu-bar app
/// recheck that app on every launch, quit and preference write, and resolve
/// nothing each time — a binding that reads as present and does nothing.
@Test func everyBoundIDHasAResolverBehindIt() {
    for id in ChannelBinding.boundBundleIDs {
        #expect(ChannelBinding.resolve(bundleID: id) != nil,
                "\(id) is in boundBundleIDs but ChannelBinding.resolve has no case for it")
    }
}

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
