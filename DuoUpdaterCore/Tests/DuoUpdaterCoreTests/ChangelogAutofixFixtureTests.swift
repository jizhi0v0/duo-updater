import Testing
import Foundation
@testable import DuoUpdaterCore

/// Every fixture `duo autofix` commits, read with the recipe as compiled.
///
/// An autofix pull request adds data, never test code: a slice of the vendor's
/// page (`<stem>.txt`) and a manifest (`<stem>.json`) naming the recipe and the
/// entries the fix read from it. This one test reads them all, so the fix stays
/// pinned after it merges — a later edit to the recipe that stops reading the
/// page goes red here — and a fixture whose recipe has gone fails rather than
/// lingering unread. The directory is empty until the first fix lands.
struct ChangelogAutofixFixtureTests {

    private struct Manifest: Decodable {
        let recipeID: String
        let fixture: String
        let entryVersions: [String]
    }

    private static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/changelog-autofix")
    }

    @Test func everyAutofixFixtureStillReadsAsItDidWhenItWasCommitted() throws {
        let manifests = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for url in manifests where url.pathExtension == "json" {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
            let recipe = try #require(
                ChangelogRecipeRegistry.recipes.first { $0.recipeID == manifest.recipeID },
                "\(url.lastPathComponent): no recipe \(manifest.recipeID)")
            let page = try String(
                contentsOf: Self.directory.appendingPathComponent(manifest.fixture), encoding: .utf8)
            let read = ChangelogExtractor.extract(from: page, using: recipe)?.entries.map(\.version)
            #expect(read == manifest.entryVersions, "\(url.lastPathComponent)")
        }
    }
}
