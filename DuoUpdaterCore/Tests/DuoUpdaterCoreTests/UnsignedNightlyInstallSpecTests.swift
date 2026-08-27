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
/// Detection for these two channels doesn't exist yet (blocked on #93), so
/// today this iterates zero matching recipes — that's expected. The guard is
/// for the day a nightly/snapshot-channel recipe gets added and copy-pastes an
/// `install:`/`installAssetPattern` from a sibling nightly that (unlike these
/// two) genuinely is notarized, e.g. Freelens or DB Browser nightly.
@Suite struct UnsignedNightlyInstallSpecTests {

    @Test func vlcNonStableRecipesCarryNoInstallSpec() {
        for recipe in VendorProbeRegistry.recipes
        where recipe.bundleID == "org.videolan.vlc" && recipe.channel != .stable {
            #expect(
                recipe.install == nil,
                "\(recipe.bundleID) (\(recipe.channel)): nightly is unsigned — must stay detection-only, see issue #95")
        }
    }

    @Test func keePassXCNonStableRulesCarryNoInstallSpec() {
        for rule in GitHubReleaseRegistry.rules
        where rule.bundleID == "org.keepassxc.keepassxc" && rule.channel != .stable {
            #expect(
                rule.installAssetPattern == nil && rule.installerKind == nil,
                "\(rule.bundleID) (\(rule.channel)): snapshot is unsigned — must stay detection-only, see issue #95")
        }
    }
}
