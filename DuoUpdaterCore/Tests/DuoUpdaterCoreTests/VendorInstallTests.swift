import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Live verification of the vendor in-place install pipeline — WITHOUT the final
/// swap, so it never touches the installed apps. Confirms the two things that
/// can't be unit-tested offline: that each recipe resolves a real installer URL,
/// and that a downloaded build passes the mandatory code-signature + Team ID gate.

/// Every recipe with an install spec must resolve a concrete download URL + kind
/// from its live feed — on ITS OWN channel. Prints the plan to stderr.
///
/// The stable half is a curated smoke list: `duo verify` sweeps all ~55 stable
/// install recipes nightly (with per-host throttling, retries and a baseline), so
/// there is no reason to re-run that breadth on every `swift test`.
///
/// The non-stable half is NOT curated — it is derived from the registry, so every
/// channel recipe is covered and a new one cannot be added without appearing here.
/// Channels get the stricter treatment for two reasons. They are the ones written
/// by copying a stable sibling, which is how Signal Beta ended up reusing stable's
/// dmg filename pattern: the version still resolved, one-click silently degraded
/// to detection-only, and nothing anywhere reported it. And they are the ones
/// where "it resolved something" is not enough — resolving the STABLE artifact
/// for a Beta install passes every other check, including the Team-ID gate, so
/// each one is held to `ChannelProofRegistry`'s marker for its own train.
///
/// The channel is load-bearing in the fixture too: `VendorProbeSource` only picks
/// a recipe whose channel matches the app's, and `InstalledApp.releaseChannel`
/// defaults to `.stable` — a bundleID-only list exercised nothing but stable.
/// Setting it directly deliberately bypasses scan-time detection (Mozilla's
/// `RemotingName`, Android Studio's channel-marked bundle filename, Tailscale's
/// `UnstableUpdatesEnabled`); `ChannelGuardTests` covers that half. It also leaves
/// `isToolboxManaged` false, so JetBrains/Android Studio are exercised on their
/// website-install path — the Toolbox gate is pinned separately in
/// `toolboxManagedCopiesResolveDetectionOnly`.
@Test func vendorResolvesInstallPlans() async {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    // The stable bundles we've enabled for one-click install (zip/dmg/tarGz swap,
    // or pkg → system installer).
    let stable: [(id: String, channel: ReleaseChannel)] = [
        ("com.microsoft.VSCode", .stable), ("app.chatwise", .stable),
        ("com.openai.codex", .stable), ("com.conductor.app", .stable),
        ("org.videolan.vlc", .stable), ("dev.kdrag0n.MacVirt", .stable),
        ("io.tailscale.ipn.macsys", .stable), ("com.anthropic.claudefordesktop", .stable),
        ("ai.elementlabs.lmstudio", .stable), ("dev.warp.Warp-Stable", .stable),
        ("com.google.android.studio", .stable),  // website-install path (Toolbox copies are gated)
        ("com.oray.sunlogin.macclient", .stable),  // AweSun: pkg → system installer (WAF Referer)
        ("com.postmanlabs.mac", .stable),          // Postman: zip → in-place (self-updater, same Team)
        // Signal stable's sibling is derived below; keep stable here so the pair is
        // always resolved together — the two feeds are what got confused.
        ("org.whispersystems.signal-desktop", .stable),
        // Outlook: pkg → system installer. Absent from this list, the 2026-08-09
        // breakage (Microsoft dropped the key the install spec read) showed up
        // nowhere — the version kept resolving and one-click just stopped
        // existing. This live check is what makes that loud.
        ("com.microsoft.Outlook", .stable),
    ]
    let targets =
        stable.map { ChannelProofKey($0.id, $0.channel) }
        + ChannelProofRegistry.channelRecipesWithInstall.sorted {
            ($0.bundleID, $0.channel.rawValue) < ($1.bundleID, $1.channel.rawValue)
        }
    let byKey = Dictionary(
        VendorProbeRegistry.recipes.filter { $0.install != nil }
            .map { (ChannelProofKey($0.bundleID, $0.channel), $0) },
        uniquingKeysWith: { a, _ in a })

    let source = VendorProbeSource()
    func probe(_ key: ChannelProofKey) async -> RemoteVersion? {
        let app = InstalledApp(
            name: key.bundleID, bundleID: key.bundleID,
            shortVersion: "0.0.0", buildVersion: "0",
            path: URL(fileURLWithPath: "/Applications/\(key.bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: key.channel)
        return (try? await source.latestVersion(for: app)) ?? nil
    }

    // Bounded fan-out: firing all ~45 feed fetches at once is both rude to the
    // vendors and enough contention to time a probe out while the rest of this
    // suite is downloading, which showed up as a spurious "resolved no URL". A
    // miss is retried ONCE and the retry is logged — the breakage this guards
    // against is deterministic and fails both attempts; a network blip does not.
    var results: [ChannelProofKey: RemoteVersion?] = [:]
    for chunk in stride(from: 0, to: targets.count, by: 12).map({
        Array(targets[$0..<min($0 + 12, targets.count)])
    }) {
        await withTaskGroup(of: (ChannelProofKey, RemoteVersion?).self) { group in
            for key in chunk { group.addTask { (key, await probe(key)) } }
            for await (key, remote) in group { results[key] = remote }
        }
    }
    var retried: [ChannelProofKey] = []
    for key in targets where (results[key] ?? nil)?.downloadURL == nil {
        retried.append(key)
        results[key] = await probe(key)
    }

    log("\n=== vendor install plans (\(targets.count) recipes) ===")
    if !retried.isEmpty {
        log("↻ retried after a first-pass miss: \(retried.map(\.description).joined(separator: ", "))")
    }
    // Tracks the vendor is currently between releases on — derived from the
    // registry, never hand-listed.
    //
    // A channel recipe that resolves nothing is normally rot, which is what this
    // sweep exists to catch. It is not rot when the vendor has closed a track,
    // and the recipe says which tracks can be closed by carrying a
    // `trackClosedPattern` — the vendor's own statement that nothing is
    // published there (CapCut empties `lastest_beta_number` between betas).
    //
    // Reading it off the registry rather than repeating the key here is the
    // difference between one source of truth and two that drift: a hand-written
    // list goes on exempting a recipe whose declaration was removed.
    let dormantTracks = Set(
        byKey.values.filter { $0.trackClosedPattern != nil }
            .map { ChannelProofKey($0.bundleID, $0.channel) })

    // Recipes whose probe cannot even be addressed from this machine, because the
    // endpoint is keyed by an identifier the vendor's own app writes locally —
    // Codex reads an `installationId` out of Application Support, and without it
    // `VendorProbeSource` answers `.notApplicable("no device identity at …")`
    // rather than failing. That is the recipe working as designed, and on a
    // machine where the app is not installed it is the ONLY possible answer.
    //
    // The first CI run failed here for exactly that reason and it read like a
    // vendor outage: `com.openai.codex [stable]: v?  [nil] — NO URL`. It is the
    // same shape as CleanShot's resolver — a test that passes for whoever has the
    // app installed and fails for everyone else — and the same shape as running
    // this suite anywhere but the author's Mac.
    //
    // Derived from the registry, and — following what 0113017 fixed for track
    // closure — exempt by RESULT, not by declaration: a recipe is skipped only
    // when its identity is actually absent here. A machine that has the app must
    // go on being covered, or the exemption quietly deletes the coverage it was
    // meant to preserve.
    // `localReads`, not `identities`. That property exists precisely so guards
    // derive from ONE list — its own doc records that splitting the rollout track
    // out of `identities` broke two guards the day it happened, and enumerating
    // `identities` here would have made this the third. A track selector with no
    // fallback answers `.notApplicable("no rollout track at …")` the same way.
    //
    // The file being absent is NOT on its own the production rule. Production asks
    // `identity.resolve(endpoint)`, which stands a declared `fallback` in for an
    // unreadable value — so an identity with a fallback is fully addressable on a
    // machine that has no such file, and exempting it for that would hand a
    // genuine vendor breakage a free pass.
    //
    // ANY unaddressable read, not all of them. `resolveEndpoint` substitutes the
    // reads in order and returns `.notApplicable` at the FIRST one that resolves
    // to nil, so one such read decides the whole probe and the rest are never
    // consulted. `allSatisfy` was the first version of this line and it was wrong
    // in the direction that costs a green build: codex declares two reads, and the
    // second one — the plan_type claim — carries `fallback: "unknown"` by design,
    // so "every read is unaddressable" is false on a machine that has neither
    // file. CI failed on exactly that (2026-09-05, run 33946637714:
    // `com.openai.codex [stable] resolved no installer URL`) while the author's
    // Mac, which has both files, stayed green — the same everyone-but-me shape
    // this exemption exists to remove. Measured on both sides:
    //
    //   author's Mac : bootstrap.json value=SET fallback=nil |
    //                  ~/.codex/auth.json value=SET fallback=unknown  → probed
    //   hosted runner: both value=nil                                 → exempt
    let unaddressableKeys = Set(
        byKey.values
            .filter { recipe in
                recipe.localReads.contains { $0.value() == nil && $0.fallback == nil }
            }
            .map { ChannelProofKey($0.bundleID, $0.channel) })

    for key in targets {
        let remote = results[key] ?? nil
        // Only when it actually resolved nothing. `trackClosedPattern` is a
        // permanent property of the recipe — it says how this vendor SIGNALS
        // dormancy, not that the track is closed today — so keying the exemption
        // on the declaration alone breaks twice over: the sweep fails the day the
        // vendor reopens the track (and advises deleting the very declaration
        // that keeps the row calm next time it closes), and while the track IS
        // open the assertions below are skipped, so a working channel quietly
        // stops being covered.
        if remote?.downloadURL == nil, dormantTracks.contains(key) {
            log("• \(key): dormant — vendor publishes no current build on this track")
            continue
        }
        if remote?.downloadURL == nil, unaddressableKeys.contains(key) {
            log("• \(key): no device identity on this machine — the vendor's app is not installed here, so this probe has nothing to address and proved nothing")
            continue
        }
        let kind = remote?.vendorInstallerKind.map { "\($0)" } ?? "nil"
        let sum = remote?.expectedSHA512 != nil ? "sha512✓" : "—"
        // `versionIsBuild` recipes (Outlook) put the build in `version` and leave
        // `shortVersion` nil unless they carry a display pattern — fall back so the
        // sweep never prints a bare "v?" for a recipe that did resolve.
        let shown = remote?.shortVersion ?? remote?.version ?? "?"
        log("• \(key): v\(shown)  [\(kind)] \(sum)")
        log("    \(remote?.downloadURL?.absoluteString ?? "NO URL")")
        #expect(remote?.downloadURL != nil, "\(key) resolved no installer URL")
        #expect(remote?.vendorInstallerKind != nil, "\(key) resolved no installer kind")
        // pkg → manual installer (system installer); archives → in-place swap.
        #expect(remote?.requiresManualInstaller == (remote?.vendorInstallerKind == .pkg),
                "\(key) install routing disagrees with its kind")
        // …and that the build came off this channel's train. Same rule the nightly
        // `duo verify` sweep applies, read from the core registry so the two can't
        // drift (see `RecipeSanity.crossChannelArtifact`).
        if let recipe = byKey[key], let remote {
            let complaint = RecipeSanity.crossChannelArtifact(recipe: recipe, remote: remote)
            #expect(complaint == nil, "\(key): \(complaint ?? "")")
        }
    }
}

/// `ChannelProofRegistry.proofs` must cover every non-stable install recipe, and
/// must not carry entries for recipes that no longer exist.
///
/// Offline and instant, unlike the live sweep above — this is the half that has to
/// fail in a PR, so someone adding a channel recipe is forced to say how they know
/// it isn't crossing trains rather than discovering it from a nightly warning.
@Test func channelProofsCoverEveryChannelRecipe() {
    let needed = Set(ChannelProofRegistry.channelRecipesWithInstall)
    let have = Set(ChannelProofRegistry.proofs.keys)
    let unproven = needed.subtracting(have).map(\.description).sorted()
    let orphaned = have.subtracting(needed).map(\.description).sorted()
    #expect(unproven.isEmpty, "channel recipes with an install spec but no ChannelProof: \(unproven)")
    #expect(orphaned.isEmpty, "ChannelProof entries for recipes that no longer carry a channel install spec: \(orphaned)")
    // A duplicate (bundleID, channel) used to mean an unreachable recipe, because
    // `latestVersion` took the FIRST match for the app's channel. It now probes
    // every match and answers with the highest (`VendorProbeSource.best`), so a
    // duplicate is legal — but only when it is deliberate. The `variant` is that
    // declaration: it also splits the two recipes' `recipeID`s, without which they
    // would share one verify baseline entry and one issue history.
    let grouped = Dictionary(grouping: VendorProbeRegistry.recipes) {
        ChannelProofKey($0.bundleID, $0.channel)
    }
    for (key, group) in grouped where group.count > 1 {
        #expect(
            group.allSatisfy { $0.variant != nil },
            "\(key.description) has \(group.count) recipes; each needs a `variant`, else it is an accidental duplicate that doubles the requests and shares a baseline key")
        #expect(
            Set(group.map(\.recipeID)).count == group.count,
            "\(key.description) has recipes with the same variant")
        // `best(of:)` ranks one string per outcome, and `versionIsBuild` decides
        // whether that string is a build or a marketing version. Mixing the two
        // within a channel would compare e.g. 26053122 against 16.109.3 — the
        // phantom-update bug `versionIsBuild` exists to prevent.
        #expect(
            Set(group.map(\.versionIsBuild)).count == 1,
            "\(key.description) mixes versionIsBuild across endpoints that get compared")
    }
}

