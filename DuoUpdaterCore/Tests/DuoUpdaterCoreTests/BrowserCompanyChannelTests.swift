import Foundation
import Testing

@testable import DuoUpdaterCore

/// Arc's and Dia's release-candidate (Early Birds) builds, told apart from stable
/// by `BCNYReleaseType` — `ReleaseChannel.detect` step 0.95.
///
/// The inputs are each package's own Info.plist values, read off the real
/// packages on 2026-10-08: name, bundle id, `CFBundleShortVersionString` and
/// `BCNYReleaseType`. Every other signal `detect` reads is silent for these
/// apps, so these are all it is handed.
@Suite struct BrowserCompanyChannelTests {

    private static let arc = "company.thebrowser.Browser"
    private static let dia = "company.thebrowser.dia"

    private func detect(
        _ name: String, _ bundleID: String, _ version: String, _ releaseType: String?
    ) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: name, bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: name, browserCompanyReleaseType: releaseType)
    }

    @Test func theReleaseCandidateBuildsReadAsRC() {
        #expect(detect("Arc", Self.arc, "1.168.0", "Release Candidate") == .rc)
        #expect(detect("Dia", Self.dia, "1.52.0", "Release Candidate") == .rc)
    }

    @Test func theStableBuildsStayStable() {
        #expect(detect("Arc", Self.arc, "1.167.0", "Release") == .stable)
        #expect(detect("Arc", Self.arc, "1.167.1", "Release") == .stable)
        #expect(detect("Dia", Self.dia, "1.51.0", "Release") == .stable)
        #expect(detect("Dia", Self.dia, "1.51.1", "Release") == .stable)
    }

    /// Without the key — the scanner had never read it before this rule — an RC
    /// build has nothing else that says what it is.
    @Test func withoutTheKeyAnRCBuildReadsAsStable() {
        #expect(detect("Dia", Self.dia, "1.52.0", nil) == .stable)
    }

    /// Only the value seen on a real package maps. Their updater also knows
    /// internal feeds whose builds have never been observed, so an unknown value
    /// is not guessed at.
    @Test func anyOtherValueIsNotAChannelSignal() {
        for value in ["Canary", "Prototype", "Release Candidate 2", "release candidate", ""] {
            #expect(detect("Dia", Self.dia, "1.52.0", value) == .stable)
        }
    }

    /// The key is the vendor's own; another app that happened to carry it is not
    /// judged by it.
    @Test func otherBundleIDsAreNotReadByThisRule() {
        #expect(detect("Example", "com.example.app", "1.0", "Release Candidate") == .stable)
    }

    /// `.rc` changes the label, not what Sparkle offers: with no binding the
    /// allowed set is the default channel plus the one the installed build's own
    /// feed item carries, and both trains' items are untagged.
    @Test func sparkleStillReadsTheChannelFromTheFeed() {
        let app = InstalledApp(
            name: "Dia", bundleID: Self.dia,
            shortVersion: "1.52.0", buildVersion: "88244",
            path: URL(fileURLWithPath: "/Applications/Dia.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string:
                "https://releases.diabrowser.com/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/BoostBrowser-updates.xml"),
            releaseChannel: .rc, channelIsAuthoritative: false)
        let item = SparkleAppcastItem(shortVersionString: "1.52.0 (88244)", version: "88244")
        #expect(SparkleAppcastSource.allowedChannels(for: app, in: [item]) == [nil])
    }
}
