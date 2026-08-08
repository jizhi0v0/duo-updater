import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func intelliJVersionPatternSurvivesAFourthSegment() {
    // JetBrains shipped "2026.2.0.1" against a pattern pinned to exactly three
    // segments, so it matched nothing and the row fell to "unknown" — a silent
    // failure, since a probe that resolves no version isn't an error anywhere.
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "com.jetbrains.intellij" }
    let pattern = try! #require(recipe?.versionPattern)
    func version(in body: String) -> String? {
        guard let m = body.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(body[m])
        return match.range(of: #"[0-9]{4}(\.[0-9]+)+"#, options: .regularExpression)
            .map { String(match[$0]) }
    }
    #expect(version(in: #"{"version":"2026.2.0.1","build":"262.8665.337"}"#) == "2026.2.0.1")
    #expect(version(in: #"{"version":"2026.1.4"}"#) == "2026.1.4")
    // `majorVersion` is 2-component and must never be what we pick up.
    #expect(version(in: #"{"majorVersion":"2026.2"}"#) == nil)
}

@Test func whatsAppPatternStripsTheDownloadFilenamesExtraLeadingSegment() {
    // The bundle reports 26.22.20; the file is WhatsApp-2.26.31.27.dmg. Capturing
    // the whole thing would compare "2.26.31.27" against "26.22.20", read the
    // installed copy as NEWER, and hide every update forever.
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "net.whatsapp.WhatsApp" }
    let pattern = try! #require(recipe?.versionPattern)
    let location = "https://scontent.xx.fbcdn.net/v/t39/1000_n.dmg/WhatsApp-2.26.31.27.dmg?_nc_cat=107"
    let range = try! #require(location.range(of: pattern, options: .regularExpression))
    let matched = String(location[range])
    let version = try! #require(matched.range(of: #"[0-9]+\.[0-9]+\.[0-9]+(?=\.dmg)"#, options: .regularExpression))
    #expect(String(matched[version]) == "26.31.27")
    #expect(VersionComparator.isNewer("26.31.27", than: "26.22.20"))
    // The unstripped form is what this guards against.
    #expect(!VersionComparator.isNewer("2.26.31.27", than: "26.22.20"))
}

@Test func uuRemotePatternReadsTheVersionedPackageName() {
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "com.netease.uuremote" }
    let pattern = try! #require(recipe?.versionPattern)
    let location = "https://a56.gdl.netease.com/uuyc_4.35.0.pkg?key1=abc&key2=def"
    let range = try! #require(location.range(of: pattern, options: .regularExpression))
    #expect(String(location[range]) == "uuyc_4.35.0.pkg")
    // Both are read from a Location header, never by following the redirect: the
    // target is the installer itself (259 MB / 69 MB).
    #expect(recipe?.followRedirects == false)
}