// MARK: - the `.recipeAnchor` surface (issue #81)

/// Adding a field to `VendorProbeRecipe` must be a decision, not an omission.
///
/// `channelAnchorSurface` is derived by reflection, so a new field joins the
/// surface by construction — the opposite of the hand-written list it replaced,
/// which silently stopped covering `entryStartPattern` the day that field
/// landed. What reflection cannot decide is whether the new field belongs in
/// `nonAnchorFields` instead. This count is what forces that question: it fails
/// on the next field added, and the fix is one line either way — bump the number
/// (the field is part of what the recipe reads) or add the label to
/// `nonAnchorFields` (it only labels the recipe).
@Test func channelAnchorSurfaceCoversEveryRecipeField() {
    let recipe = VendorProbeRegistry.recipes[0]
    let labels = Mirror(reflecting: recipe).children.compactMap(\.label)
    // 24 since `trackClosedPattern` (2026-09-04). It stays IN, and unlike its
    // sibling `transientBodyPattern` it is not channel-neutral: only the beta
    // recipe carries one, and the string it holds names a beta-specific key
    // (`lastest_beta_number`). That makes it a field a proof could legitimately
    // name — it is part of what the recipe reads — without being tautological
    // the way `channel` is. Useful or not as an anchor, the rule for
    // `nonAnchorFields` is tautology, and this is not one.
    //
    // 23 since `transientBodyPattern` (2026-09-01), which stays IN for the same
    // reason `buildNamespace` did (22, 2026-08-30): `nonAnchorFields` is for
    // fields that would make a channel anchor tautological — a `.beta` recipe
    // carries the literal "beta" in `channel` — and neither `bundle`/`vendor` nor
    // the shape of a vendor's error envelope is a channel token. The envelope
    // pattern is channel-NEUTRAL (CapCut's two tracks share one string, as they
    // share one `url`), so anchoring a proof to it would prove nothing — but that
    // is a bad proof, not a tautological one, and a proof must name the fields it
    // relies on anyway (#110). Useless as an anchor, harmless in the surface,
    // same as every other Bool here.
    #expect(labels.count == 24,
            "VendorProbeRecipe gained or lost a field (now \(labels.count): \(labels.sorted())) — decide whether it belongs in the .recipeAnchor surface or in nonAnchorFields, then update this count")
    // A renamed field would turn its exclusion into a silent no-op, quietly
    // widening the surface instead of narrowing it. Same class of bug, other
    // direction.
    for excluded in VendorProbeRecipe.nonAnchorFields {
        #expect(labels.contains(excluded),
                "nonAnchorFields names '\(excluded)', which is not a field of VendorProbeRecipe any more")
    }
}

