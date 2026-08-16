import Testing
import Foundation
@testable import DuoUpdaterCore

/// Google's two desktop apps, which need the registry's two newest tricks: an
/// update service that only answers a POST, and a download page that advertises
/// two products at once.

/// The Omaha reply, trimmed to the fields the recipe reads. Captured live on
/// 2026-08-16 by asking `update.googleapis.com` as version `0.0.0.0`; the
/// leading `)]}'` is Google's anti-JSON-hijacking prefix and is kept here on
/// purpose, because the pattern has to skip it.
private let omahaGeminiFixture = #"""
)]}'
{"response":{"server":"prod","protocol":"3.0","app":[{"appid":"com.google.GeminiMacOS","cohort":"1:3j3x:","status":"ok","cohortname":"Prod","updatecheck":{"status":"ok","urls":{"url":[{"codebase":"http://edgedl.me.gvt1.com/edgedl/release2/gemini/ca3wnj3nkm3xllpgbrzxdw4xjy_1.94.11.734/"},{"codebase":"https://edgedl.me.gvt1.com/edgedl/release2/gemini/ca3wnj3nkm3xllpgbrzxdw4xjy_1.94.11.734/"},{"codebase":"http://dl.google.com/release2/gemini/ca3wnj3nkm3xllpgbrzxdw4xjy_1.94.11.734/"},{"codebase":"https://dl.google.com/release2/gemini/ca3wnj3nkm3xllpgbrzxdw4xjy_1.94.11.734/"}]},"manifest":{"version":"1.94.11.734","packages":{"package":[{"hash_sha256":"e7d26399d63bee35aeafa0bb0edae3dbbf8cc1ba4451248aa517ae68edb1399e","size":126074911,"name":"Gemini-1.94.11.734.dmg","required":true}]}}}}]}}
"""#

/// Antigravity's electron-builder manifest, captured verbatim on 2026-08-16 from
/// the Cloud Run service its own updater polls.
private let antigravityFeedFixture = #"""
version: 2.8.1
files:
- url: https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-6512087774658560/darwin-arm/Antigravity.zip
  sha512: VtCAAII2RtMdkdZ8CoV4Kg3Qgljkyhze/6P+LJUgLBvIWLBq4WVNgGIEgadaUMxDxzmnxRCS0XVsH/QwOMMIeA==
  size: 165926585
