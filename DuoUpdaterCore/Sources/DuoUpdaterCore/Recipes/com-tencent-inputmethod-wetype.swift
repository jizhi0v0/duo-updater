import Foundation

enum com_tencent_inputmethod_wetype {
    static let set = AppRecipeSet(
        family: "com-tencent-inputmethod-wetype",
        probes: [
        // History: docs/app-audits/com-tencent-inputmethod-wetype.md#历史与实测
        // WeType (微信输入法) — Tencent's input method. Installs under
        // `/Library/Input Methods` (not /Applications), now scanned by AppScanner.
        // No standard source resolves it: its bundled Sparkle has NO SUFeedURL in
        // Info.plist (set at runtime), and the hardcoded public appcast froze at
        // 1.4.1 (2025-07) while 2.x updates ride an in-app WeChat push channel. The
        // version comes from the manifest the vendor's own installer reads (below);
        // the official changelog page is only the notes source (the ChangelogRecipe
        // further down). History has the earlier recipe that read the version off
        // that page, and the one-click withdrawal of 2026-08-16.
        //
        // The real reason a bundle swap was always the wrong shape here: the
        // vendor's own `WeTypeInstaller.app` does more than copy. Its binary
        // carries `Registered input source from /Library/Input Methods/WeType.app,
        // result:` — it REGISTERS the input source with the system, and whatever
        // per-version migration sits alongside that. Replacing the bundle skips
        // every one of those steps.

        // Read the endpoint the vendor's OWN installer reads, not the marketing
        // page. `WeTypeInstaller.app` is a stub that ships no payload — it
        // GETs `?channel=InstallInfo`, which 302s to a per-build JSON manifest:
        //
        //   {"zip_download_url": ".../2.2.3/WeType_2.2.3_657.zip",
        //    "zip_version": "2.2.3.657", "zip_download_md5": "…"}
        //
        // Not the `WeTypeInstaller_<x.y.z>_<build>_<letter>.zip` filenames on
        // `z.weixin.qq.com/web/change-log/macos`, which an earlier recipe read:
        // those numbers are **the installer stub's own version, not the app's**.
        // The two can track each other closely enough to look right, which is
        // exactly how a wrong-scheme recipe survives: it never fails, it just
        // answers with a number from the wrong namespace (History has the versions
        // and how the nightly sweep caught it).
        //
        // That page also lags on its own account (History has a dated case), so
        // neither the filenames nor the notes on it are a version source.
        //
        // ONE-CLICK, restored 2026-08-28 (withdrawn 2026-08-16 after a user lost
        // their WeType settings; History has the evidence), and the reason it is
        // back is that the install now has the same SHAPE as the vendor's own
        // update rather than the shape of its installer.
        //
        // What the stub's `install.sh` does is `rm -rf` the whole `WeType.app` and
        // `mv` a fresh one in, then `chown -R root:staff` + `chmod -R 775`. What
        // `WeTypeUpdater.app` — the updater that ships INSIDE the bundle and runs
        // for every ordinary release — does instead is keep the outer directory
        // and rotate `Contents` through `.Contents.update` / `.Contents.old` (its
        // binary carries those exact paths, plus `will exchange Contents:
        // previous=`). The second one is the update path, and it is the one
        // `InPlaceSwap.rotateContents` reproduces: the registered `.app` path, its
        // inode, its ownership and its modes are all left alone.
        //
        // `zip_download_url` is the real payload, not the small stub the marketing
        // page links: a notarized `WeType.app`, Team 88L2Q4487U, which the code
        // signature + Team + bundle-id gates check before anything moves. The
        // response also carries `zip_download_md5`; `checksumPattern` is SHA-512
        // base64, so it is deliberately NOT wired up rather than mis-declared.
        //
        // The withdrawal was about the user's dictionary and settings, which live
        // in `~/Library/Application Support/WeType/` and never in the bundle.
        // Those are snapshotted alongside the bundle rollback point and restored
        // with it — see `InputMethodDataBackup`, including what it does not cover
        // (a user who has turned rollback points off gets no snapshot either).
        VendorProbeRecipe(
            bundleID: "com.tencent.inputmethod.wetype",
            url: URL(string: "https://z.weixin.qq.com/web/mac/download?channel=InstallInfo")!,
            mode: .responseBody,
            versionPattern: #""zip_version"\s*:\s*"[0-9]+(?:\.[0-9]+){2}\.([0-9]+)""#,
            downloadURL: URL(string: "https://z.weixin.qq.com/"),
            changelogURL: URL(string: "https://z.weixin.qq.com/web/change-log/macos"),
            versionIsBuild: true,
            displayVersionPattern: #""zip_version"\s*:\s*"([0-9]+(?:\.[0-9]+){2})\.[0-9]+""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""zip_download_url"\s*:\s*"(https://[^"]+\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // WeType (微信输入法) — the official changelog page its VendorProbe
        // names as `changelogURL`. Next.js page with the data server-rendered
        // inline (an `__next_f` RSC blob, no JS needed): a flat list of release
        // objects for ALL platforms, tagged
        // `"platform":1`=iOS / `2`=Android / `3`=macOS / `4`=Windows. The entry
        // pattern ties the captured version/body to its OWN object's `"platform":3`
        // (version precedes platform; `[^"]*` can't cross a structural quote, so it
        // can't bleed into an adjacent platform's object) — so only macOS releases
        // become entries. The notes live in `content_html`, where each line is its
        // own tag — usually `<h2>` (including the dash-bulleted lines), sometimes
        // `<ul><li>` or `<p>` — so itemPatterns try all three. No human per-entry
        // date is published (only a unix `release_date`), so `date` is omitted
        // rather than shown as a raw epoch. CRUCIAL: the list runs oldest→newest, so
        // `newestLast` flips it to newest-first before the cap. Quotes inside notes
        // are `&quot;`-encoded (no raw `"`), so the `[^"]*` field bounds hold and the
        // default HTML entity decode renders them. A parse miss falls back to
        // embedding this same page (the VendorProbe's changelogURL).
        ChangelogRecipe(
            bundleID: "com.tencent.inputmethod.wetype",
            source: URL(string: "https://z.weixin.qq.com/web/change-log/macos")!,
            entryPattern:
                #""version":"(?<version>[0-9][^"]*)","content":"[^"]*","#
                + #""content_html":"(?<body>[^"]*)","platform":3"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<h2[^>]*>(?<item>.*?)</h2>"#,
                #"<p[^>]*>(?<item>.*?)</p>"#,
            ],
            maxEntries: 20,
            newestLast: true),
        ])
}