/// The concrete gap #81 was filed for: an anchor living in `entryStartPattern`.
///
/// Still a live property after #110 made anchors name their fields, and this is
/// the test that says so: the fields a proof may name are DERIVED, so any field
/// the recipe reads can be named — including the one the old hand-written
/// surface never learned about. What changed is that naming it is now required
/// rather than implied, which is why the proof is built here instead of read out
/// of the registry (the registered WeChat RC proof names `versionPattern` and
/// `install`, and correctly refuses a recipe anchored only in a third field).
/// The negative case shows the guard has not simply gone quiet instead.
@Test func theAnchorSurfaceSeesEntryStartPattern() {
    func wechatRC(versionPattern: String, entryStartPattern: String?) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: versionPattern,
            entryStartPattern: entryStartPattern,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .rc)
    }
    // No `RemoteVersion` here: the artifact proves nothing for this recipe — RC
    // and Stable are served from the same directory with the same filename
    // template, which is why this proof is an anchor and not an `.artifact` match
    // in the first place — so the anchor match IS the whole check.
    func anchorFailure(_ recipe: VendorProbeRecipe) -> String? {
        RecipeSanity.recipeAnchorFailure(
            pattern: #""id":.*"rc""#, fields: ["entryStartPattern"],
            channel: recipe.channel, subject: recipe)
    }

    // Anchored through `entryStartPattern`, and named there: the guard is satisfied.
    let anchoredInEntryPattern = wechatRC(
        versionPattern: #""version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
        entryStartPattern: #"\{"id":\s*"rc""#)
    #expect(anchorFailure(anchoredInEntryPattern) == nil,
            "entryStartPattern must be nameable — a derived field list is the point of #81")

    // …and the guard still fires when the anchor is not in the field that named
    // it, so the line above is the field being reachable, not the guard going quiet.
    //
    // `entryStartPattern` is PRESENT here and merely lost its token, rather than
    // being nil. A nil field's surface is the literal string "nil", which fails to
    // match for a different reason than a real field that drifted — so testing
    // only the nil case would not distinguish "the field is checked" from "the
    // field does not exist", and would pass either way.
    let driftedInEntryPattern = wechatRC(
        versionPattern: #""version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
        entryStartPattern: #"\{"date":""#)
    #expect(anchorFailure(driftedInEntryPattern) != nil,
            "a named field that still exists but lost its channel token must be complained about")

    let absentEntryPattern = wechatRC(
        versionPattern: #""version":\s*"([0-9]+(?:\.[0-9]+)+)""#, entryStartPattern: nil)
    #expect(anchorFailure(absentEntryPattern) != nil,
            "a recipe with its channel anchor removed must still be complained about")
}