path: Antigravity.zip
sha512: VtCAAII2RtMdkdZ8CoV4Kg3Qgljkyhze/6P+LJUgLBvIWLBq4WVNgGIEgadaUMxDxzmnxRCS0XVsH/QwOMMIeA==
stagingPercentage: 100
"""#

/// What the download page prints for the same release — the source this recipe
/// used first, kept as a fixture because it is what the version must NOT read.
/// It sells two products at once, and states this one with a build suffix the
/// shipped bundle does not report.
private let antigravityPageFixture = #"""
<a href="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/darwin-arm/Antigravity%20IDE.dmg">Download IDE</a>
<a href="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-6512087774658560/darwin-arm/Antigravity.dmg">Download</a>
"""#

private func googleRecipe(_ bundleID: String) -> VendorProbeRecipe? {
    VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }
}

struct GoogleProbeRecipeTests {

    @Test func geminiReadsTheManifestPastGooglesJSONPrefix() throws {
        let recipe = try #require(googleRecipe("com.google.GeminiMacOS"))
        #expect(VendorProbeRecipe.extractVersion(
            from: omahaGeminiFixture, pattern: recipe.versionPattern) == "1.94.11.734")
    }

    /// The service answers "noupdate" to anyone asking with the version they
    /// already have, so the body must ask as an ancient one. That is the whole
    /// trick, and an edit to "keep it current" would silently blind the probe.
    @Test func geminiAsksOmahaAsAnAncientVersion() throws {
        let recipe = try #require(googleRecipe("com.google.GeminiMacOS"))
        let body = try #require(recipe.requestBody)
        #expect(body.json.contains(#""version":"0.0.0.0""#))
        #expect(body.json.contains(#""appid":"com.google.GeminiMacOS""#))
        #expect(body.contentType == "application/json")
        // A body only means anything on the mode that POSTs it.
        if case .responseBody = recipe.mode {} else {
            Issue.record("a request body needs .responseBody mode")
        }
    }

    @Test func geminiJoinsTheCDNBaseWithThePackageName() throws {
        let recipe = try #require(googleRecipe("com.google.GeminiMacOS"))
        let spec = try #require(recipe.install)
        guard case .bodyTemplate(let template, let fields) = spec.urlSource else {
            Issue.record("expected a two-field template"); return
        }
        var url = template
        for (index, field) in fields.enumerated() {
            let part = try #require(
                VendorProbeRecipe.extractVersion(from: omahaGeminiFixture, pattern: field))
            url = url.replacingOccurrences(of: "{\(index)}", with: part)
        }
        #expect(url == "https://dl.google.com/release2/gemini/"
            + "ca3wnj3nkm3xllpgbrzxdw4xjy_1.94.11.734/Gemini-1.94.11.734.dmg")
    }

    /// The feed states the bundle's own string — a plain `2.8.1`, the same value
    /// the mounted artifact reports (2026-08-16).
    @Test func antigravityReadsTheFeedsMarketingVersion() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        #expect(VendorProbeRecipe.extractVersion(
            from: antigravityFeedFixture, pattern: recipe.versionPattern) == "2.8.1")
    }

    /// Why the feed replaced the download page: on that page the same release
    /// reads `2.8.1-6512087774658560`, and a second product (the IDE, 2.5.5) sits
    /// beside it. Both numbers are wrong for this row — the first would report an
    /// update installing can never clear, the second belongs to another app.
    @Test func antigravityNoLongerReadsTheAmbiguousDownloadPage() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        #expect(antigravityPageFixture.contains("2.5.5"))
        #expect(antigravityPageFixture.contains("2.8.1-6512087774658560"))
        #expect(VendorProbeRecipe.extractVersion(
            from: antigravityPageFixture, pattern: recipe.versionPattern) == nil,
            "the page must no longer satisfy this pattern at all")
    }

    @Test func antigravityInstallsTheCheckedZipFromTheFeed() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(
            from: antigravityFeedFixture, pattern: pattern)
            == "https://storage.googleapis.com/antigravity-public/"
            + "antigravity-hub/2.8.1-6512087774658560/darwin-arm/Antigravity.zip")
        #expect(spec.kind == .zip)
        // The feed publishes a base64 SHA-512 over the bytes actually served, so
        // the download is checksummed as well as signature-gated.
        let checksum = try #require(spec.checksumPattern)
        #expect(VendorProbeRecipe.extractVersion(
            from: antigravityFeedFixture, pattern: checksum)
            == "VtCAAII2RtMdkdZ8CoV4Kg3Qgljkyhze/6P+LJUgLBvIWLBq4WVNgGIEgadaUMxDxzmnxRCS0XVsH/QwOMMIeA==")
    }

    /// The app's updater identifies itself with an `x-user-staging-id` for staged
    /// rollout. We must not: the feed answers the same manifest without it, and
    /// that header is a per-machine identifier.
    @Test func antigravitySendsNoMachineIdentifier() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        #expect(recipe.identity == nil)
        #expect(recipe.requestBody == nil)
        #expect(!recipe.url.absoluteString.contains("staging"))
    }

    /// A request body is meaningless on the other modes, and every recipe that
    /// carries one must be a POST-only service — derived from the registry so a
    /// future recipe can't quietly break the rule.
    @Test func onlyResponseBodyRecipesCarryARequestBody() {
        for recipe in VendorProbeRegistry.recipes where recipe.requestBody != nil {
            if case .responseBody = recipe.mode { continue }
            Issue.record("\(recipe.bundleID) carries a request body on a non-body mode")
        }
    }
}
