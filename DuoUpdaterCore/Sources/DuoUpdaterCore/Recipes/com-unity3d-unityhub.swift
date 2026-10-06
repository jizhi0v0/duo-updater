import Foundation

enum com_unity3d_unityhub {
    static let set = AppRecipeSet(
        family: "com-unity3d-unityhub",
        probes: [
        // Shared rationale for 2026-08-16 vendor batch: Recipes/dev-commandline-waveterm.swift.

        // Unity Hub — electron-builder feed. Despite the "Setup" in the asset
        // name this zip is NOT a stub installer: it expands to `Unity Hub.app`
        // itself (com.unity3d.unityhub, 3.20.1, Team 9QW8UQUTAA, notarized),
        // which is what makes one-click safe here and not the 1Password trap.
        //
        // The download is checked against the `sha512` (base64) of the `files:`
        // item whose `url:` is the arm64 zip the URL pattern reads — not the dmg
        // or x64 items beside it. The checksum pattern stays inside that one item
        // whatever its key order; if the item has no `sha512` it matches nothing
        // rather than a neighbouring item's or the top-level one. Unlike Signal's,
        // this feed's digest describes the bytes the CDN serves.
        // History: docs/app-audits/com-unity3d-unityhub.md#历史与实测
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
                kind: .zip,
                checksumPattern:
                    #"\A(?:(?!UnityHubSetup-[^\s]+-arm64\.zip)[\s\S])*?\n[ \t]*-[ \t](?=[^\n]*(?:\n[ \t]+(?![\s-])[^\n]*)*?UnityHubSetup-[^\s]+-arm64\.zip)(?:[^\n]*\n[ \t]+(?![\s-]))*?sha512:[ \t]*([A-Za-z0-9+/=]+)"#)),
        ])
}