/// A `.recipeAnchor` whose PATTERN matches anything is the third way to write a
/// proof that cannot fail, and the one neither `everyRegisteredAnchorNamesRealFields`
/// nor the field-scoping closes.
///
/// Probed against several unrelated strings rather than just `""`. The empty
/// string alone is NOT the total discriminator an earlier version of this claimed:
/// it catches `""`, `a?` and `.*`, but `.+` and `.` match every real surface while
/// failing on `""`, so they would have slipped through while asserting nothing
/// beyond "this field is non-empty". A pattern that matches all of these probes is
/// not distinguishing anything about a channel.
///
/// Covers all THREE registries. The GitHub side has no anchors today, and on the
/// binding side this is the half `everyBindingProofFailsOnItsOwnStableSibling`
/// cannot backstop: TablePlus's stable `feedHTTPHeaders` surface is `""`, so `.+`
/// would pass that test too.
@Test func noRegisteredAnchorMatchesEverything() {
    // Deliberately unlike any real feed URL, header or vendor marker.
    let arbitrary = ["x", "0", "   ", "zzz zzz"]
    func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    // Two ways to assert nothing, and they need different probes — which is the
    // bug an earlier version of this test had, checking only the first:
    //   * matching `""` means matching every surface there is (`.*`, `a?`, `^`);
    //   * matching every arbitrary NON-empty string means the anchor only asserts
    //     "this field is non-empty" (`.+`, `.`), which no channel proof should be.
    func vacuous(_ pattern: String) -> Bool {
        matches(pattern, "") || arbitrary.allSatisfy { matches(pattern, $0) }
    }
    func check(_ label: String, _ map: [ChannelProofKey: ChannelArtifactProof]) {
        for (key, proof) in map {
            guard case .recipeAnchor(let pattern, _) = proof else { continue }
            #expect(!vacuous(pattern),
                    "\(label) \(key): the anchor /\(pattern)/ matches arbitrary unrelated text, so it can never report drift")
        }
    }
    check("vendor", ChannelProofRegistry.proofs)
    check("github", ChannelProofRegistry.githubProofs)
    check("binding", ChannelProofRegistry.bindingProofs)
}

// MARK: - anchors are checked field by field (issue #110)

/// The failure #110 was filed for: one anchored field covering for another.
///
/// WeChat DevTools RC is the live case and the sharpest one — its RC artifact is
/// byte-for-byte shaped like Stable's (same host, same directory, same filename
/// template), so this anchor is the ONLY thing between an RC user and a Stable
/// build. `"id": "rc"` sits in both `versionPattern` and the install
/// `bodyPattern`; matched against the joined surface, either one alone kept the
/// proof green.
///
/// Driven through `crossChannelArtifact` on the REGISTERED proof, so it is the
/// shipping registry entry under test and not a hand-built stand-in. Each half is
/// knocked out in turn: under the old any-field surface both of these passed.
@Test func eachNamedAnchorFieldIsCheckedOnItsOwn() {
    func wechatRC(versionPattern: String, installPattern: String) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: versionPattern,
            install: VendorInstallSpec(urlSource: .bodyPattern(installPattern), kind: .pkg),
            channel: .rc)
    }
    let anchoredVersion = #""id":\s*"rc"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#
    let anchoredInstall = #""id":\s*"rc"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#
    // The same patterns with the channel block dropped — what "someone rewrites
    // that regex" or "the vendor renames the block" actually looks like.
    let driftedVersion = #""version":\s*"([0-9]+(?:\.[0-9]+)+)""#
    let driftedInstall = #""url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#

    let remote = RemoteVersion(
        shortVersion: "1.06.2508260", version: "1.06.2508260",
        downloadURL: URL(string: "https://dldir1.qq.com/WechatWebDev/release/abc123/wechat_devtools_1.06.2508260_darwin_arm64.pkg")!,
        sourceName: "Vendor")

    #expect(
        RecipeSanity.crossChannelArtifact(
            recipe: wechatRC(versionPattern: anchoredVersion, installPattern: anchoredInstall),
            remote: remote) == nil,
        "the recipe as shipped, anchored in both named fields, must pass")

    let installDrifted = RecipeSanity.crossChannelArtifact(
        recipe: wechatRC(versionPattern: anchoredVersion, installPattern: driftedInstall),
        remote: remote)
    #expect(installDrifted != nil,
            "the install spec — the half that PICKS the artifact — lost its channel block, and the version pattern must not cover for it")
    #expect(installDrifted?.contains("install") == true,
            "the finding must name the field that drifted, not just the recipe: \(installDrifted ?? "nil")")

    let versionDrifted = RecipeSanity.crossChannelArtifact(
        recipe: wechatRC(versionPattern: driftedVersion, installPattern: anchoredInstall),
        remote: remote)
    #expect(versionDrifted != nil,
            "the version pattern lost its channel block, and the install spec must not cover for it")
    #expect(versionDrifted?.contains("versionPattern") == true,
            "the finding must name the field that drifted: \(versionDrifted ?? "nil")")
}

