import Foundation

enum net_antelle_keeweb {
    static let set = AppRecipeSet(
        family: "net-antelle-keeweb",
        githubRules: [
        // KeeWeb — open-source KeePass (kdbx) password manager, Electron 12.
        // Its own updater reads https://app.keeweb.info/update.json (1.18.7
        // today), downloads `KeeWeb-<v>.mac.<arch>.dmg` from this repo's
        // release into `$TMPDIR/KeeWeb/` and checks it against the release's
        // `Verify.sign.sha256`; it swaps the bundle only when the user clicks
        // "Restart and update" (the bundled `Contents/Installer/KeeWeb
        // Installer.app` applet mounts the dmg, `rm -rf`s the app and copies the
        // new one in, asking for admin rights when the app is root-owned). No
        // login item or resident helper: the browser's native-messaging host
        // (`Contents/MacOS/util/keeweb-native-messaging-host`) is started by
        // the browser and exits when KeeWeb's socket closes.
        //
        // Tags read `v1.18.7`; the bundle says 1.18.7 (build is a commit,
        // `dfc6201`). The repo also holds an un-prefixed tag `1.19.0` with no
        // release, hence `v?`. Since 1.16.1 every release carries
        // `KeeWeb-<v>.mac.arm64.dmg` and `.mac.x64.dmg` (no universal build);
        // the two differ only in architecture (same Info.plist and app.asar on
        // 1.18.7). Both are net.antelle.keeweb, Team 3LE7JZ657W, notarized;
        // same id and Team back to 1.14.2 (x86_64 `KeeWeb-<v>.mac.dmg`). The
        // arm64 dmg also replaces an x64 copy: DuoUpdater runs on Apple
        // silicon only. Last stable release 2021-07-18; the 2026 prereleases
        // (v1.18.8, v1.18.9) carry no macOS asset and /releases/latest skips them.
        GitHubReleaseRule(
            bundleID: "net.antelle.keeweb",
            owner: "keeweb", repo: "keeweb",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^KeeWeb-[0-9]+(?:\.[0-9]+)+\.mac\.arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
