import Foundation

enum com_bilingify_readest {
    static let set = AppRecipeSet(
        family: "com-bilingify-readest",
        githubRules: [
        // Readest — open-source ebook reader (readest/readest, Tauri 2). Its own
        // updater is tauri-plugin-updater: it reads `latest.json` (R2 mirror,
        // then this repo's /releases/latest), asks the user, then downloads the
        // `.app.tar.gz` into memory and swaps the bundle in place; nothing is
        // parked on disk. No helper or login item ships in the bundle.
        //
        // Tags read `v0.12.16`; the bundle says 0.12.16. Every release but two
        // carries one `Readest_<version>_universal.dmg` (com.bilingify.readest,
        // Team J5W48D69VR, notarized; same id and Team back to v0.7.9). The two
        // are v0.9.90 and v0.9.91, whose dmg is named
        // `Readest_<version>_universal_darwin.dmg`; the install pattern does not
        // match it, and both sit far below the newest release. Were a future
        // /releases/latest to ship that name, the engine would find no matching
        // asset on it, fetch the list, skip that release and offer the newest
        // earlier one that matches, with an `installAssetRenamed` warning naming
        // the skipped tag (a recipe miss once more than five in a row lack a
        // match). The new release would then not be offered until the pattern
        // accepts the `_darwin` name. The other
        // zips in a release are the KOReader / Calibre / CrossPoint plugins and
        // the send-to-readest extension, not the app. Two releases (v0.9.39,
        // v0.11.16) are flagged prerelease; they are ordinary builds, and
        // /releases/latest skips them.
        GitHubReleaseRule(
            bundleID: "com.bilingify.readest",
            owner: "readest", repo: "readest",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Readest_[0-9]+(?:\.[0-9]+)+_universal\.dmg$"#,
            installerKind: .dmg),
        ],
        // One-click only for stable builds. The in-app "Nightly Builds" toggle
        // installs daily builds from download.readest.com/nightly/ (not GitHub)
        // under the same bundle id and Team, versioned `<base>-<YYYYMMDDHH>`
        // (`0.12.16-2026102206`). Such a copy keeps detection, which only ever
        // offers a stable release with a newer base, but the stable dmg would
        // take it off the nightly build; its own updater moves it on.
        oneClickGates: [
            OneClickGate(
                bundleID: "com.bilingify.readest",
                requirement: .installedVersion(pattern: #"^[0-9]+(?:\.[0-9]+)+$"#),
                reason: "a Readest nightly build; update it from Readest's own updater"),
        ])
}