/// The two ways a field-scoped anchor could be written so that it can never fail
/// — the outcome worse than having no proof, because it reads as green forever.
///
/// Neither is reachable from the registry today (`everyRegisteredAnchorNamesRealFields`
/// is what holds that line in a PR); this pins the runtime half, for a proof
/// written after that test was read.
@Test func anAnchorThatCannotFailIsItselfAFinding() {
    let recipe = VendorProbeRegistry.recipes.first {
        $0.bundleID == "com.tencent.wechatdevtools" && $0.channel == .rc
    }
    let subject = try! #require(recipe)

    #expect(
        RecipeSanity.recipeAnchorFailure(
            pattern: #""id":.*"rc""#, fields: [],
            channel: .rc, subject: subject) != nil,
        "an anchor naming no field matches vacuously and must be reported")

    #expect(
        RecipeSanity.recipeAnchorFailure(
            pattern: #""id":.*"rc""#, fields: ["versionPatern"],
            channel: .rc, subject: subject) != nil,
        "a typo'd field name has nothing to match against and must be reported, not skipped")

    // A field that exists but only LABELS the recipe is refused for the same
    // reason `nonAnchorFields` exists: `channel` literally contains "rc".
    #expect(
        RecipeSanity.recipeAnchorFailure(
            pattern: #"rc"#, fields: ["channel"],
            channel: .rc, subject: subject) != nil,
        "naming a labelling field must be refused, not answered with a tautology")
}

/// Every registered anchor names at least one field, and every name is a real
/// anchorable field of the recipe or rule it is registered against.
///
/// This is what keeps the field names from being magic strings: a rename, a typo,
/// or an anchor pinned to a labelling field turns the proof into something that
/// cannot fail, and that is exactly the silent-no-op shape this file keeps being
/// bitten by. Covers BOTH registries, so the GitHub side cannot acquire the
/// weaker behaviour by being written later.
@Test func everyRegisteredAnchorNamesRealFields() {
    let recipesByKey = Dictionary(
        VendorProbeRegistry.recipes.map { (ChannelProofKey($0.bundleID, $0.channel), $0) },
        uniquingKeysWith: { a, _ in a })
    for (key, proof) in ChannelProofRegistry.proofs {
        guard case .recipeAnchor(let pattern, let fields) = proof else { continue }
        #expect(!fields.isEmpty, "\(key): the anchor /\(pattern)/ names no field, so it cannot fail")
        guard let recipe = recipesByKey[key] else { continue }
        for label in fields {
            #expect(recipe.channelAnchorSurface(ofField: label) != nil,
                    "\(key): the anchor names '\(label)', which is not an anchorable field of VendorProbeRecipe")
        }
    }

    let rulesByKey = Dictionary(
        GitHubReleaseRegistry.rules.map { (ChannelProofKey($0.bundleID, $0.channel), $0) },
        uniquingKeysWith: { a, _ in a })
    for (key, proof) in ChannelProofRegistry.githubProofs {
        guard case .recipeAnchor(let pattern, let fields) = proof else { continue }
        #expect(!fields.isEmpty, "\(key): the anchor /\(pattern)/ names no field, so it cannot fail")
        #expect(rulesByKey[key] != nil, "\(key) has a .recipeAnchor proof but no rule")
        guard let rule = rulesByKey[key] else { continue }
        for label in fields {
            #expect(rule.channelAnchorSurface(ofField: label) != nil,
                    "\(key): the anchor names '\(label)', which is not an anchorable field of GitHubReleaseRule")
        }
    }
}

/// An anchor that contains quotes must match wherever in the recipe it lives.
///
/// `String(describing:)` renders a string nested inside an optional, an array, an
/// enum payload or another struct through its DEBUG description, which escapes
/// quotes — so `"id":.*"rc"` would silently fail to match the very install spec
/// the old surface reached into with exactly that call. Three of the five
/// registered anchors carry quotes or angle brackets, so the surface has to yield
/// strings verbatim rather than described.
@Test func anchorsWithQuotesMatchNestedFieldsToo() {
    let recipe = VendorProbeRecipe(
        bundleID: "com.example.subject",
        url: URL(string: "https://example.invalid/config.json")!,
        mode: .responseBody,
        versionPattern: #""version":\s*"([0-9.]+)""#,
        install: VendorInstallSpec(
            urlSource: .bodyPattern(#""id":\s*"rc"[\s\S]*?"url":\s*"(https://[^"]+\.pkg)""#),
            kind: .pkg),
        channel: .rc)
    let surface = recipe.channelAnchorSurface
    #expect(surface.contains(#""id":\s*"rc""#),
            "a quoted marker inside the install spec must appear verbatim, not debug-escaped")
    #expect(!surface.contains(#"\""#),
            "no field may reach the surface through a debug description")
}

/// Broadening the surface must not make an anchor vacuously true.
///
/// Deriving is the fix for a guard that silently shrinks; the failure mode it
/// trades into is a guard that silently GROWS until the anchor matches something
/// that says nothing about which channel the recipe reads. `nonAnchorFields`
/// exists to hold that line — a `.beta` recipe literally carries the word "beta"
/// in `channel` — and this asserts the line is where it needs to be for every
/// anchor actually registered: none of them can be satisfied by the labelling
/// fields alone.
@Test func registeredAnchorsAreNotSatisfiedByLabellingFieldsAlone() {
    let byKey = Dictionary(
        VendorProbeRegistry.recipes.map { (ChannelProofKey($0.bundleID, $0.channel), $0) },
        uniquingKeysWith: { a, _ in a })
    for (key, proof) in ChannelProofRegistry.proofs {
        guard case .recipeAnchor(let pattern, _) = proof else { continue }
        guard let recipe = byKey[key] else { continue }
        let labellingOnly = Mirror(reflecting: recipe).children
            .filter { $0.label.map(VendorProbeRecipe.nonAnchorFields.contains) ?? false }
            .map { String(describing: $0.value) }
            .joined(separator: "\n")
        #expect(
            labellingOnly.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil,
            "\(key): the anchor /\(pattern)/ is satisfied by fields that only label the recipe, so it proves nothing about which channel it reads")
    }
}

