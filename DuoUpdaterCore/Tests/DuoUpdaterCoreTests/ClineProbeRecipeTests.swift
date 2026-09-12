import Testing
import Foundation
@testable import DuoUpdaterCore

/// Cline Desktop ships two independently-identified apps — `bot.cline.app` and
/// `bot.cline.app.beta` — each reading its own Tauri updater manifest off a
/// rolling GitHub release tag. The addresses are not inferred from the URL shape:
/// `strings Contents/MacOS/cline-app` on each real bundle yields exactly one
/// `releases/download/…` address, and it is that channel's own.
///
/// Fixtures are the live manifests fetched 2026-09-12, trimmed only in `notes`
/// (free prose the probe never reads) and in the base64 `signature` blobs. Every
/// structural key is verbatim, **including the `windows-x86_64` platform** — the
/// one entry whose `url` is an `.exe`, and the reason both install patterns anchor
/// `_universal.app.tar.gz` instead of taking the first URL in the body.
private let clineStableManifest = """
{
  "version": "0.0.26",
  "notes": "- The composer now shows the current branch's GitHub pull request \\u2014 PR number, merge statu",
  "pub_date": "2026-09-11T07:46:41.714Z",
  "platforms": {
    "darwin-aarch64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.26/Cline_0.0.26_universal.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.26/Cline_0.0.26_universal.app.tar.gz"
    },
    "windows-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.26/Cline_0.0.26_x64-setup.exe"
    }
  }
}
"""

private let clineBetaManifest = """
{
  "version": "0.0.23-beta.1",
  "notes": "- Beta: configure and opt in to image generation under Customize \\u2192 Tools. Provider credent",
  "pub_date": "2026-09-03T01:46:32.549Z",
  "platforms": {
    "darwin-aarch64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.23-beta.1/Cline-Beta_0.0.23-beta.1_universal.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.23-beta.1/Cline-Beta_0.0.23-beta.1_universal.app.tar.gz"
    },
    "windows-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.23-beta.1/Cline-Beta_0.0.23-beta.1_x64-setup.exe"
    }
  }
}
"""

private func clineRecipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
    let id = channel == .beta ? "bot.cline.app.beta" : "bot.cline.app"
    return try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == id && $0.channel == channel },
        "no Cline recipe registered for \(id) [\(channel.rawValue)]")
}

/// The install URL exactly as `VendorProbeSource` recovers it for a
/// `.bodyPattern` spec — the same `extractVersion` call, so this cannot drift
/// into testing a different resolution than production performs.
private func resolvedInstallURL(_ recipe: VendorProbeRecipe, body: String) -> String? {
    guard case .bodyPattern(let pattern)? = recipe.install?.urlSource else { return nil }
    return VendorProbeRecipe.extractVersion(from: body, pattern: pattern)
}

@Test func clineStableProbeReadsTheVersionItsOwnUpdaterWouldInstall() throws {
    let recipe = try clineRecipe(.stable)
    #expect(recipe.url.absoluteString
        == "https://github.com/cline/cline/releases/download/desktop-latest/latest.json")
    #expect(VendorProbeRecipe.extractVersion(
        from: clineStableManifest, pattern: recipe.versionPattern) == "0.0.26")
}

@Test func clineBetaProbeReadsItsOwnTrack() throws {
    let recipe = try clineRecipe(.beta)
    #expect(recipe.url.absoluteString
        == "https://github.com/cline/cline/releases/download/desktop-beta/latest.json")
    #expect(VendorProbeRecipe.extractVersion(
        from: clineBetaManifest, pattern: recipe.versionPattern) == "0.0.23-beta.1")
}

/// The mutation this exists for: drop the closing `"` from the stable
/// `versionPattern`. The stable body still reads `0.0.26` and every other
/// assertion here still passes — but a `-beta.N` value now matches its numeric
/// PREFIX, so a beta manifest served to the stable rail would report `0.0.23`, a
/// version never published to that track. Both directions are asserted because a
/// pattern that matches the wrong track is silent end to end: it resolves, it
/// downloads, and the artifact is a real notarized build from the same vendor.
@Test func clineChannelPatternsRejectEachOthersManifests() throws {
    let stable = try clineRecipe(.stable)
    let beta = try clineRecipe(.beta)
    #expect(VendorProbeRecipe.extractVersion(
        from: clineBetaManifest, pattern: stable.versionPattern) == nil)
    #expect(VendorProbeRecipe.extractVersion(
        from: clineStableManifest, pattern: beta.versionPattern) == nil)
    #expect(resolvedInstallURL(stable, body: clineBetaManifest) == nil)
    #expect(resolvedInstallURL(beta, body: clineStableManifest) == nil)
}

/// The same manifest with `windows-x86_64` moved to the FRONT of `platforms`.
///
/// This exists because the natural test — "the resolved URL is the tarball" —
/// does not measure the anchoring at all. Verified by mutation 2026-09-12:
/// loosening the install pattern to `/Cline_[0-9][^"]*` leaves every assertion
/// against the real manifest passing, because the two darwin keys are listed
/// first and first-match lands on the tarball anyway. `platforms` is a JSON
/// OBJECT — its key order is the vendor's build script's business, not a
/// guarantee — so the ordering the real body happens to have is not something to
/// rest a safety property on.
private let clineStableManifestWindowsFirst = """
{
  "version": "0.0.26",
  "pub_date": "2026-09-11T07:46:41.714Z",
  "platforms": {
    "windows-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.26/Cline_0.0.26_x64-setup.exe"
    },
    "darwin-aarch64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.26/Cline_0.0.26_universal.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9t<trimmed>",
      "url": "https://github.com/cline/cline/releases/download/desktop-v0.0.26/Cline_0.0.26_universal.app.tar.gz"
    }
  }
}
"""

