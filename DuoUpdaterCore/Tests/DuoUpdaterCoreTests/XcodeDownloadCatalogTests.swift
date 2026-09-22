import Foundation
import Testing
@testable import DuoUpdaterCore

private func entry(
    _ number: String, build: String, order: Int, release: [String: Any],
    url: String?, archs: [String]? = nil
) -> [String: Any] {
    var download: [String: Any] = [:]
    if let url { download["url"] = url }
    if let archs { download["architectures"] = archs }
    return [
        "name": "Xcode", "_versionOrder": order, "requires": "26.6",
        "date": ["year": 2026, "month": 9, "day": 1],
        "version": ["number": number, "build": build, "release": release],
        "links": ["download": download],
    ]
}

private func catalog(_ entries: [[String: Any]], host: HostArch = .arm64) throws -> [XcodeDownloadItem] {
    let data = try JSONSerialization.data(withJSONObject: entries)
    return XcodeDownloadCatalog.items(from: XcodeReleasesSource.parse(data), host: host)
}

private let cdn = "https://download.developer.apple.com/Developer_Tools"

@Test func downloadCatalogIsOnePerBuildNewestFirstWithThisMacsArchive() throws {
    let items = try catalog([
        entry("26.6", build: "17F113", order: 26_006_000_999, release: ["release": true],
              url: "\(cdn)/Xcode_26.6/Xcode_26.6_Universal.xip", archs: ["arm64", "x86_64"]),
        entry("26.6", build: "17F113", order: 26_006_000_999, release: ["release": true],
              url: "\(cdn)/Xcode_26.6/Xcode_26.6_Apple_silicon.xip", archs: ["arm64"]),
        entry("27.1", build: "27A9269", order: 27_001_000_001, release: ["beta": 1],
              url: "\(cdn)/Xcode_27.1_beta/Xcode_27.1_beta_Apple_silicon.xip", archs: ["arm64"]),
    ])
    #expect(items.map(\.build) == ["27A9269", "17F113"])
    #expect(items[0].isPrerelease)
    #expect(items[0].displayVersion == "27.1 beta 1 (27A9269)")
    #expect(!items[1].isPrerelease)
    #expect(items[1].fileName == "Xcode_26.6_Apple_silicon.xip")
    #expect(items[1].authorizedURL.host == "developer.apple.com")
    #expect(items[1].date == DateComponents(year: 2026, month: 9, day: 1))
}

@Test func downloadCatalogOnIntelSkipsAppleSiliconOnlyBuilds() throws {
    let items = try catalog([
        entry("27.1", build: "27A9269", order: 2, release: ["beta": 1],
              url: "\(cdn)/Xcode_27.1_beta/Xcode_27.1_beta_Apple_silicon.xip", archs: ["arm64"]),
    ], host: .x86_64)
    #expect(items.isEmpty)
}

/// Older entries say nothing about architectures; their one archive is still
/// offered, but only when it is the only one the build has.
@Test func downloadCatalogOffersAnUnlabelledSingleArchive() throws {
    let items = try catalog([
        entry("16.4", build: "16F6", order: 1, release: ["release": true],
              url: "\(cdn)/Xcode_16.4/Xcode_16.4.xip"),
        entry("16.3", build: "16E140", order: 0, release: ["release": true],
              url: "\(cdn)/Xcode_16.3/Xcode_16.3_a.xip"),
        entry("16.3", build: "16E140", order: 0, release: ["release": true],
              url: "\(cdn)/Xcode_16.3/Xcode_16.3_b.xip"),
    ])
    #expect(items.map(\.fileName) == ["Xcode_16.4.xip"])
}

@Test func downloadCatalogDropsEntriesWithoutAnAllowedURL() throws {
    let items = try catalog([
        entry("1.0", build: "A1", order: 2, release: ["release": true], url: nil),
        entry("2.0", build: "B2", order: 1, release: ["release": true],
              url: "https://evil.example/Developer_Tools/X/X.xip"),
    ])
    #expect(items.isEmpty)
}

/// 16.4 RC and 16.4 are the same build, `16F6`, each with its own archive —
/// both are listed (live index, 2026-09-22).
@Test func downloadCatalogKeepsAnRCAndItsReleaseApart() throws {
    let items = try catalog([
        entry("16.4", build: "16F6", order: 16_004_000_999, release: ["release": true],
              url: "\(cdn)/Xcode_16.4/Xcode_16.4.xip"),
        entry("16.4", build: "16F6", order: 16_004_000_901, release: ["rc": 1],
              url: "\(cdn)/Xcode_16.4_Release_Candidate/Xcode_16.4_Release_Candidate.xip"),
    ])
    #expect(items.map(\.fileName) == ["Xcode_16.4.xip", "Xcode_16.4_Release_Candidate.xip"])
    #expect(items.map(\.isPrerelease) == [false, true])
    #expect(Set(items.map(\.id)).count == 2)
}
