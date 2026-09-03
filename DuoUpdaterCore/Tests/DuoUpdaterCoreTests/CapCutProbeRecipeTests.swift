import Testing
import Foundation
@testable import DuoUpdaterCore

/// CapCut's two-track probe.
///
/// The recipes are looked up from the registry rather than restated here, and
/// both are exercised against the `update_reminder` object captured VERBATIM from
/// the vendor on 2026-08-27. That object is the whole hazard surface: it holds
/// three `capcutpc_beta` artifacts and one `capcutpc_0` artifact side by side, so
/// a pattern that is one key off resolves a real, live, correctly-signed build
/// from the wrong track.
struct CapCutProbeRecipeTests {

    /// Verbatim slice of
    /// `https://editor-api.capcutapi.com/service/settings/v3/?aid=359289&device_platform=mac&channel=capcutpc_0&version_code=9.99`,
    /// 2026-08-27 — key order, spacing and all. The full response is ~376 KB of
    /// unrelated feature flags; each recipe's pattern was confirmed to match
    /// EXACTLY ONCE in that whole body, so keeping only this object here loses no
    /// discriminating power (every other `CapCut_…dmg` string in the response is
    /// in this object).
    ///
    /// The three decoys are the point:
    ///   * `update_url`      — the vendor's per-DEVICE pick. Identical to the beta
    ///                         URL for an anonymous request and to the STABLE one
    ///                         in the copy CapCut cached for this machine, which
    ///                         is exactly why no recipe may read it.
    ///   * `lastest_sync_url`— a third `capcutpc_beta` artifact, build 4468 —
    ///                         OLDER than `lastest_url`'s 4531.
    ///   * `lastest_stable_url` vs `lastest_url` — one substring apart.
    private static let body = """
        {"data":{"__logid":"20260827175208134E0787F4B71D1BCC4E","settings_time":1787651528,\
        "settings":{"update_reminder": {"lastest_stable_url_md5": "5e95c2e4cd0fed91d9f49a9d386717af", \
        "update_frequency": 1, "current_version": 99900, "lastest_stable_version": 590592, \
        "alwaysremind": 1, "lastest_stable_update_content": "- Fixed some known issues and improved \
        the trimming experience.\\nWe thank you for supporting CapCut and look forward to creating \
        beautiful moments together.", "build_number": 4531, "lastest_sync_builder_number": 4468, \
        "lastest_stable_builder_number": 4490, "lastest_sync_url": \
        "https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_3_5-beta1_4468_capcutpc_beta_creatortool.dmg", \
        "update_version": 590848, "timeinterval": 72, "update_url_md5": "bafa43171d14a736f255436447e52471", \
        "lastest_sync_url_md5": "2f09cdbcc3c3e4f06135de7ea10c499a", "updatestyle": "prompt", \
        "lastest_builder_number": 4531, "lastest_url_md5": "bafa43171d14a736f255436447e52471", \
        "beta_number": "4", "lastest_version": 590848, "lastest_sync_version": 590597, \
        "lastest_beta_number": "4", "lastest_url": \
        "https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg", \
        "update_url": \
        "https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg", \
        "lastest_stable_url": \
        "https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg"}}},\
        "message": "success"}
        """

    /// What each track's bundle actually reports, read off the real artifacts on
    /// 2026-08-27 — the stable one from `/Applications/CapCut.app`, the beta one by
    /// downloading and mounting `CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg`.
    ///
    /// The two tracks do NOT agree about which field carries what, and that is the
    /// single most surprising fact about this app: stable puts the same string in
    /// both fields, while beta's marketing version is `"9.3" + build counter` and
    /// only its `CFBundleVersion` matches the filename. Hence one recipe with
    /// `versionIsBuild` and one without.
    private static let installedStableShortVersion = "9.3.0"
    private static let installedStableBuildVersion = "9.3.0"
    private static let installedBetaShortVersion = "9.3.4531"
    private static let installedBetaBuildVersion = "9.4.0-beta4"

    private static let recipes = VendorProbeRegistry.recipes
        .filter { $0.bundleID == CapCutChannel.bundleID }

