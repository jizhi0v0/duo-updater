import Foundation

enum org_grunenberg_EasyFind {
    static let set = AppRecipeSet(
        family: "org-grunenberg-EasyFind",
        probes: [
        // History: docs/app-audits/org-grunenberg-EasyFind.md#历史与实测
        // EasyFind (DEVONtechnologies) — no Sparkle at all: the app carries
        // neither `Sparkle.framework` nor an `SUFeedURL` (verified 2026-08-16 by
        // unpacking the shipped zip), so a copy installed from the vendor's site
        // has no source whatsoever. Homebrew's cask is `auto_updates:false` and
        // therefore covers brew-installed copies already — this recipe is for the
        // direct-download ones.
        //
        // The source is the shared freeware page, which lists several unrelated
        // apps with their own version numbers (e.g. 1.9.11, 6.0.1, 4.5.3 …). The
        // pattern is anchored to EasyFind's own download PATH rather than to any
        // "Version X" text, so it cannot drift onto a neighbour's number:
        //   …/download/freeware/easyfind/5.0.2/EasyFind.app.zip
        // The install URL is the same link, read from the same page — no
        // templating, so a vendor rename of the artifact can't silently 404.
        //
        // One-click: that zip holds `EasyFind.app`, org.grunenberg.EasyFind, Team
        // 679S2QUWR8 (DEVONtechnologies, LLC), notarized Developer ID, spctl
        // accepted (checked 2026-08-16; History has the version).
        VendorProbeRecipe(
            bundleID: "org.grunenberg.EasyFind",
            url: URL(string: "https://www.devontechnologies.com/apps/freeware")!,
            mode: .responseBody,
            versionPattern:
                #"/download/freeware/easyfind/([0-9]+(?:\.[0-9]+)+)/EasyFind\.app\.zip"#,
            downloadURL: URL(string: "https://www.devontechnologies.com/apps/freeware"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download\.devontechnologies\.com/download/freeware/easyfind/[0-9.]+/EasyFind\.app\.zip)"#),
                kind: .zip)),
        ])
}
