import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// A vendor reporting its own outage **inside a 200**.
///
/// CapCut's settings endpoint does this: ByteDance's internal RPC overruns its
/// 500 ms budget and the edge answers `{"data": {},"message": "ExecBizCode
/// error: … request timeout …"}` — 392 bytes where the answer is ~436 KB, with
/// a success status on it. Nothing in the response says "server error", so the
/// probe read it as `versionPatternNoMatch`: *the recipe is broken, a human must
/// fix it*. On 2026-09-01 that put a red "1 app could not be checked — no match
/// in 391-byte body" banner in front of the user twice in two minutes, for a
/// recipe that was fine both times and answered on the next round.
///
/// What these pin is the whole split: the same bytes are a retryable vendor
/// hiccup for a recipe that declares the envelope's shape, and remain an
/// accusation against the recipe for every recipe that doesn't.
///
/// Two tests here DO wait the production `URLSession.gatewayRetryDelay` (800 ms
/// each), against `GatewayRetryTests`'s rule that tests never do. That rule
/// holds where the delay is already a parameter; these drive `probeDiagnostic`,
/// which is the entry point the app and the sweep use, and threading a
/// test-only delay down through it would put a seam in production code to save
/// 1.6 s. Driving the real entry point is the more valuable half of the trade.
@Suite struct VendorErrorEnvelopeTests {

    /// Serves a scripted list of bodies, one per connection, and counts them —
    /// so a test can prove *which* answer the probe ended up with and how many
    /// requests it cost. The last body repeats once the script runs out, which is
    /// what makes "and then it was still broken" expressible.
    final class ScriptedServer: @unchecked Sendable {
        /// The script lives in its own object so the connection handler can hold
        /// it directly: capturing the server itself would reference `port` before
        /// `init` has assigned it.
        final class Script: @unchecked Sendable {
            private let lock = NSLock()
            private var bodies: [String]
            private var served = 0

            init(_ bodies: [String]) { self.bodies = bodies }

            /// The next body, with the last one repeating once the script runs
            /// out — which is what makes "and then it was still broken"
            /// expressible.
            func next() -> String {
                lock.lock(); defer { lock.unlock() }
                served += 1
                return bodies.count > 1 ? bodies.removeFirst() : bodies[0]
            }

            var count: Int { lock.lock(); defer { lock.unlock() }; return served }
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "VendorErrorEnvelopeStub")
        private let script: Script
        let port: UInt16

        init(bodies: [String], status: Int = 200) throws {
            precondition(!bodies.isEmpty)
            let script = Script(bodies)
            self.script = script
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue

            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let payload = Data(script.next().utf8)
                    var header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
                    header += "Content-Type: application/json\r\n"
                    header += "Content-Length: \(payload.count)\r\n"
                    header += "Connection: close\r\n\r\n"
                    conn.send(
                        content: Data(header.utf8) + payload,
                        completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            listener.start(queue: queue)

            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let bound = resolved else { throw URLError(.cannotConnectToHost) }
            self.port = bound
        }

        /// How many requests reached the server.
        var requests: Int { script.count }

        var url: URL { URL(string: "http://127.0.0.1:\(port)/settings")! }
        func stop() { listener.cancel() }
    }

    // MARK: - the two bodies, both shaped like the real ones

    /// The envelope, in the shape the vendor actually serves it: a success
    /// status, an empty top-level `data`, and an internal stack trace where the
    /// answer belongs. Captured 2026-09-01 (message elided in the middle only).
    private static let envelope = """
        {"data": {},"message": "ExecBizCode error: GetPyCodeSettings error: \
        GetSettingsFromPython error, err = remote or network error[remote]: \
        error_code=1204 cds_key=THRIFT_EGRESS|toutiao.settings.settings:sg:sg1:| \
        GetBizSettingsJson|prod| reason=request timeout connect_timeout=100ms(from cp) \
        request_timeout=500ms(from cp) real_time=501018us fault_delay=0ms"}
        """

