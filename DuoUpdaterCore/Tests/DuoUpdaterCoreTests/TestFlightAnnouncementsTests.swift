import Testing
import Foundation
@testable import DuoUpdaterCore

/// Reading TestFlight's notifications as a second witness to what its local store
/// holds (#478).
///
/// The fixture is a **real record**, lifted byte for byte out of
/// `group.com.apple.usernoted` on 2026-09-09 — the "Ready to Test" notice for a
/// build pushed from this repo's owner's own TestFlight app, at the moment the
/// local store did not have it. A synthesised one would test the parser against my
/// idea of the shape rather than the shape, which is the failure this whole area
/// keeps producing.
struct TestFlightAnnouncementsTests {

    /// `“Claudo” Ready to Test — Version 0.3.384 (1307)`, app 6761822408.
    /// Carries no account identifier: the record holds the app id, two notification
    /// UUIDs, a date, the visible strings, and the archived payload.
    static let realRecord = Data(base64Encoded:
        "YnBsaXN0MDDYAQIDBAUGBwgJCgsMDQ4PHlRzdHlsVGludGxTYXBwVHV1aWRUZGF0ZVRzcmNlU3JlcVRvcmlnEAEJXxAU" +
        "Y29tLmFwcGxlLlRlc3RGbGlnaHRPEBDUKU+TqFpA7LpYoFy6w/iKI0HIKNNc6TpYTxAQFs3lKjTJS96lvUZkYbIVqNcQ" +
        "ERITFBUWFxgZGhscHVRkdXJsVGRlc3RUc291blR1c2RhVGJvZHlUdGl0bFRpZGVuXxAuaHR0cHM6Ly90ZXN0ZmxpZ2h0" +
        "LmFwcGxlLmNvbS92MS9hcHAvNjc2MTgyMjQwOBAP0E8RAaJicGxpc3QwMNQBAgMEBQYHClgkdmVyc2lvblkkYXJjaGl2" +
        "ZXJUJHRvcFgkb2JqZWN0cxIAAYagXxAPTlNLZXllZEFyY2hpdmVy0QgJVHJvb3SAAasLDBkaGxwiIyQqK1UkbnVsbNMN" +
        "Dg8QFBhXTlMua2V5c1pOUy5vYmplY3RzViRjbGFzc6MREhOAAoADgASjFRYXgAWACYAKgAhTYXBzUWFRYtMNDg8dHxih" +
        "HoAGoSCAB4AIVWFsZXJ0bxAWIBwAQwBsAGEAdQBkAG8gHQAgAFIAZQBhAGQAeQAgAHQAbwAgAFQAZQBzAHTSJSYnKFok" +
        "Y2xhc3NuYW1lWCRjbGFzc2VzXE5TRGljdGlvbmFyeaInKVhOU09iamVjdBMAAAABkwk4yBIN/xiOAAgAEQAaACQAKQAy" +
        "ADcASQBMAFEAUwBfAGUAbAB0AH8AhgCKAIwAjgCQAJQAlgCYAJoAnACgAKIApACrAK0ArwCxALMAtQC7AOoA7wD6AQMB" +
        "EAETARwBJQAAAAAAAAIBAAAAAAAAACwAAAAAAAAAAAAAAAAAAAEqXxA7VmVyc2lvbiAwLjMuMzg0ICgxMzA3KSBjYW4g" +
        "bm93IGJlIGluc3RhbGxlZCBvbiB5b3VyIGRldmljZS5vEBYgHABDAGwAYQB1AGQAbyAdACAAUgBlAGEAZAB5ACAAdABv" +
        "ACAAVABlAHMAdF8QJERCOTJBN0NCLTgyNEItNDJFMS1BMUI0LTNDMDY2Nzc1OUJERBACAAgAGQAeACMAJwAsADEANgA6" +
        "AD8AQQBCAFkAbAB1AIgAlwCcAKEApgCrALAAtQC6AOsA7QDuApQC0gMBAygAAAAAAAACAQAAAAAAAAAfAAAAAAAAAAAA" +
        "AAAAAAADKg=="
    )!

    /// Mutation: read the build id by scanning `$objects` for a large integer
    /// (the shape the shell probe used while investigating) — the app id
    /// 6761822408 is also in there and is larger, so the answer silently becomes
    /// the app id and this fails.
    @Test func aRealRecordYieldsItsAppAndBuildIDs() throws {
        let parsed = try #require(TestFlightAnnouncements.parse(record: Self.realRecord))
        #expect(parsed.appAdamID == 6761822408)
        // Not the CFBundleVersion (1307) — TestFlight's own build id. Checked
        // against the live store the same minute this fixture was taken:
        // `select ZBUNDLEVERSION, ZBUILDID … → 1307 | 234821774`. That equality is
        // the entire premise of using these notices as a witness, and it is pinned
        // here rather than asserted in prose.
        #expect(parsed.buildID == 234821774)
    }

    /// A record we cannot fully read must produce nothing at all. This witness only
    /// ever refuses claims, so a half-parsed record could refuse one on the strength
    /// of a field we did not actually understand.
    ///
    /// Mutation: default the app id to 0 when `durl` is absent instead of returning
    /// nil — the announcement survives with a nonsense app and this fails.
    @Test func aRecordWithoutADefaultActionURLIsNotAnAnnouncement() throws {
        var root = try #require(PropertyListSerialization.propertyList(
            from: Self.realRecord, options: [], format: nil) as? [String: Any])
        var request = try #require(root["req"] as? [String: Any])
        request.removeValue(forKey: "durl")
        root["req"] = request
        let stripped = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0)
        #expect(TestFlightAnnouncements.parse(record: stripped) == nil)
    }

    /// Same again for the payload that carries the build id — the half this one
    /// cannot do without.
    @Test func aRecordWithoutThePayloadIsNotAnAnnouncement() throws {
        var root = try #require(PropertyListSerialization.propertyList(
            from: Self.realRecord, options: [], format: nil) as? [String: Any])
        var request = try #require(root["req"] as? [String: Any])
        request.removeValue(forKey: "usda")
        root["req"] = request
        let stripped = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0)
        #expect(TestFlightAnnouncements.parse(record: stripped) == nil)
    }

    /// The lookup is per app: one app's announcements must never answer for another,
    /// or the gate they feed would refuse a verdict for the wrong row.
    ///
    /// Mutation: drop the `appAdamID` filter in `buildIDs(forAppAdamID:)` — every
    /// app gets every build id and this fails.
    @Test func buildIDsAreScopedToTheirApp() {
        let witness = TestFlightAnnouncements(announcements: [
            .init(appAdamID: 1, buildID: 100),
            .init(appAdamID: 1, buildID: 101),
            .init(appAdamID: 2, buildID: 200),
        ])
        #expect(witness.buildIDs(forAppAdamID: 1) == [100, 101])
        #expect(witness.buildIDs(forAppAdamID: 2) == [200])
        #expect(witness.buildIDs(forAppAdamID: 3).isEmpty)
        #expect(witness.buildIDs(forAppAdamID: nil).isEmpty)
    }

    /// A store we could not open must look like "nothing to say", never like
    /// "nothing was announced" — the two are the same value here, so the flag is the
    /// only thing that keeps a caller from reading a denied read as evidence.
    @Test func anUnreadableStoreIsMarkedInaccessible() {
        let witness = TestFlightAnnouncements(
            databaseURL: URL(fileURLWithPath: "/nonexistent/usernoted.db"))
        #expect(!witness.accessible)
        #expect(witness.announcements.isEmpty)
    }
}
