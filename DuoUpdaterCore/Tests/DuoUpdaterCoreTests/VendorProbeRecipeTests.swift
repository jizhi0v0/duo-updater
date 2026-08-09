import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func intelliJVersionPatternSurvivesAFourthSegment() {
    // JetBrains shipped "2026.2.0.1" against a pattern pinned to exactly three
    // segments, so it matched nothing and the row fell to "unknown" — a silent
    // failure, since a probe that resolves no version isn't an error anywhere.
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "com.jetbrains.intellij" }
    let pattern = try! #require(recipe?.versionPattern)
    func version(in body: String) -> String? {
        guard let m = body.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(body[m])
        return match.range(of: #"[0-9]{4}(\.[0-9]+)+"#, options: .regularExpression)
            .map { String(match[$0]) }
    }
    #expect(version(in: #"{"version":"2026.2.0.1","build":"262.8665.337"}"#) == "2026.2.0.1")
    #expect(version(in: #"{"version":"2026.1.4"}"#) == "2026.1.4")
    // `majorVersion` is 2-component and must never be what we pick up.
    #expect(version(in: #"{"majorVersion":"2026.2"}"#) == nil)
}

@Test func whatsAppPatternStripsTheDownloadFilenamesExtraLeadingSegment() {
    // The bundle reports 26.22.20; the file is WhatsApp-2.26.31.27.dmg. Capturing
    // the whole thing would compare "2.26.31.27" against "26.22.20", read the
    // installed copy as NEWER, and hide every update forever.
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "net.whatsapp.WhatsApp" }
    let pattern = try! #require(recipe?.versionPattern)
    let location = "https://scontent.xx.fbcdn.net/v/t39/1000_n.dmg/WhatsApp-2.26.31.27.dmg?_nc_cat=107"
    let range = try! #require(location.range(of: pattern, options: .regularExpression))
    let matched = String(location[range])
    let version = try! #require(matched.range(of: #"[0-9]+\.[0-9]+\.[0-9]+(?=\.dmg)"#, options: .regularExpression))
    #expect(String(matched[version]) == "26.31.27")
    #expect(VersionComparator.isNewer("26.31.27", than: "26.22.20"))
    // The unstripped form is what this guards against.
    #expect(!VersionComparator.isNewer("2.26.31.27", than: "26.22.20"))
}

@Test func uuRemotePatternReadsTheVersionedPackageName() {
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "com.netease.uuremote" }
    let pattern = try! #require(recipe?.versionPattern)
    let location = "https://a56.gdl.netease.com/uuyc_4.35.0.pkg?key1=abc&key2=def"
    let range = try! #require(location.range(of: pattern, options: .regularExpression))
    #expect(String(location[range]) == "uuyc_4.35.0.pkg")
    // Both are read from a Location header, never by following the redirect: the
    // target is the installer itself (259 MB / 69 MB).
    #expect(recipe?.followRedirects == false)
    // One-click: pkg, handed to macOS's installer for the user to confirm.
    #expect(recipe?.install?.kind == .pkg)
}

// MARK: - Signal

/// Real `beta-mac.yml` / `latest-mac.yml` bodies, 2026-08-09 (sha512 values
/// truncated — nothing reads them, see `signalRecipesCarryNoChecksum`).
private enum SignalFeedFixture {
    static let beta = """
        version: 8.23.0-beta.1
        files:
          - url: signal-desktop-beta-mac-x64-8.23.0-beta.1.zip
            sha512: +eoIsBwXULOiZGrNqFahggIyL9N/9ku+qr/1d6B5jmpUu+QZ1q9f
            size: 149001180
          - url: signal-desktop-beta-mac-arm64-8.23.0-beta.1.zip
            sha512: TX5BDJafhAthnojxnyraqXlhAuIz9+B84u0Eara4vH6R4+p0DkKc
            size: 144039668
          - url: signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg
            sha512: nQpe7uU/zhXzXmrkTBaaijVw3VEzJ7V0RLB5IzBzhrDXYyRhNQRP
            size: 263191264
        path: signal-desktop-beta-mac-x64-8.23.0-beta.1.zip
        sha512: +eoIsBwXULOiZGrNqFahggIyL9N/9ku+qr/1d6B5jmpUu+QZ1q9f
        vendor:
          minOSVersion: 21.0.1
        releaseDate: '2026-08-05T23:09:31.413Z'
        """

