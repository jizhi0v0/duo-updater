import Foundation

enum com_trae_app {
    static let set = AppRecipeSet(
        family: "com-trae-app",
        probes: [
        // TRAE (`com.trae.app`, Team 79M8227NKH). The endpoint is the public API
        // the website's download page reads,
        // `api.trae.ai/icube/api/v1/native/version/trae/latest`. Under
        // `data.manifest.darwin.versions[]` each entry is
        // `{region, arch, url, version}`, and `version` is the dmg's
        // `CFBundleShortVersionString`. This follows the build anyone downloads
        // by hand from the website, which can be newer than the build TRAE's own
        // in-app check allocates.
        //
        // TRAP: the same body carries `version` fields that are not this app's
        // macOS build: `manifest.win32` / `manifest.linux`, `data.solo` (TraeWork,
        // another product) and `data.tob.manifest` (another build of the same
        // bundle id). So both patterns walk `data` → `manifest` → `darwin` →
        // `versions` without crossing a `solo`, `tob` or `mobile` key (nor, inside
        // `darwin`, a `win32` or `linux` key), and take the one entry for region
        // `va` and their architecture. A response that is shaped any other way
        // matches nothing and the app stays unknown.
        //
        // Region: every region names the same version; `va` is the vendor's
        // international CDN (`lf-cdn.trae.ai/obj/trae-ai-us/`). Reading one entry
        // keeps the version and the URL in the same object.
        //
        // Architecture: separate arm64 (`apple`) and x86_64 (`intel`) dmgs, so one
        // recipe per architecture, split by `hostRequirement` so exactly one runs
        // on any Mac. Each install pattern also pins its own
        // `TraeCode-darwin-<arch>.dmg`, independent of the `arch` label.
        //
        // One-click: both dmgs are notarized, Team 79M8227NKH like the installed
        // app; the bundle holds only its Electron helpers and Squirrel, nothing
        // installed outside it, so `.dmg`. The body carries no digest.
        traeRecipe(arch: .arm64),
        traeRecipe(arch: .x86_64),
        ])

    /// Everything up to the start of the `manifest.darwin.versions[]` entry for
    /// region `va` and the API's name for `arch`.
    private static func darwinEntry(arch: HostArch) -> String {
        let label = arch == .arm64 ? "apple" : "intel"
        return #"(?s)"data"\s*:\s*\{(?:(?!"(?:solo|tob|mobile)"\s*:).)*?"#
            + #""manifest"\s*:\s*\{(?:(?!"(?:solo|tob|mobile)"\s*:).)*?"#
            + #""darwin"\s*:\s*\{(?:(?!"(?:solo|tob|mobile|win32|linux)"\s*:).)*?"#
            + #""versions"\s*:\s*\[[^\]]*?"#
            + #"\{(?=[^{}]*"region"\s*:\s*"va")(?=[^{}]*"arch"\s*:\s*"\#(label)")"#
    }

    static func traeRecipe(arch: HostArch) -> VendorProbeRecipe {
        let file = arch == .arm64 ? "arm64" : "x64"
        return VendorProbeRecipe(
            bundleID: "com.trae.app",
            url: URL(string: "https://api.trae.ai/icube/api/v1/native/version/trae/latest")!,
            mode: .responseBody,
            versionPattern: darwinEntry(arch: arch)
                + #"[^{}]*?"version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.trae.ai/download"),
            changelogURL: URL(string: "https://docs.trae.ai/ide/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(darwinEntry(arch: arch)
                    + #"[^{}]*?"url"\s*:\s*"(https://lf-cdn\.trae\.ai/obj/trae-ai-us/pkg/app/releases/stable/[0-9.]+/darwin/TraeCode-darwin-\#(file)\.dmg)""#),
                kind: .dmg),
            variant: file,
            hostRequirement: VendorHostRequirement(architectures: [arch]))
    }
}