    /// A healthy answer, cut to the one object the beta recipe reads. Same
    /// envelope keys as the real response (`data` populated, `message: success`),
    /// which is what makes it a control for the pattern rather than just a body
    /// that happens to match.
    private static let healthy = """
        {"data":{"settings":{"update_reminder": {"lastest_url": \
        "https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/\
        CapCut_9_4_0-beta7_4560_capcutpc_beta_creatortool.dmg"}}},"message": "success"}
        """

    /// Both patterns come from the shipping recipe — a copy here would drift from
    /// the registry and start proving something about itself.
    private static func shippingBetaRecipe() throws -> VendorProbeRecipe {
        try #require(
            VendorProbeRegistry.recipes.first {
                $0.bundleID == CapCutChannel.bundleID && $0.channel == .beta
            })
    }

    /// The shipping recipe's patterns, pointed at the stub. `install` is dropped
    /// deliberately: resolving CapCut's installer URL is a separate concern with
    /// its own tests, and leaving it in would put a second failure mode inside
    /// tests about the first.
    private static func recipe(
        url: URL, versionPattern: String, transientBodyPattern: String?
    ) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.subject", url: url, mode: .responseBody,
            versionPattern: versionPattern, transientBodyPattern: transientBodyPattern,
            versionIsBuild: true)
    }

    // MARK: - what the fix does

    /// The retry is the whole user-visible fix: the vendor's bad half-second no
    /// longer reaches the menu bar at all.
    @Test func anEnvelopeIsRetriedOnceAndTheSecondAnswerWins() async throws {
        let shipping = try Self.shippingBetaRecipe()
        let server = try ScriptedServer(bodies: [Self.envelope, Self.healthy])
        defer { server.stop() }

        let outcome = await VendorProbeSource().probeDiagnostic(
            Self.recipe(
                url: server.url, versionPattern: shipping.versionPattern,
                transientBodyPattern: shipping.transientBodyPattern))

        #expect(outcome.failure == nil)
        // Not merely "some version": the build only present in the SECOND body,
        // which proves the answer came from the retry and not from a replay of
        // the first response.
        #expect(outcome.remote?.version == "9.4.0-beta7")
        #expect(server.requests == 2)
    }

    /// Exactly once. A wedged endpoint must not turn one check into an
    /// open-ended loop across a 145-app fan-out — the same contract
    /// `GatewayRetryTests` pins for a gateway 5xx, which this rides on.
    @Test func anEnvelopeThatSurvivesTheRetryIsInfraNotABrokenRecipe() async throws {
        let shipping = try Self.shippingBetaRecipe()
        let server = try ScriptedServer(bodies: [Self.envelope])
        defer { server.stop() }

        let outcome = await VendorProbeSource().probeDiagnostic(
            Self.recipe(
                url: server.url, versionPattern: shipping.versionPattern,
                transientBodyPattern: shipping.transientBodyPattern))

        let failure = try #require(outcome.failure)
        #expect(failure.kind == "vendorErrorEnvelope")
        // The point of the whole change: `.infra` is retried by `duo verify` and
        // never filed as an issue, where `.recipe` accuses a recipe that is fine.
        #expect(failure.classification == .infra)
        // The text the user reads in the failed-check banner has to say whose
        // problem it is; "no match in 391-byte body" said the opposite.
        #expect(failure.detail.contains("the vendor answered with an error"))
        #expect(server.requests == 2)
    }

    /// The other half of the contract, and the reason this is a per-recipe
    /// declaration rather than a heuristic: a recipe that has NOT written the
    /// envelope down is unchanged — same verdict, same one request, no silent
    /// "the vendor is having a bad day" over a pattern that genuinely broke.
    @Test func withoutADeclaredEnvelopeTheSameBodyIsStillAPatternMiss() async throws {
        let shipping = try Self.shippingBetaRecipe()
        let server = try ScriptedServer(bodies: [Self.envelope])
        defer { server.stop() }

        let outcome = await VendorProbeSource().probeDiagnostic(
            Self.recipe(
                url: server.url, versionPattern: shipping.versionPattern,
                transientBodyPattern: nil))

        let failure = try #require(outcome.failure)
        #expect(failure.kind == "versionPatternNoMatch")
        #expect(failure.classification == .recipe)
        #expect(server.requests == 1)
    }

    /// A healthy answer must not pay for any of this. Without this the retry
    /// could be firing on every CapCut check — doubling the traffic to an
    /// endpoint that answers ~436 KB — and every other test here would still
    /// pass.
    @Test func aHealthyBodyCostsExactlyOneRequest() async throws {
        let shipping = try Self.shippingBetaRecipe()
        let server = try ScriptedServer(bodies: [Self.healthy])
        defer { server.stop() }

        let outcome = await VendorProbeSource().probeDiagnostic(
            Self.recipe(
                url: server.url, versionPattern: shipping.versionPattern,
                transientBodyPattern: shipping.transientBodyPattern))

        #expect(outcome.remote?.version == "9.4.0-beta7")
        #expect(server.requests == 1)
    }

    /// The gate that keeps this from reopening a policy the retry helper spent
    /// its whole header refusing: a rate limit answers with an empty payload far
    /// more often than an answer does, so an envelope predicate consulted on any
    /// status would double our request rate against the very limiter complaining
    /// about it — on every Mac, on both tracks, on every check. Only a **2xx**
    /// makes an outage a *disguised* one.
    ///
    /// 429 rather than 500 because it is the expensive one to get wrong: the
    /// retry spends the budget being rationed and brings the reset nearer.
    @Test func anEnvelopeUnderARateLimitIsNotRetried() async throws {
        let shipping = try Self.shippingBetaRecipe()
        let server = try ScriptedServer(bodies: [Self.envelope], status: 429)
        defer { server.stop() }

        let outcome = await VendorProbeSource().probeDiagnostic(
            Self.recipe(
                url: server.url, versionPattern: shipping.versionPattern,
                transientBodyPattern: shipping.transientBodyPattern))

        // The status is the verdict, and it is reported as the status — the body
        // never gets a say.
        #expect(outcome.failure?.kind == "httpStatus429")
        #expect(server.requests == 1)
    }

    // MARK: - the declaration itself

    /// `matchesTransientBody` swallows an uncompilable pattern with `try?` and
    /// answers false, which is the safe direction — the recipe reverts to
    /// today's `versionPatternNoMatch` — but it is silent, and a typo would look
    /// exactly like a vendor that had stopped misbehaving. Registry-wide rather
    /// than CapCut-only for the same reason `entryStartPattern`'s check is.
    @Test func transientBodyPatternsInTheRegistryAreValidRegexes() {
        for recipe in VendorProbeRegistry.recipes {
            guard let pattern = recipe.transientBodyPattern else { continue }
            #expect(
                (try? NSRegularExpression(pattern: pattern)) != nil,
                "\(recipe.bundleID) [\(recipe.channel.rawValue)]: transientBodyPattern '\(pattern)' does not compile as a regex")
        }
    }

    /// The declaration buys two things — a retry and a lenient classification —
    /// and only the classification is unconditional. The retry is wired into the
    /// `.responseBody` fetch and `versionFeedData` refuses to repeat a POST, so a
    /// recipe declaring the envelope in any other shape would silently get the
    /// half that stops issues being filed WITHOUT the half the user feels, and
    /// nothing would say so: `.redirectFilename` reads a filename and
    /// `.zipEntryPlist` a plist value, so neither can even see a JSON envelope.
    @Test func transientBodyIsOnlyDeclaredWhereItCanBeHonoured() {
        for recipe in VendorProbeRegistry.recipes where recipe.transientBodyPattern != nil {
            if case .responseBody = recipe.mode {} else {
                Issue.record(
                    "\(recipe.recipeID) declares transientBodyPattern but is not a .responseBody recipe — it would get the classification without the retry")
            }
            #expect(
                recipe.requestBody == nil,
                "\(recipe.recipeID) declares transientBodyPattern on a POST, which versionFeedData will not retry")
        }
    }
}