    static let stable = """
        version: 8.22.0
        files:
          - url: signal-desktop-mac-x64-8.22.0.zip
            sha512: fX3AK4YIeoHrl30iB3hc4YsBaImssX8NGg0Zoma+DJDdeJL6Y9NV
            size: 148929566
          - url: signal-desktop-mac-arm64-8.22.0.zip
            sha512: 0yLqy1+k93lqmITMfxmTC8QlZlVaD+9vZT7pfyeH+IB18lMn4Xhw
            size: 143982985
          - url: signal-desktop-mac-universal-8.22.0.dmg
            sha512: tnwYvOYmHj0U5V/Xdta4qsfhDzSg+Fxffry731Dk7HVShbxoCt6C
            size: 263091467
        path: signal-desktop-mac-x64-8.22.0.zip
        sha512: fX3AK4YIeoHrl30iB3hc4YsBaImssX8NGg0Zoma+DJDdeJL6Y9NV
        vendor:
          minOSVersion: 21.0.1
        releaseDate: '2026-08-05T21:53:25.563Z'
        """
}

/// Mirrors `VendorProbeSource.resolveInstall`'s `.bodyPatternRelative` branch,
/// which is private: capture group 1 is a filename, resolved against `base`.
private func resolveRelativeInstallURL(
    _ recipe: VendorProbeRecipe, body: String
) -> URL? {
    guard case .bodyPatternRelative(let pattern, let base)? = recipe.install?.urlSource,
          let raw = VendorProbeRecipe.extractVersion(from: body, pattern: pattern)
    else { return nil }
    return URL(string: raw, relativeTo: base)?.absoluteURL
}

private func signalRecipe(_ bundleID: String) -> VendorProbeRecipe {
    VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }!
}

/// Signal names the beta dmg `signal-desktop-beta-mac-universal-…`, with a
/// `beta-` segment stable doesn't have. The beta spec reused stable's pattern, so
/// it matched nothing: the version still resolved, one-click just vanished into
/// detection-only with no error anywhere. Each channel's pattern is pinned to its
/// own spelling, and must NOT match the other channel's feed — a cross-match would
/// hand a beta install a stable build (or vice versa).
@Test func signalInstallPatternsAreChannelSpecific() {
    let stable = signalRecipe("org.whispersystems.signal-desktop")
    let beta = signalRecipe("org.whispersystems.signal-desktop-beta")
    #expect(beta.channel == .beta)

    #expect(
        resolveRelativeInstallURL(beta, body: SignalFeedFixture.beta)?.absoluteString
            == "https://updates.signal.org/desktop/signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg")
    #expect(
        resolveRelativeInstallURL(stable, body: SignalFeedFixture.stable)?.absoluteString
            == "https://updates.signal.org/desktop/signal-desktop-mac-universal-8.22.0.dmg")

    // The regression itself: stable's pattern is blind to the beta filename.
    #expect(resolveRelativeInstallURL(stable, body: SignalFeedFixture.beta) == nil)
    // And the fix stays one-way — beta's pattern must not claim a stable build.
    #expect(resolveRelativeInstallURL(beta, body: SignalFeedFixture.stable) == nil)

    // Only the universal dmg is installable; the per-arch zips must never win.
    for (recipe, body) in [(stable, SignalFeedFixture.stable), (beta, SignalFeedFixture.beta)] {
        let url = resolveRelativeInstallURL(recipe, body: body)?.absoluteString ?? ""
        #expect(url.hasSuffix(".dmg"))
        #expect(url.contains("-universal-"))
    }
}

/// Signal's CI signs + staples the dmg AFTER electron-builder writes the yml, so
/// the feed's sha512 covers 2563 fewer bytes than the CDN serves. A checksum gate
/// built from that hash aborts every install (`VendorInstaller` gate 1 throws), so
/// both recipes deliberately ship without one and lean on the signature/Team/
/// bundle-id gates instead.
@Test func signalRecipesCarryNoChecksum() {
    for id in ["org.whispersystems.signal-desktop", "org.whispersystems.signal-desktop-beta"] {
        let spec = try! #require(signalRecipe(id).install)
        #expect(spec.kind == .dmg)
        #expect(spec.checksumPattern == nil)
    }
}

@Test func whatsAppAndUURemoteInstallFromTheirLatestRedirect() {
    // The install must re-resolve the redirect at download time rather than pin the
    // version that was current when the recipe was written — these endpoints always
    // point at the newest package.
    for id in ["net.whatsapp.WhatsApp", "com.netease.uuremote"] {
        let recipe = try! #require(VendorProbeRegistry.recipes.first { $0.bundleID == id })
        let spec = try! #require(recipe.install)
        guard case .redirect(let url) = spec.urlSource else {
            Issue.record("\(id) should install from its redirect endpoint")
            continue
        }
        #expect(url == recipe.url)
    }
}
