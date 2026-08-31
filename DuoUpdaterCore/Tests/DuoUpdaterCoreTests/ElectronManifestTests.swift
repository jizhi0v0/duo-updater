import Testing
import Foundation
@testable import DuoUpdaterCore

// Manifest bodies below are the real `*-mac.yml` files those vendors served on
// 2026-08-31, trimmed only of entries that repeat. The arch cases are the whole
// reason this type exists, so they are tested against the exact filenames that
// caught the bug rather than against invented ones.

@Test func picksTheArm64ArtifactOverTheOneTheManifestCallsPrimary() {
    // ChatWise 26.8.0. Its top-level `path` names the **x64** build, so a reader
    // that trusted `path` would hand an Apple-silicon Mac an Intel zip — the
    // "installs fine, won't open" failure the registry pins arm64 to avoid.
    let manifest = ElectronManifest.parse("""
        version: 26.8.0
        files:
          - url: ChatWise-26.8.0-x64.zip
            sha512: X64SHA==
            size: 100
          - url: ChatWise-26.8.0-arm64.zip
            sha512: ARM64SHA==
            size: 99
        path: ChatWise-26.8.0-x64.zip
        sha512: X64SHA==
        releaseDate: '2026-08-27T01:59:39.485Z'
        """)
    let file = try! #require(manifest?.artifact(forArch: "arm64"))
    #expect(file.url == "ChatWise-26.8.0-arm64.zip")
    #expect(file.sha512 == "ARM64SHA==")
}

@Test func fallsBackToTheUniversalArtifactWhenNoArchIsNamed() {
    // Canva 1.124.1 — and note the shape that makes "first url wins" wrong: the
    // same dmg is listed three times after the zip.
    let manifest = ElectronManifest.parse("""
        version: 1.124.1
        files:
          - url: Canva-1.124.1-universal-mac.zip
            sha512: ZIPSHA==
            size: 220714081
          - url: Canva-1.124.1-universal.dmg
            sha512: DMGSHA==
            size: 229488791
          - url: Canva-1.124.1-universal.dmg
            sha512: DMGSHA==
            size: 229488791
        path: Canva-1.124.1-universal-mac.zip
        sha512: ZIPSHA==
        """)
    #expect(manifest?.artifact()?.url == "Canva-1.124.1-universal-mac.zip")
}

@Test func anUnmarkedArtifactIsAccepted() {
    // Notion's default manifest. Nothing in the filename says which architecture
    // it is — which is exactly why the SOURCE probes for an `arm64-mac.yml`
    // sibling before trusting this. At the manifest level, an unmarked name is
    // taken as runnable, because most vendors ship one universal artifact and
    // label it nothing at all.
    let manifest = ElectronManifest.parse("""
        version: 7.31.3
        files:
          - url: Notion-7.31.3.zip
            sha512: ZIPSHA==
            size: 126113061
        path: Notion-7.31.3.zip
        sha512: ZIPSHA==
        """)
    #expect(manifest?.artifact()?.url == "Notion-7.31.3.zip")
}

@Test func anX64OnlyManifestOffersNoArtifactAtAll() {
    // Detection without an install is an honest row; an install button that
    // fetches a build this Mac cannot run is not.
    let manifest = ElectronManifest.parse("""
        version: 3.0.0
        path: App-3.0.0-x64.zip
        sha512: SHA==
        """)
    #expect(manifest?.version == "3.0.0")
    #expect(manifest?.artifact(forArch: "arm64") == nil)
}

@Test func theTopLevelScalarsAreNotConfusedByTheNestedOnes() {
    // `url:` and `sha512:` appear at both levels meaning different things, and
    // `path`/`sha512` at the top must keep naming the primary artifact.
    let manifest = try! #require(ElectronManifest.parse("""
        version: 7.31.3
        files:
          - url: Notion-7.31.3.zip
            sha512: FILESHA==
            size: 126113061
        path: Notion-7.31.3.zip
        sha512: TOPSHA==
        releaseDate: '2026-08-27T01:59:39.485Z'
        """))
    #expect(manifest.version == "7.31.3")
    #expect(manifest.sha512 == "TOPSHA==")
    #expect(manifest.files.count == 1)
    #expect(manifest.files[0].sha512 == "FILESHA==")
    #expect(manifest.releaseDate == "2026-08-27T01:59:39.485Z")
}

@Test func aBodyWithNoVersionIsNotAManifest() {
    #expect(ElectronManifest.parse("files:\n  - url: x.zip\n") == nil)
    #expect(ElectronManifest.parse("") == nil)
}

@Test func artifactURLsResolveAgainstTheManifestsOwnDirectory() {
    // Same rule Sparkle applies to an enclosure, and for the same reason: the
    // manifest lists a bare filename.
    let manifest = ElectronManifest.parse("""
        version: 2.4.0
        path: Typeless-2.4.0-arm64.zip
        sha512: SHA==
        """)
    let url = manifest?.artifactURL(
        relativeTo: URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml")!)
    #expect(url == URL(string: "https://typeless-static.com/desktop-release/Typeless-2.4.0-arm64.zip"))
}

// MARK: - the source's own rules

@Test func theArchSiblingIsProbedOnlyBesideTheDefaultManifest() {
    // Only `latest-mac.yml` is asking "which architecture?".
    #expect(ElectronManifestSource.mayProbeArchSibling(
        URL(string: "https://desktop-release.notion-static.com/latest-mac.yml")!))
    // Typeless ships `channel: arm64` — already answered; probing would refetch
    // the same file.
    #expect(!ElectronManifestSource.mayProbeArchSibling(
        URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml")!))
    // And a named CHANNEL is not asking it at all. Probing `arm64-mac.yml` beside
    // `beta-mac.yml` would move a beta user onto the stable build whenever the
    // two agreed on a version — crossing trains, not architectures.
    #expect(!ElectronManifestSource.mayProbeArchSibling(
        URL(string: "https://updates.signal.org/desktop/beta-mac.yml")!))
}

@Test func theInstallerKindComesFromTheChosenArtifact() {
    #expect(ElectronManifestSource.kind(of: "Notion-arm64-7.31.3.zip") == .zip)
    #expect(ElectronManifestSource.kind(of: "Canva-1.124.1-universal.dmg") == .dmg)
    #expect(ElectronManifestSource.kind(of: nil) == nil)
    #expect(ElectronManifestSource.kind(of: "manifest.yml") == nil)
}

@Test func anAppWithNoElectronConfigIsNotThisSourcesBusiness() async throws {
    let app = InstalledApp(
        name: "Nothing", bundleID: "com.example.nothing", shortVersion: "1.0",
        buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Nothing.app"),
        isMASApp: false, sparkleFeedURL: nil)
    #expect(try await ElectronManifestSource().latestVersion(for: app) == nil)
}
