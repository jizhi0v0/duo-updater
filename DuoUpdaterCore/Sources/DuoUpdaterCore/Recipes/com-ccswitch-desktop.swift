import Foundation

enum com_ccswitch_desktop {
    static let set = AppRecipeSet(
        family: "com-ccswitch-desktop",
        githubRules: [
        // MARK: - 2026-08-16 coverage batch
        //
        // Candidates came from the Homebrew 365-day cask install ranking crossed
        // against this registry, then triaged by DOWNLOADING each real artifact,
        // mounting it read-only and reading its Info.plist + `codesign`/`spctl`.
        // (The sweep's raw evidence lives outside the repo — `docs/` is gitignored —
        // so each rule below carries its own findings inline instead of citing it.)
        // Every rule below therefore states a bundle id, Team ID and notarization
        // status read off the very asset its `installAssetPattern` selects — not off
        // the vendor's download page. Apps that turned out to ship a usable
        // `SUFeedURL` are deliberately absent: `SparkleAppcastSource` already covers
        // them with no rule at all.
        //
        // One shared caveat, repeated on the two rules it reaches — CLOSED for the
        // shape described here, kept because the reasoning still decides which
        // rules are safe. When an app's `CFBundleShortVersionString` has no patch
        // component AND its `CFBundleVersion` is a small dotless counter,
        // `UpdateChecker.evaluate`'s "the vendor folded the build into the version"
        // fallback rebuilds the installed side as short + "." + build — "3.5" + "1"
        // = "3.5.1" — and used to read a genuine x.y.1 release as already
        // installed. Of the artifacts inspected for this batch only Anki and
        // noTunes have that shape.
        //
        // The fallback now requires the remote to EQUAL the rebuilt string and the
        // build to be a counter of at least 100, so a hand-stamped "1" no longer
        // reaches it at all. What is left exposed is narrower: a constant build of
        // 100 or more under a two-component marketing version. The other rules are
        // safe for one of two DIFFERENT reasons, worth keeping straight: a dotted
        // `CFBundleVersion` skips the fallback outright, while a three-component
        // short version still RUNS it — the rebuilt string is simply four
        // components, which is very unlikely to match a real release. The second
        // group is practically safe, not structurally immune: four-component
        // versions do exist in this batch (OpenLens reports 6.5.2-366), and there
        // it is the dotted build that keeps it off this path.

        // CC Switch — Claude Code / Codex profile switcher, no Sparkle, ships one
        // macOS dmg per release (`CC-Switch-v<ver>-macOS.dmg`, beside a .zip and a
        // .tar.gz of the same build). Tags are `vX.Y.Z` → default pattern. One-click:
        // that dmg's `CC Switch.app` is com.ccswitch.desktop, Team R8UR22V2F9,
        // notarized — same identity as the install, so the swap passes the gate.
        GitHubReleaseRule(
            bundleID: "com.ccswitch.desktop",
            owner: "farion1231", repo: "cc-switch",
            installAssetPattern: #"^CC-Switch-v[0-9.]+-macOS\.dmg$"#,
            installerKind: .dmg),
        ])
}
