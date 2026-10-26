import Foundation

enum com_mailspring_mailspring {
    static let set = AppRecipeSet(
        family: "com-mailspring-mailspring",
        githubRules: [
        // Mailspring — open-source mail client (Foundry376/Mailspring, Electron).
        // It updates itself with Electron's built-in autoUpdater (Squirrel.Mac,
        // no electron-builder `app-update.yml`): on launch and every 30 min it
        // asks updates.getmailspring.com/check/darwin/<arch>/<version>/<id>/stable,
        // downloads what that names and ShipIt swaps it in. That server answers
        // with this repo's own release asset URL (arm64 → the AppleSilicon zip,
        // x64 → `Mailspring.zip`), so GitHub and the vendor serve the same bytes.
        // The sync engine `mailsync` is a per-account child process, not a helper
        // or launchd job: it exits about 30 s after its parent's stdin closes.
        //
        // Tags read `1.26.2`; the bundle says 1.26.2. Each release carries
        // unversioned `Mailspring-AppleSilicon.zip` (arm64, since 1.10.4) and
        // `Mailspring.zip` (x86_64), both com.mailspring.mailspring, Team
        // X9RJ36K9D4, notarized; same id and Team back to 1.0.12. An Intel
        // build running on Apple silicon is moved to the arm64 zip by the
        // vendor's own updater too (it reports arch arm64 when the CPU is
        // Apple's), so the rule installs the arm64 zip for every copy.
        GitHubReleaseRule(
            bundleID: "com.mailspring.mailspring",
            owner: "Foundry376", repo: "Mailspring",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Mailspring-AppleSilicon\.zip$"#,
            installerKind: .zip),
        ])
}
