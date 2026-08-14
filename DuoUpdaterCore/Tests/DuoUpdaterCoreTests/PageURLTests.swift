import Testing
import Foundation
@testable import DuoUpdaterCore

/// Guards the artifact/page split in `RemoteVersion`.
///
/// The bug this suite exists for: `makeRemoteVersion` overwrote the vendor's
/// human-facing download page with the install plan's artifact URL whenever a
/// recipe had a one-click spec, and the UI's "Open page" button reads that same
/// field. So on ToDesk and UU Remote, "Open download page" handed the browser a
/// `.pkg` — it started a download instead of opening a page.
///
/// Nothing failed while that was true, which is why the checks below are
/// structural: they read the shipping registry rather than a hand-written list,
/// so a recipe added later can't quietly reintroduce it.
@Suite struct PageURLTests {

    /// File extensions that mean "this URL is a download, not a page".
    static let artifactExtensions: Set<String> = [
        "dmg", "pkg", "zip", "xip", "tar", "gz", "tgz", "bz2", "appx", "exe", "msi",
    ]

    /// A recipe's `downloadURL` is documented as where to send the user to
    /// download by hand — i.e. a page. If one ever points straight at an archive,
    /// the "Open page" button downloads a file, which is the whole defect.
    @Test func recipeDownloadURLsArePagesNotArtifacts() {
        for recipe in VendorProbeRegistry.recipes {
            guard let url = recipe.downloadURL else { continue }
            let ext = url.pathExtension.lowercased()
            #expect(
                !Self.artifactExtensions.contains(ext),
                "\(recipe.bundleID): downloadURL is an artifact (.\(ext)) — \(url.absoluteString)")
            #expect(
                url.scheme == "https",
                "\(recipe.bundleID): downloadURL is not https — \(url.absoluteString)")
        }
    }

    /// A detection-only recipe has no install path, so the page link is the ONLY
    /// action its row can offer. `pageURL` is now strictly the curated
    /// `downloadURL` (never the probe endpoint, which serves a file), so a
    /// detection-only recipe without one leaves the user with a dead row.
    @Test func detectionOnlyRecipesCarryAPage() {
        for recipe in VendorProbeRegistry.recipes where recipe.install == nil {
            #expect(
                recipe.downloadURL != nil,
                "\(recipe.bundleID): detection-only recipe has no downloadURL, so its row has no page to open")
        }
    }

    /// The regression itself: with an install spec, the artifact goes to
    /// `downloadURL` (the installer fetches it) and the vendor page survives in
    /// `pageURL` (the button opens it). Before the fix the page was dropped.
    @Test func installSpecKeepsTheVendorPage() throws {
        let page = URL(string: "https://www.todesk.com/download.html")!
        let artifact = URL(string: "https://dl.todesk.com/macos/ToDesk_4.9.7.4.pkg")!
        let recipe = VendorProbeRecipe(
            bundleID: "com.youqu.todesk.mac",
            url: URL(string: "https://www.todesk.com/download.html")!,
            mode: .responseBody,
            versionPattern: #"ToDesk_([0-9.]+)\.pkg"#,
            downloadURL: page,
            install: VendorInstallSpec(urlSource: .redirect(artifact), kind: .pkg))

        let remote = VendorProbeSource.makeRemoteVersion(
            recipe: recipe,
            version: "4.9.7.4",
            install: recipe.install,
            plan: (url: artifact, checksum: nil),
            resolvedDownload: page)

        #expect(remote.downloadURL == artifact)
        #expect(remote.pageURL == page)
    }

    /// Detection-only: the probe endpoint must not leak into `pageURL`. UU Remote's
    /// endpoint (`…/release/dl/4`) 302s straight to a pkg, so opening it downloads.
    @Test func probeEndpointNeverBecomesAPage() throws {
        let endpoint = URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4")!
        let recipe = VendorProbeRecipe(
            bundleID: "com.example.probe",
            url: endpoint,
            mode: .redirectFilename,
            versionPattern: #"foo_([0-9.]+)\.pkg"#)

        let remote = VendorProbeSource.makeRemoteVersion(
            recipe: recipe,
            version: "1.2.3",
            install: nil,
            plan: nil,
            resolvedDownload: endpoint)

        #expect(remote.pageURL == nil)
    }
}
