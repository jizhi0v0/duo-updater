import Testing
import Foundation
@testable import DuoKit

/// The scan-timeout sentence has one spelling, shared by `duo` and the sweep.
///
/// There were two copies, both blaming a privacy prompt that macOS 27 does not
/// raise (see `BoundedScan`). Derived from the source tree rather than from a list
/// of call sites, so a third caller that spells its own is caught too.
@Suite struct BoundedScanMessageTests {

    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DuoKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // CLI
            .appendingPathComponent("Sources")
    }

    private static func swiftSources() throws -> [(name: String, text: String)] {
        let files = FileManager.default.enumerator(
            at: sourcesDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Mutation: put the old sentence back in `Verify.installedVersions`, or in
    /// `Inventory.scan`.
    @Test func onlyBoundedScanSpellsTheSentence() throws {
        let sources = try Self.swiftSources()
        #expect(sources.count > 10, "found \(sources.count) sources — wrong directory?")
        let spelling = sources.filter { $0.text.contains("did not finish within") }.map(\.name)
        #expect(spelling == ["BoundedScan.swift"])
        let callers = sources.filter { $0.text.contains("BoundedScan.gaveUpMessage(after:") }
            .map(\.name).sorted()
        #expect(callers == ["Inventory.swift", "Verify.swift"])
    }

    /// Mutation: restore "almost always the TestFlight database waiting on an
    /// 'access data from other apps' prompt".
    @Test func theSentenceNamesNoCause() {
        let message = BoundedScan.gaveUpMessage(after: .seconds(20))
        #expect(message.contains("did not finish within"))
        for cause in ["prompt", "TestFlight", "privacy", "permission"] {
            #expect(!message.localizedCaseInsensitiveContains(cause), "names \(cause): \(message)")
        }
    }
}
