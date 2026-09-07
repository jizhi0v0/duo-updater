import Foundation
import Testing
@testable import DuoKit
@testable import DuoUpdaterCore

/// The `warn` path has no live example — measured 2026-09-07, every declaration
/// in the registry is universal (#415) — so the classifier is tested directly
/// rather than against a real package. A check whose only interesting branch is
/// unreachable in production is exactly the kind this repo asks to be pinned by
/// construction instead of by fixture.
struct PackageArchitectureProbeTests {

    /// Mutation: compare against a literal `"arm64,x86_64"` instead of counting
    /// names, and the `x86_64,arm64` cases go red. Both spellings are live —
    /// 9 recipes use one order, 6 the other — so order carries no meaning and a
    /// string comparison would call half the registry single-architecture.
    @Test(arguments: [
        ("arm64,x86_64", false), ("x86_64,arm64", false),
        ("arm64, x86_64", false), ("x86_64", true), ("arm64", true),
        ("arm64,arm64", true),
    ])
    func universalIsDecidedByCountingNamesNotBySpelling(value: String, isSingle: Bool) {
        let declaration = PackageArchitectureProbe.classify(value)
        if case .single = declaration {
            #expect(isSingle, "\(value) was read as single-architecture")
        } else {
            #expect(!isSingle, "\(value) was read as universal")
        }
        #expect(declaration.value == value)   // the vendor's spelling is preserved verbatim
    }

    /// Mutation: drop the `\s*` around `=` and the formatted spelling goes red.
    /// This is an XML attribute, not a fixed vendor string — a reformatted
    /// Distribution is the same declaration.
    @Test func theAttributeIsReadWhateverTheXMLSpacing() {
        let bodies = [
            #"<options hostArchitectures="arm64,x86_64"/>"#,
            #"<options hostArchitectures = "arm64,x86_64" />"#,
            "<options\n    hostArchitectures=\"arm64,x86_64\"\n/>",
        ]
        for body in bodies {
            #expect(PackageArchitectureProbe.hostArchitecturesAttribute(
                in: Data(body.utf8)) == "arm64,x86_64", "failed on: \(body)")
        }
        // Absent must read as nil, not as an empty declaration — `.absent` and
        // `.single("")` are different findings.
        #expect(PackageArchitectureProbe.hostArchitecturesAttribute(
            in: Data(#"<options rootVolumeOnly="true"/>"#.utf8)) == nil)
    }

    /// The declaration text a report shows must not lose the case that produced
    /// it. `NOT-XAR` with an empty reason was a real defect: the raw `<!DO` a
    /// vendor's HTML interstitial starts with is stripped by `Redactor`, so the
    /// diagnostic arrived empty (measured on Sunlogin).
    @Test func anUnreadablePackageSaysWhatArrived() {
        let declaration = PackageArchitectureProbe.Declaration
            .notAFlatPackage("bytes=28 magic=0x3c21444f")
        #expect(declaration.value.contains("3c21444f"))
        #expect(!declaration.value.hasSuffix("()"))
    }

    /// Registry-derived, not a hand-written list: every pkg spec must be one the
    /// sweep can name. A recipe flipping `.tar` → `.pkg` silently moves an app
    /// onto the gate-less install route (#415), and this is what notices.
    @Test func everyPkgSpecIsCoveredBySweepAndScript() {
        let pkgs = VendorProbeRegistry.recipes.filter { $0.install?.kind == .pkg }
        #expect(!pkgs.isEmpty, "no pkg specs found — the filter, not the registry, is wrong")
        // Guards the count the docs and #415 quote, so the prose cannot drift away
        // from the registry without something going red.
        #expect(pkgs.count == 22, """
            The pkg install route changed size (\(pkgs.count) specs, was 22). That is \
            worth reading, not just re-pinning: every one of these is installed with \
            no architecture gate. Re-run scripts/pkg_host_architectures.py and update \
            #415 before changing this number.
            """)
        #expect(Set(pkgs.map(\.recipeID)).count == pkgs.count, "recipeIDs must be unique")
    }

    /// Mutation: use `recipe.recipeID` instead of `pkgArchID(recipe)` inside
    /// `pkgArchFinding` and this goes red.
    ///
    /// `Baseline` keys its entries on the id ALONE, so a pkgarch finding sharing
    /// the vendor recipe's id lands in the vendor recipe's baseline entry: one
    /// `consecutiveActionable` streak fed by two sweeps, and one issue number for
    /// both. Every other registry namespaces for this reason (`appstore:`,
    /// `feed:`, `github:`, `vendor:`).
    ///
    /// ⚠️ Asserted through `pkgArchFinding`, NOT by calling `pkgArchID` directly.
    /// The first version of this test did the latter and the mutation stayed
    /// GREEN — reverting the call site cannot be seen by a test that never goes
    /// through the call site.
    @Test func pkgArchFindingsGetTheirOwnBaselineKey() throws {
        let pkgs = VendorProbeRegistry.recipes.filter { $0.install?.kind == .pkg }
        let recipe = try #require(pkgs.first)
        let finding = Verify.pkgArchFinding(
            recipe, host: "example.invalid",
            outcome: .success(.universal("arm64,x86_64")), elapsedMs: 1)
        #expect(finding.recipeID.hasPrefix("pkgarch:"))
        #expect(finding.recipeID != recipe.recipeID)
        // Across the whole route, no pkgarch id may collide with any vendor id.
        let pkgArchIDs = Set(pkgs.map {
            Verify.pkgArchFinding($0, host: "-", outcome: nil, elapsedMs: 0).recipeID
        })
        let vendorIDs = Set(VendorProbeRegistry.recipes.map(\.recipeID))
        #expect(pkgArchIDs.isDisjoint(with: vendorIDs))
        #expect(pkgArchIDs.count == pkgs.count, "ids must stay unique per channel")
    }

    /// The sweep's status mapping, which no real package can exercise: measured
    /// 2026-09-07, every declaration in the registry is universal, so `.warn` —
    /// its only actionable branch — has no live example. Without this the branch
    /// would ship having never produced a finding.
    ///
    /// Mutation: flip `single ? .warn : .ok` either way and this goes red.
    /// Mutation: warn on `.absent` (the tempting "we should know about these")
    /// and this goes red too — 7 of 22 declare nothing, so that would file seven
    /// findings on day one.
    @Test func onlyASingleArchitectureDeclarationWarns() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.install?.kind == .pkg })
        func status(_ d: PackageArchitectureProbe.Declaration) -> FindingStatus {
            Verify.pkgArchFinding(recipe, host: "-", outcome: .success(d), elapsedMs: 0).status
        }
        #expect(status(.single("x86_64")) == .warn)
        #expect(status(.universal("arm64,x86_64")) == .ok)
        #expect(status(.absent) == .ok)
        #expect(status(.notAFlatPackage("bytes=28 magic=0x3c21444f")) == .ok)
        // A vendor hanging up is infra, never a recipe defect — filing those
        // trains the reader to ignore the sweep.
        #expect(Verify.pkgArchFinding(
            recipe, host: "-", outcome: .failure(URLError(.timedOut)), elapsedMs: 0)
            .status == .infra)
        // The declaration is recorded even when nothing is wrong, so drift shows
        // up as a report diff rather than needing someone to re-read a comment.
        let ok = Verify.pkgArchFinding(
            recipe, host: "-", outcome: .success(.universal("arm64,x86_64")), elapsedMs: 0)
        #expect(ok.warnings.contains("hostArchitectures=arm64,x86_64"))
    }
}
