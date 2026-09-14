import Foundation

enum MstyStudio {
    static let set = AppRecipeSet(
        family: "MstyStudio",
        probes: [
        // History: docs/app-audits/MstyStudio.md#历史与实测
        // Msty Studio — official electron-builder manifest lists both x64 and
        // arm64 assets and reports the same version as Info.plist. MstyStudio,
        // Team S6CF5A8MX9, notarized.
        //
        // ONE-CLICK via `.fixed`: this vendor's filenames carry no version
        // (`MstyStudio_arm64.zip`), so the artifact URL is a constant and there is
        // nothing to template. The manifest that names the version sits in the
        // same directory, so the two always describe one release.
        //
        // THE CHECKSUM PATTERN IS ANCHORED ON THE arm64 FILENAME, and that anchor
        // is the whole reason this recipe was blocked. `checksumPattern` is a
        // separate first-match over the body, and this manifest lists four
        // artifacts — `MstyStudio_x64.zip` FIRST, then arm64, then both dmgs — so
        // the obvious `^\s+sha512:` would hand the x64 digest to an arm64
        // download and fail every install. Requiring `url: MstyStudio_arm64.zip`
        // immediately before the digest makes the pairing structural rather than
        // positional (History has the 2026-08-29 check against a downloaded zip).
        //
        // The checksum earns its place twice over here. Because the URL is a
        // "latest" path while the digest belongs to the version the probe
        // compared, a release published between the check and the click fails the
        // checksum instead of silently installing a version nobody compared —
        // loud, and cleared by re-checking. Without it this recipe could report
        // one version and install another.
        //
        // That second job is BEST-EFFORT, and the limit belongs here rather than
        // in a reader's assumption: a checksum is optional at install time
        // (`VendorInstaller` gates it behind `if let expected`), so if this
        // pattern ever stops matching — the vendor reorders the keys inside an
        // entry, or renames the asset — the install proceeds unverified and the
        // "latest" URL is once again free to be a version nobody compared. Only
        // the nightly sweep notices, through `checksumPatternNoMatch`, after the
        // fact. Making it fatal instead was considered and refused: a vendor
        // reformat would turn "installed a slightly newer build" into "one-click
        // is dead", which is the worse of the two failures.
        //
        // The artifact this spec selects extracts to an arm64 `MstyStudio.app`
        // signed `Developer ID Application: Ashok Gelal (S6CF5A8MX9)`, accepted by
        // spctl as Notarized Developer ID (checked 2026-08-29; History has the
        // version and size).
        VendorProbeRecipe(
            bundleID: "MstyStudio",
            url: URL(string: "https://next-assets.msty.studio/app/latest/mac/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*v?([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://msty.ai/"),
            changelogURL: URL(string: "https://msty.ai/resources/changelog/studio/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://next-assets.msty.studio/app/latest/mac/"
                        + "MstyStudio_arm64.zip")!),
                kind: .zip,
                checksumPattern: #"url:\s*MstyStudio_arm64\.zip\s*\n\s*sha512:\s*(\S+)"#)),
        ])
}
