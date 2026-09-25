import Foundation
import Testing
@testable import DuoKit
@testable import DuoUpdaterCore

/// `duo check` pairs the installed build with the source's build. They have to be
/// read in the same namespace, or a Blender alpha row prints its
/// `CFBundleVersion` ("5.3.0") beside the builder's commit.
struct CheckInstalledBuildNamespaceTests {

    private func result(remoteNamespace: InstalledApp.BuildNamespace) -> UpdateResult {
        let app = InstalledApp(
            name: "Blender", bundleID: "org.blenderfoundation.blender",
            shortVersion: "5.3.0", buildVersion: "5.3.0", vendorBuildVersion: "3bcf2d172c1f",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Blender.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "5.3.0", version: "425ab43ad645", buildNamespace: remoteNamespace,
            downloadURL: nil, sourceName: "Vendor")
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "5.3.0"))
    }

    @Test func aVendorBuildIsPairedWithTheInstalledVendorBuild() {
        #expect(Check.installedBuild(result(remoteNamespace: .vendor)) == "3bcf2d172c1f")
    }

    @Test func aBundleBuildIsStillPairedWithCFBundleVersion() {
        #expect(Check.installedBuild(result(remoteNamespace: .bundle)) == "5.3.0")
    }
}
