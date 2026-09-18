import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `Finding.observing(_:)` and `Finding.adding(warning:)` rebuild a finding
/// field by field to attach a note or a complaint. Every argument of
/// `Finding.init` has a default, so a rebuild that forgets one does not fail to
/// compile — it silently writes `nil` into `report.json`, and it does so for
/// exactly the rows that carry a complaint, which are the rows a human reads.
///
/// This has now happened twice. `entryCount` was dropped when the rebuilds first
/// shipped, and the fix was a comment on each saying "every field forwarded".
/// `entryVersions` was dropped anyway, by the change that added it — and added
/// it specifically so a BACKWARDS complaint could be explained, so the field
/// went missing from the complaining rows it was introduced to serve.
///
/// A comment asking the next author to remember is what failed, so this asks
/// nobody: the check walks `Mirror` over both findings and compares every child
/// it finds. A field added to `Finding` tomorrow is covered the day it exists,
/// without being named here — provided it is given a distinctive value below,
/// which is what `everyFieldIsDistinguishable` enforces.
@Suite struct FindingRebuildTests {

    /// Every field set to something no default could produce, so that a dropped
    /// field reads as a difference rather than coincidentally matching `nil`.
    private static let populated = Finding(
        recipeID: "changelog:com.example.app:-", registry: .changelog,
        bundleID: "com.example.app", channel: "beta",
        status: .warn, version: "4.8.0",
        failureKind: "versionPatternNoMatch", failureDetail: "detail text",
        warnings: ["first warning"], endpointHost: "example.invalid",
        pattern: "<h3>(?<version>[^<]+)</h3>",
        attempts: 3, gatewayRetries: 2,
        entryCount: 20, entryVersions: ["4.8.0", "4.7.9", "4.7.8"],
        headingMatchesPage: true,
        elapsedMs: 1234, bodySample: "<h3>4.8.0</h3>")

    private func children(_ finding: Finding) -> [String: String] {
        var out: [String: String] = [:]
        for child in Mirror(reflecting: finding).children {
            guard let label = child.label else { continue }
            out[label] = String(describing: child.value)
        }
        return out
    }

    /// The fixture is only load-bearing while every field actually carries a
    /// value a default could not produce. A field left at `nil`/empty here would
    /// make the comparison below pass for a rebuild that drops it.
    ///
    /// Mutation: set any one argument of `populated` back to its default.
    @Test func everyFieldIsDistinguishable() {
        let fields = children(Self.populated)
        #expect(!fields.isEmpty)
        for (label, value) in fields {
            #expect(value != "nil", "\(label) is nil — a dropped rebuild would match it")
            #expect(value != "[]", "\(label) is empty — a dropped rebuild would match it")
            #expect(!value.isEmpty, "\(label) is blank")
        }
    }

    /// Mutation: delete any `<field>: <field>,` pair from either rebuild in
    /// `Finding.observing(_:)` / `Finding.adding(warning:)`.
    ///
    /// `warnings` is excluded because appending to it is the entire point of
    /// both methods, and `status` because `adding(warning:)` promotes `ok` to
    /// `warn` on purpose. Everything else must survive untouched.
    @Test func findingRebuildsForwardEveryField() {
        let before = children(Self.populated)
        let rebuilds: [(name: String, finding: Finding)] = [
            ("observing", Self.populated.observing(Finding.machineNotePrefix + "a note")),
            ("adding(warning:)", Self.populated.adding(warning: "a complaint")),
        ]
        for (name, rebuilt) in rebuilds {
            let after = children(rebuilt)
            #expect(Set(after.keys) == Set(before.keys), "\(name) changed the field set")
            for (label, value) in before where label != "warnings" && label != "status" {
                #expect(after[label] == value,
                        "\(name) dropped or altered \(label): \(value) → \(after[label] ?? "<missing>")")
            }
            // The one both methods are allowed to change, and must: the note is
            // appended, the original kept.
            #expect(rebuilt.warnings.count == Self.populated.warnings.count + 1, "\(name)")
            #expect(rebuilt.warnings.first == Self.populated.warnings.first, "\(name)")
        }
    }

    /// The field that prompted this suite, stated on its own so a failure names
    /// the regression rather than a generic field mismatch.
    ///
    /// `entryVersions` is what tells a reader whether a BACKWARDS complaint means
    /// the pattern slipped or the vendor published above the old entry
    /// (`Baseline.pageStillCarries`), so losing it on complaining rows loses it
    /// precisely where it is read.
    @Test func aComplainingRowKeepsTheEntryVersionsThatExplainIt() {
        let complaining = Self.populated.adding(
            warning: "version went BACKWARDS since the last sweep (4.8.0 → 4.7.9)")
        #expect(complaining.entryVersions == ["4.8.0", "4.7.9", "4.7.8"])
        #expect(complaining.observing(Finding.machineNotePrefix + "note").entryVersions
            == ["4.8.0", "4.7.9", "4.7.8"])
    }
}
