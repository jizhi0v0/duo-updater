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

/// The links the Antigravity download page carries side by side, verbatim. The
/// first belongs to a DIFFERENT product (the IDE, on its own version line); it is
/// here so the tests can prove the pattern doesn't take it.
private let antigravityPageFixture = #"""
<a href="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/darwin-arm/Antigravity%20IDE.dmg">Download IDE</a>
<a href="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-6512087774658560/darwin-arm/Antigravity.dmg">Download</a>
<a href="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-6512087774658560/darwin-x64/Antigravity.dmg">Download (Intel)</a>
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

    /// The page's string is `2.8.1-6512087774658560`; the installed bundle reports
    /// a plain `2.8.1` (read off the mounted dmg, 2026-08-16). Capturing the
    /// suffix would report an update that installing can never clear.
    @Test func antigravityStopsBeforeTheBuildSuffix() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        #expect(VendorProbeRecipe.extractVersion(
            from: antigravityPageFixture, pattern: recipe.versionPattern) == "2.8.1")
    }

    /// The same page advertises the Antigravity *IDE* at 2.5.5. Anchoring to the
    /// hub path is what keeps one product's version off the other's row.
    @Test func antigravityIgnoresTheIDEOnTheSamePage() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        let ideOnly = antigravityPageFixture
            .split(separator: "\n")
            .filter { $0.contains("/antigravity/stable/") }
            .joined(separator: "\n")
        #expect(!ideOnly.isEmpty, "fixture must still carry the IDE link")
        #expect(VendorProbeRecipe.extractVersion(
            from: ideOnly, pattern: recipe.versionPattern) == nil)
    }

    @Test func antigravityInstallsTheArmHubBuild() throws {
        let recipe = try #require(googleRecipe("com.google.antigravity"))
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(
            from: antigravityPageFixture, pattern: pattern)
            == "https://storage.googleapis.com/antigravity-public/"
            + "antigravity-hub/2.8.1-6512087774658560/darwin-arm/Antigravity.dmg")
        #expect(spec.kind == .dmg)
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
