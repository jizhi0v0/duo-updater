import Foundation

enum com_aliyun_lingma_ide {
    static let set = AppRecipeSet(
        family: "com-aliyun-lingma-ide",
        probes: [
        // History: docs/app-audits/com-aliyun-lingma-ide.md#历史与实测
        // Qoder CN IDE — the mainland-China build of Qoder IDE. The bundle id is
        // still the pre-rename `com.aliyun.lingma.ide` (the product used to be
        // Lingma), the app is `Qoder CN IDE.app`, the Team is 9DFNGU9AK5 (the same
        // as Qoder CN, not the global IDE's T27K5A5ZWD). Built from the same
        // source as the global IDE: the same release carries the same commit on
        // both sides.
        //
        // A VS Code fork, but NOT on the path its `product.json` `updateUrl`
        // suggests. The app asks
        // `<updateUrl>/api/qodercn/update/<platform>/<quality>/<productVersion>`
        // — a `qodercn` segment, and the installed VERSION where VS Code puts a
        // commit (read off the app's own traffic). The plain VS Code path
        // `/api/update/…/<commit>` on the same host is a different, legacy table:
        // it answers "Lingma 0.11.4" to any commit it does not know, so reading it
        // would report a years-old product line and never an update.
        //
        // Asked with `latest`, like the global IDE, so an answer is always
        // expected; the installed version's own slot answers 204 when current.
        //
        // ⚠️ STAGED ROLLOUT, keyed on `machineId` — the same scheme as the global
        // IDE's `center.qoder.sh` (see `Recipes/com-qoder-ide.swift` for the
        // mechanism and why the id is read, never recomputed or made up). Without
        // an id the answer alternates per request between the newest release and
        // the one before it; with the app's own id it is the answer the app's
        // updater gets, every time. The same Mac holds the same id in both IDEs
        // and the two servers roll out independently, so each recipe asks its own.
        // `umid` and `os` change nothing and are not sent.
        //
        // `productVersion`, not `name` ("QoderCN") and not `version` (the commit).
        //
        // The install URL is built from the RESOLVED version, not read from the
        // body, the opposite choice from the global IDE, and for a measured
        // reason: the body names `ide.qoder.com.cn/qoder/release/lastest/…zip`
        // (the vendor's spelling), a moving alias that the CDN edge was still
        // serving as the previous release while the API already answered the new
        // one. Taking it would install the older build under the newer label. The
        // versioned path `release/<version>/QoderCN-darwin-arm64.zip` is the same
        // object the origin's `lastest` resolves to once it is current.
        //
        // `darwin-arm64` only: `/darwin/stable/latest` answers the x64 zip, and
        // `darwin-x64` and the `insider` quality 404.
        VendorProbeRecipe(
            bundleID: "com.aliyun.lingma.ide",
            url: URL(string: "https://lingma-api.tongyi.aliyun.com/algo"
                + "/api/qodercn/update/darwin-arm64/stable/latest?machineId=__IDENTITY__")!,
            mode: .responseBody,
            versionPattern: #""productVersion"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://qoder.cn/download"),
            changelogURL: URL(string: "https://docs.qoder.cn/product-overview/qoder-cn-ide-update-log"),
            publishedAtPattern: #""timestamp"\s*:\s*([0-9]{9,})"#,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://ide.qoder.com.cn/qoder/release/{version}/QoderCN-darwin-arm64.zip"),
                kind: .zip),
            identities: [ProbeIdentity.vsCodeMachineID(applicationSupportDirectory: "QoderCN")]),
        ],
        changelogs: [
        // Same docs build as every other Qoder page, so the shared entry pattern;
        // the version here is bare ("1.31.0"), which it accepts. The page is
        // written after the release ships, so it can trail the probe by a
        // release or so.
        ChangelogRecipe(
            bundleID: "com.aliyun.lingma.ide",
            source: URL(string: "https://docs.qoder.cn/product-overview/qoder-cn-ide-update-log")!,
            entryPattern: ChangelogRecipeRegistry.qoderEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
