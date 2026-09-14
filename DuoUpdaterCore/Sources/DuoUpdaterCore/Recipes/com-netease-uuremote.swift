import Foundation

enum com_netease_uuremote {
    static let set = AppRecipeSet(
        family: "com-netease-uuremote",
        probes: [
        // History: docs/app-audits/com-netease-uuremote.md#历史与实测
        // UURemote (网易UU远程) — no Sparkle, no public version JSON, and the
        // product page is client-rendered so the HTML carries no version at all.
        // The one machine-readable surface is the download button's endpoint, found
        // in the page's markup: NetEase's release API 302s to the versioned package
        // (e.g. `uuyc_4.35.0.pkg`), which is the version the app reports.
        //
        // The Homebrew cask can't cover a copy installed straight from the vendor:
        // its provenance gate (correctly) only adopts apps brew actually installed.
        //
        // A `.pkg` hands off to macOS's own installer, so the user still confirms
        // it there (same flow as ToDesk and AweSun); the install spec re-resolves
        // the redirect at download time so it always fetches the current package,
        // not this version's.
        // No `changelogURL`: no changelog page was found when checked (2026-08-22;
        // History has the candidate URLs and what they returned).
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
