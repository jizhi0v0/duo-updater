import Foundation
import Testing
@testable import DuoUpdaterCore

/// Trimmed from a real `listDownloads` response (2026-09-23): the fields read,
/// verbatim, for four Xcode releases plus one non-Xcode download. Both dates are
/// kept so a test can tell which one is read.
private let appleSample = #"""
{"resultCode":0,"downloads":[
{"name":"Xcode 27.1 beta","description":"Xcode 27.1 beta includes Swift 6.4 and SDKs for iOS 27.1, iPadOS 27, tvOS 27, macOS 27, and visionOS 27. Xcode 27.1 beta supports on-device debugging in iOS 17 and later, tvOS 17 and later, watchOS 10 and later, and visionOS. Xcode 27.1 beta requires a Mac running macOS Tahoe 26.6 or later on Apple silicon.","isReleased":0,"datePublished":"09/18/26 17:07","dateCreated":"09/18/26 10:32","files":[{"filename":"Xcode 27.1 beta.xip","remotePath":"/Developer_Tools/Xcode_27.1_beta/Xcode_27.1_beta.xip","fileSize":2027292809}]},
{"name":"Xcode 26","description":"Xcode enables you to develop, test, and distribute apps for all Apple platforms.","isReleased":1,"datePublished":"09/15/25 14:00","dateCreated":"09/15/25 14:03","files":[{"filename":"Xcode 26 Apple silicon.xip","remotePath":"/Developer_Tools/Xcode_26/Xcode_26_Apple_silicon.xip","fileSize":2230256043},{"filename":"Xcode 26 Universal.xip","remotePath":"/Developer_Tools/Xcode_26/Xcode_26_Universal.xip","fileSize":2827013395}]},
{"name":"Xcode 27 Release Candidate","description":"Xcode 27 Release Candidate enables you to develop.","isReleased":0,"datePublished":"09/09/26 12:00","dateCreated":"09/09/26 11:49","files":[{"filename":"Xcode 27 Release Candidate.xip","remotePath":"/Developer_Tools/Xcode_27_Release_Candidate/Xcode_27_Release_Candidate.xip","fileSize":2014229334}]},
{"name":"Xcode 16.4","description":"Xcode 16.4 enables you to develop.","isReleased":0,"datePublished":"05/28/25 10:15","dateCreated":"05/27/25 12:22","files":[{"filename":"Xcode 16.4.xip","remotePath":"/Developer_Tools/Xcode_16.4/Xcode_16.4.xip","fileSize":3036085732}]},
{"name":"Xcode 3.2.3 and iOS SDK 4.0.2","description":"","datePublished":"06/01/10 10:00","files":[{"filename":"x.dmg","remotePath":"/Developer_Tools/xcode_3.2.3/x.dmg"}]},
{"name":"Additional Tools for Xcode 27","description":"","datePublished":"09/14/26 17:00","files":[{"filename":"a.dmg","remotePath":"/Developer_Tools/Additional_Tools/a.dmg"}]}
]}
"""#

@Test func appleListParsesXcodeXipReleasesOnly() {
    let releases = AppleDeveloperDownloadList.parse(Data(appleSample.utf8))
    #expect(releases.map(\.displayName) == ["27.1 beta", "26", "27 Release Candidate", "16.4"])
    let beta = releases[0]
    #expect(beta.isPrerelease)
    #expect(beta.requiresMacOS == "26.6")
    #expect(beta.listed == Date(timeIntervalSince1970: 1_789_752_720))  // 2026-09-18 10:32 PDT = 17:32 UTC
    #expect(releases[1].archives.map(\.arch) == [.appleSilicon, .universal])
    // isReleased says 0 for the final 16.4; the name decides.
    #expect(!releases[3].isPrerelease)
    #expect(releases[2].isPrerelease)
}

@Test func appleListFailsSoftOnAnythingUnreadable() {
    #expect(AppleDeveloperDownloadList.parse(Data("<html>".utf8)).isEmpty)
    #expect(AppleDeveloperDownloadList.parse(Data(#"{"resultCode":1100,"downloads":[]}"#.utf8)).isEmpty)
}

private func indexEntry(_ number: String, build: String, order: Int, release: [String: Any],
                        url: String, archs: [String]? = nil, day: Int) -> [String: Any] {
    var download: [String: Any] = ["url": url]
    if let archs { download["architectures"] = archs }
    return ["name": "Xcode", "_versionOrder": order, "requires": "26.6",
            "date": ["year": 2026, "month": 9, "day": day],
            "version": ["number": number, "build": build, "release": release],
            "links": ["download": download]]
}

@Test func mergeAddsOnlyWhatTheIndexLacksAtItsDate() throws {
    let cdn = "https://download.developer.apple.com/Developer_Tools"
    let index = XcodeReleasesSource.parse(try JSONSerialization.data(withJSONObject: [
        indexEntry("27.2", build: "27B5019j", order: 27_002_000_001, release: ["beta": 1],
                   url: "\(cdn)/Xcode_27.2_beta/Xcode_27.2_beta.xip", day: 16),
        indexEntry("27.0", build: "27A266a", order: 27_000_000_901, release: ["rc": 1],
                   url: "\(cdn)/Xcode_27_Release_Candidate/Xcode_27_Release_Candidate.xip", day: 9),
        // The index lists 26's Universal archive only: the release is still known.
        indexEntry("26.0", build: "17A324", order: 26_000_000_999, release: ["release": true],
                   url: "\(cdn)/Xcode_26/Xcode_26_Universal.xip", archs: ["arm64", "x86_64"], day: 1),
    ]))
    let apple = AppleDeveloperDownloadList.parse(Data(appleSample.utf8))
    let items = XcodeDownloadCatalog.merged(index: index, apple: apple, host: .arm64)

    #expect(items.map(\.displayVersion) == [
        "27.1 beta",                    // Apple only, 09-18: ahead of 27.2 beta (09-16)
        "27.2 beta 1 (27B5019j)",
        "27.0 RC 1 (27A266a)",
        "26.0 (17A324)",
        "16.4",                         // Apple only, 2025: after everything newer
    ])
    #expect(items[0].onlyFromApple && items[0].build == nil)
    #expect(items[0].authorizedURL == XcodeReleasesSource.authorizedDownloadURL(
        fromCDN: "\(cdn)/Xcode_27.1_beta/Xcode_27.1_beta.xip"))
    #expect(items[0].date == DateComponents(year: 2026, month: 9, day: 18))
    #expect(!items[1].onlyFromApple)
    #expect(Set(items.map(\.id)).count == items.count)
}

@Test func mergeOnIntelTakesUniversalAndSkipsAppleSiliconOnly() {
    let apple = AppleDeveloperDownloadList.parse(Data(appleSample.utf8))
    let items = XcodeDownloadCatalog.merged(index: [], apple: apple, host: .x86_64)
    // 27.1 beta's one archive says "on Apple silicon" in its description.
    #expect(items.map(\.fileName) == [
        "Xcode_27_Release_Candidate.xip", "Xcode_26_Universal.xip", "Xcode_16.4.xip",
    ])
}

/// The day an Apple-only row shows is the day Apple created the entry, in
/// Pacific time. Both entries are verbatim from the live list (2026-09-23).
@Test func appleOnlyRowShowsThePacificDayTheEntryWasCreated() {
    let json = #"""
    {"resultCode":0,"downloads":[
    {"name":"Xcode 27 beta 2","description":"","datePublished":"06/18/26 18:17","dateCreated":"06/22/26 15:40","files":[{"filename":"Xcode 27 beta 2.xip","remotePath":"/Developer_Tools/Xcode_27_beta_2/Xcode_27_beta_2.xip"}]},
    {"name":"Xcode 12.2","description":"","datePublished":"10/25/20 05:33","dateCreated":"11/12/20 18:52","files":[{"filename":"Xcode 12.2.xip","remotePath":"/Developer_Tools/Xcode_12.2/Xcode_12.2.xip"}]}
    ]}
    """#
    let apple = AppleDeveloperDownloadList.parse(Data(json.utf8))
    let items = XcodeDownloadCatalog.merged(index: [], apple: apple, host: .arm64)
    // Released 06-22 (xcodereleases agrees); `datePublished` says 06-18.
    #expect(items.first { $0.displayVersion == "27 beta 2" }?.date
        == DateComponents(year: 2026, month: 6, day: 22))
    // 18:52 PST is already 11-13 in UTC.
    #expect(items.first { $0.displayVersion == "12.2" }?.date
        == DateComponents(year: 2020, month: 11, day: 12))
}
