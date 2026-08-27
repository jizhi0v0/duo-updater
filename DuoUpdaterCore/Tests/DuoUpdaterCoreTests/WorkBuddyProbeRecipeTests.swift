import Testing
import Foundation
@testable import DuoUpdaterCore

/// WorkBuddy's four recipes: two sites (international / China), each crossed with
/// the two macOS architectures the vendor ships.
///
/// The whole suite is DERIVED from the registry — the recipes are found by bundle
/// id prefix and every per-recipe expectation is computed from that recipe's own
/// `variant`, so a fifth recipe (or a renamed variant) is covered the day it lands
/// instead of the day someone remembers to extend a hand-written list.
struct WorkBuddyProbeRecipeTests {

    /// The two sites and the version each served when the recipes were written.
    /// `body` is the endpoint's response captured verbatim on 2026-08-27.
    private struct Site {
        let bundleID: String
        let host: String
        /// `CFBundleShortVersionString` of the real bundle for that train, read
        /// off the vendor's own DMG — deliberately the THREE-segment string, which
        /// is the point of the version pattern.
        let installedShortVersion: String
        let bodies: [String: String]  // variant slug → captured response body
    }

    private static let sites: [Site] = [
        Site(
            bundleID: "com.workbuddy.workbuddy-ai",
            host: "www.workbuddy.ai",
            installedShortVersion: "5.4.2",
            bodies: [
                "arm64": #"{"version":"5.4.2.36857725","url":"https://codebuddy-1328495429.cos.accelerate.myqcloud.com/workbuddy/saas/darwin-arm64/WorkBuddy-darwin-arm64-5.4.2.36857725-d74591c4.zip","productVersion":"5.4.2.36857725","sha256hash":"5d28d2b009dddb661ca8f2b1821dc57f853132071ae23101465f385d016a7743","timestamp":1787580925,"hash":"","name":"","supportsFastUpdate":false}"#,
                "x64": #"{"version":"5.4.2.36857725","url":"https://codebuddy-1328495429.cos.accelerate.myqcloud.com/workbuddy/saas/darwin-x64/WorkBuddy-darwin-x64-5.4.2.36857725-d74591c4.zip","productVersion":"5.4.2.36857725","sha256hash":"0f1dce554df89f5e50db04823144e01faee7ea88483875cdc7066406d15b362b","timestamp":1787580925,"hash":"","name":"","supportsFastUpdate":false}"#,
            ]),
        Site(
            bundleID: "com.workbuddy.workbuddy",
            host: "www.workbuddy.cn",
            installedShortVersion: "5.3.14",
            bodies: [
                "arm64": #"{"version":"5.3.14.36279234","url":"https://download.codebuddy.cn/workbuddy/saas/darwin-arm64/WorkBuddy-darwin-arm64-5.3.14.36279234-825709d4.zip","productVersion":"5.3.14.36279234","sha256hash":"a7c18fecd2939f8bd7a00ab5accdd905dbc5bbd5927291c9c5762541c1bd6a61","timestamp":1787002434,"hash":"","name":"","supportsFastUpdate":false}"#,
                "x64": #"{"version":"5.3.14.36279234","url":"https://download.codebuddy.cn/workbuddy/saas/darwin-x64/WorkBuddy-darwin-x64-5.3.14.36279234-825709d4.zip","productVersion":"5.3.14.36279234","sha256hash":"25fe856763ff917e3086135f445c1016085ef7130433661994840e7a4c0a09ce","timestamp":1787002434,"hash":"","name":"","supportsFastUpdate":false}"#,
            ]),
    ]

    private static let recipes = VendorProbeRegistry.recipes.filter {
        $0.bundleID.hasPrefix("com.workbuddy.")
    }

