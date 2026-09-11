import Testing
import Foundation
@testable import DuoUpdaterCore

// `duo verify`'s edge-copy check: which recipes it asks, and what it says. The
// network half lives in the CLI (`Verify.edgeCopyComplaint`); these are the rules.

// MARK: - Derived from the registry

/// Every recipe that reads an electron manifest is inside the check. A `*-mac.yml`
/// recipe the predicate turns away — it grew a query, or started POSTing — would
/// otherwise leave the sweep without anyone deciding it should.
@Test func everyElectronManifestRecipeIsAskedAboutEdgeCopies() {
    let manifests = VendorProbeRegistry.recipes.filter { $0.url.path.hasSuffix("-mac.yml") }
    #expect(!manifests.isEmpty,
            "no *-mac.yml recipes found — did the registry or this filter change?")
    let skipped = manifests.filter { !RecipeSanity.readsElectronManifest($0) }.map(\.recipeID)
    #expect(skipped.isEmpty,
            "*-mac.yml recipes the edge-copy check would skip: \(skipped)")
}

// MARK: - The rules themselves

@Test func onlyAPlainManifestFetchIsAsked() throws {
    let manifest = try #require(
        VendorProbeRegistry.recipes.first { RecipeSanity.readsElectronManifest($0) })
    // A query the recipe states itself: adding ours would change the request.
    #expect(!RecipeSanity.readsElectronManifest(
        manifest.with(url: URL(string: "https://example.invalid/latest-mac.yml?channel=x")!)))
    // Not an electron manifest at all.
    #expect(!RecipeSanity.readsElectronManifest(
        manifest.with(url: URL(string: "https://example.invalid/appcast.xml")!)))
    #expect(!RecipeSanity.readsElectronManifest(
        manifest.with(url: URL(string: "https://example.invalid/latest.yml")!)))
}

@Test func onlyADisagreementIsAComplaint() throws {
    #expect(RecipeSanity.edgeCopyComplaint(bare: "3.2.7", origin: "3.2.7") == nil)
    let complaint = try #require(RecipeSanity.edgeCopyComplaint(bare: "3.2.5", origin: "3.2.7"))
    #expect(complaint.contains("3.2.5") && complaint.contains("3.2.7"))
    // Either direction: the two addresses are simply not serving the same document.
    #expect(RecipeSanity.edgeCopyComplaint(bare: "3.2.7", origin: "3.2.5") != nil)
}

@Test func theCheckAsksWithTheSameQueryTheSourceSends() {
    let url = URL(string: "https://example.invalid/app/upgrade/latest-mac.yml")!
    #expect(ElectronUpdateConfig.noCacheURL(for: url, token: "k3v9")
        == URL(string: "https://example.invalid/app/upgrade/latest-mac.yml?noCache=k3v9"))
    let stated = URL(string: "https://example.invalid/latest-mac.yml?channel=x")!
    #expect(ElectronUpdateConfig.noCacheURL(for: stated, token: "k3v9") == stated)
}
