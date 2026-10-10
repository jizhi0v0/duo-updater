import Foundation
import Testing
@testable import DuoUpdaterCore

/// The Microsoft AutoUpdate manifests (`…/MacAutoupdate/0409<AppID>.xml`) exist on
/// two hosts. `res.public.onecdn.static.microsoft` is the one Microsoft documents
/// as MAU's manifest endpoint and the one that advances; the same path on
/// `officecdn.microsoft.com` still answers 200 with a well-formed manifest that
/// stopped at 16.109. A recipe on the old host reports an old build and nothing
/// fails, so the host is checked here rather than left to a sweep that would see
/// a version parse and call it good.
@Suite struct MicrosoftAutoUpdateManifestHostTests {
    static let manifestHost = "res.public.onecdn.static.microsoft"

    /// Derived from the registry, so a MAU-manifest recipe added later is held to
    /// the same host without anyone listing it here.
    @Test func everyMAUManifestRecipeReadsTheDocumentedHost() {
        let mau = VendorProbeRegistry.recipes.filter {
            $0.url.path.contains("/MacAutoupdate/") && $0.url.pathExtension == "xml"
        }
        // Vacuity guard: Outlook and OneNote read MAU manifests today. If none
        // match, the filter is wrong and this test checks nothing.
        #expect(mau.count >= 2, "found \(mau.map(\.bundleID))")
        for recipe in mau {
            #expect(recipe.url.host == Self.manifestHost,
                    "\(recipe.bundleID): \(recipe.url.absoluteString)")
        }
    }

    /// The first dict of the real OneNote manifest from the documented host
    /// (`0409ONMC2019.xml`), trimmed to the keys the recipe reads plus the deltas
    /// it must not pick. The App ID is still `ONMC2019` at 16.113: the "2019" is
    /// not what froze the old host's copy.
    private static let oneNoteManifestFixture = """
    <dict>
        <key>Application ID</key>
        <string>ONMC2019</string>
        <key>Baseline Version</key>
        <string>16.113.26081216</string>
        <key>BinaryUpdaterLocation</key>
        <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/OneNote_16.113.26081216_to_16.113.26100421_BinaryDelta.pkg</string>
        <key>FullUpdaterLocation</key>
        <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_OneNote_16.113.26100421_Updater.pkg</string>
        <key>Location</key>
        <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/OneNote_16.113.26081216_to_16.113.26100421_Delta.pkg</string>
        <key>Title</key>
        <string>Microsoft OneNote Update 16.113.4 (26100421)</string>
        <key>Update Version</key>
        <string>16.113.26100421</string>
    </dict>
    """

    @Test func oneNoteReadsTheCurrentManifestVersionAndItsFullUpdater() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.microsoft.onenote.mac" })
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.oneNoteManifestFixture, pattern: recipe.versionPattern) == "16.113.26100421")
        guard case .bodyPattern(let pattern) = try #require(recipe.install).urlSource else {
            Issue.record("expected a body pattern"); return
        }
        let resolved = try #require(
            VendorProbeRecipe.extractVersion(from: Self.oneNoteManifestFixture, pattern: pattern))
        #expect(resolved.hasSuffix("/Microsoft_OneNote_16.113.26100421_Updater.pkg"))
        #expect(!resolved.contains("Delta"))
    }
}
