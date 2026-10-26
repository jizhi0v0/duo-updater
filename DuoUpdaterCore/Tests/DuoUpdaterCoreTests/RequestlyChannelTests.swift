import Foundation
import Testing

@testable import DuoUpdaterCore

/// Requestly's stable app ships as `io.requestly.beta` — `ReleaseChannel.detect`
/// step 0.997 keeps step 2's `.beta` suffix match from calling it beta.
///
/// Inputs are the real packages' Info.plist values (26.6.26 / 26.6.29 arm64 dmgs,
/// name "Requestly", Team YQ5FZQ855D; 1.4.0 x64 dmg, Team AFBT5Z9V94).
@Suite struct RequestlyChannelTests {

    private func detect(_ bundleID: String, _ version: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Requestly", bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: "Requestly.app")
    }

    @Test func requestlyReadsAsStable() {
        for version in ["26.6.29", "26.6.26", "25.6.25", "2.0.0", "1.4.0"] {
            #expect(detect("io.requestly.beta", version) == .stable, "\(version)")
        }
    }

    /// Control: the generic bundle-id suffix rule still applies to everyone else.
    @Test func otherBetaSuffixedIDsStayBeta() {
        #expect(detect("com.example.app.beta", "1.0.0") == .beta)
    }
}