/// Every registered `.recipeAnchor` still matches its own recipe — offline.
///
/// The live sweep above checks this too, but only where the network answers.
/// This is the half that fails in a PR: an anchor that stopped matching means
/// either the recipe drifted off its channel-dedicated endpoint or the marker
/// was retyped, and both should be caught before a nightly run notices.
@Test func registeredAnchorsMatchTheirRecipes() {
    let byKey = Dictionary(
        VendorProbeRegistry.recipes.map { (ChannelProofKey($0.bundleID, $0.channel), $0) },
        uniquingKeysWith: { a, _ in a })
    for (key, proof) in ChannelProofRegistry.proofs {
        guard case .recipeAnchor(let pattern, let fields) = proof else { continue }
        let recipe = byKey[key]
        #expect(recipe != nil, "\(key) has a .recipeAnchor proof but no recipe")
        guard let recipe else { continue }
        // Per named field, not against the join: a proof that names two fields is
        // asserting the token is in BOTH, and this is where that is checked
        // offline (issue #110).
        for label in fields.sorted() {
            #expect(
                recipe.channelAnchorSurface(ofField: label)?.range(
                    of: pattern, options: [.regularExpression, .caseInsensitive]) != nil,
                "\(key): the recipe's \(label) no longer matches its anchor /\(pattern)/")
        }
    }
}

/// The install half of a vendor probe must stay OFF for a Toolbox-managed copy.
///
/// Android Studio's Canary/Beta are the one case where a Toolbox-managed app is
/// still routed through its `VendorProbeRecipe` (Toolbox's local verdict is flaky
/// there — see `InstalledApp.prefersVendorProbeOverToolbox`). We borrow the probe
/// for the VERSION only: installing must still go through Toolbox, never an
/// in-place bundle swap that would desync Toolbox's state. Same recipe and channel
/// the sweep above resolves, so the only difference is the Toolbox flag — this
/// pins the gate, not the recipe.
@Test func toolboxManagedCopiesResolveDetectionOnly() async throws {
    let source = VendorProbeSource()
    for channel in [ReleaseChannel.canary, .beta] {
        let app = InstalledApp(
            name: "Android Studio", bundleID: "com.google.android.studio",
            shortVersion: "0.0.0", buildVersion: "AI-000.0.0",
            path: URL(fileURLWithPath: "/Applications/Android Studio Preview.app"),
            isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil,
            releaseChannel: channel)
        #expect(app.prefersVendorProbeOverToolbox)  // linchpin for the branch below
        let remote = try await source.latestVersion(for: app)
        #expect(remote?.version != nil, "Toolbox-managed \(channel.rawValue) lost its version")
        #expect(remote?.vendorInstallerKind == nil,
                "Toolbox-managed \(channel.rawValue) offered an in-place install")
        #expect(remote?.requiresManualInstaller == true)
    }
}

/// A Mac App Store copy must never be answered by a vendor probe — for ANY recipe.
///
/// The store build and the vendor's own download are two different distributions
/// that share a bundle id, and the vendor's runs ahead: on 2026-08-23 the store
/// had WhatsApp 26.32.75 while `web.whatsapp.com` redirected to
/// `WhatsApp-2.26.33.19.dmg`. `MacAppStoreSource` sits first in `SourceStack`, but
/// `UpdateChecker` falls through to the next source on a thrown error as well as
/// on a miss — so a single flaky iTunes lookup (a proxy dropping, a storefront
/// that 404s) is enough to hand the app to this source. That is not hypothetical:
/// it is what pinned WhatsApp's row to 26.33.19, offering an Update button that
/// would have swapped the store copy — `_MASReceipt`, sandbox entitlements and all
/// — for a Developer ID build the store could never update again.
///
/// Derived from the registry rather than a hand-written list: the gate is
/// unconditional, so a new recipe must not be able to opt out of it by omission.
/// Instant and offline — the gate returns before any network work, which is also
/// what makes a regression loud (without it every recipe here goes to the wire).
@Test func appStoreCopiesAreNeverAnsweredByAVendorProbe() async throws {
    let source = VendorProbeSource()
    for recipe in VendorProbeRegistry.recipes {
        let app = InstalledApp(
            name: recipe.bundleID, bundleID: recipe.bundleID,
            shortVersion: "0.0.0", buildVersion: "0",
            path: URL(fileURLWithPath: "/Applications/\(recipe.bundleID).app"),
            isMASApp: true, sparkleFeedURL: nil,
            releaseChannel: recipe.channel)
        let remote = try await source.latestVersion(for: app)
        #expect(
            remote == nil,
            "\(recipe.bundleID) [\(recipe.channel.rawValue)]: vendor probe answered for an App Store copy with \(remote?.displayVersion ?? "?") — the store owns that app's updates")
    }
}

/// AweSun's download host (`dw.oray.com`) sits behind an Aliyun WAF that serves
/// the dmg only to requests carrying a `Referer` — otherwise an anti-bot JS
/// challenge page (text/html). This proves (a) the recipe resolves a pkg plan
/// that carries the `Referer` header, and (b) that header is load-bearing: the
/// SAME range request serves `application/octet-stream` with it and `text/html`
/// without it. Uses a 1-byte range so it never pulls the ~99 MB dmg.
@Test func aweSunPkgPlanCarriesLoadBearingWAFHeader() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "AweSun", bundleID: "com.oray.sunlogin.macclient",
        shortVersion: "0.0.0", buildVersion: "0",
        path: URL(fileURLWithPath: "/Applications/AweSun.app"),
        isMASApp: false, sparkleFeedURL: nil)

    guard let remote = await LiveProbe.remote(app, source: source, "AweSun") else { return }
    #expect(remote.vendorInstallerKind == .pkg)
    #expect(remote.requiresManualInstaller == true)             // → system installer
    #expect(remote.downloadURL?.pathExtension.lowercased() == "dmg")
    #expect(remote.downloadHeaders["Referer"] != nil)           // WAF header present
    guard let url = remote.downloadURL else { return }

    func contentType(withReferer: Bool) async throws -> String? {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if withReferer, let ref = remote.downloadHeaders["Referer"] {
            req.setValue(ref, forHTTPHeaderField: "Referer")
        }
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
    }

    let withHeader = try await contentType(withReferer: true)
    let without = try await contentType(withReferer: false)
    #expect(withHeader?.contains("application/octet-stream") == true)  // real dmg
    #expect(without?.contains("text/html") == true)                    // WAF challenge
}

