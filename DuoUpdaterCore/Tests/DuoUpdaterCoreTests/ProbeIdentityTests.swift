import Foundation
import Testing

@testable import DuoUpdaterCore

/// `ProbeIdentity` reads a machine's own device id off disk so a rollout-gated
/// endpoint can be asked the question the app itself asks. Everything here is
/// offline — the point is the decode/validate/substitute contract, and the
/// refusals that keep a fabricated or malformed value off the wire.
@Suite struct ProbeIdentityTests {

    /// Claude's shape: a UUID wrapped in base64, at `Claude/ant-did`.
    private static let claudeIdentity = ProbeIdentity(
        applicationSupportPath: "Claude/ant-did",
        encoding: .base64,
        validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#)

    private static let uuid = "f24275e6-4ea8-4096-bd28-8120d30d42e5"

    /// Write `contents` to `<tmp>/Claude/ant-did` and hand back the tmp root to
    /// pass as the Application Support directory.
    private func appSupport(withAntDID contents: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Claude"), withIntermediateDirectories: true)
        if let contents {
            try Data(contents.utf8).write(
                to: root.appendingPathComponent("Claude/ant-did"))
        }
        return root
    }

    @Test func decodesABase64WrappedUUID() throws {
        let root = try appSupport(withAntDID: Data(Self.uuid.utf8).base64EncodedString())
        #expect(Self.claudeIdentity.value(applicationSupportDirectory: root) == Self.uuid)
    }

    /// Files written by other processes routinely end with a newline; that is not
    /// a malformed id.
    @Test func trimsWhitespaceInsideAndAroundTheEncoding() throws {
        let inner = Data("\(Self.uuid)\n".utf8).base64EncodedString()
        let root = try appSupport(withAntDID: "  \(inner)\n")
        #expect(Self.claudeIdentity.value(applicationSupportDirectory: root) == Self.uuid)
    }

    /// The app isn't installed, or has never launched. This must read as "recipe
    /// doesn't apply here", never as a broken recipe — see the `.notApplicable`
    /// path in `VendorProbeSource.fetchBody`.
    @Test func aMissingFileYieldsNil() throws {
        let root = try appSupport(withAntDID: nil)
        #expect(Self.claudeIdentity.value(applicationSupportDirectory: root) == nil)
        #expect(Self.claudeIdentity.resolve(
            URL(string: "https://example.com/?device_id=__IDENTITY__")!,
            applicationSupportDirectory: root) == nil)
    }

    /// The vendor rewrote the file into some other format. Sending whatever is in
    /// there would be both useless and a disclosure.
    @Test func aValueThatFailsTheRecipesPatternIsRefused() throws {
        let root = try appSupport(
            withAntDID: Data("not-a-uuid".utf8).base64EncodedString())
        #expect(Self.claudeIdentity.value(applicationSupportDirectory: root) == nil)
    }

    /// The pattern must match the WHOLE value: a well-formed UUID with junk
    /// appended is not a well-formed UUID.
    @Test func theValidationPatternIsAnchoredAtBothEnds() throws {
        let root = try appSupport(
            withAntDID: Data("\(Self.uuid)&admin=1".utf8).base64EncodedString())
        #expect(Self.claudeIdentity.value(applicationSupportDirectory: root) == nil)
    }

    /// The structural backstop under the per-recipe pattern: even a permissive
    /// pattern can't get URL-significant characters into the query. Without this,
    /// a recipe author's loose `.+` would let a rewritten file steer the request
    /// to another host.
    @Test func urlSignificantCharactersAreRefusedRegardlessOfThePattern() throws {
        let permissive = ProbeIdentity(
            applicationSupportPath: "Claude/ant-did", encoding: .plain,
            validationPattern: ".+")
        for hostile in ["a&b=c", "a/../b", "a?b", "a#b", "a b", "évil"] {
            let root = try appSupport(withAntDID: hostile)
            #expect(
                permissive.value(applicationSupportDirectory: root) == nil,
                "'\(hostile)' must not reach a request URL")
        }
    }

    /// Pointed at the wrong file, we stop rather than parse (let alone transmit)
    /// something large.
    @Test func anOversizedFileIsRefused() throws {
        let root = try appSupport(
            withAntDID: String(repeating: "a", count: ProbeIdentity.maxFileBytes + 1))
        let plain = ProbeIdentity(
            applicationSupportPath: "Claude/ant-did", encoding: .plain,
            validationPattern: "a+")
        #expect(plain.value(applicationSupportDirectory: root) == nil)
    }

    @Test func substitutesTheValueIntoTheQuery() throws {
        let root = try appSupport(withAntDID: Data(Self.uuid.utf8).base64EncodedString())
        let resolved = Self.claudeIdentity.resolve(
            URL(string: "https://api.anthropic.com/x?device_id=__IDENTITY__")!,
            applicationSupportDirectory: root)
        #expect(resolved?.absoluteString == "https://api.anthropic.com/x?device_id=\(Self.uuid)")
    }

    /// A recipe that declares an identity but forgot the placeholder would
    /// silently probe the unpersonalized URL and look healthy. Fail loudly (nil →
    /// `.notApplicable`) instead.
    @Test func aURLWithoutThePlaceholderResolvesToNil() throws {
        let root = try appSupport(withAntDID: Data(Self.uuid.utf8).base64EncodedString())
        #expect(Self.claudeIdentity.resolve(
            URL(string: "https://api.anthropic.com/x")!,
            applicationSupportDirectory: root) == nil)
    }

    // MARK: - ChatGPT's shape: a key inside a JSON object

    /// ChatGPT keeps its rollout id next to an unrelated flag, so unlike
    /// `ant-did` the whole file is not the value.
    private static let codexIdentity = ProbeIdentity(
        applicationSupportPath: "com.openai.codex/production-appcast-bootstrap.json",
        encoding: .jsonKey("installationId"),
        validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#)

    /// Write `contents` to `<tmp>/com.openai.codex/production-appcast-bootstrap.json`.
    private func appSupport(withBootstrap contents: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("com.openai.codex"), withIntermediateDirectories: true)
        if let contents {
            try Data(contents.utf8).write(
                to: root.appendingPathComponent("com.openai.codex/production-appcast-bootstrap.json"))
        }
        return root
    }

    /// The file as ChatGPT actually writes it, sibling flag and all.
    @Test func readsTheInstallationIDOutOfTheBootstrapObject() throws {
        let root = try appSupport(
            withBootstrap: #"{"backendAppcastEnabled":true,"installationId":"\#(Self.uuid)"}"#)
        #expect(Self.codexIdentity.value(applicationSupportDirectory: root) == Self.uuid)
    }

    /// A first run that has not been assigned an id yet writes the flag alone.
    /// Absent is not an error — it is "this recipe doesn't cover this machine".
    @Test func aBootstrapWithoutTheKeyYieldsNil() throws {
        let root = try appSupport(withBootstrap: #"{"backendAppcastEnabled":true}"#)
        #expect(Self.codexIdentity.value(applicationSupportDirectory: root) == nil)
    }

    /// The key is present but holds the wrong type. Coercing it with string
    /// interpolation would put `12345` on the wire as though it were an id.
    @Test func aNonStringValueYieldsNil() throws {
        let root = try appSupport(withBootstrap: #"{"installationId":12345}"#)
        #expect(Self.codexIdentity.value(applicationSupportDirectory: root) == nil)
    }

    /// The format changed under us, or we are pointed at the wrong file.
    @Test func aFileThatIsNotJSONYieldsNil() throws {
        let root = try appSupport(withBootstrap: Self.uuid)
        #expect(Self.codexIdentity.value(applicationSupportDirectory: root) == nil)
    }

    /// Extraction does not exempt a value from validation: a string that is not
    /// an id is refused the same as in every other encoding.
    @Test func aJSONValueThatIsNotAUUIDIsRefused() throws {
        let root = try appSupport(withBootstrap: #"{"installationId":"not-an-id"}"#)
        #expect(Self.codexIdentity.value(applicationSupportDirectory: root) == nil)
    }

}

/// The identity must not escape the fetch. Everything the verify sweep persists —
/// and therefore everything that can reach `verify/report.json` or a public GitHub
/// issue — is checked here against the registry as it actually stands.
@Suite struct ProbeIdentityRedactionTests {

    private var identityRecipes: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.identity != nil }
    }

    /// `recipe.url` is what `Verify` reads the endpoint host from and what the
    /// log lines carry. It must still hold the placeholder, never a value.
    @Test func theRegistryHoldsPlaceholdersNotValues() throws {
        for recipe in identityRecipes {
            let identity = try #require(recipe.identity)
            #expect(
                recipe.url.absoluteString.contains(identity.placeholder),
                "\(recipe.recipeID) declares an identity its URL never uses")
            // The real value, if this machine has one, must not be baked in.
            if let value = identity.value() {
                #expect(!recipe.url.absoluteString.contains(value))
            }
        }
    }

    /// An identity recipe must not use a mode that routes the fetched URL into
    /// the outcome. `.redirectFilename` puts the resolved endpoint into
    /// `resolvedDownload` → `RemoteVersion.downloadURL`, which is persisted; a
    /// `.responseBody` recipe's download comes from the response instead.
    @Test func identityRecipesReadTheBodyRatherThanTheResolvedURL() throws {
        for recipe in identityRecipes {
            guard case .responseBody = recipe.mode else {
                Issue.record("\(recipe.recipeID) must use .responseBody so the personalized URL stays out of the outcome")
                continue
            }
            // `.responseBody` falls back to `recipe.url` as the download when the
            // recipe names no page — which would be an unfetchable placeholder.
            #expect(
                recipe.downloadURL != nil,
                "\(recipe.recipeID) must name a downloadURL; the placeholder URL is not a usable fallback")
        }
    }
}
