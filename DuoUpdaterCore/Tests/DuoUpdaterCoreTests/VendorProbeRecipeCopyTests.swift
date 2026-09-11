import Testing
import Foundation
@testable import DuoUpdaterCore

// `VendorProbeRecipe.with(url:)` / `with(entryStartPattern:)` promise to change ONE
// field and carry every other one over. `copy(...)` used to drop three of them —
// `transientBodyPattern`, `trackClosedPattern`, `buildLineage` all have defaults,
// so leaving them out of the rebuild compiled fine and reset them to nil. That
// mattered once `duo verify`'s edge-copy check started re-probing recipes through
// `with(url:)`: a recipe that honours an error envelope or a closed track on its
// first probe would not on its second.
//
// Compared by reflection, field by field, across the whole registry, so a field
// added to the recipe later and forgotten in `copy` goes red here too.

private func fields(_ recipe: VendorProbeRecipe, excluding skipped: String) -> [String: String] {
    var out: [String: String] = [:]
    for child in Mirror(reflecting: recipe).children {
        guard let label = child.label, label != skipped else { continue }
        out[label] = String(describing: child.value)
    }
    return out
}

@Test func withURLCarriesEveryOtherField() {
    let elsewhere = URL(string: "https://example.invalid/elsewhere")!
    for recipe in VendorProbeRegistry.recipes {
        let copy = recipe.with(url: elsewhere)
        #expect(copy.url == elsewhere)
        #expect(fields(copy, excluding: "url") == fields(recipe, excluding: "url"),
                "with(url:) changed more than the URL of \(recipe.recipeID)")
    }
}

@Test func withEntryStartPatternCarriesEveryOtherField() {
    for recipe in VendorProbeRegistry.recipes {
        let copy = recipe.with(entryStartPattern: "<entry")
        #expect(copy.entryStartPattern == "<entry")
        #expect(fields(copy, excluding: "entryStartPattern")
                    == fields(recipe, excluding: "entryStartPattern"),
                "with(entryStartPattern:) changed more than that field of \(recipe.recipeID)")
    }
}

/// The comparison above can only catch a dropped field that some recipe actually
/// sets. These three are the ones that were dropped; if the registry ever stops
/// using one, the reflection test loses its teeth for it without a word.
@Test func theRegistryExercisesTheFieldsCopyUsedToDrop() {
    let recipes = VendorProbeRegistry.recipes
    #expect(recipes.contains { $0.transientBodyPattern != nil })
    #expect(recipes.contains { $0.trackClosedPattern != nil })
    #expect(recipes.contains { $0.buildLineage != nil })
}