    private static func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            throw RecipeShapeError.notABodyPattern(recipe.recipeID)
        }
        #expect(spec.kind == .zip)
        return pattern
    }

    private enum RecipeShapeError: Error { case notABodyPattern(String) }

    // MARK: - registry shape

    /// The two sites are two APPS, not two channels: distinct bundle ids, both
    /// stable. Nothing about this app family may ever grow a channel, because a
    /// channel is the one axis that could route one site's artifact at the other
    /// site's install.
    @Test func bothSitesAreSeparateStableApps() throws {
        #expect(Set(Self.recipes.map(\.bundleID)) == Set(Self.sites.map(\.bundleID)))
        #expect(Self.recipes.allSatisfy { $0.channel == .stable })
        #expect(!Self.recipes.isEmpty)
    }

    /// Each (bundle id, channel) group carries one recipe per architecture, and
    /// each declares the `hostRequirement` that makes exactly one of them eligible
    /// on any given Mac. Without this the arm64 recipe would out-rank — and then
    /// hand an unrunnable zip to — an Intel install.
    @Test func eachSiteSplitsByArchitectureAndOnlyByArchitecture() throws {
        let byBundle = Dictionary(grouping: Self.recipes, by: \.bundleID)
        for (bundleID, group) in byBundle {
            #expect(Set(group.compactMap(\.variant)) == ["arm64", "x64"],
                    "\(bundleID) should have exactly an arm64 and an x64 recipe")
            for recipe in group {
                let slug = try #require(recipe.variant)
                let expected: HostArch = slug == "arm64" ? .arm64 : .x86_64
                let requirement = try #require(
                    recipe.hostRequirement, "\(recipe.recipeID) has no hostRequirement")
                #expect(requirement.architectures == [expected])
                // Architecture only — no OS floor was observed for either train,
                // and inventing one would silently strand machines.
                #expect(requirement.minimumSystemVersion == nil)
                #expect(requirement.isSatisfied(byOS: "26.0", arch: expected))
                #expect(!requirement.isSatisfied(
                    byOS: "26.0", arch: expected == .arm64 ? .x86_64 : .arm64))
            }
        }
    }

    /// The endpoint is a "should I update?" service: handing it the version you
    /// already run answers 204 No Content. `version=0.0.0` is what makes it a
    /// latest-version query, so its presence is pinned, as is the `platform` slug
    /// agreeing with the recipe's own variant.
    @Test func everyEndpointAsksAsAnImpossiblyOldClient() throws {
        for recipe in Self.recipes {
            let slug = try #require(recipe.variant)
            let url = recipe.url.absoluteString
            #expect(url.contains("version=0.0.0"),
                    "\(recipe.recipeID) would get a 204 for an up-to-date install")
            #expect(url.contains("platform=workbuddy-darwin-\(slug)"),
                    "\(recipe.recipeID) asks about the wrong architecture")
            #expect(url.hasPrefix("https://"))
            // No account identifiers on the wire: the app's own `x-user-id` /
            // `x-tenant-id` parameters are optional and we send neither.
            #expect(!url.contains("x-user-id") && !url.contains("x-tenant-id"))
            #expect(recipe.identities.isEmpty && recipe.track == nil)
        }
    }

    /// Each recipe reads the site whose bundle id it targets. A crossed host would
    /// offer the CN train to an international install and vice versa — the two
    /// have independent version numbers, so it would be silent and permanent.
    @Test func eachRecipeReadsItsOwnSite() throws {
        for site in Self.sites {
            for recipe in Self.recipes where recipe.bundleID == site.bundleID {
                #expect(recipe.url.host() == site.host,
                        "\(recipe.recipeID) probes \(recipe.url.host() ?? "?"), not \(site.host)")
            }
        }
    }

    // MARK: - the version scheme (the phantom-update trap)

    /// The endpoint reports four segments; the installed bundle reports three, and
    /// the fourth appears in NEITHER `CFBundleShortVersionString` nor
    /// `CFBundleVersion`. Comparing the raw field would read "update available"
    /// forever, so the pattern must discard it — and must leave the compared value
    /// exactly equal to what the real bundle reports.
    @Test func theBuildCounterIsDiscardedSoAnUpToDateInstallCompensatesEqual() throws {
        for site in Self.sites {
            for recipe in Self.recipes where recipe.bundleID == site.bundleID {
                let slug = try #require(recipe.variant)
                let body = try #require(site.bodies[slug])
                let version = try #require(
                    VendorProbeRecipe.extractVersion(
                        from: body, pattern: recipe.versionPattern),
                    "\(recipe.recipeID) resolved no version from its captured body")
                #expect(version == site.installedShortVersion)
                #expect(VersionComparator.compare(version, site.installedShortVersion)
                    == .orderedSame,
                    "\(recipe.recipeID) would report a phantom update against an install of \(site.installedShortVersion)")
                // The build counter is in the body and must not be in the answer.
                #expect(body.contains("\(site.installedShortVersion)."))
                #expect(!version.contains("\(site.installedShortVersion)."))
                // It is the marketing version, not a build: routing it into the
                // build field would compare it against `CFBundleVersion` instead.
                #expect(!recipe.versionIsBuild)
            }
        }
    }

    /// A vendor that drops back to a plain three-segment version must not silently
    /// take the probe dark — the fourth segment is optional in the pattern.
    @Test func aThreeSegmentVersionStillMatches() throws {
        let recipe = try #require(Self.recipes.first)
        let body = #"{"productVersion":"6.0.0","timestamp":1787580925}"#
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == "6.0.0")
    }

    /// The pattern reads `productVersion` — the field the app's own updater
    /// prefers — and not some other version-shaped number in the document.
    @Test func theVersionComesFromProductVersion() throws {
        let recipe = try #require(Self.recipes.first)
        let body = #"{"version":"9.9.9.1","productVersion":"5.4.2.36857725","timestamp":1787580925}"#
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == "5.4.2")
    }

    // MARK: - the install artifact

    /// Every recipe resolves the zip its own captured body names.
    @Test func eachRecipeInstallsTheArtifactItsOwnBodyNames() throws {
        for site in Self.sites {
            for recipe in Self.recipes where recipe.bundleID == site.bundleID {
                let slug = try #require(recipe.variant)
                let body = try #require(site.bodies[slug])
                let pattern = try Self.installPattern(recipe)
                let resolved = try #require(
                    VendorProbeRecipe.extractVersion(from: body, pattern: pattern),
                    "\(recipe.recipeID) resolved no install URL")
                #expect(resolved.hasSuffix(".zip"))
                #expect(resolved.contains("/darwin-\(slug)/"))
                #expect(resolved.contains("WorkBuddy-darwin-\(slug)-"))
            }
        }
    }

    /// The guard that makes the architecture split real: an arm64 recipe fed the
    /// x64 response (and vice versa) must resolve NOTHING rather than quietly hand
    /// back a bundle this Mac cannot run. `hostRequirement` already keeps the wrong
    /// recipe from being selected; this is the second lock, for the day the
    /// endpoint starts ignoring its own `platform` parameter.
    @Test func noRecipeResolvesTheOtherArchitecturesArtifact() throws {
        for site in Self.sites {
            for recipe in Self.recipes where recipe.bundleID == site.bundleID {
                let slug = try #require(recipe.variant)
                let otherSlug = slug == "arm64" ? "x64" : "arm64"
                let otherBody = try #require(site.bodies[otherSlug])
                let pattern = try Self.installPattern(recipe)
                #expect(VendorProbeRecipe.extractVersion(
                    from: otherBody, pattern: pattern) == nil,
                    "\(recipe.recipeID) accepted the \(otherSlug) artifact")
            }
        }
    }

    /// The sibling guard to the architecture one, on the other axis: the two
    /// sites' artifact paths are IDENTICAL (`/workbuddy/saas/darwin-<arch>/…`),
    /// so only the host says which site a zip came from. Fed the other site's
    /// response, a recipe must resolve nothing rather than install the other
    /// site's build — which the Team ID gate could never catch, both sites being
    /// signed by the same team.
    @Test func noRecipeResolvesTheOtherSitesArtifact() throws {
        for site in Self.sites {
            let others = Self.sites.filter { $0.bundleID != site.bundleID }
            #expect(!others.isEmpty)
            for recipe in Self.recipes where recipe.bundleID == site.bundleID {
                let slug = try #require(recipe.variant)
                let pattern = try Self.installPattern(recipe)
                for other in others {
                    // Same architecture, other site: the ONLY difference is the host.
                    let otherBody = try #require(other.bodies[slug])
                    #expect(VendorProbeRecipe.extractVersion(
                        from: otherBody, pattern: pattern) == nil,
                        "\(recipe.recipeID) accepted \(other.bundleID)'s artifact")
                }
            }
        }
    }

    /// `sha256hash` is a SHA-256 hex digest; `checksumPattern` consumes base64
    /// SHA-512. Asserting it would fail every download, so it is deliberately
    /// unset and the Team ID signature gate carries the swap.
    @Test func theSHA256FieldIsDeliberatelyUnused() throws {
        for recipe in Self.recipes {
            let spec = try #require(recipe.install)
            #expect(spec.checksumPattern == nil)
        }
    }

    // MARK: - the publish date

    /// `timestamp` is a bare Unix epoch in seconds, which `ReleaseDate` accepts.
    @Test func theTimestampParsesAsAPublishDate() throws {
        for site in Self.sites {
            for recipe in Self.recipes where recipe.bundleID == site.bundleID {
                let slug = try #require(recipe.variant)
                let body = try #require(site.bodies[slug])
                let pattern = try #require(recipe.publishedAtPattern)
                let raw = try #require(
                    VendorProbeRecipe.extractVersion(from: body, pattern: pattern))
                let date = try #require(ReleaseDate.parse(raw),
                                        "\(recipe.recipeID): '\(raw)' did not parse")
                // Sanity: inside the window this vendor could plausibly have
                // published in, so a millisecond epoch (year ~58000) would fail.
                #expect(date > Date(timeIntervalSince1970: 1_700_000_000))
                #expect(date < Date(timeIntervalSince1970: 2_000_000_000))
            }
        }
    }

    // MARK: - where the user is sent

    /// The probe endpoint returns raw JSON, so neither the manual-download link nor
    /// the changelog may fall back to it.
    @Test func theUserIsSentToAPageRatherThanTheJSONEndpoint() throws {
        for recipe in Self.recipes {
            let download = try #require(recipe.downloadURL)
            let changelog = try #require(recipe.changelogURL)
            #expect(download != recipe.url)
            #expect(changelog != recipe.url)
            #expect(!download.absoluteString.contains("/v2/update"))
            #expect(!changelog.absoluteString.contains("/v2/update"))
        }
    }
}
