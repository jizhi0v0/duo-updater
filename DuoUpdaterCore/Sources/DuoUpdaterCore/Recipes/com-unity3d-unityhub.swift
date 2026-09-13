import Foundation

enum com_unity3d_unityhub {
    static let set = AppRecipeSet(
        family: "com-unity3d-unityhub",
        probes: [
        // Unity Hub — electron-builder feed. Despite the "Setup" in the asset
        // name this zip is NOT a stub installer: it expands to `Unity Hub.app`
        // itself (com.unity3d.unityhub, 3.20.1, Team 9QW8UQUTAA, notarized),
        // which is what makes one-click safe here and not the 1Password trap.
        VendorProbeRecipe(
            bundleID: "com.unity3d.unityhub",
            url: URL(string: "https://public-cdn.cloud.unity3d.com/hub/prod/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://unity.com/unity-hub"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"([0-9][^\s/]*/UnityHubSetup-[^\s]+-arm64\.zip)"#,
                    base: URL(string: "https://public-cdn.cloud.unity3d.com/hub/prod/")!),
                kind: .zip)),
        ])
}
