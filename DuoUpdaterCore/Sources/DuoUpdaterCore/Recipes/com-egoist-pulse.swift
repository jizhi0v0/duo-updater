import Foundation

enum com_egoist_pulse {
    static let set = AppRecipeSet(
        family: "com-egoist-pulse",
        githubRules: [
        // Pulse (egoist, Team GJE9R5VE87) — an activity monitor built with
        // egoist's Go toolkit mygo. No Sparkle: its own updater reads
        // `update-darwin-arm64.json` from the latest GitHub release and swaps
        // in a `.tar.gz` (or a `.delta` from the previous version). The same
        // release carries `Pulse.<version>.arm64.dmg`, the file the website's
        // mac download redirects to; tag `v0.1.5` matches
        // CFBundleShortVersionString (checked 2026-10-10 on 0.1.4/0.1.5).
        //
        // Apple silicon only: the executable is a single arm64 slice and no
        // Intel dmg is published. The release's `install.sh` installs the
        // Linux build and refuses to run on macOS, so there is no command-line
        // install to track. One-click installs the notarised dmg; no nested
        // apps or helpers in the bundle.
        GitHubReleaseRule(
            bundleID: "com.egoist.pulse",
            owner: "egoist", repo: "pulse-feedback",
            installAssetPattern: #"^Pulse\.[0-9.]+\.arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
