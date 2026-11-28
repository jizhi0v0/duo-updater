import Foundation

enum ci_not_rune {
    static let bundleID = "ci.not.rune"
    static let slug = "Losses/rune"

    private static let stableVersion = #"[0-9]+\.[0-9]+\.[0-9]+"#
    private static let previewMajor = #"(?:[2-9]|[1-9][0-9]+)"#
    private static let alphaVersion = #"\#(previewMajor)\.[0-9]+\.[0-9]+-alpha\.[0-9]+"#
    private static let alphaBundleVersion = #"^\#(previewMajor)\.[0-9]+\.1[0-9]{3}\z"#

    // The GitHub app uses the same ID on both tracks. Since 2.x the Alpha
    // stage is encoded in the last component of the bundle version.
    static func isAlpha(_ bundleVersion: String) -> Bool {
        bundleVersion.range(of: alphaBundleVersion, options: .regularExpression) != nil
    }

    static func bundleVersion(in pubspec: String, release: String, channel: ReleaseChannel) -> String? {
        // The release tag supplies the major/minor; Flutter takes both bundle
        // versions from the top-level pubspec version. Reject a wrong track or
        // an unrecognized version format rather than comparing a tag to a build.
        guard let version = VendorProbeRecipe.extractVersion(
            from: pubspec, pattern: #"(?m)^version: ([0-9]+\.[0-9]+\.[0-9]+)[ \t]*\r?$"#),
              version.split(separator: ".").prefix(2) == release.split(separator: ".").prefix(2),
              isAlpha(version) == (channel == .alpha)
        else { return nil }
        return version
    }

    // History: docs/app-audits/ci-not-rune.md#历史与实测
    static let set = AppRecipeSet(
        family: "ci-not-rune",
        githubRules: [
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "Losses", repo: "rune",
                versionPattern: #"^v(\#(stableVersion))\z"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^Rune-v\#(stableVersion)-macOS\.dmg\z"#,
                installerKind: .dmg),
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "Losses", repo: "rune",
                usePrereleases: true,
                versionPattern: #"^v(\#(alphaVersion))\z"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^Rune-v\#(alphaVersion)-macOS\.dmg\z"#,
                installerKind: .dmg,
                channel: .alpha),
        ],
        githubChannelProofs: [
            ChannelProofKey(bundleID, .alpha): .artifact(#"/download/v\#(alphaVersion)/"#),
        ])
}
