import Foundation

enum com_google_android_studio {
    static let set = AppRecipeSet(
        family: "com-google-android-studio",
        probes: [
        // History: docs/app-audits/com-google-android-studio.md#历史与实测
        // Android Studio — for WEBSITE-direct installs only. Toolbox-managed
        // copies are gated out of VendorProbeSource and handled by ToolboxSource
        // (open Toolbox); this recipe fires for a hand-downloaded Android Studio.
        // developer.android.com/studio is static HTML carrying both the version
        // and the arm64 dmg href on the same page. Team EQHXZ8M8AV.
        VendorProbeRecipe(
            bundleID: "com.google.android.studio",
            url: URL(string: "https://developer.android.com/studio")!,
            mode: .responseBody,
            versionPattern: #"install/([0-9]{4}\.[0-9]+\.[0-9]+)\.[0-9]+/android-studio-[^"]*mac_arm\.dmg"#,
            changelogURL: URL(string: "https://developer.android.com/studio/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://edgedl\.me\.gvt1\.com/android/studio/install/[0-9.]+/android-studio-[^"]*mac_arm\.dmg)"#),
                kind: .dmg)),

        // Android Studio — Canary & Beta preview installs. Both share Stable's
        // `com.google.android.studio`; the install's channel is read from the
        // bundle filename (see `ReleaseChannel.detect` step 0.5), and the channel
        // gate routes each here. Source is Google's official releases-list JSON
        // (`jb.gg/android-studio-releases-list.json`, the same data the download
        // page uses; 307→TeamCity, redirect followed). CRUCIAL: the installed
        // `CFBundleShortVersionString` is truncated (e.g. "2026.1") and identical
        // across tracks, so a marketing-version compare is useless — we compare on
        // the `build` field (e.g. "AI-261.24374.151.2612.15561891"), which matches the
        // installed `CFBundleVersion` byte-for-byte, via `versionIsBuild`.
        //
        // STABILITY FLOOR (not "newest preview wins"): each preview channel accepts
        // builds at its own quality OR more stable, never less stable. Android
        // Studio's quality ladder is Canary (least stable) → Beta → RC → stable.
        //   • Canary install → newest of {Canary, Beta, RC}: a Canary 7 install
        //     correctly moves onto `2026.1.2 RC 1` when no newer Canary exists, and
        //     onto `2026.1.3 Canary 1` once the next feature version opens.
        //   • Beta install → newest of {Beta, RC} ONLY — it must NEVER be offered a
        //     Canary build (that's a stability DOWNGRADE). When a Beta sits on the
        //     latest RC and the only newer thing is the next version's Canary, the
        //     Beta is correctly up to date.
        // (An earlier "highest across all previews" version wrongly pushed
        //  `2026.1.3 Canary 1` at a Beta install that was already current; and the
        //  original channel-pure "Canary only" wrongly hid the RC the user wanted.
        //  See `InstalledApp.prefersVendorProbeOverToolbox`.)
        //
        // NOT newest-first (see issue #76): the feed is ordered by PUBLICATION
        // DATE, not by version. With two feature trains open at once, a newer
        // train's Canary can publish AFTER an older train's RC, so plain first-match
        // on the channel set lands on the older train's RC. `entryStartPattern` slices the feed into its
        // `{"date":…}` items and makes `versionPattern`/`displayVersionPattern`/
        // the install URL all resolve against the ONE entry whose build compares
        // highest, instead of three separate first-matches over the whole feed
        // that could each land on a different entry (flipping `selectHighest` on
        // `versionPattern` alone would have done exactly that — see its doc).
        // dmg patterns mirror each channel set. Suppression is conditional, not a
        // property of this recipe: `VendorProbeSource` sets `allowInstall` from
        // `InstalledApp.prefersVendorProbeOverToolbox`, which is true only for a
        // Toolbox-MANAGED Canary/Beta — that copy stays detection-only and updates
        // through Toolbox. A HAND-INSTALLED Canary/Beta (`isToolboxManaged ==
        // false`) gets `allowInstall = true` and IS offered this one-click, which is
        // why the dmg patterns below must stay correct and in lockstep with the
        // version set, not merely decorative. Team EQHXZ8M8AV.
        VendorProbeRecipe(
            bundleID: "com.google.android.studio",
            url: URL(string: "https://jb.gg/android-studio-releases-list.json")!,
            mode: .responseBody,
            versionPattern:
                #""build"\s*:\s*"(AI-[^"]+)","platformVersion":"[^"]*","name":"[^"]*","channel":"(?:Canary|Beta|RC)""#,
            changelogURL: URL(string: "https://developer.android.com/studio/preview/features"),
            versionIsBuild: true,
            // Show the feed's clean marketing name (e.g. "2026.1.2 RC 1") not the raw
            // build id (e.g. "AI-261.…"); the build still drives the comparison.
            displayVersionPattern:
                #""name":"[^"]*\|\s*([^"]+)","channel":"(?:Canary|Beta|RC)""#,
            // Each item starts with its own `"date"` key — see `entryStartPattern`.
            entryStartPattern: #"\{"date":""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://edgedl\.me\.gvt1\.com/android/studio/install/[0-9.]+/android-studio-[^"]*(?:canary|beta|rc)[0-9]*-mac_arm\.dmg)"#),
                kind: .dmg),
            channel: .canary),
        VendorProbeRecipe(
            bundleID: "com.google.android.studio",
            url: URL(string: "https://jb.gg/android-studio-releases-list.json")!,
            mode: .responseBody,
            // Beta accepts only Beta/RC — NEVER Canary (a stability downgrade).
            versionPattern:
                #""build"\s*:\s*"(AI-[^"]+)","platformVersion":"[^"]*","name":"[^"]*","channel":"(?:Beta|RC)""#,
            changelogURL: URL(string: "https://developer.android.com/studio/preview/features"),
            versionIsBuild: true,
            // Show the feed's clean marketing name (e.g. "2026.1.2 RC 1") not the raw
            // build id (e.g. "AI-261.…"); the build still drives the comparison.
            displayVersionPattern:
                #""name":"[^"]*\|\s*([^"]+)","channel":"(?:Beta|RC)""#,
            // Each item starts with its own `"date"` key — see `entryStartPattern`.
            entryStartPattern: #"\{"date":""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://edgedl\.me\.gvt1\.com/android/studio/install/[0-9.]+/android-studio-[^"]*(?:beta|rc)[0-9]*-mac_arm\.dmg)"#),
                kind: .dmg),
            channel: .beta),
        ],
        channelProofs: [
        // Android Studio: each preview channel accepts builds at its own quality OR
        // MORE STABLE (the stability floor documented on the recipes), so the marker
        // has to be that whole ladder, not just the channel's own name — Canary
        // resolves the newest of {Canary, Beta, RC}, Beta the newest of {Beta, RC}.
        // That is not a bug being papered over: an RC genuinely is the legitimate
        // answer for a Canary install once it is the highest build on the ladder —
        // e.g. before a newer feature version's Canary train has opened. (It is NOT
        // legitimate merely because the RC was the most recently PUBLISHED item —
        // the feed is ordered by publish date, not by version; see issue #76 and
        // `VendorProbeRecipe.entryStartPattern`, which now resolves that correctly.)
        // Google's Beta train has in practice shipped RELEASE CANDIDATES for years
        // (no `Beta` item since 2025-03-18), so `-rc<N>-` is the marker actually
        // seen on both.
        // What the marker still excludes is the pair that WOULD be a cross-channel
        // install: `Release` (e.g. `android-studio-quail3-mac_arm.dmg`) and `Patch`
        // (`…-patch1-mac_arm.dmg`) — neither carries a ladder token.
        ChannelProofKey("com.google.android.studio", .canary):
            .artifact(#"-(canary|beta|rc)[0-9]*-mac"#),
        ChannelProofKey("com.google.android.studio", .beta): .artifact(#"-(beta|rc)[0-9]*-mac"#),
        ])
}
