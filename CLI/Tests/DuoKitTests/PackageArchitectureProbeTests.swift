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
}
