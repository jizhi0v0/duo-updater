import Testing
import Foundation
@testable import DuoUpdaterCore

/// A new rule in `ReleaseChannel.detect()` step 4 is cheap to write and expensive
/// to get wrong: it reads a string every covered app carries, so a rule that is a
/// little too loose reclassifies apps that were being updated fine, and they go
/// quiet rather than fail loudly.
///
/// Hand-written "must stay stable" lists (there is one next door in
/// `ChannelGuardTests`) only cover the shapes somebody thought of. This replays
/// the rule over the versions our recipes ACTUALLY resolved — `verify/baseline.json`,
/// which the nightly `duo verify` sweep rewrites — so the guarded population grows
/// on its own as coverage does.
///
/// If this fails after a sweep updated the baseline, that is the alarm working: a
/// covered app has started shipping a version that classifies differently than its
/// recipe declares. Read the diff before touching this test.
@Test func noCoveredRecipeVersionContradictsItsDeclaredChannel() throws {
    let baseline = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("verify/baseline.json")

    let data = try Data(contentsOf: baseline)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let entries = try #require(json?["entries"] as? [String: [String: Any]])
    #expect(entries.count > 200, "baseline shrank unexpectedly — is it still the sweep's output?")

    // Firefox Developer Edition reports `155.0b5`, which step 4's Mozilla
    // `<maj>.<min>b<N>` rule reads as `.beta`. That is not a live defect and not
    // this rule's doing: step 0 resolves Firefox from `application.ini`'s
    // `RemotingName` (`firefox-dev`) and returns before step 4 is reached — see
    // `ReleaseChannel.detect`'s header. Keyed by bundle id, not by version, so a
    // version bump doesn't silently re-arm it.
    let decidedBeforeStep4: Set<String> = ["org.mozilla.firefoxdeveloperedition"]

    var contradictions: [String] = []
    var checked = 0

    for (key, entry) in entries {
        guard let version = entry["lastGoodVersion"] as? String, !version.isEmpty else { continue }
        // Keys are "<source>:<bundleID>:<channel>"; changelog rows carry "-".
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { continue }
        let bundleID = String(parts[1])
        let declaredRaw = String(parts[parts.count - 1])
        let declared = declaredRaw == "-" ? ReleaseChannel.stable
            : (ReleaseChannel(rawValue: declaredRaw) ?? .stable)
        if decidedBeforeStep4.contains(bundleID) { continue }
        checked += 1

        // Neutral name and no bundle id, so ONLY the version string can speak —
        // this isolates step 4 from the signals that would normally outrank it.
        let fromVersion = ReleaseChannel.detect(
            name: "App", bundleID: nil, keystoneChannel: nil, version: version)

        // Reading as `.stable` is always allowed: the recipe's own channel comes
        // from elsewhere (bundle id, display name, an app preference). What must
        // never happen is the version asserting a DIFFERENT non-stable channel.
        if fromVersion != .stable && fromVersion != declared {
            contradictions.append("\(key) version \(version) → \(fromVersion), declared \(declared)")
        }
    }

    #expect(checked > 200, "swept too few entries — did the key format change?")
    #expect(contradictions.isEmpty,
            Comment(rawValue: "version strings contradict their recipe's channel:\n"
                              + contradictions.sorted().joined(separator: "\n")))
}
