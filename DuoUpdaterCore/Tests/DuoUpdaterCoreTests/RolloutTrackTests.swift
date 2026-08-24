import Foundation
import Testing

@testable import DuoUpdaterCore

/// A rollout track is only worth carrying if the sweep can tell whether it is
/// still deciding anything. These cover that question — the two-request verdict
/// — and the registry invariants that keep the verdict from dying silently.
@Suite(.serialized)
struct RolloutTrackTests {

    /// Answers each request with the version its `plan_type` maps to, so a test
    /// can put the vendor into "two tracks" or "merged" and see what we make of
    /// it. An unmapped value fails the request, which is how the unreachable
    /// case is staged.
    private final class PlanRouter: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var versions: [String: String] = [:]

        static func serve(_ versions: [String: String]) {
            lock.lock(); defer { lock.unlock() }
            Self.versions = versions
        }

        private static func version(for plan: String?) -> String? {
            lock.lock(); defer { lock.unlock() }
            return plan.flatMap { versions[$0] }
        }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [PlanRouter.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let plan = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "plan_type" }?.value
            guard let version = Self.version(for: plan) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("<version>\(version)</version>".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// A recipe whose track can never be read — the path does not exist — so the
    /// value on the wire is always the fallback. That is the state the finding
    /// exists for, and it makes these tests independent of whatever this machine
    /// happens to be signed into.
    private static func recipe(fallback: String, contrast: String) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.tracked",
            url: URL(string: "https://tracks.example/appcast?plan_type=__PLANTYPE__")!,
            mode: .responseBody,
            versionPattern: #"<version>([0-9.]+)</version>"#,
            track: RolloutTrack(
                selector: ProbeIdentity(
                    location: .home(".duo-updater-absent-by-design/auth.json"),
                    encoding: .plain,
                    validationPattern: #"[a-z0-9_]{1,32}"#,
                    placeholder: "__PLANTYPE__",
                    fallback: fallback),
                contrastValue: contrast,
                contrastTrackName: "the contrast track"))
    }

    private func verdict(fallback: String, contrast: String) async -> RolloutTrackVerdict? {
        await VendorProbeSource(recipes: [], session: PlanRouter.session())
            .rolloutTrackVerdict(Self.recipe(fallback: fallback, contrast: contrast))
    }

    /// The vendor is running two tracks: which value we send decides what we are
    /// offered, so sending the wrong one has a cost right now.
    @Test func twoAnswersAreReportedAsDiverged() async {
        PlanRouter.serve(["free": "2.0", "business": "1.0"])
        #expect(
            await verdict(fallback: "free", contrast: "business")
                == .diverged(ours: "2.0", contrast: "1.0"))
    }

    /// The rollout finished and the tracks merged. Nothing we send today can be
    /// wrong, so there is nothing to report — and, crucially, nothing that
    /// proves we would have chosen right had they still been split.
    @Test func oneAnswerIsReportedAsConverged() async {
        PlanRouter.serve(["free": "2.0", "business": "2.0"])
        #expect(await verdict(fallback: "free", contrast: "business") == .converged("2.0"))
    }

    /// The vendor being unreachable is not the recipe being wrong.
    @Test func anUnreachableEndpointIsIndeterminate() async {
        PlanRouter.serve([:])
        #expect(await verdict(fallback: "free", contrast: "business") == .indeterminate)
    }

    /// The silent death this exists to prevent: a contrast equal to the value we
    /// would send anyway asks the same question twice, so the check can never
    /// find anything. Pinned here, and forbidden across the registry below.
    @Test func aContrastEqualToOurOwnValueEstablishesNothing() async {
        PlanRouter.serve(["free": "2.0", "business": "1.0"])
        #expect(await verdict(fallback: "free", contrast: "free") == .indeterminate)
    }

    /// A track whose value cannot be read reports itself as defaulted. That is
    /// the cheap half of the finding's precondition — it costs no request, which
    /// is why the sweep checks it first and only then pays for a verdict.
    @Test func anUnreadableTrackReportsAsFallback() {
        let source = VendorProbeSource(recipes: [], session: PlanRouter.session())
        #expect(
            source.trackProvenance(Self.recipe(fallback: "free", contrast: "business"))
                == .fallback)
    }

    /// A recipe with no track is asked nothing.
    @Test func aRecipeWithoutATrackHasNoVerdict() async {
        let plain = VendorProbeRecipe(
            bundleID: "com.example.plain",
            url: URL(string: "https://tracks.example/appcast")!,
            mode: .responseBody,
            versionPattern: #"<version>([0-9.]+)</version>"#)
        #expect(
            await VendorProbeSource(recipes: [], session: PlanRouter.session())
                .rolloutTrackVerdict(plain) == nil)
    }
}

/// The registry's own tracks, checked against the rules that keep the verdict
/// meaningful. Both failures below would leave a track that looks configured and
/// reports healthy forever.
@Suite struct RolloutTrackRegistryTests {

    private var tracked: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.track != nil }
    }

    /// The contrast goes on the wire through the same gate as a read value, so a
    /// contrast its own selector rejects turns every verdict into
    /// `.indeterminate` — silently, and only in the window where it mattered.
    @Test func everyContrastSurvivesItsOwnSelectorsValidation() throws {
        for recipe in tracked {
            let track = try #require(recipe.track)
            #expect(
                track.selector.resolve(recipe.url, substituting: track.contrastValue) != nil,
                "\(recipe.recipeID)'s contrast '\(track.contrastValue)' fails its own validation")
        }
    }

    /// And it must differ from the fallback. The finding only fires when we ARE
    /// on the fallback; a contrast equal to it compares that value against
    /// itself, and the one check that can catch a defaulted track never fires.
    @Test func noContrastEqualsItsOwnFallback() throws {
        for recipe in tracked {
            let track = try #require(recipe.track)
            #expect(
                track.contrastValue != track.selector.fallback,
                "\(recipe.recipeID)'s contrast is its own fallback, so the divergence check is dead")
        }
    }
}
