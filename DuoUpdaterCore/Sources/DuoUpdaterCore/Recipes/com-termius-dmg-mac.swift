import Foundation

enum com_termius_dmg_mac {
    static let set = AppRecipeSet(
        family: "com-termius-dmg-mac",
        probes: [
        // Shared rationale for 2026-08-16 vendor batch: Recipes/dev-commandline-waveterm.swift.

        // Termius — electron-builder feed, one per architecture. The artifacts
        // are unversioned (`Termius.dmg`), so the install URL is fixed and the
        // version comes from the feed. Verified 2026-08-16 on the arm64 dmg:
        // com.termius-dmg.mac, 9.43.1, Team 6KN952WR85, notarized.
        // snapshot-lint:allow — this dated verification stays in code: `Recipes/dev-commandline-waveterm.swift`'s batch block names Termius stable and relies on it.
        VendorProbeRecipe(
            bundleID: "com.termius-dmg.mac",
            url: URL(string: "https://autoupdate.termius.com/mac-arm64/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://termius.com/download/macos"),
            // `termius.com/release-notes` 404s (checked 2026-08-27). The live
            // page is on the docs host; `termius.com/changelog` redirects here,
            // so point at the destination rather than depend on the redirect.
            changelogURL: URL(string: "https://docs.termius.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://autoupdate.termius.com/mac-arm64/Termius.dmg")!),
                kind: .dmg)),

        // History: docs/app-audits/com-termius-dmg-mac.md#历史与实测
        // Termius Beta — a genuinely independent bundle id from stable's
        // `com.termius-dmg.mac` (issue #91), so no cross-channel risk and
        // `ReleaseChannel.detect()` needs no new rule: `CFBundleName`/
        // `CFBundleDisplayName` is "Termius Beta", which its existing
        // standalone-word `channelWord` step already resolves to `.beta`.
        //
        // Same electron-builder feed shape as stable, on the SAME
        // autoupdate.termius.com host stable already probes, just under the
        // mac-beta-universal path — found by reading the vendor's own Homebrew
        // cask (`Casks/t/termius.rb`), whose `livecheck` block points
        // electron_builder-strategy readers at
        // `https://autoupdate.termius.com/mac/latest-mac.yml` (stable's
        // un-suffixed, Intel-only sibling of the arm64 feed above) — that is
        // what led here, since the app's own bundled `app-update.yml` names an
        // `acl: private` S3 bucket that a plain GET can't read (403, verified).
        //
        // One-click: the real dmg holds com.termius-beta.mac, Team 6KN952WR85,
        // Notarized Developer ID, not sandboxed — same Team as stable, so
        // `VendorInstaller`'s Team gate holds. Unlike the arm64-only stable
        // recipe above, this feed's dmg is UNIVERSAL (x86_64 arm64), so one
        // recipe correctly serves every Mac with no `hostRequirement` needed
        // (downloaded and mounted 2026-08-27; History has the version checked).
        //
        // checksumPattern is safe here — unlike Signal Beta, whose CDN staples
        // the dmg AFTER electron-builder computed the feed's sha512 (see the
        // comment on Signal's recipe in `Recipes/org-whispersystems-signal-desktop.swift`), Termius Beta's declared
        // `sha512` for "Termius Beta.dmg" was independently verified
        // 2026-08-27 to equal `shasum -a 512 | base64` of the downloaded file,
        // byte for byte.
        //
        // No changelogURL. When this recipe was written, stable's changelogURL
        // was `https://termius.com/release-notes`, which 404'd; stable now points
        // at the docs-host page (above). Whether that page carries the beta
        // builds' notes has not been checked (History has the original note).
        VendorProbeRecipe(
            bundleID: "com.termius-beta.mac",
            url: URL(string: "https://autoupdate.termius.com/mac-beta-universal/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://termius.com/beta-program"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://autoupdate.termius.com/mac-beta-universal/Termius%20Beta.dmg")!),
                kind: .dmg,
                checksumPattern: #"Termius Beta\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#),
            channel: .beta),
        ],
        channelProofs: [
        // Termius Beta already has an independent bundle id (`com.termius-beta.mac`
        // vs stable's `com.termius-dmg.mac`), so this is belt-and-suspenders: the
        // resolved install URL's own path names the channel.
        ChannelProofKey("com.termius-beta.mac", .beta): .artifact(#"/mac-beta-universal/"#),
        ])
}
