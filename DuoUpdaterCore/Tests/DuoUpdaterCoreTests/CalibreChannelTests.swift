import Foundation
import Testing

@testable import DuoUpdaterCore

/// calibre's preview builds, told apart from stable by a third version
/// component of 100 or more — `ReleaseChannel.detect` step 0.98, the bound the
/// vendor's `setup/publish.py` enforces.
///
/// The inputs are each package's own Info.plist values: preview and stable share
/// `net.kovidgoyal.calibre` and the name "calibre", and
/// `CFBundleShortVersionString` = `CFBundleVersion` on both (`9.15.101`;
/// `9.14.0`, `9.15.0`).
@Suite struct CalibreChannelTests {

    private static let bundleID = "net.kovidgoyal.calibre"

    private func detect(_ version: String, bundleID: String = Self.bundleID) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "calibre", bundleID: bundleID, keystoneChannel: nil, version: version,
            bundleFileName: "calibre")
    }

    @Test func thePreviewBuildReadsAsPreview() {
        #expect(detect("9.15.101") == .preview)
        // The lowest number `publish_preview` accepts.
        #expect(detect("9.15.100") == .preview)
    }

    @Test func releasesStayStable() {
        for version in ["9.14.0", "9.15.0", "9.3.1", "0.9.44"] {
            #expect(detect(version) == .stable, "\(version)")
        }
        // The highest number `publish` accepts.
        #expect(detect("9.15.99") == .stable)
    }

    /// Only the three-component numbering the tooling checks.
    @Test func otherShapesAreNotReadByThisRule() {
        for version in ["9.15", "9.15.101.1", "9.101", "9.15.101b", "9.15.0101x", ""] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    /// A three-digit patch is an ordinary release number for other apps.
    @Test func otherBundleIDsAreNotReadByThisRule() {
        #expect(detect("9.15.101", bundleID: "com.example.app") == .stable)
        #expect(ReleaseChannel.detect(
            name: "App", bundleID: nil, keystoneChannel: nil, version: "9.15.101") == .stable)
    }
}
