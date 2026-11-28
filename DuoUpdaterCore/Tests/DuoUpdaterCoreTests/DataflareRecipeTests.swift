import Foundation
import Testing
@testable import DuoUpdaterCore

struct DataflareRecipeTests {
    private static let archive = "https://assets.dataflare.app/release/darwin/aarch64/Dataflare.app.tar.gz"
    private static let manifest = #"{"version":"3.2.6","url":"\#(archive)","signature":"dW50cnVzdGVkIGNvbW1lbnQ="}"#

    @Test func resolvesVersionedNativeDMGFromOfficialManifest() async throws {
        let probe = try #require(app_dataflare_desktop.set.probes.first)
        let reordered = #"{"url":"\#(Self.archive)","signature":"dW50cnVzdGVkIGNvbW1lbnQ=","version":"3.2.6"}"#
        for body in [Self.manifest, reordered] {
            let server = try RecipeVerificationTests.StubServer(body: body, contentType: "application/json")
            defer { server.stop() }
            let remote = await VendorProbeSource().probeDiagnostic(probe.with(url: server.url)).remote
            #expect(remote?.shortVersion == "3.2.6")
            #expect(remote?.downloadURL?.absoluteString
                == "https://assets.dataflare.app/release/darwin/aarch64/Dataflare-3.2.6.dmg")
            #expect(remote?.vendorInstallerKind == .dmg)
        }
        #expect(probe.hostRequirement?.architectures == [.arm64])
        #expect(probe.channel == .stable)
    }

    @Test func rejectsPreviewAndNonNativeManifests() throws {
        let probe = try #require(app_dataflare_desktop.set.probes.first)
        let invalid = [
            Self.manifest.replacingOccurrences(of: "3.2.6", with: "3.2.6-beta.1"),
            Self.manifest.replacingOccurrences(of: "/aarch64/", with: "/x86_64/"),
            Self.manifest.replacingOccurrences(of: "assets.dataflare.app", with: "example.org"),
            #"{"error":\#(Self.manifest)}"#,
            #"{"error":"use \"version\":\"3.2.6\"","url":"\#(Self.archive)"}"#,
            "",
        ]
        for body in invalid {
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: probe.versionPattern) == nil)
        }
    }

    @Test func preservesDatedEntriesAndChangesHeading() throws {
        let notes = """
            ## v3.2.6

            **Published:** `2026-10-31T12:00:00Z`

            **Changes**

            - Fix DuckDB version

            ## v3.2.5

            **Published:** `2026-10-23T12:00:00Z`

            **Changes**

            - Add `Opper` as an AI provider
            """
        let recipe = try #require(app_dataflare_desktop.set.changelogs.first)
        let entries = try #require(ChangelogExtractor.extract(from: notes, using: recipe)).entries
        #expect(entries.map(\.version) == ["3.2.6", "3.2.5"])
        #expect(entries.map(\.date) == ["2026-10-31", "2026-10-23"])
        #expect(entries.map(\.content) == [
            [.heading("Changes"), .note("Fix DuckDB version")],
            [.heading("Changes"), .note("Add Opper as an AI provider")],
        ])
    }
}
