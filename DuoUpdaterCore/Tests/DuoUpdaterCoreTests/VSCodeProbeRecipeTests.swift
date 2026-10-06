import Foundation
import Testing
@testable import DuoUpdaterCore

/// `update.code.visualstudio.com/api/update/darwin-arm64/stable/latest`,
/// captured verbatim 2026-10-07.
private let vsCodeStableFixture = #"""
{"url":"https://vscode.download.prss.microsoft.com/dbazure/download/stable/07f806f999227108933c2e30515b26eecc1fda74/VSCode-darwin-arm64.zip","name":"1.140.0","version":"07f806f999227108933c2e30515b26eecc1fda74","productVersion":"1.140.0","hash":"bae275acfae29dbcbb93118c3b46d787b632051f","timestamp":1790759204424,"sha256hash":"86a64f1cc9f4e0b5fc44969530994742f4bd61e7b98d9637238c5e24b26593b0","supportsFastUpdate":true,"notes":"07f806f999227108933c2e30515b26eecc1fda74"}
"""#

/// The `insider` track's answer, same day.
private let vsCodeInsidersFixture = #"""
{"url":"https://vscode.download.prss.microsoft.com/dbazure/download/insider/2a59476c9bfcb90b3ddc372c36762471b7dfad1c/VSCode-darwin-arm64.zip","name":"1.141.0-insider","version":"2a59476c9bfcb90b3ddc372c36762471b7dfad1c","productVersion":"1.141.0-insider","hash":"2a2a2356b140b14cbd45dc3c1acd23b3504a4385","timestamp":1791275459327,"sha256hash":"b92a9e0c09db9c2bca34f82bd400da345a89a8263fde82510d95b072a128c5c6","supportsFastUpdate":true,"notes":"2a59476c9bfcb90b3ddc372c36762471b7dfad1c"}
"""#

/// VS Code stable and Insiders: one-click takes the zip the update API names and
/// checks it against the `sha256hash` in the same response.
@Suite struct VSCodeProbeRecipeTests {

    private static let cases: [(bundleID: String, body: String, url: String, digest: String)] = [
        ("com.microsoft.VSCode", vsCodeStableFixture,
         "https://vscode.download.prss.microsoft.com/dbazure/download/stable/"
            + "07f806f999227108933c2e30515b26eecc1fda74/VSCode-darwin-arm64.zip",
         "86a64f1cc9f4e0b5fc44969530994742f4bd61e7b98d9637238c5e24b26593b0"),
        ("com.microsoft.VSCodeInsiders", vsCodeInsidersFixture,
         "https://vscode.download.prss.microsoft.com/dbazure/download/insider/"
            + "2a59476c9bfcb90b3ddc372c36762471b7dfad1c/VSCode-darwin-arm64.zip",
         "b92a9e0c09db9c2bca34f82bd400da345a89a8263fde82510d95b072a128c5c6"),
    ]

    private func recipe(_ bundleID: String) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
    }

    private func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern for \(recipe.bundleID)")
            return ""
        }
        #expect(spec.kind == .zip)
        return pattern
    }

    /// The url and the digest come out of the same body. A `.redirect` would be
    /// followed only when Update is pressed, by which time a new build may have
    /// moved it off the file the digest describes.
    @Test func eachTrackInstallsTheZipItsOwnBodyNames() throws {
        for c in Self.cases {
            let pattern = try installPattern(try recipe(c.bundleID))
            #expect(VendorProbeRecipe.extractVersion(from: c.body, pattern: pattern) == c.url,
                    "\(c.bundleID)")
        }
    }

    /// Neither track's pattern accepts the other track's zip: same host, same
    /// filename, only the `/stable/` vs `/insider/` segment differs.
    @Test func neitherTrackResolvesTheOtherTracksZip() throws {
        let stable = try installPattern(try recipe("com.microsoft.VSCode"))
        let insiders = try installPattern(try recipe("com.microsoft.VSCodeInsiders"))
        #expect(VendorProbeRecipe.extractVersion(from: vsCodeInsidersFixture, pattern: stable) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: vsCodeStableFixture, pattern: insiders) == nil)
    }

    /// `sha256hash` (hex) is read, in the SHA-256 slot — not the 40-hex `hash`
    /// (SHA-1) and not the commit.
    @Test func eachTrackChecksTheZipAgainstTheResponsesSHA256() throws {
        for c in Self.cases {
            let spec = try #require(try recipe(c.bundleID).install)
            #expect(spec.checksumFormat == .sha256Hex, "\(c.bundleID)")
            let pattern = try #require(spec.checksumPattern)
            #expect(VendorProbeRecipe.extractVersion(from: c.body, pattern: pattern) == c.digest,
                    "\(c.bundleID)")
        }
    }

    /// A response without `sha256hash` reads nothing rather than the SHA-1 beside it.
    @Test func aResponseWithoutTheDigestReadsNone() throws {
        for c in Self.cases {
            let pattern = try #require(try recipe(c.bundleID).install?.checksumPattern)
            let body = c.body.replacingOccurrences(of: #""sha256hash":"\#(c.digest)","#, with: "")
            #expect(body != c.body)
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern) == nil,
                    "\(c.bundleID)")
        }
    }
}
