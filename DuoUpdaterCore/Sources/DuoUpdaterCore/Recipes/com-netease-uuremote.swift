import Foundation

enum com_netease_uuremote {
    static let set = AppRecipeSet(
        family: "com-netease-uuremote",
        probes: [
        // UURemote (网易UU远程) — no Sparkle, no public version JSON, and the
        // product page is client-rendered so the HTML carries no version at all.
        // The one machine-readable surface is the download button's endpoint, found
        // in the page's markup: NetEase's release API 302s to the versioned package
        // (`uuyc_4.35.0.pkg`), which is the version the app reports.
        //
        // The Homebrew cask can't cover this: its provenance gate (correctly) only
        // adopts apps brew actually installed, and this one was installed directly.
        //
        // One-click verified 2026-08-09 on the 4.35.0 package: `pkgutil
        // --check-signature` reports "Developer ID Installer: Hangzhou Bobo
        // Technology Co Ltd (PU9BNSBJW7)" — the same team as the installed bundle —
        // notarized, with a trusted timestamp. A `.pkg` hands off to macOS's own
        // installer, so the user still confirms it there (same flow as ToDesk and
        // AweSun); the install spec re-resolves the redirect at download time so it
        // always fetches the current package, not this version's.
        // No `changelogURL`: there is no such page. `uuyc.163.com/changelog` and
        // `/update` both answer 200, but they return byte-identical content to a
        // path that does not exist — an SPA catch-all serving the homepage, not a
        // changelog. The download page is a distinct page but contains no
        // 更新日志/更新说明/新增/修复 markers at all. (Checked 2026-08-22.)
        VendorProbeRecipe(
            bundleID: "com.netease.uuremote",
            url: URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4?channel=gwqd")!,
            mode: .redirectFilename,
            versionPattern: #"uuyc_([0-9]+(?:\.[0-9]+)+)\.pkg"#,
            // The probe endpoint above 302s straight to the pkg, so it must never
            // be what a "download page" link opens — that just downloads a file.
            // uuyc.163.com is the product's own site (网易UU远程官网).
            downloadURL: URL(string: "https://uuyc.163.com/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4?channel=gwqd")!),
                kind: .pkg),
            followRedirects: false),
        ])
}