    private static func recipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
        try #require(recipes.first { $0.channel == channel },
                     "no CapCut recipe for \(channel.rawValue)")
    }

    private static func version(_ recipe: VendorProbeRecipe, in text: String) -> String? {
        VendorProbeRecipe.extractVersion(from: text, pattern: recipe.versionPattern)
    }

    /// The installer URL a track's spec resolves out of `text`, or nil when the
    /// pattern matches nothing.
    ///
    /// Records an issue rather than returning nil when the spec is not a
    /// `.bodyPattern`, because three of the tests below assert a nil result: a
    /// silent `return nil` on a changed spec shape would turn each of them into a
    /// no-op that still reports green.
    private static func installURL(
        _ channel: ReleaseChannel, in text: String
    ) throws -> String? {
        let recipe = try Self.recipe(channel)
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record(
                "\(recipe.recipeID) is no longer a body-pattern install; every nil-result assertion in this suite has gone vacuous")
            return nil
        }
        return VendorProbeRecipe.extractVersion(from: text, pattern: pattern)
    }

    // MARK: - registry shape

    /// Derived from the registry, not a hand-written list: a third CapCut track
    /// added later shows up here as a failure rather than as silent non-coverage.
    @Test func capCutRegistersExactlyTheTwoTracksTheVendorPublishes() {
        #expect(Set(Self.recipes.map(\.channel)) == [.stable, .beta])
        #expect(Self.recipes.count == 2)
        for recipe in Self.recipes {
            #expect(recipe.variant == nil)
            // Apple silicon only — `lipo -archs` on the shipped build reports
            // `arm64` alone (launcher, libVECreator, and the helper app), and the
            // vendor publishes ONE dmg. Without this an Intel Mac would be shown a
            // version forever and handed a one-click the arch gate can only refuse.
            #expect(recipe.hostRequirement?.architectures == [.arm64])
            // No machine identifier and no rollout selector go on the wire: the
            // endpoint answers anonymously, and keeping it that way is what stops
            // this machine's ByteDance device id from reaching a verify report.
            #expect(recipe.identities.isEmpty && recipe.track == nil)
            #expect(recipe.install?.kind == .dmg)
            #expect(recipe.install?.checksumPattern == nil,
                    "the vendor publishes MD5; checksumPattern consumes base64 SHA-512")
            #expect(recipe.changelogURL == nil, "no vendor release-notes page exists")
            if case .responseBody = recipe.mode {} else {
                Issue.record("\(recipe.recipeID) is not a body-parsing recipe")
            }
        }
    }

    /// Both tracks come off ONE endpoint. If they ever diverge, they can land in
    /// different `version_code` rollout buckets and quietly report builds from two
    /// different worlds — the failure the shared `capCutRecipe` helper exists to
    /// make impossible.
    @Test func bothTracksReadTheSameEndpoint() throws {
        let urls = Set(Self.recipes.map(\.url))
        #expect(urls.count == 1)
        let url = try #require(urls.first)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.name, $0.value ?? "") }) })
        // Every one of these is REQUIRED: drop any and the response comes back
        // with no `update_reminder` at all (measured 2026-08-27).
        #expect(query["aid"] == "359289")
        #expect(query["device_platform"] == "mac")
        #expect(query["version_code"] == "9.99")
        // `capcutpc_beta` is a real CapCut channel token and returns NOTHING here.
        // The beta track is selected by which key the pattern reads, never by this.
        #expect(query["channel"] == "capcutpc_0")
    }

    /// `version_code` must stay two-segment, and this is the structural reason
    /// rather than today's-answer reason: `RecipeSanity` flags a version that
    /// appears verbatim in the request URL — the tell for a pattern that matched
    /// the query instead of the body — and every CapCut release is three-segment,
    /// so a two-segment query value can never BE an answer. Bumping the pinned
    /// value to `9.3.0` would pass on the day it was written and start crying wolf
    /// the moment the vendor's stable release caught up with it.
    @Test func theVersionCodeCanNeverCollideWithAnAnswer() throws {
        let url = try #require(Self.recipes.first?.url)
        let versionCode = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "version_code" }?.value)
        #expect(versionCode.split(separator: ".").count == 2,
                "'\(versionCode)' has as many segments as a CapCut release, so it can collide")
        for channel in [ReleaseChannel.stable, .beta] {
            let recipe = try Self.recipe(channel)
            let version = try #require(Self.version(recipe, in: Self.body))
            #expect(RecipeSanity.complaints(version: version, recipe: recipe).isEmpty,
                    "\(recipe.recipeID) resolved '\(version)', which RecipeSanity objects to")
        }
    }

    // MARK: - the version

    /// The stable track resolves the marketing version the installed bundle
    /// reports, dots and all — the underscore→dot join is what makes an
    /// up-to-date CapCut compare equal instead of showing a phantom update.
    @Test func theStableTrackMatchesTheInstalledMarketingVersion() throws {
        let recipe = try Self.recipe(.stable)
        #expect(recipe.versionIsBuild == false,
                "stable's marketing and build fields are the same string")
        let version = try #require(Self.version(recipe, in: Self.body))
        #expect(version == Self.installedStableShortVersion)
        #expect(VersionComparator.compare(version, Self.installedStableShortVersion)
            == .orderedSame,
            "an up-to-date CapCut would be shown a phantom update")
    }

    /// The beta track resolves the newest beta build, suffix intact.
    @Test func theBetaTrackResolvesTheNewestBetaBuild() throws {
        let recipe = try Self.recipe(.beta)
        #expect(Self.version(recipe, in: Self.body) == "9.4.0-beta4")
    }

    /// The regression that only downloading the real beta artifact could find:
    /// the two tracks put their version in DIFFERENT Info.plist fields.
    ///
    /// The beta bundle's marketing version is `9.3.4531` while the filename (and
    /// its `CFBundleVersion`) say `9.4.0-beta4`. Compared as a marketing version —
    /// which is what `versionIsBuild: false` would do — `9.4.0-beta4` beats
    /// `9.3.4531` at the second component, 4 > 3, so a user sitting on exactly the
    /// build the feed is offering would be told to install it, every check,
    /// forever. Against `CFBundleVersion` it compares equal.
    @Test func theBetaTrackComparesAgainstTheFieldThatActuallyMatches() throws {
        let recipe = try Self.recipe(.beta)
        #expect(recipe.versionIsBuild,
                "beta's filename version is its CFBundleVersion, not its marketing string")
        let version = try #require(Self.version(recipe, in: Self.body))
        #expect(version == Self.installedBetaBuildVersion)
        #expect(VersionComparator.compare(version, Self.installedBetaBuildVersion)
            == .orderedSame,
            "an up-to-date CapCut beta would be shown a phantom update")
        // The failure this guards, spelled out: against the marketing field the
        // same pair reads as an update.
        #expect(VersionComparator.isNewer(version, than: Self.installedBetaShortVersion),
                "if this stops being true the phantom is gone and this test lost its subject")
        // A stable install that opted into betas must still be offered the beta:
        // its CFBundleVersion is the plain 9.3.0.
        #expect(VersionComparator.isNewer(version, than: Self.installedStableBuildVersion))
    }

    /// The vendor's build counter (`4490`, `4531`) is matched and discarded. It is
    /// in neither `CFBundleShortVersionString` nor `CFBundleVersion` — both are the
    /// bare "9.3.0" — so letting it into the version would be a phantom that never
    /// clears.
    @Test func theBuildCounterNeverReachesTheVersion() throws {
        for channel in [ReleaseChannel.stable, .beta] {
            let version = try #require(Self.version(try Self.recipe(channel), in: Self.body))
            #expect(!version.contains("4490") && !version.contains("4531"))
        }
    }

    // MARK: - one-click

    /// The installer and the version must come out of the SAME `update_reminder`
    /// key. The object holds four CapCut dmg URLs under four keys — two of them
    /// naming the same file today — so a version pattern reading one and an
    /// install pattern reading another would resolve two different releases, and
    /// every gate downstream would still pass: same vendor, same Team, a real
    /// notarized bundle.
    @Test func eachTrackInstallsTheReleaseItReported() throws {
        for channel in [ReleaseChannel.stable, .beta] {
            let recipe = try Self.recipe(channel)
            let version = try #require(Self.version(recipe, in: Self.body))
            let url = try #require(try Self.installURL(channel, in: Self.body))
            #expect(url.hasPrefix("https://sf16-web-tos-buz.capcutstatic.com/"),
                    "the download host must be pinned, not matched with [^\"]+")
            // The vendor writes the version with underscores in the filename.
            #expect(url.contains(version.replacingOccurrences(of: ".", with: "_")),
                    "\(recipe.recipeID) reported \(version) but would download \(url)")
        }
    }

    /// Neither install spec may resolve the other track's artifact — the silent
    /// cross-channel swap `ChannelArtifactProof` exists for. Both the key and the
    /// `capcutpc_<token>` in the filename are pinned, so this holds in both
    /// directions and regardless of JSON order.
    @Test func neitherInstallSpecCanResolveTheOthersArtifact() throws {
        let stableOnly = """
            {"lastest_stable_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg"}
            """
        let betaOnly = """
            {"lastest_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg"}
            """
        #expect(try Self.installURL(.stable, in: betaOnly) == nil)
        #expect(try Self.installURL(.beta, in: stableOnly) == nil)
        // On the real body the beta spec must take `lastest_url`, never the older
        // `lastest_sync_url` build that sits ahead of it in the object.
        let beta = try #require(try Self.installURL(.beta, in: Self.body))
        #expect(beta.hasSuffix("CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg"))
    }

    /// The registered proof must actually match what the beta spec resolves —
    /// a proof that no longer describes its recipe asserts nothing.
    @Test func theRegisteredBetaProofMatchesTheResolvedArtifact() throws {
        let proof = try #require(
            ChannelProofRegistry.proofs[ChannelProofKey(CapCutChannel.bundleID, .beta)])
        guard case .artifact(let marker) = proof else {
            Issue.record("CapCut beta's proof should be an artifact marker")
            return
        }
        let url = try #require(try Self.installURL(.beta, in: Self.body))
        #expect(url.range(of: marker, options: [.regularExpression, .caseInsensitive]) != nil)
        // ...and must NOT match the stable artifact, or it proves nothing.
        let stableURL = try #require(try Self.installURL(.stable, in: Self.body))
        #expect(stableURL.range(of: marker, options: [.regularExpression, .caseInsensitive])
            == nil)
    }

    // MARK: - version ordering

    /// The `-betaN` suffix sorts BELOW the suffix-less string a bundle reports
    /// (the Mozilla `bN` precedent), so the beta recipe cannot phantom against an
    /// install of that same marketing version — and a real version bump still
    /// reads as newer.
    @Test func theBetaSuffixSortsAsAPreReleaseRatherThanAhead() {
        #expect(VersionComparator.isNewer("9.4.0-beta4", than: "9.4.0") == false)
        #expect(VersionComparator.isNewer("9.4.0-beta4", than: "9.3.0"))
        #expect(VersionComparator.isNewer("9.5.0-beta1", than: "9.4.0-beta4"))
    }

    // MARK: - cross-track isolation

    /// Neither pattern may read the other track's artifact. Both the KEY and the
    /// `capcutpc_<token>` inside the filename are pinned, so this holds even if
    /// the vendor reorders the object.
    @Test func neitherTrackCanResolveTheOthersArtifact() throws {
        let stableOnly = """
            {"lastest_stable_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg"}
            """
        let betaOnly = """
            {"lastest_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg"}
            """
        #expect(Self.version(try Self.recipe(.stable), in: betaOnly) == nil)
        #expect(Self.version(try Self.recipe(.beta), in: stableOnly) == nil)
    }

    /// `lastest_sync_url` is a THIRD `capcutpc_beta` artifact in the same object,
    /// at an OLDER build (4468 against 4531). A beta pattern anchored on the
    /// filename alone would match it, and on this body it comes first — so the
    /// probe would have silently reported 9.3.5-beta1 as the newest beta.
    @Test func theBetaTrackIgnoresTheSyncArtifact() throws {
        let syncOnly = """
            {"lastest_sync_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_3_5-beta1_4468_capcutpc_beta_creatortool.dmg"}
            """
        #expect(Self.version(try Self.recipe(.beta), in: syncOnly) == nil)
        // And on the real body, where the sync key is listed BEFORE `lastest_url`.
        #expect(Self.version(try Self.recipe(.beta), in: Self.body) != "9.3.5-beta1")
    }

    /// `update_url` is the vendor's per-device pick, not a track. It was the
    /// STABLE dmg in the copy CapCut cached for this machine and the BETA dmg in
    /// the anonymous response captured here — the same key, two different answers
    /// — so no recipe may be anchored to it.
    @Test func noRecipeReadsThePerDevicePick() throws {
        for recipe in Self.recipes {
            #expect(!recipe.versionPattern.contains("\"update_url\""),
                    "\(recipe.recipeID) is anchored to the per-device pick")
        }
        let pickOnly = """
            {"update_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg"}
            """
        for recipe in Self.recipes {
            #expect(Self.version(recipe, in: pickOnly) == nil)
        }
    }

    /// A response with no `update_reminder` at all — what the endpoint returns
    /// once a `version_code` falls outside the vendor's rollout window — must
    /// resolve NOTHING rather than something. That is the loud failure the pinned
    /// `9.99` trades for, and `duo verify` reports it.
    @Test func aResponseWithoutUpdateReminderResolvesNothing() throws {
        let empty = """
            {"data":{"__logid":"20260827175208134E0787F4B71D1BCC4E",\
            "settings_time":1787651528},"message": "success"}
            """
        for recipe in Self.recipes {
            #expect(Self.version(recipe, in: empty) == nil)
        }
    }

    // MARK: - the vendor's own error envelope

    /// Verbatim, 2026-09-01: one of 24 parallel requests came back with this
    /// instead of the ~436 KB answer, **HTTP 200**. ByteDance's internal RPC
    /// overran its own 500 ms budget (`request_timeout=500ms`, `real_time=501018us`)
    /// and the edge served the failure as a success. The shipping app hit it twice
    /// in two minutes the same evening.
    private static let errorEnvelope = """
        {"data": {},"message": "ExecBizCode error: GetPyCodeSettings error: \
        GetSettingsFromPython error, err = remote or network error[remote]: \
        error_code=1204 cds_key=THRIFT_EGRESS|toutiao.settings.settings:sg:sg1:| \
        GetBizSettingsJson|prod| reason=request timeout connect_timeout=100ms(from cp) \
        request_timeout=500ms(from cp) real_time=501018us fault_delay=0ms"}
        """

    /// The half that made this look like a broken recipe: no pattern matches, so
    /// without the declaration below the probe reports `versionPatternNoMatch` —
    /// "go fix this recipe" — for a vendor having a bad half-second.
    @Test func theErrorEnvelopeCarriesNoVersionForEitherTrack() throws {
        for recipe in Self.recipes {
            #expect(Self.version(recipe, in: Self.errorEnvelope) == nil)
            #expect(try Self.installURL(recipe.channel, in: Self.errorEnvelope) == nil)
        }
    }

    /// Both tracks recognise it, since both read the same endpoint.
    @Test func bothTracksRecogniseTheErrorEnvelope() {
        for recipe in Self.recipes {
            #expect(recipe.transientBodyPattern != nil,
                    "\(recipe.recipeID) no longer declares the vendor's error envelope")
            #expect(recipe.matchesTransientBody(Self.errorEnvelope))
        }
    }

    /// The direction that matters more: the pattern must never fire on an answer.
    /// It wins over `versionPatternNoMatch`, so one that over-matches converts a
    /// genuinely broken recipe into "the vendor is having a bad day" forever, and
    /// `duo verify` stops filing it.
    ///
    /// The third body is the one that could plausibly be confused: a real answer
    /// whose `update_reminder` is MISSING, which is what the endpoint returns when
    /// the pinned `version_code` falls out of the vendor's rollout window. That is
    /// a loud recipe failure by design (see `aResponseWithoutUpdateReminderResolvesNothing`)
    /// and must stay one — its `data` is populated, the envelope's is empty.
    @Test func theEnvelopePatternNeverFiresOnAnAnswer() throws {
        // Verbatim opening of the REAL out-of-window response — captured
        // 2026-09-01 at `version_code=99.9.9`, 647,199 bytes, no
        // `update_reminder` anywhere in it. A hand-written approximation would
        // have been proving the shape someone imagined; what makes this body
        // safe is that the vendor still fills `data` when it declines to answer,
        // and only a capture can say that. (The full body is not kept: the
        // pattern is anchored to the document start, so its opening IS the part
        // under test. Checked whole once, along with the 435,426-byte healthy
        // body and the 379,393-byte `version_code=9` response — none matches.)
        let withoutUpdateReminder = """
            {"data":{"__logid":"20260901182107D626FCBA7EEEAE142266",\
            "settings_time":1788085267,"settings":{"lip_sync_ab_test": {"enable": true}, \
            "veabtest_enable_decoder_d3d11_sync_opt": false}}}
            """
        // An empty `data` nested somewhere inside a real answer — the shape an
        // unanchored pattern would trip on. (Measured: the real 436 KB body has
        // no empty `data` object anywhere in it, so this is a guard against the
        // body they serve next year, not against today's.)
        let nestedEmptyData = """
            {"data":{"settings":{"some_feature": {"data": {}},"update_reminder": \
            {"lastest_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg"}}},\
            "message": "success"}
            """
        for recipe in Self.recipes {
            #expect(!recipe.matchesTransientBody(Self.body))
            #expect(!recipe.matchesTransientBody(withoutUpdateReminder))
            #expect(!recipe.matchesTransientBody(nestedEmptyData))
        }
        // …and the nested-empty-data body is still a body a recipe can read, so
        // the assertion above is about the envelope pattern and not about a body
        // nothing could parse.
        #expect(Self.version(try Self.recipe(.beta), in: nestedEmptyData) == "9.4.0-beta4")
    }

    /// A beta build published without a `-betaN` suffix still resolves — the
    /// suffix is optional — and still cannot be confused with a stable artifact.
    @Test func aSuffixLessBetaBuildStillResolves() throws {
        let plain = """
            {"lastest_url": "https://sf16-web-tos-buz.capcutstatic.com/obj/\
            capcut-web-buz-sg/packages/CapCut_9_4_1_4600_capcutpc_beta_creatortool.dmg"}
            """
        #expect(Self.version(try Self.recipe(.beta), in: plain) == "9.4.1")
        #expect(Self.version(try Self.recipe(.stable), in: plain) == nil)
    }
}