/// Outlook's Office AutoUpdate manifest publishes three `.pkg` URLs per entry and
/// only one of them is installable: `FullUpdaterLocation` (the 1.29GB standalone
/// package), never the `_Delta.pkg` / `_BinaryDelta.pkg` patches, whose
/// `InstallationCheck()` tests nothing but the min OS — run one against a
/// mismatched baseline and it lays down a partial Outlook without complaint.
///
/// The other half is the version-scheme trap: `Update Version` is the BUILD
/// (16.109.26053122; the pkg's own Distribution declares marketing 16.109.3), so
/// this pins the resolved pkg to the build the SAME probe reported. A live check,
/// because the failure it guards against is a vendor-side edit — Microsoft
/// dropping the `Update Version Location` key is what killed one-click in the
/// first place, and no fixture would have noticed.
@Test func microsoftOutlookInstallURLMatchesProbedBuild() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "Microsoft Outlook", bundleID: "com.microsoft.Outlook",
        shortVersion: "0.0.0", buildVersion: "0",
        path: URL(fileURLWithPath: "/Applications/Microsoft Outlook.app"),
        isMASApp: false, sparkleFeedURL: nil)

    guard let remote = await LiveProbe.remote(app, source: source, "Outlook") else { return }
    #expect(remote.vendorInstallerKind == .pkg)
    #expect(remote.requiresManualInstaller == true)   // → system installer
    // versionIsBuild routes the build into `version` and leaves `shortVersion` nil.
    let build = try #require(remote.version)
    #expect(remote.shortVersion == nil)
    let url = try #require(remote.downloadURL?.absoluteString)
    #expect(url.hasSuffix("/Microsoft_Outlook_\(build)_Updater.pkg"))
    #expect(!url.contains("Delta"))
}

/// Postman ships a zip we swap in place, even though it self-updates via Squirrel:
/// the build comes from Postman's own CDN (`dl.pstmn.io`, no WAF) and the bundle
/// inside is signed by the SAME Team as the installed app, so the install can't
/// cross channels or downgrade. Confirms the resolved plan and that the CDN
/// actually serves a versioned zip (1-byte range — no ~131 MB pull).
@Test func postmanZipPlanResolvesOfficialBuild() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "Postman", bundleID: "com.postmanlabs.mac",
        shortVersion: "0.0.0", buildVersion: "0",
        path: URL(fileURLWithPath: "/Applications/Postman.app"),
        isMASApp: false, sparkleFeedURL: nil)

    guard let remote = await LiveProbe.remote(app, source: source, "Postman") else { return }
    let url = try #require(remote.downloadURL)
    let version = try #require(remote.shortVersion)
    #expect(remote.vendorInstallerKind == .zip)
    #expect(remote.requiresManualInstaller == false)            // → in-place swap
    #expect(remote.downloadHeaders.isEmpty)                     // no WAF, no headers
    #expect(url.host == "dl.pstmn.io")
    #expect(url.absoluteString.contains(version))               // versioned URL
    #expect(url.absoluteString.hasSuffix("osx_arm64"))

    var req = URLRequest(url: url)
    req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    let (_, resp) = try await URLSession.shared.data(for: req)
    let http = resp as? HTTPURLResponse
    let disp = http?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    #expect(disp.lowercased().contains(".zip"))                 // a real zip download
    #expect(disp.contains(version))                             // for this exact version
}

