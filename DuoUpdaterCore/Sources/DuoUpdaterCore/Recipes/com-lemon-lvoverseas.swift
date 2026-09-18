import Foundation

enum com_lemon_lvoverseas {
    static let set = AppRecipeSet(
        family: "com-lemon-lvoverseas",
        probes: [
        // MARK: - 2026-08-27 CapCut (ByteDance)

        // History: docs/app-audits/com-lemon-lvoverseas.md#历史与实测
        // CapCut has no appcast. It embeds Sparkle.framework — and `MacUpdater`
        // inside `libVECreator.dylib` does drive `SUAppcastItem` — but the bundle
        // carries NO `SUFeedURL`, and the decision of *what* to install is made
        // before Sparkle sees it: `UpdateController` reads a block of
        // `update_reminder.*` keys out of ByteDance's Settings SDK blob and
        // synthesizes the item from them. There is no iTunes entry, no GitHub
        // repo, and the vendor's own download page hands out a 3.6 MB
        // `CapCut-Downloader.app` stub rather than a versioned artifact, so this
        // endpoint is the only surface that answers at all.
        //
        // The endpoint is the Settings SDK's own, reconstructed from the shipped
        // binaries rather than guessed: `libSettings.dylib`'s `SettingsRequest.cpp`
        // spells the query (`?device_platform=&channel=&aid=&version_code=…`),
        // `libVECreator.dylib` carries the app id (`359289`), and CapCut's
        // `~/Movies/CapCut/User Data/Config/channel` carries the channel token
        // (`tea_channel=capcutpc_0`). It needs no device id, no install id and no
        // mssdk signature — a plain anonymous GET answers.
        //
        // Two-witness check on the answer, because a per-device rollout endpoint is
        // exactly where an anonymous probe could quietly get a different world than
        // the app does: the `lastest_*` fields in this anonymous response are
        // byte-identical to the ones in the copy CapCut itself cached for this
        // machine (`~/Movies/CapCut/User Data/MMKV/settings_json`, 2026-08-27).
        // What does NOT agree is `update_version`/`update_url` — the vendor's
        // per-device PICK, which was the stable 9.3.0 dmg in CapCut's own cache and
        // the beta 9.4.0-beta4 dmg in the anonymous response. So these recipes read
        // the track fields and never the pick; see `CapCutChannel` for what that
        // divergence means for a user.
        //
        // TRAP, `version_code`: it is required (dropping it, or sending a value the
        // vendor can't parse, removes `update_reminder` from the response entirely)
        // AND it selects a rollout bucket (History has the measured buckets).
        // The stable field was 9.3.0 for every value that answered at all, so only
        // the beta recipe is exposed to this. `9.99` is pinned for both because it
        // sits above every 9.x build the vendor has published — so it stays in the
        // newest bucket rather than ageing into the legacy one, a failure that
        // would be SILENT (so is the vendor rolling every bucket back at once,
        // which no pin avoids — see the audit). Falling out of the window instead
        // (when CapCut reaches 10.x, or if the vendor narrows the range) removes
        // the key and the pattern matches nothing, which `duo verify` reports.
        // Same "pin an impossible version to turn a should-I-update service into a
        // what-is-latest one" move WorkBuddy used to make
        // (`VendorProbeRegistry.workBuddyRecipe`), aimed the other way because
        // CapCut's buckets run the other way — and the direction is why this pin
        // survives while WorkBuddy's did not. WorkBuddy pinned a version BELOW
        // every release and its service answered with an upgrade chain, so the pin
        // froze on the chain's first hop as the vendor shipped past it (#737,
        // #738; that recipe now sends no version at all). A pin ABOVE every
        // release cannot land on a hop — there is nothing above it to step to.
        //
        // What pinning `version_code` COSTS, stated because it is not obvious:
        // CapCut has a working binary-patch path (`UpdatingModel::startRunUpdateDiffPatch`,
        // an `update.delta` alongside `update.dmg`, per-release `cfg.diff_url` /
        // `cfg.diff_md5`, and gray keys `diff_update.enable` /
        // `enable_fallback_try` / `fallback_try_count` / `package_version_mapping`).
        // That last key is the tell: patches are keyed FROM a version TO a version.
        // `9.99` is not a version anyone runs, so a request carrying it can never
        // match a patch mapping — this recipe is structurally cut off from the
        // delta route, not merely unlucky.
        //
        // Note what that evidence IS: `cfg.diff_url=%s` / `cfg.diff_md5=%s` are LOG
        // FORMAT STRINGS in `updatecontroller.cpp` — CapCut printing its own
        // `ReminderUpdateCfg` fields — not fields seen in a response. They prove
        // the client can apply a patch, not that the server sends one.
        //
        // The pin costs nothing today: the vendor ships everyone the full package right
        // now (History has how that was checked). The real blocker is the pinned
        // `version_code` above — a from→to mapping
        // cannot match a version nobody runs — and un-pinning it needs a way to put
        // the installed version on the wire, which no recipe field offers today.
        //
        // Two components, not three, is also load-bearing: `RecipeSanity` complains
        // when an extracted version appears verbatim in the request URL (the tell
        // for a pattern that matched the query instead of the body). `9.3.0` would
        // trip that whenever stable is 9.3.0, as it was when this was written. CapCut versions
        // are always three-segment, so a two-segment `version_code` can never
        // collide with an answer.
        //
        // `channel`: `capcutpc_beta` is a REAL CapCut channel token, and both
        // recipes send `capcutpc_0` instead. The channel a recipe serves is
        // decided by which `lastest_*` key it reads, not by this parameter. The
        // token is currently inert — both values answer with the same
        // `update_reminder` (History has the measurements) — so `capcutpc_0` is
        // kept for its longer measured history, not because `capcutpc_beta` is
        // known to be harmful. Re-measure before changing it.
        //
        // Version scheme: the `lastest_*_version` integers are nibble-packed
        // (590592 = 0x090300 = 9.3.0), which no regex can decode, so the version is
        // read out of the artifact FILENAME instead — `CapCut_9_3_0_4490_…` — with
        // one capture group per segment. `extractVersion` joins multiple groups
        // with ".", which is what turns the vendor's underscores into the string
        // the bundle reports. The `_4490_` build counter is matched and discarded.
        //
        // TRAP, and the reason the two recipes disagree about `versionIsBuild`:
        // **the two tracks put their version in DIFFERENT Info.plist fields**, and
        // they are swapped relative to each other. Both dmgs were downloaded and
        // mounted on 2026-08-27 rather than reasoned about:
        //
        //   CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg
        //       CFBundleShortVersionString  9.3.0
        //       CFBundleVersion             9.3.0
        //   CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg
        //       CFBundleShortVersionString  9.3.4531      ← "9.3" + the build counter
        //       CFBundleVersion             9.4.0-beta4   ← what the filename says
        //
        // So the filename version equals the beta bundle's BUILD field, not its
        // marketing one. With `versionIsBuild: false` the engine would compare
        // `9.4.0-beta4` against a beta install's marketing `9.3.4531` — 4 > 3 —
        // and every beta user would be told to install the build they are already
        // running, forever. `versionIsBuild: true` on the beta recipe routes it
        // into `RemoteVersion.version` so it lands against `CFBundleVersion`, where
        // an up-to-date beta compares EQUAL. Stable needs no such thing (both of
        // its fields are the same string) and must not have it: mixing the two
        // within one channel is what the guard in `channelProofsCoverEveryChannelRecipe`
        // forbids, and across channels they are compared against different
        // installed fields anyway.
        //
        // A consequence worth stating: for a beta install, `ReleaseChannel.detect()`
        // sees only `9.3.4531` — its `-betaN` rule never fires — so the ONLY thing
        // that can classify a beta bundle as beta is `CapCutChannel`. That is why
        // its no-recorded-preference fallback reads the build's own channel token
        // rather than deferring to detect().
        //
        // The channel token in each filename (`capcutpc_0` vs `capcutpc_beta`) is
        // inside the pattern, not around it, so neither recipe can read the other
        // track's artifact even if the vendor reordered the JSON — and the beta
        // pattern is additionally pinned to `lastest_url` so it cannot drift onto
        // `lastest_sync_url`, a THIRD `capcutpc_beta` artifact in the same object
        // (9.3.5-beta1, build 4468 — an older build than the 4531 on `lastest_url`,
        // so taking it would be a silent downgrade of the beta track).
        //
        // Only the beta pattern's third segment tolerates a `-betaN` suffix.
        // Stable's ends at digits, on the Canva precedent: a prerelease wrongly
        // published under `lastest_stable_url` then matches NOTHING and degrades to
        // unknown, instead of being reported as a stable release.
        //
        // One-click: enabled on BOTH tracks. Each dmg holds `CapCut.app` and an
        // `/Applications` symlink and nothing else — no pkg, no
        // `LaunchDaemons`/`LaunchAgents`/`PrivilegedHelperTools` — so the bundle
        // swap IS the whole update (History has how each gate was checked).
        //
        // No `checksumPattern`: the vendor publishes `lastest_stable_url_md5` /
        // `lastest_url_md5`, and `checksumPattern` consumes a base64 SHA-512. An
        // MD5 cannot be fed to it, so the Team-ID gate is the guard here.
        //
        // Cost to know about: each install is a ~1.24 GB download. The registry's
        // live signature-gate test deliberately runs on an allow-list of small
        // artifacts, so adding this does not put a gigabyte into `make test`.
        //
        // `hostRequirement` is Apple silicon, and that is measured, not assumed:
        // `lipo -archs` on the shipped build reports `arm64` and nothing else — on
        // the launcher, on `libVECreator.dylib`, and on `CapCut Helper.app` — so
        // the one dmg the vendor publishes cannot start on an Intel Mac. The
        // vendor's own schema has `lastest_stable_cpu_architecture` /
        // `lastest_cpu_architecture` keys (they are in the binary's string pool)
        // but leaves them absent from the response, i.e. it is serving one
        // artifact to everyone. Without the gate, an Intel Mac holding an older
        // CapCut would be told about a version forever and handed a one-click that
        // `SignatureVerifier`'s arch check can only refuse. Whether an Intel train
        // ever existed is NOT established here — if one turns up, this is the line
        // to revisit, and the shape to copy is Raycast's two-endpoint split.
        //
        // `downloadURL` (the manual fallback) points at the vendor's desktop page
        // for both tracks. That page only ever hands out the stable downloader
        // stub, which used to make it an active hazard for a beta user; with
        // one-click resolving each track's own artifact, the manual link is now the
        // fallback rather than the path, and the alternative (`nil`) would put a
        // ~400 KB internal settings blob behind the user-facing link.
        //
        // A Mac App Store copy of CapCut shares this bundle id — and is a
        // completely different train: `itunes.apple.com/lookup` for
        // `com.lemon.lvoverseas` returns adamId 1500855883 at version **19.2.0**
        // against this Developer ID build's 9.3.0. Nothing here can reach it:
        // `VendorProbeSource.latestVersion(for:)` declines every `isMASApp`
        // install, and `MacAppStoreSource` declines every non-store one, so the
        // separation rests entirely on `_MASReceipt`. Were either gate to go, the
        // two version schemes would produce a permanent phantom in one direction
        // and a store-entitlement-destroying swap in the other.
        //
        // No `changelogURL`: `update_reminder` does carry release notes, but the
        // same generic sentence for all three tracks ("Fixed some known issues…"),
        // and capcut.com publishes no desktop release-notes page. The honest "no release notes" state beats an unrelated page.
        capCutRecipe(
            channel: .stable, urlKey: "lastest_stable_url",
            packageToken: "capcutpc_0", patchSegment: #"[0-9]+"#,
            versionIsBuild: false),
        // The beta track is not always open. When a beta graduates and no new one
        // has started, `lastest_url` carries the STABLE artifact — the pattern
        // pins `capcutpc_beta` inside the filename, so it correctly refuses to
        // read a stable build as a beta one, and the probe finds nothing.
        //
        // `lastest_beta_number` is the vendor saying so in their own data: "4"
        // while beta4 was current (2026-08-27), empty once 9.4.0 shipped and no
        // beta replaced it (2026-09-04, with `lastest_url` == `lastest_stable_url`
        // == the 9.4.0 stable dmg). Without this the row went red, with a Retry
        // that could not work until ByteDance opened the next beta.
        //
        // Anchored to the key so it cannot be satisfied by an empty string
        // anywhere else in a ~436 KB body.
        capCutRecipe(
            channel: .beta, urlKey: "lastest_url",
            packageToken: "capcutpc_beta", patchSegment: #"[0-9]+(?:-beta[0-9]+)?"#,
            versionIsBuild: true,
            trackClosedPattern: ##""lastest_beta_number"\s*:\s*"""##),
        ],
        channelProofs: [
        // CapCut's two tracks share one bundle id, one app name and one endpoint —
        // the beta build does not even carry a channel word in the version
        // `ReleaseChannel.detect()` reads (`9.3.4531`). The artifact name is where
        // the vendor does say it: stable ships `…_capcutpc_0_creatortool.dmg` and
        // beta `…_capcutpc_beta_creatortool.dmg`, and `capcutpc_beta` was read off
        // the beta bundle's own `Contents/Resources/PackageConfig.plist` →
        // `Channel Name` after mounting it (2026-08-27), so this is the vendor's
        // own token rather than a filename convention we inferred.
        ChannelProofKey("com.lemon.lvoverseas", .beta): .artifact(#"_capcutpc_beta_"#),
        ])

    /// One CapCut track: the `update_reminder` key that names its artifact, plus
    /// the token that artifact's filename carries.
    ///
    /// Those two thread through both patterns, which is the point of building them
    /// here instead of writing them out twice. The version and the installer must
    /// come from the SAME key — `update_reminder` holds four CapCut dmg URLs under
    /// four keys, two of which name the same file today — and a hand-written pair
    /// is exactly how one of them ends up reading `lastest_url` while the other
    /// reads `lastest_sync_url`, resolving a version and an installer from two
    /// different releases with nothing downstream able to see it.
    ///
    /// The endpoint is built once for the same reason: two copies could drift onto
    /// different `version_code` rollout buckets.
    private static func capCutRecipe(
        channel: ReleaseChannel,
        urlKey: String,
        packageToken: String,
        patchSegment: String,
        versionIsBuild: Bool,
        trackClosedPattern: String? = nil
    ) -> VendorProbeRecipe {
        let host = #"https://sf16-web-tos-buz\.capcutstatic\.com"#
        return VendorProbeRecipe(
            bundleID: CapCutChannel.bundleID,
            url: URL(string: "https://editor-api.capcutapi.com/service/settings/v3/"
                     + "?aid=359289&device_platform=mac&channel=capcutpc_0&version_code=9.99")!,
            mode: .responseBody,
            versionPattern:
                #""\#(urlKey)"\s*:\s*"[^"]*/CapCut_([0-9]+)_([0-9]+)_(\#(patchSegment))_[0-9]+_\#(packageToken)_creatortool\.dmg""#,
            // ByteDance's settings service overrunning its own 500 ms internal RPC
            // budget: HTTP 200, `{"data": {},"message": "ExecBizCode error: …
            // request timeout … real_time=501018us"}`, ~390 bytes where the answer
            // is ~436 KB. An empty TOP-LEVEL `data` is the structural claim "no
            // settings were returned"; the message text is an internal stack trace
            // and is not matched on. See `transientBodyPattern`.
            transientBodyPattern: #"^\s*\{\s*"data"\s*:\s*\{\s*\}"#,
            trackClosedPattern: trackClosedPattern,
            downloadURL: URL(string: "https://www.capcut.com/tools/desktop-video-editor"),
            versionIsBuild: versionIsBuild,
            install: VendorInstallSpec(
                // Host pinned rather than `[^"]+`: the channel token and the host
                // are the only things in a resolved URL that say what this file is.
                urlSource: .bodyPattern(
                    #""\#(urlKey)"\s*:\s*"(\#(host)/[^"]*_\#(packageToken)_creatortool\.dmg)""#),
                kind: .dmg),
            channel: channel,
            hostRequirement: VendorHostRequirement(architectures: [.arm64]))
    }
}
