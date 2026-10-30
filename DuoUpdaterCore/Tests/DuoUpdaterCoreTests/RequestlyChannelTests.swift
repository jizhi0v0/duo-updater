import Foundation
import Testing

@testable import DuoUpdaterCore

/// Requestly's bundle id ends in `.beta` but it has one release train, so
/// `ReleaseChannel.detect` step 0.997 cancels the suffix rule for it.
///
/// The inputs are the real bundle's: `io.requestly.beta`, the name "Requestly"
/// (CFBundleName and CFBundleDisplayName), versions `26.6.29` / `26.6.26`, and
/// an `app-update.yml` whose `releaseType` is `release`.
@Suite struct RequestlyChannelTests {

    private static let bundleID = "io.requestly.beta"

    private func detect(_ version: String, bundleID: String = Self.bundleID) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "Requestly", bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: "Requestly.app")
    }

    @Test func theOneTrainReadsAsStable() {
        for version in ["26.6.29", "26.6.26", "26.6.22"] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    /// The suffix rule still applies to every other app — this is a bundle-id
    /// exception, not a change to step 2.
    @Test func otherBetaSuffixedBundleIDsStillReadAsBeta() {
        #expect(detect("1.0.0", bundleID: "com.example.beta") == .beta)
    }
}