/// `platforms` lists three entries and the Windows one is an `.exe`. Anchoring on
/// `_universal.app.tar.gz` is what keeps that out; the two darwin keys name the
/// SAME universal tarball, so among the MATCHING entries first-match is correct
/// rather than an ordering bet.
@Test func clineInstallNeverResolvesTheWindowsInstallerEvenWhenItIsListedFirst() throws {
    let stable = try clineRecipe(.stable)
    let resolved = resolvedInstallURL(stable, body: clineStableManifestWindowsFirst)
    #expect(resolved == "https://github.com/cline/cline/releases/download/"
        + "desktop-v0.0.26/Cline_0.0.26_universal.app.tar.gz")
    #expect(resolved?.contains(".exe") == false)
}

@Test func clineInstallResolvesTheMacTarballAndNeverTheWindowsInstaller() throws {
    let stable = try resolvedInstallURL(try clineRecipe(.stable), body: clineStableManifest)
    #expect(stable == "https://github.com/cline/cline/releases/download/"
        + "desktop-v0.0.26/Cline_0.0.26_universal.app.tar.gz")
    let beta = try resolvedInstallURL(try clineRecipe(.beta), body: clineBetaManifest)
    #expect(beta == "https://github.com/cline/cline/releases/download/"
        + "desktop-v0.0.23-beta.1/Cline-Beta_0.0.23-beta.1_universal.app.tar.gz")
    for url in [stable, beta] {
        #expect(url?.hasSuffix(".app.tar.gz") == true)
        #expect(url?.contains(".exe") == false)
    }
}

/// Both tarballs were downloaded and unpacked 2026-09-12: each holds exactly one
/// `.app` at the archive root, `spctl` accepted as Notarized Developer ID under
/// Team 6F2AYU54ZH, universal (x86_64 + arm64). `.tarGz` is therefore the right
/// unpacking, and — per `VendorInstallerKind`'s own rule — the app installs
/// nothing outside its bundle, so it does not need `.pkg`.
@Test func clineInstallsAsATarballBecauseThatIsWhatTheManifestNames() throws {
    for channel in [ReleaseChannel.stable, .beta] {
        let recipe = try clineRecipe(channel)
        #expect(recipe.install?.kind == .tarGz, "\(channel.rawValue)")
    }
}

/// `pub_date` is what the Release Log gets each round; a vendor-probe recipe
/// contributes no history backfill, so this single field is the whole dating
/// story for these two rows.
@Test func clineProbeDatesTheReleaseItResolves() throws {
    for (channel, expected) in [(ReleaseChannel.stable, "2026-09-11T07:46:41.714Z"),
                                (.beta, "2026-09-03T01:46:32.549Z")] {
        let recipe = try clineRecipe(channel)
        let body = channel == .beta ? clineBetaManifest : clineStableManifest
        let pattern = try #require(recipe.publishedAtPattern)
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern) == expected)
        // The string must be one `ReleaseDate` can actually read — a pattern that
        // matches but yields nothing readable is a warning at runtime, not a test
        // failure, so assert the parse here.
        let fields = ReleaseDate.publishedFields(from: expected)
        #expect(fields.publishedAt != nil || fields.vendorDay != nil,
                "\(channel.rawValue): pub_date did not parse")
    }
}

/// The two channels are different apps on disk, which is why the beta recipe may
/// never accept a stable tag the way CotEditor's cyclical train does. Pinned so
/// that "let beta take the graduation" — correct for a shared-bundle-id vendor —
/// cannot be copied here, where it would replace `bot.cline.app.beta` with a
/// different bundle id entirely.
@Test func clineChannelsAreSeparateBundleIDsNotASharedOne() throws {
    #expect(try clineRecipe(.stable).bundleID == "bot.cline.app")
    #expect(try clineRecipe(.beta).bundleID == "bot.cline.app.beta")
    // `detect()` must reach `.beta` on its own — the recipe's channel field is a
    // declaration, not the thing that routes an installed copy to it.
    #expect(ReleaseChannel.detect(
        name: "Cline Beta", bundleID: "bot.cline.app.beta", keystoneChannel: nil,
        version: "0.0.23-beta.1") == .beta)
    #expect(ReleaseChannel.detect(
        name: "Cline", bundleID: "bot.cline.app", keystoneChannel: nil,
        version: "0.0.26") == .stable)
}

/// The manual-download link must belong to the row's own track. `cline.bot/desktop`
/// publishes ONLY the stable dmg and the Windows exe — measured 2026-09-12, a scan
/// of that page for any beta artifact URL returns nothing, though it says "beta" in
/// prose — so pointing the beta row there would hand a beta user a different bundle
/// id that installs alongside their copy instead of updating it.
///
/// The mutation: set the beta recipe's `downloadURL` to the stable one. Nothing
/// else in this file notices, because `downloadURL` takes no part in resolving a
/// version or an artifact.
@Test func clineBetaSendsManualDownloadsSomewhereBetaBuildsActuallyExist() throws {
    let stable = try clineRecipe(.stable).downloadURL?.absoluteString
    let beta = try clineRecipe(.beta).downloadURL?.absoluteString
    #expect(stable == "https://cline.bot/desktop")
    #expect(beta != stable)
    #expect(beta == "https://github.com/cline/cline/releases")
}
