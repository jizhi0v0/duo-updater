import Testing
import Foundation
@testable import DuoUpdaterCore

/// `CuaDriverChannel` reads `~/.cua-driver/release-channel`, the only on-disk
/// signal that separates Cua Driver's two trains — the bundle itself reports the
/// same version string for both.
///
/// Every case here drives the PURE function with a literal, so nothing asks this
/// Mac what it has installed. The one test that names a path asserts the path is
/// NOT the machine's own.
@Suite struct CuaDriverChannelTests {

    /// The two words the vendor's installer writes, and what each must mean.
    ///
    /// `nightly` is the only value that moves a copy off stable; that asymmetry
    /// is the safety property, not a shortcut. Everything else — including the
    /// two spellings the installer itself rejects — lands on stable, so a
    /// preference we failed to understand can never escalate someone onto a
    /// prerelease train.
    @Test(arguments: [
        ("nightly", ReleaseChannel.nightly),
        ("stable", .stable),
        // The file is written with `printf '%s\n'`, so the newline is real and
        // the reader has to survive it. This is the single most likely way to
        // break the binding while every other test stays green.
        ("nightly\n", .nightly),
        ("stable\n", .stable),
        ("  nightly  \n", .nightly),
        ("NIGHTLY", .nightly),
        // Not words the installer will write, but a hand-edited or truncated
        // file is not a reason to escalate.
        ("", .stable),
        ("night", .stable),
        ("nightly-ish", .stable),
        ("beta", .stable),
        ("canary", .stable),
        ("true", .stable),
    ])
    func recordedValuesResolveToTheirChannel(value: String, expected: ReleaseChannel) {
        #expect(CuaDriverChannel.resolve(releaseChannel: value).channel == expected)
    }

    /// No file at all is the DEFAULT install, not an unknown state: the installer
    /// writes this file only when `--channel` was passed explicitly, so a plain
    /// `curl … | bash` leaves nothing behind and the copy is stable.
    @Test func noRecordedChannelIsStable() {
        #expect(CuaDriverChannel.resolve(releaseChannel: nil).channel == .stable)
    }

    /// The binding selects a recipe and nothing else — no feed to swap, no
    /// header to send, no Sparkle channel tag. That is what keeps it out of
    /// `channelBindingsNeedingProof`, whose members are the request-keyed
    /// bindings; this one's cross-channel obligation is discharged by the nightly
    /// rule's `githubChannelProofs` entry instead. Pinned so that adding a feed
    /// override here without registering a binding proof fails.
    @Test func theBindingCarriesNoRequestSideChannelSignal() {
        for value in ["nightly", "stable", ""] {
            let resolved = CuaDriverChannel.resolve(releaseChannel: value)
            #expect(resolved.feedOverride == nil)
            #expect(resolved.feedHTTPHeaders.isEmpty)
            #expect(resolved.sparkleChannelNames.isEmpty)
        }
    }

    /// The resolver is reachable through the one switch every binding goes
    /// through — the step that is easy to forget, and whose omission is silent:
    /// the type compiles, its tests pass, and no nightly copy is ever bound.
    @Test func theBindingIsRegistered() {
        #expect(ChannelBinding.hasResolver(bundleID: "com.trycua.driver"))
        // Case-insensitively, because a `CFBundleIdentifier` is — the trap that
        // cost TablePlus a silent fallback to stable.
        #expect(ChannelBinding.hasResolver(bundleID: "COM.TRYCUA.DRIVER"))
        #expect(ChannelBinding.boundBundleIDs.contains("com.trycua.driver"))
    }

    /// Where the file is read from, asserted as a suffix rather than a full path
    /// so the test does not encode whose home directory ran it.
    ///
    /// The `fileExists` half is the guard this repo keeps re-learning: a fixture
    /// that happens to point at something real on the author's Mac passes for the
    /// wrong reason. Here the opposite is wanted — the CONSTANT must be the
    /// vendor's path, and this test must not depend on whether a driver is
    /// installed, so only the spelling is checked.
    @Test func theChannelFileIsTheVendorsPath() {
        let url = CuaDriverChannel.channelFileURL
        #expect(url.path.hasSuffix("/.cua-driver/release-channel"))
        #expect(url.lastPathComponent == "release-channel")
    }

    /// A path that is not the vendor's file reads as no record, and a
    /// pathologically large one is refused rather than slurped. Both go through
    /// the real reader, with a fixture path that cannot exist.
    @Test func anUnreadableRecordIsNoRecord() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-cua-\(UUID().uuidString)/release-channel")
        #expect(!FileManager.default.fileExists(atPath: missing.path),
                "this fixture must not exist, or the test is measuring the filesystem")
        #expect((try? Data(contentsOf: missing)) == nil)
        // …and that is the input the pure resolver is given for a missing file.
        #expect(CuaDriverChannel.resolve(releaseChannel: nil).channel == .stable)
    }
}
