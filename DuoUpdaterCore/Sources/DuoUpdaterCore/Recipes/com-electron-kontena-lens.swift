import Foundation

enum com_electron_kontena_lens {
    static let set = AppRecipeSet(
        family: "com-electron-kontena-lens",
        probes: [
        // Lens — electron-builder feed. The version carries a literal `-latest`
        // suffix (`2026.6.260931-latest`) and so does the shipped bundle's own
        // `CFBundleShortVersionString`, verified on the mounted dmg
        // (com.electron.kontena-lens, Team JJ22T2W355, notarized). Both sides
        // therefore compare like-for-like; do NOT "clean up" the suffix here,
        // that would make every check report a phantom update.
        VendorProbeRecipe(
            bundleID: "com.electron.kontena-lens",
            url: URL(string: "https://api.k8slens.dev/binaries/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://k8slens.dev/"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Lens-[^\s]+-arm64\.dmg)"#,
                    base: URL(string: "https://api.k8slens.dev/binaries/")!),
                kind: .dmg)),
        ])
}
