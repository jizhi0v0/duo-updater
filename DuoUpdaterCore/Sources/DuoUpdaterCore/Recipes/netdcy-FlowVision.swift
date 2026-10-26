import Foundation

enum netdcy_FlowVision {
    /// A Swift 6.2 runtime entry point the Xcode 26 builds import and the Xcode 16
    /// (and older) builds do not.
    static let xcode26Marker = "swift_coroFrameAlloc"
    static let defaultOffering =
        #"^(?:GitHub:FlowVision\.[0-9]+(?:\.[0-9]+)+\.zip|Homebrew:flowvision)$"#
    static let xcode26Offering = #"^GitHub:FlowVision\.[0-9]+(?:\.[0-9]+)+\.Xcode26\.zip$"#

    static let set = AppRecipeSet(
        family: "netdcy-FlowVision",
        githubRules: [
        // FlowVision (netdcy/FlowVision) — a native image viewer. It has no
        // updater of its own: no Sparkle, no SUFeedURL, and neither the source
        // nor the executable names GitHub or a releases URL. Nothing nested
        // (ffmpeg frameworks only), so nothing keeps running across a swap.
        //
        // Tags read `1.7.6`; the bundle says 1.7.6 (build 20260908). From 1.7.3
        // each release ships two builds of one bundle (netdcy.FlowVision, Team
        // M9PR3WG2FN, notarized, same version): `FlowVision.<v>.zip`, built with
        // Xcode 16, and `FlowVision.<v>.Xcode26.zip`, built with Xcode 26 (the
        // Liquid Glass toolbar on macOS 26). Only the executable tells them apart
        // to a gate (`DTXcode` 1640 / 2620 in Info.plist is not something a gate
        // reads). 1.7.0–1.7.2 shipped one zip, built with Xcode 26. This rule
        // answers for copies without the Xcode 26 marker; the next for copies
        // with it. 1.3.1 and older are ad-hoc (no Team), so the gate refuses
        // their one-click; they still see the update.
        // History: docs/app-audits/netdcy-FlowVision.md#历史与实测
        GitHubReleaseRule(
            bundleID: "netdcy.FlowVision",
            owner: "netdcy", repo: "FlowVision",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^FlowVision\.[0-9]+(?:\.[0-9]+)+\.zip$"#,
            installerKind: .zip),
        // The Xcode 26 build: same tags, its own zip, for a copy whose executable
        // carries the Xcode 26 marker.
        GitHubReleaseRule(
            bundleID: "netdcy.FlowVision",
            owner: "netdcy", repo: "FlowVision",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^FlowVision\.[0-9]+(?:\.[0-9]+)+\.Xcode26\.zip$"#,
            installerKind: .zip,
            variant: "xcode26",
            installedExecutableMarker: xcode26Marker),
        ],
        // Each build's zip goes only to copies of that build, so a one-click never
        // swaps the Xcode 26 build (Liquid Glass toolbar) for the Xcode 16 one or
        // back. The `flowvision` cask installs the Xcode 16 zip. The installer
        // also checks the downloaded package for the same marker.
        oneClickGates: [
            OneClickGate(
                bundleID: "netdcy.FlowVision",
                requirement: .executableLacks(marker: xcode26Marker),
                reason: "this copy is FlowVision's Xcode 26 build and the update is the Xcode 16 build; download the Xcode26 zip from its GitHub release",
                offering: defaultOffering),
            OneClickGate(
                bundleID: "netdcy.FlowVision",
                requirement: .executableContains(marker: xcode26Marker),
                reason: "this copy is not FlowVision's Xcode 26 build and the update is; download the plain zip from its GitHub release",
                offering: xcode26Offering),
        ])
}
