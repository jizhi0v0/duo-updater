import Foundation

enum com_mucommander_muCommander {
    static let set = AppRecipeSet(
        family: "com-mucommander-muCommander",
        githubRules: [
        // muCommander — a Java file manager packaged with jpackage (bundled JRE).
        // No `SUFeedURL`: its own check reads `mucommander.com/version/version.xml`
        // and only opens the release page in a browser, so nothing here races it.
        //
        // Tags are `<version>-<packaging release>` (`1.6.2-1`); the bundle's
        // `CFBundleShortVersionString` and `CFBundleVersion` are both the bare
        // `1.6.2`. The pattern keeps only the version, so a respin (`1.6.2-2`, as
        // `0.9.4-2` once was) compares equal to an installed 1.6.2 and offers
        // nothing. The suffix is optional for bare tags; anchoring keeps
        // `0.9.1rc2`-style tags out. No release has ever been flagged prerelease.
        //
        // One-click: the `-aarch64.dmg` (Developer ID `CZHQQ65L42`, notarized
        // from 1.4.0 on). The image carries a licence agreement, which
        // `DiskImageMount` answers on stdin. The `-noarch.dmg` edition shares
        // the bundle id but is unsigned and launched by a shell stub over the
        // system Java; the gate below keeps it on detection only.
        GitHubReleaseRule(
            bundleID: "com.mucommander.muCommander",
            owner: "mucommander", repo: "mucommander",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)(?:-[0-9]+)?$"#,
            installAssetPattern: #"(?i)^mucommander-[0-9]+(?:\.[0-9]+)+(?:-[0-9]+)?-aarch64\.dmg$"#,
            installerKind: .dmg),
        ],
        oneClickGates: [
            // jpackage's Mach-O launcher (every dmg from 1.3.0 x86_64 to 1.6.2
            // arm64) links `JLI_Launch`; the noarch edition's
            // `universalJavaApplicationStub` is a bash script without it. The
            // arm64 build would swap that edition for the bundled-JRE one.
            OneClickGate(
                bundleID: "com.mucommander.muCommander",
                requirement: .executableContains(marker: "JLI_Launch"),
                reason: "this is muCommander's noarch edition (system Java, unsigned); update it by hand from the release page"),
        ])
}
