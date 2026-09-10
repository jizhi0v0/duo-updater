import Testing
@testable import DuoUpdaterCore

@Suite("TCCPreflight.admitsOtherAppsData")
struct OtherAppsDataAccessTests {

    /// Full Disk Access never answers "not determined" (it has no prompt), so a
    /// Mac that never granted it reads `.denied`. Mutation: answer `true` for
    /// `.denied` — then every refresh on such a Mac reads TestFlight's store and
    /// gets a "Data Access Blocked" notice for it.
    @Test func withoutFullDiskAccessNothingIsRead() {
        #expect(!TCCPreflight.admitsOtherAppsData(fullDiskAccess: .denied))
        #expect(!TCCPreflight.admitsOtherAppsData(fullDiskAccess: .notDetermined))
    }

    /// Mutation: answer `false` for `.granted` — TestFlight rows could then never
    /// be checked, on exactly the Macs that did everything asked of them.
    @Test func fullDiskAccessAdmits() {
        #expect(TCCPreflight.admitsOtherAppsData(fullDiskAccess: .granted))
    }

    /// Mutation: answer `false` for `.unknown` — the SPI going away in some macOS
    /// release would switch TestFlight off for everyone, granted or not.
    @Test func anUnanswerableStatusKeepsTheOldBehaviour() {
        #expect(TCCPreflight.admitsOtherAppsData(fullDiskAccess: .unknown))
    }
}
