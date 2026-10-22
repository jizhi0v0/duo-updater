import Foundation

enum us_eidinger_SwiftPlantUML {
    static let set = AppRecipeSet(
        family: "us-eidinger-SwiftPlantUML",
        githubRules: [
        // SwiftPlantUML (SwiftPlantUMLApp.app) — host app for an Xcode Source
        // Editor extension and a Finder action extension that draw class
        // diagrams. No updater of its own: the "Release Notes" menu item only
        // opens the releases page in the browser (AppDelegate.showReleaseNotes).
        // The extensions and their embedded XPC service are started on demand
        // by their hosts (Xcode, Finder) and launchd; the app ships no login
        // item, LaunchAgent or helper app, so one-click needs no gate. A swap
        // while Xcode is open may leave Xcode on the old extension until it
        // relaunches, the same as replacing the app by hand.
        //
        // Tags read `1.6.0`, matching CFBundleShortVersionString; all 11 tags
        // (1.0.0–1.6.0) are stable. `SwiftPlantUMLApp.zip`, the only asset, is
        // universal, us.eidinger.SwiftPlantUML, Team 6V66CC3AN6, notarized,
        // in every release from 1.0.0 on.
        GitHubReleaseRule(
            bundleID: "us.eidinger.SwiftPlantUML",
            owner: "MarcoEidinger", repo: "SwiftPlantUML-Xcode-Extension",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^SwiftPlantUMLApp\.zip$"#,
            installerKind: .zip),
        ])
}
