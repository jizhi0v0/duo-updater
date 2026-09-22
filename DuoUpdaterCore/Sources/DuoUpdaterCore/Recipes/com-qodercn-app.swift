import Foundation

enum com_qodercn_app {
    static let set = AppRecipeSet(
        family: "com-qodercn-app",
        changelogs: [
        // History: docs/app-audits/com-qodercn-app.md#历史与实测
        // Qoder CN — the mainland-China build of the Qoder desktop app, and a
        // product of its own, not a download mirror of `com.qoder.app`: its own
        // bundle id (`com.qodercn.app`), its own app name (`Qoder CN.app`), and its
        // own Team (9DFNGU9AK5, Hangzhou Yundian, where the global app is
        // B6U242QL73). The two can sit side by side on one Mac.
        //
        // No version recipe: the bundle's own `app-update.yml` names
        // `provider: generic`, `url: https://static.qoder.com.cn/qoder-app/releases`,
        // so `ElectronManifestSource` reads the `latest-mac.yml` the app's own
        // updater reads — version, arm64 zip, sha512 — and that is the whole
        // detection and one-click path.
        //
        // The notes live on the CN docs site, which is the same docs build as
        // `docs.qoder.com` (`data-component-part` update blocks, the version
        // spelled "Qoder 0.3.4"), so the shared Qoder entry pattern applies
        // unchanged. Only the date differs: "2026年09月20日", rendered as text.
        //
        // ⚠️ The slugs on that site do not follow the product names: this page is
        // `/product-overview/qoder-update-log` (titled "Qoder CN 更新日志"), while
        // `/product-overview/qoder-cn-update-log` is the index of every CN
        // product's log and carries no entries at all.
        ChangelogRecipe(
            bundleID: "com.qodercn.app",
            source: URL(string: "https://docs.qoder.cn/product-overview/qoder-update-log")!,
            entryPattern: ChangelogRecipeRegistry.qoderEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
