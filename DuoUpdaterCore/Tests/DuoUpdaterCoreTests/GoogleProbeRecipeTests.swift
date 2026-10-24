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

    /// The download is checked against the package's `hash_sha256` (hex), which
    /// Google lists BEFORE the package's `name`.
    @Test func geminiChecksTheDownloadAgainstThePackagesSHA256() throws {
        let recipe = try #require(googleRecipe("com.google.GeminiMacOS"))
        let spec = try #require(recipe.install)
        #expect(spec.checksumFormat == .sha256Hex)
        let pattern = try #require(spec.checksumPattern)
        #expect(VendorProbeRecipe.extractVersion(from: omahaGeminiFixture, pattern: pattern)
            == "e7d26399d63bee35aeafa0bb0edae3dbbf8cc1ba4451248aa517ae68edb1399e")

        // The 2026-10-07 reply's shape: an `actions` block naming the same dmg
        // (as `run`, not `name`) ahead of the packages, and a base64 SHA-1 `hash`.
        let current = omahaGeminiFixture
            .replacingOccurrences(
                of: #""manifest":{"version":"1.94.11.734","#,
                with: #""manifest":{"version":"1.94.11.734","actions":{"action":[{"run":"Gemini-1.94.11.734.dmg","event":"install"},{"event":"postinstall"}]},"#)
            .replacingOccurrences(
                of: #""required":true}"#, with: #""required":true,"hash":"XFUQOg+le3g42ptq+6mg9w6Z4is\u003d"}"#)
        #expect(current.contains(#""run":"Gemini-1.94.11.734.dmg""#))
        #expect(VendorProbeRecipe.extractVersion(from: current, pattern: pattern)
            == "e7d26399d63bee35aeafa0bb0edae3dbbf8cc1ba4451248aa517ae68edb1399e")
    }

    /// The package the URL names carries no digest: nothing is read, not a later
    /// package's digest, which would refuse the good download.
    @Test func geminiReadsNoDigestFromAnotherPackage() throws {
        let recipe = try #require(googleRecipe("com.google.GeminiMacOS"))
        let pattern = try #require(recipe.install?.checksumPattern)
        let body = omahaGeminiFixture
            .replacingOccurrences(
                of: #""hash_sha256":"e7d26399d63bee35aeafa0bb0edae3dbbf8cc1ba4451248aa517ae68edb1399e","#, with: "")
            .replacingOccurrences(
                of: #""required":true}]"#,
                with: #""required":true},{"hash_sha256":"\#(String(repeating: "a", count: 64))","name":"Gemini-1.94.10.700.dmg"}]"#)
        #expect(!body.contains("e7d26399"))
        #expect(body.contains("Gemini-1.94.10.700.dmg"))
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern) == nil)
    }

    /// "Open page" opens `downloadURL`, so it must be the desktop landing page.
    /// Two wrong answers, neither of which `PageURLTests` can see: the old
    /// `gemini.google.com/download` answered 404 or a /sorry bot challenge
    /// (both seen 2026-09-14), and the page's own
    /// "Download for macOS" button, `gemini.google/download/mac/`, has no file
    /// extension but 302s straight to the dmg — the browser would download a file.
    /// This pins the choice; it cannot tell whether the page is still up.
    @Test func geminiSendsAHumanToTheDesktopPageRatherThanItsRedirect() throws {
        let recipe = try #require(googleRecipe("com.google.GeminiMacOS"))
        #expect(recipe.downloadURL?.absoluteString == "https://gemini.google/desktop/")
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
        #expect(recipe.identities.isEmpty)
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

/// Antigravity IDE is a SECOND app, not a channel of the one above: its own
/// bundle id, its own version line (2.5.5 against 2.9.1), an Electron VS Code fork
/// rather than the native hub. It was installed and scanned but matched no recipe,
/// so its row had no source at all.
@Test func antigravityIDEIsCoveredSeparatelyFromTheHub() throws {
    let ide = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.google.antigravity-ide" })
    let hub = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.google.antigravity" })
    #expect(ide.url != hub.url, "two products, two endpoints")

    // No machine identifier in the URL. The app sends a SHA-256 of the hostname in
    // that slot; we send its own fallback literal instead, so nothing per-machine
    // leaves here. Same reasoning as the `x-user-staging-id` header the hub omits.
    #expect(ide.url.absoluteString.hasSuffix("/no_hostname"))
    #expect(!ide.url.absoluteString.contains("sha256"))

    // The commit slot is a hash that can never be real. VS Code's update API
    // answers 204 for a current commit and the manifest otherwise, so naming a
    // live commit would return nothing to compare against.
    #expect(ide.url.absoluteString.contains("/0000000000000000000000000000000000000000/"))

    // Detection only: the artifact has not been signature-checked and the URL is
    // arm64-specific.
    #expect(ide.install == nil)
}

/// The real response, verbatim (2026-08-22). Three traps in one body: the version
/// fields are all the VS Code BASE version, and the only real version sits in the
/// download path next to a build id that must not ride along.
@Test func antigravityIDEReadsTheAppVersionNotTheVSCodeBase() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.google.antigravity-ide" })
    let body = #"""
    {"timestamp":1786614782,"supportsFastUpdate":true,"version":"ecfbad74d93962fc8ca485d93ab9b4f3d4cb6cf8","ideVersion":"Antigravity IDE","productVersion":"1.107.0","name":"1.107.0","hash":"106a021b7e59064312712385cab3c035cee68399","sha256hash":"33338ced839cb00fcc779ab96e4cdc79e06c894bc21cdb02249715286700c648","url":"https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/darwin-arm/Antigravity IDE.zip","displayName":"macOS for Apple Silicon (.zip)"}
    """#
    // 2.5.5 is what the shipped bundle reports. 1.107.0 (productVersion / name) is
    // VS Code's base version — comparing THAT against the installed 2.5.5 would
    // offer an update that can never be satisfied.
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == "2.5.5")

    // The build id after the dash must not be captured — the hub recipe documents
    // the same trap for its own feed (`2.8.1-6512087774658560` vs a plain 2.8.1).
    #expect(VendorProbeRecipe.extractVersion(
        from: body, pattern: recipe.versionPattern)?.contains("-") != true)

    // A body carrying only the VS Code fields, with no download URL, yields nothing
    // rather than falling back to 1.107.0.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"productVersion":"1.107.0","name":"1.107.0"}"#,
        pattern: recipe.versionPattern) == nil)

    // Segment count isn't pinned, so a future 2.6 or 2.5.5.1 still reads.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"url":"https://x/antigravity/stable/2.6-123/darwin-arm/a.zip"}"#,
        pattern: recipe.versionPattern) == "2.6")
}

/// #1621, end to end through the shipping Gemini recipe: Omaha rolls a cohort
/// per request unless the request carries one it assigned, so two checks seconds
/// apart can answer different builds — and the pre-install re-check refused the
/// install. The stub below is Omaha as measured on 2026-10-24: a cohort it
/// assigned is sticky, and anything else (none, empty, unknown) is rolled again
/// — here alternately into the rollout and out of it, so the failure is
/// reproducible rather than a coin flip.
@Suite(.serialized) struct GeminiCohortEchoTests {

    static let rolloutCohort = "1:3j3x/3wu9:"
    static let prodCohort = "1:3j3x:3wu9@0.3"

    private final class RolloutOmaha: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var rolls = 0
        nonisolated(unsafe) private static var sentCohorts: [String?] = []
        nonisolated(unsafe) private static var replyOverride: String?

        static func reset(reply: String? = nil) {
            lock.lock(); rolls = 0; sentCohorts = []; replyOverride = reply; lock.unlock()
        }
        static func sent() -> [String?] { lock.lock(); defer { lock.unlock() }; return sentCohorts }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RolloutOmaha.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        private func requestBody() -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            var data = Data()
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }

        override func startLoading() {
            // The body must still be JSON after the substitution, or the real
            // service would answer nothing.
            let object = try? JSONSerialization.jsonObject(with: requestBody()) as? [String: Any]
            let app = ((object?["request"] as? [String: Any])?["app"] as? [[String: Any]])?.first
            let sent = app?["cohort"] as? String

            Self.lock.lock()
            Self.sentCohorts.append(sent)
            let assigned: String
            if sent == GeminiCohortEchoTests.rolloutCohort || sent == GeminiCohortEchoTests.prodCohort {
                assigned = sent!
            } else {
                Self.rolls += 1
                assigned = Self.rolls % 2 == 1 ? GeminiCohortEchoTests.rolloutCohort : GeminiCohortEchoTests.prodCohort
            }
            let override = Self.replyOverride
            Self.lock.unlock()

            let version = assigned == GeminiCohortEchoTests.rolloutCohort ? "1.135.1.1291" : "1.131.4.1198"
            let name = assigned == GeminiCohortEchoTests.rolloutCohort ? "Rollout - Prod" : "Prod"
            let reply = override ?? #"""
            )]}'
            {"response":{"server":"prod","protocol":"3.0","app":[{"appid":"com.google.GeminiMacOS","cohort":"\#(assigned)","status":"ok","cohortname":"\#(name)","updatecheck":{"status":"ok","urls":{"url":[{"codebase":"https://dl.google.com/release2/gemini/x_\#(version)/"}]},"manifest":{"version":"\#(version)","packages":{"package":[{"hash_sha256":"\#(String(repeating: "a", count: 64))","name":"Gemini-\#(version).dmg"}]}}}}]}}
            """#
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static func gemini() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.google.GeminiMacOS" })
    }

    private static func scratchStore() -> (EchoedFieldStore, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echoed-fields-\(UUID().uuidString).json")
        return (EchoedFieldStore(fileURL: url), url)
    }

    private static func version(_ source: VendorProbeSource, _ recipe: VendorProbeRecipe) async -> String? {
        await source.probeDiagnostic(recipe).remote?.shortVersion
    }

    /// The failure as reported: no memory of the cohort, so the offer and the
    /// re-check land in different groups. Pinned so the stub is known to
    /// reproduce it — the next test is only meaningful if this one holds.
    @Test func withoutAStoreTheCheckAndTheRecheckDisagree() async throws {
        RolloutOmaha.reset()
        let recipe = try Self.gemini()
        let source = VendorProbeSource(recipes: [], session: RolloutOmaha.session())
        let offered = await Self.version(source, recipe)
        let confirmed = await Self.version(source, recipe)
        #expect(offered == "1.135.1.1291")
        #expect(confirmed == "1.131.4.1198")
        #expect(RolloutOmaha.sent() == ["", ""])
    }

    /// The fix: the re-check carries the cohort the offer's reply assigned, and
    /// is answered from the same group.
    @Test func theRecheckIsAnsweredFromTheCohortTheCheckWasAssigned() async throws {
        RolloutOmaha.reset()
        let recipe = try Self.gemini()
        let (store, _) = Self.scratchStore()
        let source = VendorProbeSource(
            recipes: [], session: RolloutOmaha.session(), echoedFields: store)
        let offered = await Self.version(source, recipe)
        let confirmed = await Self.version(source, recipe)
        let later = await Self.version(source, recipe)
        #expect(offered == "1.135.1.1291")
        #expect(confirmed == offered)
        #expect(later == offered)
        #expect(RolloutOmaha.sent() == ["", GeminiCohortEchoTests.rolloutCohort, GeminiCohortEchoTests.rolloutCohort])
        #expect(await store.value(for: recipe.recipeID) == GeminiCohortEchoTests.rolloutCohort)
    }

    /// The offer and the re-check may come from different processes — the menu
    /// bar's check, `duo install`'s re-check. Two sources over one file stand in
    /// for them.
    @Test func aSecondProcessReadsTheCohortTheFirstStored() async throws {
        RolloutOmaha.reset()
        let recipe = try Self.gemini()
        let (_, url) = Self.scratchStore()
        let app = VendorProbeSource(
            recipes: [], session: RolloutOmaha.session(), echoedFields: EchoedFieldStore(fileURL: url))
        let cli = VendorProbeSource(
            recipes: [], session: RolloutOmaha.session(), echoedFields: EchoedFieldStore(fileURL: url))
        let offered = await Self.version(app, recipe)
        let confirmed = await Self.version(cli, recipe)
        #expect(offered == "1.135.1.1291")
        #expect(confirmed == offered)
    }

    /// A reply naming something that is not a cohort — here one that would
    /// close the JSON string and open a field of its own — is neither stored nor
    /// sent; the next request asks as a fresh client.
    @Test func aHostileAssignmentIsNotStoredOrSent() async throws {
        let recipe = try Self.gemini()
        let (store, _) = Self.scratchStore()
        let source = VendorProbeSource(
            recipes: [], session: RolloutOmaha.session(), echoedFields: store)
        for hostile in [#"1:a\",\"x\":\"y"#, #"1:a\\u0022"#, "1:a b", "<script>"] {
            RolloutOmaha.reset(reply: #")]}' {"response":{"app":[{"cohort":"\#(hostile)","updatecheck":{"manifest":{"version":"1.131.4.1198"}}}]}}"#)
            _ = await source.probeDiagnostic(recipe)
            #expect(await store.value(for: recipe.recipeID) == nil, "\(hostile) was stored")
        }
        RolloutOmaha.reset()
        _ = await source.probeDiagnostic(recipe)
        #expect(RolloutOmaha.sent() == [""])
    }
}

/// The store on its own: what it keeps, and what it does with a file it did not
/// write.
@Suite struct EchoedFieldStoreTests {

    private func scratch() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echoed-fields-\(UUID().uuidString).json")
    }

    @Test func recordsReadsBackAndForgetsOnEmpty() async throws {
        let url = scratch()
        let store = EchoedFieldStore(fileURL: url)
        #expect(await store.value(for: "r") == nil)
        await store.record("1:a:", for: "r")
        #expect(await store.value(for: "r") == "1:a:")
        #expect(await EchoedFieldStore(fileURL: url).value(for: "r") == "1:a:")
        await store.record("", for: "r")
        #expect(await store.value(for: "r") == nil)
    }

    /// Another recipe's entry survives a write for this one.
    @Test func entriesAreKeptPerRecipe() async throws {
        let store = EchoedFieldStore(fileURL: scratch())
        await store.record("1:a:", for: "one")
        await store.record("1:b:", for: "two")
        #expect(await store.value(for: "one") == "1:a:")
        #expect(await store.value(for: "two") == "1:b:")
    }

    @Test func aCorruptFileReadsAsNothing() async throws {
        let url = scratch()
        try Data("not json".utf8).write(to: url)
        let store = EchoedFieldStore(fileURL: url)
        #expect(await store.value(for: "r") == nil)
        await store.record("1:a:", for: "r")
        #expect(await store.value(for: "r") == "1:a:")
    }

    /// Nothing stored is the empty value, and the body stays JSON for every
    /// cohort shape Omaha has assigned.
    @Test func theGeminiBodyStaysJSONForEveryObservedCohort() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.google.GeminiMacOS" })
        let body = try #require(recipe.requestBody)
        let field = try #require(body.echoedField)
        for cohort in [nil, "", "1:3j3x:", "1:3j3x/3wu9:", "1:3j3x:3wu9@0.3",
                       "1:1y5:3vo3@0.0,3wo9@0.5,3w59@0.0", "1:scr:3uyr@2.0E-4"] {
            let json = field.body(body.json, stored: cohort)
            #expect(!json.contains(field.placeholder))
            let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            let app = ((object?["request"] as? [String: Any])?["app"] as? [[String: Any]])?.first
            #expect(app?["cohort"] as? String == (cohort ?? ""), "\(cohort ?? "nil")")
        }
    }

    /// What a JSON string must not receive is refused even when a recipe's own
    /// pattern would let it through — the backstop is not the pattern.
    @Test func jsonSignificantCharactersAreRefusedRegardlessOfThePattern() {
        let loose = VendorProbeRecipe.RequestBody.EchoedField(
            placeholder: "__C__", responsePattern: #""c":"(.*?)""#, validationPattern: #"[\s\S]*"#)
        for hostile in ["1:a\"", "1:a\\", "1:a b", "1:a\n", "1:a\u{2028}", "1:a\u{0}", "1:ａ"] {
            #expect(loose.accept(hostile) == nil, "\(hostile.debugDescription) passed the gate")
            #expect(loose.body(#"{"c":"__C__"}"#, stored: hostile) == #"{"c":""}"#)
        }
        #expect(loose.accept("1:1y5/3wo9:3wol@0.5,3w59@0.0") == "1:1y5/3wo9:3wol@0.5,3w59@0.0")
    }

    /// The pattern reads the assignment out of a real reply.
    @Test func theGeminiPatternReadsTheAssignedCohort() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.google.GeminiMacOS" })
        let field = try #require(recipe.requestBody?.echoedField)
        #expect(field.assigned(in: omahaGeminiFixture) == "1:3j3x:")
    }

    /// Every registry recipe that declares a field uses it exactly once, inside
    /// a JSON string — the only place the character gate makes safe.
    @Test func everyEchoedFieldSitsInsideOneJSONString() {
        for recipe in VendorProbeRegistry.recipes {
            guard let body = recipe.requestBody, let field = body.echoedField else { continue }
            #expect(body.json.components(separatedBy: field.placeholder).count == 2,
                    "\(recipe.recipeID) must use its placeholder exactly once")
            #expect(body.json.contains("\"\(field.placeholder)\""),
                    "\(recipe.recipeID) must quote its placeholder")
        }
    }
}

/// The behaviour above only ships if the stack the product builds carries a
/// store. Pinned here, beside the deferral flag's own wiring test
/// (`InstallRedirectDeferralTests.theShippingStackAsksForTheDeferral`).
@Suite struct EchoedFieldWiringTests {

    @Test func theStackPassesItsStoreToTheVendorProbe() throws {
        let store = EchoedFieldStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echoed-fields-\(UUID().uuidString).json"))
        let probe = try #require(
            SourceStack.make(githubToken: nil, echoedFields: store)
                .compactMap { $0 as? VendorProbeSource }.first)
        #expect(probe.echoedFields === store)
    }

    /// And a stack built without one keeps none — what `duo verify` relies on.
    @Test func aStackWithoutAStoreKeepsNone() throws {
        let probe = try #require(
            SourceStack.make(githubToken: nil).compactMap { $0 as? VendorProbeSource }.first)
        #expect(probe.echoedFields == nil)
    }

    /// The store must re-read, not cache: a value another process wrote after
    /// this instance's first read is what the next request sends.
    @Test func theStoreSeesAWriteMadeAfterItsFirstRead() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echoed-fields-\(UUID().uuidString).json")
        let reader = EchoedFieldStore(fileURL: url)
        await reader.record("1:a:", for: "r")
        #expect(await reader.value(for: "r") == "1:a:")
        await EchoedFieldStore(fileURL: url).record("1:b:", for: "r")
        #expect(await reader.value(for: "r") == "1:b:")
    }
}
