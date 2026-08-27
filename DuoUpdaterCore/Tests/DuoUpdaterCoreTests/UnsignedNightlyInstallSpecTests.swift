import Testing
import Foundation
@testable import DuoUpdaterCore

/// Issue #95: VLC nightly (`org.videolan.vlc`, `4.0.0-dev`) and the KeePassXC
/// snapshot (`org.keepassxc.keepassxc`, `2.8.0-snapshot`) share their bundle id
/// with an already-covered, notarized stable build, but ship completely
/// unsigned themselves — VLC nightly ad-hoc (`TeamIdentifier=not set`),
/// KeePassXC snapshot with no signature at all (verified 2026-08-27 against the
/// real downloads, see `docs/app-audits/org-videolan-vlc.md` /
/// `org-keepassxc-keepassxc.md`). `VendorInstaller`'s Team-ID gate
/// (`SignatureVerifier.verifyTeamIdentifierMatch`) would refuse the swap, so
/// neither may ever carry an install spec.
///
/// `detect()` now resolves both channels (#93 landed: `4.0.0-dev` → `.dev`,
/// `2.8.0-snapshot` → `.preview`), but neither has a RECIPE, so today each
/// `where` below matches zero recipes — that's expected, not a broken filter. What tells the two apart is the presence anchor each test
/// starts with: it fails if the bundle id it's filtering for ever stops
/// existing in the registry at all (typo'd, renamed by the vendor, or moved
/// to a different registry), which is exactly the failure mode that would
/// otherwise leave the `where` silently matching nothing forever while this
/// suite kept reporting green. Once a real non-stable recipe exists, the
/// second `#expect` in each test starts actually exercising the guard: no
/// `install:`/`installAssetPattern` may be copy-pasted onto it from a sibling
/// nightly that (unlike these two) genuinely is notarized, e.g. Freelens or
/// DB Browser nightly.
@Suite struct UnsignedNightlyInstallSpecTests {

    @Test func vlcNonStableRecipesCarryNoInstallSpec() {
        // Presence anchor — see suite doc comment.
        #expect(
            VendorProbeRegistry.recipes.contains { $0.bundleID == "org.videolan.vlc" },
            "org.videolan.vlc is no longer in VendorProbeRegistry — this test's filter would be vacuous")

        for recipe in VendorProbeRegistry.recipes
        where recipe.bundleID == "org.videolan.vlc" && recipe.channel != .stable {
            #expect(
                recipe.install == nil,
                "\(recipe.bundleID) (\(recipe.channel)): nightly is unsigned — must stay detection-only, see issue #95")
        }
    }

    @Test func keePassXCNonStableRulesCarryNoInstallSpec() {
        // Presence anchor — see suite doc comment.
        #expect(
            GitHubReleaseRegistry.rules.contains { $0.bundleID == "org.keepassxc.keepassxc" },
            "org.keepassxc.keepassxc is no longer in GitHubReleaseRegistry — this test's filter would be vacuous")

        for rule in GitHubReleaseRegistry.rules
        where rule.bundleID == "org.keepassxc.keepassxc" && rule.channel != .stable {
            #expect(
                rule.installAssetPattern == nil && rule.installerKind == nil,
                "\(rule.bundleID) (\(rule.channel)): snapshot is unsigned — must stay detection-only, see issue #95")
        }
    }
}
