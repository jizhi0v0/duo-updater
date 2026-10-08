import Testing
import Foundation
@testable import DuoUpdaterCore

/// TRAE (`com.trae.app`, `Recipes/com-trae-app.swift`): the website's download
/// API, one recipe per architecture, anchored to `data.manifest.darwin`.
struct TraeProbeRecipeTests {

    /// `api.trae.ai/icube/api/v1/native/version/trae/latest` as served on
    /// 2026-10-08, trimmed: regions `sg` and `usttp` and most Linux packages are
    /// dropped. Key order is the vendor's. The `tob` block (3.5.87, the same
    /// bundle id) and the `solo` block (TraeWork 0.1.69) are kept because they
    /// carry `region: va` / `arch: apple` entries of their own — the trap. The
    /// real body has no line breaks; they are removed below.
    static let body = #"""
    {"success":true,"status":"success","message":"","data":{"manifest":{"win32":{"download":[{"region":"va","x64":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/win32/TraeCode-Setup-x64.exe"}],"versions":[{"region":"va","arch":"x64","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/win32/TraeCode-Setup-x64.exe","version":"3.5.104"}]},
    "darwin":{"download":[{"region":"va","apple":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-arm64.dmg","intel":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-x64.dmg"}],
    "versions":[{"region":"cn","arch":"apple","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-arm64.dmg","version":"3.5.104"},{"region":"cn","arch":"intel","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-x64.dmg","version":"3.5.104"},
    {"region":"va","arch":"apple","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-arm64.dmg","version":"3.5.104"},
    {"region":"va","arch":"intel","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-x64.dmg","version":"3.5.104"}]},
    "linux":{"download":[{"region":"va","arm64.tar.gz":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/linux/TraeCode-linux-arm64.tar.gz"}],"versions":[{"region":"va","arch":"arm64.tar.gz","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/linux/TraeCode-linux-arm64.tar.gz","version":"3.5.104"}]}},
    "solo":{"win32":{"download":[{"region":"va","x64":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.87414/win32/TraeWork-Setup-x64.exe"}],"versions":[{"region":"va","arch":"x64","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.87414/win32/TraeWork-Setup-x64.exe","version":"0.1.69"}]},
    "darwin":{"download":[{"region":"va","apple":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.87414/darwin/TraeWork-darwin-arm64.dmg","intel":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.87414/darwin/TraeWork-darwin-x64.dmg"}],"versions":[{"region":"cn","arch":"apple","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.87414/darwin/TraeWork-darwin-arm64.dmg","version":"0.1.69"},{"region":"cn","arch":"intel","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.87414/darwin/TraeWork-darwin-x64.dmg","version":"0.1.69"},{"region":"va","arch":"apple","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.87414/darwin/TraeWork-darwin-arm64.dmg","version":"0.1.69"},{"region":"va","arch":"intel","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.87414/darwin/TraeWork-darwin-x64.dmg","version":"0.1.69"}]}},
    "mobile":{"ios":{"url":{"va":"https://apps.apple.com/app/id6761401019"}}},
    "tob":{"manifest":{"win32":{"download":[{"region":"va","x64":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/win32/TraeCode-Setup-x64.exe"}],"versions":[{"region":"va","arch":"x64","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/win32/TraeCode-Setup-x64.exe","version":"3.5.87"}]},
    "darwin":{"download":[{"region":"va","apple":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-arm64.dmg","intel":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-x64.dmg"}],"versions":[{"region":"cn","arch":"apple","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-arm64.dmg","version":"3.5.87"},{"region":"cn","arch":"intel","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-x64.dmg","version":"3.5.87"},
    {"region":"va","arch":"apple","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-arm64.dmg","version":"3.5.87"},
    {"region":"va","arch":"intel","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-x64.dmg","version":"3.5.87"}]},
    "linux":{"download":[{"region":"va","arm64.tar.gz":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/linux/TraeCode-linux-arm64.tar.gz"}],"versions":[{"region":"va","arch":"arm64.tar.gz","url":"https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/linux/TraeCode-linux-arm64.tar.gz","version":"3.5.87"}]}},
    "solo":{"win32":{"download":[{"region":"va"}],"versions":[]},"darwin":{"download":[{"region":"va"}],"versions":[]}},"mobile":{"ios":{},"android":{}}}},"logId":"2026100822081406F4B757E864DB400FDD"}
    """#.replacingOccurrences(of: "\n", with: "")

    static var recipes: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.bundleID == "com.trae.app" }
    }

    static func recipe(_ arch: HostArch) throws -> VendorProbeRecipe {
        try #require(recipes.first { $0.hostRequirement?.architectures == [arch] })
    }

    static let dmg: [HostArch: String] = [
        .arm64: "https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-arm64.dmg",
        .x86_64: "https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-x64.dmg",
    ]

    static func read(_ recipe: VendorProbeRecipe, _ body: String) throws -> (version: String?, url: String?) {
        guard case .bodyPattern(let pattern) = try #require(recipe.install).urlSource else {
            Issue.record("\(recipe.recipeID) is not a bodyPattern install")
            return (nil, nil)
        }
        return (VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern),
                VendorProbeRecipe.extractVersion(from: body, pattern: pattern))
    }

    /// On every host exactly one recipe runs, and it is the one for that host.
    @Test func eachArchitectureRunsExactlyOneRecipe() {
        #expect(Self.recipes.count == 2)
        #expect(Self.recipes.allSatisfy { $0.channel == .stable && $0.install?.kind == .dmg })
        for arch in HostArch.allCases {
            let running = Self.recipes.filter { $0.runs(onOS: "26.0.0", arch: arch) }
            #expect(running.count == 1, "\(arch): \(running.map(\.recipeID))")
            #expect(running.first?.hostRequirement?.architectures == [arch])
        }
    }

    @Test func readsTheWebsiteBuildAndItsOwnArchitecturesDmg() throws {
        for arch in HostArch.allCases {
            let read = try Self.read(try Self.recipe(arch), Self.body)
            #expect(read.version == "3.5.104", "\(arch)")
            #expect(read.url == Self.dmg[arch], "\(arch)")
        }
    }

    /// The `va` entry for this architecture gone from `manifest.darwin`: nothing
    /// is read, although `tob` (3.5.87) and `solo` (0.1.69) still hold one.
    @Test func neverFallsThroughToAnotherBlock() throws {
        for arch in HostArch.allCases {
            let label = arch == .arm64 ? "apple" : "intel"
            let entry = #"{"region":"va","arch":"\#(label)","url":"\#(Self.dmg[arch]!)","version":"3.5.104"}"#
            #expect(Self.body.components(separatedBy: entry).count == 2)
            let gone = Self.body.replacingOccurrences(
                of: entry, with: entry.replacingOccurrences(of: #""va""#, with: #""zz""#))
            let read = try Self.read(try Self.recipe(arch), gone)
            #expect(read.version == nil, "\(arch) read \(read.version ?? "")")
            #expect(read.url == nil, "\(arch) read \(read.url ?? "")")
        }
    }

    /// `data.manifest` renamed, or `tob` listed first: still nothing from `tob`.
    @Test func neverReadsTheTobManifest() throws {
        let noManifest = Self.body.replacingOccurrences(
            of: #""data":{"manifest":"#, with: #""data":{"gone":"#)
        let tobStart = try #require(Self.body.range(of: #""tob":"#))
        let tobBlock = String(Self.body[tobStart.lowerBound..<Self.body.range(of: #","logId""#)!.lowerBound]
            .dropLast())   // the `}` closing `data`
        let tobFirst = Self.body
            .replacingOccurrences(of: "," + tobBlock, with: "")
            .replacingOccurrences(of: #""data":{"#, with: #""data":{"# + tobBlock + ",")
        #expect(tobFirst.count == Self.body.count)
        for body in [noManifest, tobFirst] {
            for arch in HostArch.allCases {
                let read = try Self.read(try Self.recipe(arch), body)
                #expect(read.version == nil && read.url == nil, "\(arch): \(read)")
            }
        }
    }

    /// The second lock behind `hostRequirement`: an entry labelled for this
    /// architecture that names the other architecture's dmg resolves no install.
    @Test func noRecipeResolvesTheOtherArchitecturesDmg() throws {
        let apple = #"{"region":"va","arch":"apple","url":"\#(Self.dmg[.arm64]!)""#
        let intel = #"{"region":"va","arch":"intel","url":"\#(Self.dmg[.x86_64]!)""#
        let swapped = Self.body
            .replacingOccurrences(of: apple, with: "APPLE")
            .replacingOccurrences(of: intel, with: #"{"region":"va","arch":"intel","url":"\#(Self.dmg[.arm64]!)""#)
            .replacingOccurrences(of: "APPLE", with: #"{"region":"va","arch":"apple","url":"\#(Self.dmg[.x86_64]!)""#)
        #expect(swapped != Self.body)
        for arch in HostArch.allCases {
            let read = try Self.read(try Self.recipe(arch), swapped)
            #expect(read.url == nil, "\(arch) accepted \(read.url ?? "")")
        }
    }

    /// The `va` entry is read even when an earlier region names something else,
    /// so the version and the URL come from one object.
    @Test func readsTheVaEntryNotTheFirstRegion() throws {
        let cnElsewhere = Self.body.replacingOccurrences(
            of: #""region":"cn","arch":"apple","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-arm64.dmg","version":"3.5.104""#,
            with: #""region":"cn","arch":"apple","url":"https://lf-cdn.trae.com.cn/obj/trae-com-cn/pkg/app/releases/stable/2.3.99999/darwin/TraeCode-darwin-arm64.dmg","version":"3.5.200""#)
        #expect(cnElsewhere != Self.body)
        let read = try Self.read(try Self.recipe(.arm64), cnElsewhere)
        #expect(read.version == "3.5.104")
        #expect(read.url == Self.dmg[.arm64])
    }

    /// The older shape of the same body: `manifest.darwin` with a `download`
    /// list and no `versions`. Nothing is read, rather than a `versions` list
    /// further on (`linux`, `solo`, `tob`).
    @Test func aDarwinBlockWithoutVersionsReadsNothing() throws {
        let start = try #require(Self.body.range(of: #"]},"linux":{"#))
        let versions = try #require(Self.body.range(
            of: #","versions":["#, options: .backwards,
            range: Self.body.range(of: #""manifest":{"#)!.upperBound..<start.lowerBound))
        let oldShape = Self.body.replacingCharacters(in: versions.lowerBound..<start.upperBound, with: #"},"linux":{"#)
        #expect(oldShape.contains(#"TraeCode-darwin-x64.dmg"}]},"linux":{"#))
        for arch in HostArch.allCases {
            let read = try Self.read(try Self.recipe(arch), oldShape)
            #expect(read.version == nil && read.url == nil, "\(arch): \(read)")
        }
    }

    /// The entry is found by its `region` and `arch` values, not by key order.
    @Test func entryFieldOrderDoesNotMatter() throws {
        let entry = #"{"region":"va","arch":"apple","url":"\#(Self.dmg[.arm64]!)","version":"3.5.104"}"#
        let reordered = #"{"version":"3.5.104","url":"\#(Self.dmg[.arm64]!)","arch":"apple","region":"va"}"#
        let read = try Self.read(try Self.recipe(.arm64), Self.body.replacingOccurrences(of: entry, with: reordered))
        #expect(read.version == "3.5.104")
        #expect(read.url == Self.dmg[.arm64])
    }

    /// Through the probe runtime against the fixture: 3.5.104 is an update for
    /// the 3.5.87 build and not for itself.
    @Test func probesTheFixtureEndToEnd() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.body, contentType: "application/json")
        defer { server.stop() }
        let source = VendorProbeSource(hostOSVersion: "26.0.0")
        for arch in HostArch.allCases {
            let outcome = await source.probeDiagnostic(try Self.recipe(arch).with(url: server.url))
            #expect(outcome.failure == nil, "\(arch): \(String(describing: outcome.failure))")
            let version = try #require(outcome.remote?.shortVersion)
            #expect(version == "3.5.104")
            #expect(outcome.remote?.downloadURL?.absoluteString == Self.dmg[arch])
            #expect(outcome.remote?.vendorInstallerKind == .dmg)
            #expect(VersionComparator.isNewer(version, than: "3.5.87"))
            #expect(!VersionComparator.isNewer(version, than: "3.5.104"))
        }
    }
}