/// The real proof: take whichever enabled app is actually installed (ChatWise
/// preferred — it ships a SHA-512), download the official build, verify checksum,
/// unpack, and run the SAME code-signature + Team ID gate the installer uses —
/// then stop. No swap, nothing replaced.
@Test func vendorDownloadPassesSignatureGate() async throws {
    // `@Sendable`, because the gate below runs inside a detached task so it can be
    // abandoned on timeout — see `firstToFinish`.
    @Sendable func log(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    // Off unless asked for, because this is the only test in the suite that pulls
    // real vendor builds — measured 2026-09-05, 112.5 MB (ChatWise) + 48.9 MB
    // (VLC) on the author's Mac, every `make test`. That is metered bandwidth
    // being spent to re-prove something a hosted runner can prove for free, so
    // the runner is where it belongs; ci.yml sets the variable.
    //
    // An opt-out flag is normally the exact shape of thing this repository refuses
    // — a free pass that goes on being honoured after the reason for it is gone.
    // What makes this one answerable is that BOTH ways of losing the coverage are
    // loud: CI without the flag is an issue, and the flag with nothing to run is
    // an issue. There is no configuration in which this test quietly does nothing.
    let env = ProcessInfo.processInfo.environment
    let onCI = env["CI"] == "true"
    guard env["DUO_DOWNLOAD_GATE"] == "1" else {
        if onCI {
            Issue.record(Comment(rawValue: """
                CI ran without DUO_DOWNLOAD_GATE=1, so the only check that verifies a \
                real vendor download — sha512, extraction, code signature, Team ID — \
                did nothing. .github/workflows/ci.yml sets it; if it no longer does, \
                that coverage is gone and nothing else in the suite replaces it.
                """))
            return
        }
        log("""
            ⚠️ signature-gate download SKIPPED — it fetches real vendor builds. Run it
               here with `DUO_DOWNLOAD_GATE=1 make test`; otherwise CI runs it on every
               push, on GitHub's bandwidth rather than this machine's.
            """)
        return
    }

    let installed = AppScanner().scan()
    // One candidate per archive path, first installed one wins. The zip list
    // carries the checksum branch (only two recipes in the whole registry publish
    // a sha512, and the other is 237.8 MB); the dmg list exercises hdiutil mount,
    // http→https and ascending last-match. The big ones are deliberately absent —
    // OrbStack ~404 MB, Claude ~283 MB, same code paths.
    //
    // Firefox and Chrome are on the list because they are what a GitHub-hosted
    // runner actually has. Without them this test found nothing on CI and said so
    // in a `log` line nobody reads — the same silent-hole shape as #339, on the
    // gate that decides whether a downloaded bundle may replace an installed app.
    let candidates: [(kind: String, ids: [String])] = [
        ("zip", ["app.chatwise"]),
        ("dmg", ["org.videolan.vlc", "org.mozilla.firefox", "com.google.Chrome"]),
    ]
    var apps: [InstalledApp] = []
    for (kind, ids) in candidates {
        guard let app = ids.lazy.compactMap({ id in
            installed.first { $0.bundleID == id }
        }).first else {
            log("· no \(kind) candidate installed here — that path is not covered by this run")
            continue
        }
        apps.append(app)
    }
    guard !apps.isEmpty else {
        Issue.record(Comment(rawValue: """
            DUO_DOWNLOAD_GATE=1 was set and not one candidate app is installed, so this \
            proved nothing. Looked for: \(candidates.flatMap(\.ids).joined(separator: ", ")).
            """))
        return
    }
    for app in apps {
        // Bounded, because this now sits behind a required status check. Measured
        // 2026-09-05 (run 33950064978): the Firefox gate on a hosted runner printed
        // its header and then went silent for 46 minutes, until the run was
        // cancelled — it never reached the `download:` line, so it wedged inside
        // version resolution, before any archive was fetched. The root cause is
        // still unknown, and it does not need to be known for this: a step that can
        // eat the job's whole 60-minute budget in silence is a defect on its own
        // terms. `firstToFinish` gives up WITHOUT waiting for the abandoned
        // operation, which is the only reason a timeout helps here at all — a task
        // group would await the wedged child and the timeout would be decorative.
        let finished = await AppRestarter.firstToFinish(
            timeout: gateBudget, fallback: false,
            onTimeout: { log("⏱ \(app.name): gate exceeded \(gateBudget) — abandoning") }
        ) {
            do {
                try await checkGate(app, log: log)
            } catch {
                Issue.record(Comment(rawValue: "\(app.name) gate threw: \(error)"))
            }
            return true
        }
        if !finished {
            Issue.record(Comment(rawValue: """
                \(app.name): the signature gate did not finish within \(gateBudget). \
                The phase lines above say how far it got.
                """))
        }
    }
}

/// How long one app's gate may take before it is abandoned and reported.
///
/// Five minutes is generous for a ~150 MB download plus a mount and a deep
/// signature verify, and small next to the 60-minute job budget it exists to
/// protect. It is a backstop, not a performance target: the runs that work finish
/// in seconds.
private let gateBudget: Duration = .seconds(300)

private func checkGate(_ app: InstalledApp, log: @Sendable (String) -> Void) async throws {
    log("\n=== signature-gate check: \(app.name) (\(app.bundleID ?? "?")) ===")

    // Phase lines exist so a timeout is diagnostic rather than just a timeout —
    // run 33950064978 hung between this one and the next, which is the only reason
    // the wedge could be located at all.
    log("· resolving version")
    guard let remote = await LiveProbe.remote(app, "\(app.name) gate") else { return }
    guard let url = remote.downloadURL, let kind = remote.vendorInstallerKind else {
        Issue.record(Comment(rawValue: "\(app.name): resolved a version but no install plan"))
        return
    }
    log("download: \(url.absoluteString)  [\(kind)]")

    let workDir = FileManager.default.temporaryDirectory
        // `scratchSlug`, not `app.id`: the id is the full bundle PATH, so the work
        // dir came out as `…/T/vendor-gate-test-/Applications/VLC.app` — a directory
        // whose last component ends in `.app`. Unpacking into it produced
        // `VLC.app/VLC.app` and made the extract/move fail intermittently.
        // `scratchSlug` is the filesystem-safe token the real installers use for
        // exactly this.
        //
        // The UUID is what keeps two test runs off each other. `scratchSlug` is a
        // digest of the INSTALLED app's path, so it is byte-identical in every
        // checkout and every process on this machine — and the temp dir is shared
        // across all of them. This repo routinely has several worktrees open at
        // once, so a second `swift test` overlapping the first would enter this
        // function with the same path, wipe the dir out from under the run already
        // in flight, and fail it in whichever way the timing chose: the finished
        // `.partial` no longer there to move (NSCocoaError 4), `ditto` writing into
        // a destination that just vanished, or a half-copied bundle failing the
        // codesign gate (-67023). Reproduced deterministically by running two test
        // bundles ~3s apart; green with the UUID. The real installers name their
        // scratch dir deterministically on purpose — they can, because every
        // install path holds `InstallLock`, a whole-machine mutex this test does
        // not take.
        .appendingPathComponent("vendor-gate-test-\(app.scratchSlug)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    // Download.
    log("· downloading")
    let downloader = Downloader(destinationDir: workDir) { _ in }
    let file = try await downloader.download(url)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? nil
    log("· downloaded \(bytes.map { "\($0 / 1_048_576) MB" } ?? "?")")

    // Normalize extension by kind (mirror VendorInstaller).
    let ext: String
    switch kind { case .zip: ext = "zip"; case .dmg: ext = "dmg"; case .tarGz: ext = "tar.gz"; case .pkg: ext = "pkg" }
    var archive = file
    if !file.lastPathComponent.lowercased().hasSuffix(ext) {
        archive = workDir.appendingPathComponent("download.\(ext)")
        try FileManager.default.moveItem(at: file, to: archive)
    }

    // Checksum, when published.
    if let expected = remote.expectedSHA512 {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let actual = Data(SHA512.hash(data: data)).base64EncodedString()
        log("sha512 expected: \(expected.prefix(16))…  actual: \(actual.prefix(16))…")
        #expect(actual == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Unpack + the mandatory gate.
    log("· extracting")
    let newApp = try ArchiveExtractor.extractApp(from: archive, workDir: workDir)
    log("· verifying signature")
    try SignatureVerifier.verifyCodeSignature(appAt: newApp)
    let installedTeam = try SignatureVerifier.teamIdentifier(at: app.path)
    let downloadedTeam = try SignatureVerifier.teamIdentifier(at: newApp)
    log("Team ID  installed: \(installedTeam ?? "nil")  downloaded: \(downloadedTeam ?? "nil")")
    try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: app.path, downloadedApp: newApp)
    log("✅ gate passed — would swap safely (no swap performed)")
}
