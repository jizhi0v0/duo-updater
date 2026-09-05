import Testing
import Foundation
@testable import DuoUpdaterCore

/// Offline invariants over `MacAppStoreProbeRegistry` — the registry `duo
/// verify`'s App Store sweep reads. Nothing here talks to a network; the live
/// endpoint checks belong to the sweep itself (`AppStoreVerify`, in the CLI
/// package) and were run manually against real endpoints (see the registry's
/// per-case comments and this repo's task notes for the raw output).
///
/// Every test is derived FROM the registry — `MacAppStoreProbeRegistry.cases`
/// — rather than hand-listing bundle ids here a second time, so a case added
/// to the registry is automatically exercised by every invariant below and
/// none of them can silently drift out of sync with it.
struct MacAppStoreProbeRegistryTests {

    /// Mutation this pins: delete the `nativeMac`/`iosOnMac`/`wrappedIOS`
    /// distinction (collapse `Route` to one case, or drop a case's `route`
    /// field entirely) and this fails, because `MacAppStoreSource.resolve`
    /// has three branches and a registry that only ever exercises one of them
    /// leaves two silently unverified. Verified red: temporarily removing the
    /// `.wrappedIOS` case from the registry (Discord) makes this fail with
    /// "no case exercises .wrappedIOS" — confirmed by hand before writing
    /// this comment, see the task's verification notes for the actual
    /// command and diff.
    @Test func everyResolveBranchHasACase() {
        let routes = Set(MacAppStoreProbeRegistry.cases.map(\.route))
        // Derived, not written out. A hand-listed set is the one shape that
        // cannot catch what this case exists for: add a fourth `Route` and a
        // fourth branch to `resolve()`, and a literal list just keeps checking
        // the three it already knew about.
        let allRoutes = Set(MacAppStoreProbeCase.Route.allCases)
        for route in allRoutes {
            #expect(routes.contains(route), "no registry case exercises \(route)")
        }
    }

    /// Mutation this pins: give two cases the same `bundleID`. `recipeID` is
    /// what the baseline and issue history key on (`Baseline.swift`,
    /// `Finding.recipeID`); a collision would make two independent apps share
    /// one failure streak and one GitHub issue.
    @Test func recipeIDsAreUnique() {
        let ids = MacAppStoreProbeRegistry.cases.map(\.recipeID)
        #expect(Set(ids).count == ids.count, "duplicate recipeID in MacAppStoreProbeRegistry: \(ids)")
    }

    /// Mutation this pins: declare a `.nativeMac` case with `expectedKind:
    /// "software"` (or the reverse) — a copy-paste authoring mistake, not a
    /// live drift (the live sweep's `kindMismatch` check catches drift; this
    /// catches the registry contradicting its own routing rule at write
    /// time). `MacAppStoreSource.resolve` sends `kind == "mac-software"` to
    /// `nativeMacVersion` and `kind == "software"` to the other two branches
    /// — see the switch in `resolve(result:app:region:)`.
    @Test func expectedKindMatchesItsOwnRoute() {
        for probeCase in MacAppStoreProbeRegistry.cases {
            switch probeCase.route {
            case .nativeMac:
                #expect(probeCase.expectedKind == "mac-software",
                        "\(probeCase.bundleID): .nativeMac must declare kind mac-software")
            case .iosOnMac, .wrappedIOS:
                #expect(probeCase.expectedKind == "software",
                        "\(probeCase.bundleID): \(probeCase.route) must declare kind software")
            }
        }
    }

    /// Mutation this pins: a case whose `trackId` is left at `0`/negative, or
    /// a `region` that isn't a plausible two-letter storefront code — the
    /// kind of typo `duo verify --appstore --only <id>` would otherwise
    /// discover by burning a live request against the wrong id.
    @Test func fieldsAreWellFormed() {
        for probeCase in MacAppStoreProbeRegistry.cases {
            #expect(probeCase.trackId > 0, "\(probeCase.bundleID): trackId must be positive")
            #expect(probeCase.region.count == 2 && probeCase.region == probeCase.region.lowercased(),
                    "\(probeCase.bundleID): region '\(probeCase.region)' doesn't look like a storefront code")
            #expect(!probeCase.bundleID.isEmpty)
        }
    }

    /// Never derive this registry from what's installed on the sweeping
    /// machine — see the doc comment on `MacAppStoreProbeRegistry` and
    /// `scripts/check_app_audits.py`'s header for why. This is a structural
    /// check standing in for that rule: the registry must not be empty (a
    /// registry that quietly lost all its entries would make
    /// `Verify.sweepAppStore` a silent no-op) and must not accidentally grow
    /// to registry-of-everything size, which would be a sign someone wired it
    /// up to a scan instead of hand-picking entries.
    @Test func registryIsHandPickedNotScanned() {
        #expect(!MacAppStoreProbeRegistry.cases.isEmpty)
        #expect(MacAppStoreProbeRegistry.cases.count < 30,
                "MacAppStoreProbeRegistry has grown large enough to look derived from a scan rather than hand-picked")
    }
}
