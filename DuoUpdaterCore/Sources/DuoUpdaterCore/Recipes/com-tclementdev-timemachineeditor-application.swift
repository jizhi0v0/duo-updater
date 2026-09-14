import Foundation

enum com_tclementdev_timemachineeditor_application {
    static let set = AppRecipeSet(
        family: "com-tclementdev-timemachineeditor-application",
        probes: [
        // MARK: - 2026-08-29 TimeMachineEditor

        // History: docs/app-audits/com-tclementdev-timemachineeditor-application.md#历史与实测
        // TimeMachineEditor has no Sparkle feed (confirmed: the vendor's own pkg,
        // downloaded and expanded 2026-08-29, carries no `SUFeedURL` in its app's
        // Info.plist and no `Sparkle.framework`), no MAS listing, no GitHub repo —
        // the vendor's own tiny site is the only surface. Its Homebrew cask
        // (`timemachineeditor`) is `auto_updates: true`, which makes
        // `HomebrewCaskSource` skip it, so this probe is the only source that can
        // ever answer for this bundle id.
        //
        // No JSON/version API exists — the homepage IS the release note: a single
        // download link whose visible text carries the version
        // (`<a href="…/TimeMachineEditor.pkg">TimeMachineEditor 5.2.2</a> (2023,
        // February 16) …`, fetched 2026-08-29). This is exactly the endpoint
        // Homebrew's own `livecheck` block resolves against (`url :homepage`,
        // regex `href=.*TimeMachineEditor\s*v?(\d+(?:\.\d+)+)`), independently
        // confirming it's the vendor's intended version surface, not a guess. The
        // pattern here is anchored to the literal href AND the `</a>` boundary so
        // it cannot drift onto the nearby "macOS 10.13" floor mentioned in the same
        // sentence.
        //
        // The probed version matches the pkg's MARKETING field
        // (`CFBundleShortVersionString`) exactly, so no `versionIsBuild` (verified
        // 2026-08-29 against the expanded pkg; History has the fields and the
        // signature).
        //
        // kind MUST be `.pkg`, not `.dmg`/`.zip`: the payload installs siblings
        // outside the `.app` — `/Library/LaunchDaemons/
        // com.tclementdev.timemachineeditor.scheduler.plist`, a scheduler binary
        // and `tmectl` CLI under `/Library/TimeMachineEditor/`, plus a
        // `com.tclementdev.timemachineeditor.upgrader` pre/postinstall script that
        // manages the daemon across upgrades. A bundle-only unpack would leave the
        // new `.app` next to a stale daemon with nothing to notice. The download
        // URL itself is a static, unversioned filename that always serves the
        // current release, so `.fixed` needs no pattern.
        //
        // Single channel: the vendor ships no beta/nightly, so there is nothing to
        // gate — `channel` stays the default `.stable`.
        //
        // Delta/binary patch: not checked for — this is not a Sparkle app (no
        // `SUFeedURL`, no `Sparkle.framework` in the bundle) and the download is a
        // pkg with no companion `.delta`/`.patch` artifact anywhere on the page,
        // so there is nothing here to consume.
        VendorProbeRecipe(
            bundleID: "com.tclementdev.timemachineeditor.application",
            url: URL(string: "https://tclementdev.com/timemachineeditor/")!,
            mode: .responseBody,
            versionPattern:
                #"<a href="https://tclementdev\.com/timemachineeditor/TimeMachineEditor\.pkg">TimeMachineEditor\s+([0-9]+(?:\.[0-9]+)+)</a>"#,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://tclementdev.com/timemachineeditor/TimeMachineEditor.pkg")!),
                kind: .pkg)),
        ])
}
