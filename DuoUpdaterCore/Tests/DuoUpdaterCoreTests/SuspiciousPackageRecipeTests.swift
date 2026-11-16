import Foundation
import Testing
@testable import DuoUpdaterCore

struct SuspiciousPackageRecipeTests {
    private var probe: VendorProbeRecipe { com_mothersruin_SuspiciousPackageApp.set.probes[0] }

    @Test func readsMarketingVersionFromTheAppsPlist() {
        let fixture = """
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.mothersruin.SuspiciousPackageApp</string>
        <key>CFBundleShortVersionString</key><string>4.8</string>
        <key>CFBundleVersion</key><string>1457</string>
        <key>MRSDownloadSize</key><integer>8089083</integer>
        <key>MRSUpdateRequiredOSVersion</key><string>14.0</string>
        </dict></plist>
        """
        #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: probe.versionPattern) == "4.8")
        #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: probe.minimumSystemVersionPattern!) == "14.0")
        #expect(VendorProbeRecipe.extractVersion(
            from: fixture.replacingOccurrences(of: "SuspiciousPackageApp", with: "Apparency"),
            pattern: probe.versionPattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: fixture.replacingOccurrences(of: "<string>4.8</string>", with: "<string>4.9-beta</string>"),
            pattern: probe.versionPattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: fixture.replacingOccurrences(of: "<string>4.8</string>", with: "<string>5.0</string>"),
            pattern: probe.versionPattern) == "5.0")
    }

    @Test func keepsTableVersionsDatesAndNestedNotes() throws {
        // Reduced real table structure; short note text makes the nesting clear.
        let fixture = """
        <table id="versions"><tbody>
        <tr><td class="other">99.0</td><td>Not release history</td></tr>
        <tr><td class="vnum">4.8 <span class="bundle-version">(1457)</span></td>
        <td class="vnotes"><em class="date">Released on September 16, 2026</em>
        <ul><li>Added support for <code>arm64e.x1</code>.<ul>
        <li>Architecture details &amp; compatibility.</li></ul></li>
        <li>Dark &amp; tinted icons.</li></ul></td></tr>
        <tr><td class="vnum">4.7 <span class="bundle-version">(1415)</span></td>
        <td class="vnotes"><em class="date">Released on August 5, 2026</em>
        <ul><li>Quick Look fixes.</li></ul></td></tr>
        </tbody></table>
        """
        let recipe = com_mothersruin_SuspiciousPackageApp.set.changelogs[0]
        let log = try #require(ChangelogExtractor.extract(from: fixture, using: recipe))
        #expect(log.entries.map(\.version) == ["4.8", "4.7"])
        #expect(log.entries[0].date == "September 16, 2026")
        #expect(log.entries[0].items == ["Added support for arm64e.x1.", "Architecture details & compatibility.", "Dark & tinted icons."])
        #expect(log.entries[1].items == ["Quick Look fixes."])
    }
}
