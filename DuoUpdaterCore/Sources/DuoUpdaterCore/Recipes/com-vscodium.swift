import Foundation

enum com_vscodium {
    static let set = AppRecipeSet(
        family: "com-vscodium",
        githubRules: [
        // VSCodium — VS Code without the Microsoft build. Tags are bare
        // `1.126.04524` (the trailing group is VSCodium's own build stamp and IS
        // part of the installed CFBundleShortVersionString, so the default pattern's
        // multi-dot capture keeps it). The release carries every platform plus a
        // `vscodium-cli-darwin-arm64-…tar.gz`; the pattern picks the app zip.
        // One-click: com.vscodium, Team VC39D2VNQ7, notarized.
        GitHubReleaseRule(
            bundleID: "com.vscodium",
            owner: "VSCodium", repo: "vscodium",
            installAssetPattern: #"^VSCodium-darwin-arm64-[0-9.]+\.zip$"#,
            installerKind: .zip),

        // VSCodium Insiders — its own repo (VSCodium/vscodium-insiders), its own
        // bundle id com.vscodium.VSCodiumInsiders. NOT VS Code Insiders (the
        // com.microsoft.VSCodeInsiders VendorProbeRecipe in
        // VendorProbeRecipe.swift) — different product, different cask
        // (`vscodium@insiders` vs `visual-studio-code@insiders`).
        //
        // Detection needs no `ReleaseChannel` change, but not for the reason it
        // might look like: the bundle id has no `.insiders`/`-insiders` SUFFIX
        // (it's the single camelCase component "VSCodiumInsiders", no separator
        // before "Insiders"), so `detect`'s bundle-id-suffix step does not fire.
        // What actually resolves it to `.preview` is the display name step: the
        // installed app's CFBundleName/CFBundleDisplayName is "VSCodium -
        // Insiders" (confirmed below), and "Insiders" is a standalone word there.
        // `ChannelGuardTests.vscodiumInsidersDisplayNameSignalsPreview` pins our
        // half of this against `ReleaseChannel.detect`. It cannot pin the VENDOR's
        // half: the display name is their string, and if VSCodium ever glues it
        // ("VSCodiumInsiders", the shape the bundle id already has) `detect`
        // returns `.stable`, the channel gate skips this rule, and the app goes
        // quiet with the test still green. That is the failure to watch for here.
        //
        // CRUCIAL — this is the SECOND instance of a trap the VS Code Insiders
        // recipe (VendorProbeRecipe.swift) already hit, not a VSCodium quirk:
        // tags carry the `-insider` suffix (`1.126.04518-insider`), which IS
        // part of both CFBundleShortVersionString and CFBundleVersion on the
        // installed app — verified by downloading the real asset and reading
        // Info.plist directly (not just trusting the tag). The default pattern
        // `v?([0-9]+(?:\.[0-9]+)+)` stops at the last digit run and drops the
        // suffix; `VersionComparator` then pads the missing 4th component to "0",
        // which outranks the text token "insider" (a numeric component always
        // beats a textual one — see VersionComparator.swift), so the bare
        // "1.126.04518" would read as NEWER than the correctly-suffixed
        // installed version — a permanent phantom update on an up-to-date
        // install, never resolving. Any other `-insider`-suffixed product would
        // hit the same trap; the pattern below keeps the suffix in the capture
        // so it compares equal instead.
        //
        // arm64 ONLY, deliberately, even though this repo also publishes
        // `VSCodium-darwin-x64-<ver>-insider.zip`. Matching both looked free —
        // `installableAsset` prefers the native slice — but this track ships
        // PLATFORM-PARTIAL releases: tag `1.126.04405-insider` carries an x64
        // macOS zip and no arm64 one (checked against the API 2026-08-27). On
        // such a release a both-arch pattern reaches `installableAsset` step 3,
        // which on Apple silicon with Rosetta returns the FOREIGN build — so an
        // arm64 Insiders install gets swapped for an Intel one. Pinning arm64
        // makes that release carry no installable asset instead, and the
        // list-fallback below then offers nothing until an arm64 build exists,
        // which is the right answer for a host class that is all we ship to
        // (`App/project.yml`, `ARCHS: arm64`).
        //
        // One-click: verified 2026-08-27 by downloading the real
        // VSCodium-darwin-arm64-1.126.04518-insider.zip and reading the
        // extracted app directly — CFBundleIdentifier
        // com.vscodium.VSCodiumInsiders, CFBundleShortVersionString/
        // CFBundleVersion both "1.126.04518-insider", `codesign -dv` shows
        // TeamIdentifier VC39D2VNQ7 (same team as stable) with a stapled
        // notarization ticket, and `spctl -a --type execute` returns "accepted,
        // source=Notarized Developer ID" — passes VendorInstaller's same-Team
        // gate.
        GitHubReleaseRule(
            bundleID: "com.vscodium.VSCodiumInsiders",
            owner: "VSCodium", repo: "vscodium-insiders",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+-insider)$"#,
            installAssetPattern: #"^VSCodium-darwin-arm64-[0-9.]+-insider\.zip$"#,
            installerKind: .zip,
            channel: .preview),
        ],
        githubChannelProofs: [
        // VSCodium Insiders names the channel in the tag AND in the asset filename,
        // and lives in its own repository besides.
        //
        // Anchored to the tag segment on purpose. A bare `-insider` would be
        // satisfied by `VSCodium/vscodium-insiders` in the path of EVERY url this
        // rule can ever resolve, which is the same fact the stable branch of
        // `crossChannelArtifact(rule:remote:)` in `ChannelArtifactProof.swift` refuses to check on — read
        // there it prevents a false accusation, read here it would have been a
        // permanent false acquittal, and the proof could not have failed for any
        // input. Live releases could not show this: every real tag in that repo
        // carries `-insider` too, so the loose pattern and the anchored one agree
        // on all 57 of them and disagree only on the artifact this exists to
        // catch. Caught in adversarial review of #101, not by measurement.
        ChannelProofKey("com.vscodium.VSCodiumInsiders", .preview):
            .artifact(#"/download/[^/]*-insider"#),
        ])
}
