import Foundation

enum com_oray_sunlogin_macclient {
    static let set = AppRecipeSet(
        family: "com-oray-sunlogin-macclient",
        probes: [
        // AweSun (Oray) — official software API; same endpoint the Homebrew cask
        // livecheck uses. Intel build drops the `_ARM` suffix. The dmg holds a
        // signed `AweSun.pkg` (Developer ID Installer ZBNMDRTU32) → system
        // installer (pkg). We take the FILENAME out of the JSON's own
        // `downloadurl` and re-host it on `dw.oray.com` rather than build the
        // name ourselves: the vendor renamed the file once already (`AweSun_v{v}`
        // → `AweSun_{v}`, which 404'd every install at 16.6.0.32198), and the
        // field's own host alternates per request between `dw.oray.com` and
        // `d-cdn.oray.com` while the filename stays identical. We can't use the
        // URL verbatim either — the field escapes its slashes (`https:\/\/…`,
        // breaking `URL(string:)`). `dw.oray.com` is behind an Aliyun WAF that
        // returns an anti-bot JS challenge unless a `Referer` is present — so we
        // send one. If the filename can't be read, the probe degrades to opening
        // the official download page (downloadURL).
        VendorProbeRecipe(
            bundleID: "com.oray.sunlogin.macclient",
            url: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
            mode: .responseBody,
            versionPattern: #""versionno"\s*:\s*"([0-9.]+)""#,
            downloadURL: URL(string: "https://sunlogin.oray.com/download"),
            changelogURL: URL(string: "https://sunlogin.oray.com/download/update-log?soft=SLCC_X_MAC_ARM"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dw.oray.com/sl/mac/{0}",
                    fields: [#""downloadurl"\s*:\s*"[^"]*?(AweSun_[0-9][^"\\/]*_arm64\.dmg)""#]),
                kind: .pkg,
                requestHeaders: ["Referer": "https://sunlogin.oray.com/"])),
        ],
        changelogs: [
        // AweSun (Oray) — same JSON API as the VendorProbeRecipe (verified live
        // 2026-08-21: GET returns 200/~15KB; the earlier "50 bytes" observation
        // that prompted a re-check did not reproduce and the endpoint/logic are
        // both healthy — see `sunLoginSoftwareLogs`'s doc comment for the shape).
        ChangelogRecipe(
            bundleID: "com.oray.sunlogin.macclient",
            source: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
            mode: .json,
            structuredFormat: .sunLoginSoftwareLogs),
        ])
}
