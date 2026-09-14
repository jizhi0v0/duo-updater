import Foundation

enum com_tdesktop_Telegram {
    static let set = AppRecipeSet(
        family: "com-tdesktop-Telegram",
        probes: [
        // MARK: - 2026-08-16 Telegram Desktop

        // History: docs/app-audits/com-tdesktop-Telegram.md#历史与实测
        // Telegram Desktop (com.tdesktop.Telegram — NOT the App Store's Telegram
        // for macOS, ru.keepcoder.Telegram, which is a different app entirely and
        // stays on the MAS channel). The official download link 302s straight to
        // the versioned dmg — e.g. `telegram.org/dl/desktop/mac` →
        // `td.telegram.org/mac/td-setup-mac-7.2.7.dmg` — so the redirect filename
        // is both the version signal and the download.
        //
        // NOT `td.telegram.org/current4`, which is what the app's own updater
        // reads: that JSON states versions as PACKED INTEGERS (e.g.
        // `"armac": {"stable": {"released": "7000009"}}` = 7.0.9, major*10^6 +
        // minor*10^3 + patch).
        // Decoding it needs arithmetic, and every recipe here is regex-only — a
        // pattern could only ever carry `7000009` forward, which compares against
        // nothing the bundle reports. The redirect states the same release in the
        // scheme the app actually uses.
        //
        // The dmg's `Telegram.app` reports the filename's version as BOTH
        // CFBundleShortVersionString and CFBundleVersion (no build/marketing split
        // to work around) — verified by mounting the dmg on 2026-08-16 and again on
        // 2026-09-08 after the rename below; History has both checks.
        //
        // TWO FILENAME STEMS, and both are load-bearing. Telegram renamed every
        // artifact it publishes — `tsetup.*` / `tportable.*` → `td-setup-mac-*`,
        // `td-setup-win-*`, `td-portable-win-*` — and did it in two steps, which
        // is what says it was planned rather than a slip: a beta first, then the
        // stable line at 7.2.7 (History has the timeline, read 2026-09-08). The
        // redirect moved with that stable release, and the old path is retired
        // rather than lagging (checked 2026-09-08; History has the URLs).
        //
        // The retired stem nonetheless stays in the alternation, as a hedge
        // against a revert that costs nothing here: this mode reads the
        // `Location` header, which holds exactly one URL and therefore exactly
        // one filename, so a second alternative cannot latch onto a neighbouring
        // artifact the way it could in a page body. Both branches are pinned by a
        // real captured redirect in `TelegramDesktopProbeRecipeTests`.
        //
        // The captured group still ENDS AT DIGITS, and under the new scheme that
        // is what keeps this stable-channel recipe off the prerelease line:
        // Telegram names betas `td-setup-mac-7.2.6-beta.dmg`, which this pattern
        // matches NOTHING in — the Canva precedent. If this endpoint ever handed
        // out a beta, the right outcome is a loud `versionPatternNoMatch`, not a
        // prerelease reported as a stable release, so do not widen the segment to
        // absorb `-beta` to make a red row go green. `aBetaFilenameIsNotAStableRelease`
        // is the test that fails if someone does.
        VendorProbeRecipe(
            bundleID: "com.tdesktop.Telegram",
            url: URL(string: "https://telegram.org/dl/desktop/mac")!,
            mode: .redirectFilename,
            versionPattern: #"(?:tsetup\.|td-setup-mac-)([0-9]+(?:\.[0-9]+)+)\.dmg"#,
            downloadURL: URL(string: "https://desktop.telegram.org/"),
            changelogURL: URL(string: "https://telegram.org/blog"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://telegram.org/dl/desktop/mac")!),
                kind: .dmg),
            followRedirects: false),
        ])
}
