import Foundation

enum com_tinycast_app {
    static let set = AppRecipeSet(
        family: "com-tinycast-app",
        githubRules: [
        // Tinycast — an open-source native launcher (`abue-ammar/tinycast`). No
        // Sparkle: the app's own updater reads this repo's Releases list, so the
        // rules below read exactly what the vendor's updater reads. Homebrew's
        // `tinycast` / `tinycast@beta` casks are `auto_updates true` and defer to
        // it (see `HomebrewCaskSource`).
        //
        // Stable and beta are SEPARATE apps: `Tinycast.app` / `com.tinycast.app`
        // and `Tinycast Beta.app` / `com.tinycast.app.beta`, installed side by
        // side. The vendor's `ReleaseChannel` derives the channel from the bundle
        // id alone, stable takes only non-prereleases and beta only prereleases,
        // and neither ever crosses (`docs/features/updates.md` in the repo).
        //
        // Detection-only, on purpose: every release is signed by a self-signed
        // "Tinycast Self-Signed" identity with no Team Identifier, and `spctl`
        // rejects it (checked on the real 0.10.23 and 0.11.1-beta.96 zips, see
        // the audit). `SignatureVerifier` refuses a swap without a Team ID on
        // both sides, so an install pattern here could only produce an Update
        // button that fails. `TinycastGitHubRuleTests` pins that.
        //
        // The pattern is anchored at both ends. `/releases/latest` never returns
        // a prerelease, but the missing-asset list fallback walks raw tags, and
        // this repo also publishes `v0.9.7-sequoia` (macOS 15 build, same bundle
        // id) and old `-alpha.N` tags — all flagged prerelease today, and none
        // of them a stable version.
        GitHubReleaseRule(
            bundleID: "com.tinycast.app",
            owner: "abue-ammar", repo: "tinycast",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#),

        // Tinycast Beta — its own bundle id, so this is not a shared-id track
        // split: the installed copy's `CFBundleShortVersionString` keeps the
        // suffix verbatim ("0.11.1-beta.96" on the real artifact), and the
        // extracted version must keep it too or every beta reads as newer than
        // itself.
        //
        // Unlike WhatCable's beta rule this one does NOT accept stable tags: a
        // stable release is a different app (`Tinycast.app`), never the release
        // a beta copy graduates into, and the vendor's updater never offers it.
        //
        // listPageSize: newest 100 releases on 2026-09-17 (94 exist), 56 beta
        // tags, worst gap 5 (v0.9.6-beta.53 → v0.9.2-beta.49), floor 6; 10 for
        // headroom. `probesNewestFirst` keeps the common round a page of one.
        GitHubReleaseRule(
            bundleID: "com.tinycast.app.beta",
            owner: "abue-ammar", repo: "tinycast",
            usePrereleases: true,
            listPageSize: 10,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+)$"#,
            channel: .beta),
        ])
}
