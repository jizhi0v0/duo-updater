import Foundation
import Testing
@testable import DuoUpdaterCore

private func item(_ version: String) -> XcodeDownloadItem {
    XcodeDownloadItem(
        id: version, build: nil, order: nil, displayVersion: version, onlyFromApple: false,
        isPrerelease: false, date: nil, requiresMacOS: nil,
        authorizedURL: URL(string: "https://developer.apple.com/services-account/download?path=/x.xip")!,
        fileName: "x.xip")
}

/// Newest major first, "older" last, the list's order kept inside a group.
@Test func xcodeListGroupsByMajorNewestFirst() {
    let groups = XcodeDownloadGroup.grouped([
        item("27.1 beta 1 (27A9269)"), item("26.1 (17B55)"), item("27.0 (27A123)"),
        item("11.7 (11E801a)"), item("16.4 (16F6)"), item("26.0 (17A324)"), item("2.3"), item("12.5.1"),
    ])
    #expect(groups.map(\.id) == ["27", "26", "16", "12", "older"])
    #expect(groups[0].items.map(\.displayVersion) == ["27.1 beta 1 (27A9269)", "27.0 (27A123)"])
    #expect(groups.map(\.macOS) == ["27", "26", "15", "11", nil])
    #expect(groups.last?.items.map(\.displayVersion) == ["11.7 (11E801a)", "2.3"])
}

/// Open by default: the group that came with this Mac's macOS, else the newest.
@Test func xcodeListOpensTheGroupForThisMacOS() {
    let groups = XcodeDownloadGroup.grouped([item("27.0"), item("26.0"), item("16.4")])
    #expect(XcodeDownloadGroup.defaultOpen(in: groups, hostMacOSMajor: 26) == "26")
    #expect(XcodeDownloadGroup.defaultOpen(in: groups, hostMacOSMajor: 15) == "16")
    #expect(XcodeDownloadGroup.defaultOpen(in: groups, hostMacOSMajor: 28) == "27")
    #expect(XcodeDownloadGroup.defaultOpen(in: [], hostMacOSMajor: 26) == nil)
}
