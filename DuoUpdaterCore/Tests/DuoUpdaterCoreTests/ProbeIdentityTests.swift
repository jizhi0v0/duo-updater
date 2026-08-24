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

    // MARK: - ChatGPT's plan: a claim inside a JWT, under the home directory

    /// The rollout track the endpoint keys on. Omitting it books the machine onto
    /// the enterprise track, so it is read rather than guessed — see the Codex
    /// recipe in `VendorProbeRegistry`.
    private static let planIdentity = ProbeIdentity(
        location: .home(".codex/auth.json"),
        encoding: .jwtClaim(
            tokenPath: ["tokens", "access_token"],
            claimPath: ["https://api.openai.com/auth", "chatgpt_plan_type"]),
        validationPattern: #"[a-z0-9_]{1,32}"#,
        placeholder: "__PLANTYPE__",
        fallback: "unknown",
        maxBytes: 32768)

    /// Build a JWT whose payload is `claims`. Signature is a fixed stand-in: the
    /// decoder never reads it, which is itself part of the contract.
    private func jwt(claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims)
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(encoded).c2lnbmF0dXJl"
    }

    /// Write `contents` to `<tmp>/.codex/auth.json` and hand back the tmp root to
    /// pass as the home directory.
    private func home(withAuth contents: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        if let contents {
            try Data(contents.utf8).write(to: root.appendingPathComponent(".codex/auth.json"))
        }
        return root
    }

    /// The file as the app actually writes it, mirrored from a real
    /// `~/.codex/auth.json` (read 2026-08-24): the claim is namespaced two
    /// levels down inside the access token, and it shares the file with an id
    /// token, a refresh token, and `OPENAI_API_KEY` at the TOP LEVEL.
    ///
    /// That last one is why this fixture is worth keeping honest. The previous
    /// version put only nested secrets in the file, which made a test asserting
    /// "a recipe cannot reach the refresh token" pass for the wrong reason —
    /// `.jsonKey` reads top-level keys, so it missed on the PATH, not on any
    /// protection.
    private func authJSON(plan: String) throws -> String {
        let token = try jwt(claims: [
            "https://api.openai.com/auth": ["chatgpt_plan_type": plan],
        ])
        return """
            {"OPENAI_API_KEY":"sk-must-not-be-read","auth_mode":"chatgpt",\
            "last_refresh":"2026-08-24T15:26:45Z",\
            "tokens":{"access_token":"\(token)","id_token":"\(token)",\
            "refresh_token":"rt-must-not-be-read","account_id":"acct"}}
            """
    }

    @Test func readsThePlanClaimOutOfTheAccessToken() throws {
        let root = try home(withAuth: authJSON(plan: "team"))
        #expect(Self.planIdentity.value(homeDirectory: root) == "team")
    }

    /// Every tier we measured on 2026-08-24 must survive the pattern — the two
    /// tracks are only meaningful if both sides can actually be sent.
    @Test func everyKnownTierPassesValidation() throws {
        for plan in ["free", "go", "plus", "pro", "team", "business", "enterprise", "ent26"] {
            let root = try home(withAuth: authJSON(plan: plan))
            #expect(Self.planIdentity.value(homeDirectory: root) == plan)
        }
    }

    /// Never signed in, or the file moved. The probe must still run — falling
    /// back to the cautious track rather than skipping ChatGPT entirely.
    @Test func aMissingAuthFileFallsBackToUnknown() throws {
        let root = try home(withAuth: nil)
        #expect(Self.planIdentity.value(homeDirectory: root) == nil)
        let resolved = Self.planIdentity.resolve(
            URL(string: "https://example.com/?plan_type=__PLANTYPE__")!, homeDirectory: root)
        #expect(resolved?.absoluteString == "https://example.com/?plan_type=unknown")
    }

    /// A tier name we have never seen is forwarded verbatim: the vendor decides
    /// what its own slugs mean, and downgrading a new consumer tier to "unknown"
    /// would silently park those users on the enterprise track.
    @Test func anUnrecognizedTierIsForwardedRatherThanFlattened() throws {
        let root = try home(withAuth: authJSON(plan: "pro_max_2027"))
        #expect(Self.planIdentity.value(homeDirectory: root) == "pro_max_2027")
    }

    /// The claim is namespaced; a payload that puts it at the top level is not
    /// the shape this recipe declared.
    @Test func aClaimAtTheWrongPathYieldsNil() throws {
        let token = try jwt(claims: ["chatgpt_plan_type": "team"])
        let root = try home(withAuth: #"{"tokens":{"access_token":"\#(token)"}}"#)
        #expect(Self.planIdentity.value(homeDirectory: root) == nil)
    }

    /// Not a JWT at all — three dot-separated parts are the whole structural
    /// check, and a bare string fails it rather than being base64-decoded blind.
    @Test func aTokenThatIsNotAJWTYieldsNil() throws {
        let root = try home(withAuth: #"{"tokens":{"access_token":"not-a-jwt"}}"#)
        #expect(Self.planIdentity.value(homeDirectory: root) == nil)
    }

    /// The claim holds the wrong type. Coercing it would put `true` on the wire.
    @Test func aNonStringClaimYieldsNil() throws {
        let token = try jwt(claims: ["https://api.openai.com/auth": ["chatgpt_plan_type": true]])
        let root = try home(withAuth: #"{"tokens":{"access_token":"\#(token)"}}"#)
        #expect(Self.planIdentity.value(homeDirectory: root) == nil)
    }

    /// The structural backstop applies here too: a claim rewritten into something
    /// URL-significant must not reach the query, pattern or no pattern.
    @Test func aHostileClaimIsRefused() throws {
        for hostile in ["team&admin=1", "team/../x", "TEAM", "a b"] {
            let root = try home(withAuth: authJSON(plan: hostile))
            #expect(
                Self.planIdentity.value(homeDirectory: root) == nil,
                "'\(hostile)' must not reach a request URL")
        }
    }

    /// Pointed at something far larger than an auth file, we stop before parsing.
    @Test func anOversizedAuthFileFallsBackRatherThanParsing() throws {
        let padding = String(repeating: "p", count: 40000)
        let root = try home(withAuth: #"{"pad":"\#(padding)","tokens":{}}"#)
        #expect(Self.planIdentity.value(homeDirectory: root) == nil)
    }

    /// What `.jwtClaim` actually guarantees: it walks to the claim a recipe
    /// names and can return nothing else — not the token it decoded, not a
    /// sibling of that token.
    @Test func theClaimEncodingCannotReturnTheTokenItDecoded() throws {
        let root = try home(withAuth: authJSON(plan: "team"))
        let value = try #require(Self.planIdentity.value(homeDirectory: root))
        #expect(value == "team")

        // Aimed at the token itself rather than at a claim inside it: there is
        // no claim path to walk, so there is no answer to give.
        let reachingForTheToken = ProbeIdentity(
            location: .home(".codex/auth.json"),
            encoding: .jwtClaim(tokenPath: ["tokens", "access_token"], claimPath: []),
            validationPattern: ".+",
            maxBytes: 32768)
        #expect(reachingForTheToken.value(homeDirectory: root) == nil)

        // A sibling that is not a JWT decodes to nothing either.
        let reachingForTheRefreshToken = ProbeIdentity(
            location: .home(".codex/auth.json"),
            encoding: .jwtClaim(
                tokenPath: ["tokens", "refresh_token"], claimPath: ["anything"]),
            validationPattern: ".+",
            maxBytes: 32768)
        #expect(reachingForTheRefreshToken.value(homeDirectory: root) == nil)
    }

    /// The hazard the allow-list exists for, written as a test rather than left
    /// as a comment: a DIFFERENT encoding aimed at this same file reaches the
    /// API key at its top level, and the character backstop waves it through
    /// (an `sk-` key is URL-unreserved end to end).
    ///
    /// Nothing in `ProbeIdentity`'s types prevents this, which is the point —
    /// what prevents it is `RegistrySecurity.credentialBearingFileReads` plus
    /// the registry-derived check in `RegistrySecurityTests`. If this test ever
    /// goes red the hazard moved, and that guard needs re-reading before it is
    /// trusted again.
    @Test func anotherEncodingWouldReachTheAPIKeyBesideTheClaim() throws {
        let root = try home(withAuth: authJSON(plan: "team"))
        let reachingForTheKey = ProbeIdentity(
            location: .home(".codex/auth.json"),
            encoding: .jsonKey("OPENAI_API_KEY"),
            validationPattern: ".+",
            maxBytes: 32768)
        #expect(reachingForTheKey.value(homeDirectory: root) == "sk-must-not-be-read")
        #expect(
            RegistrySecurity.credentialBearingFileReads["~/.codex/auth.json"]?
                .contains(reachingForTheKey.readPath) != true,
            "this read must never appear in the allow-list")
    }

}

/// The identity must not escape the fetch. Everything the verify sweep persists —
/// and therefore everything that can reach `verify/report.json` or a public GitHub
/// issue — is checked here against the registry as it actually stands.
@Suite struct ProbeIdentityRedactionTests {

    private var identityRecipes: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { !$0.identities.isEmpty }
    }

    /// `recipe.url` is what `Verify` reads the endpoint host from and what the
    /// log lines carry. It must still hold the placeholder, never a value.
    @Test func theRegistryHoldsPlaceholdersNotValues() throws {
        for recipe in identityRecipes {
            for identity in recipe.identities {
                #expect(
                    recipe.url.absoluteString.contains(identity.placeholder),
                    "\(recipe.recipeID) declares an identity its URL never uses")
                // The real value, if this machine has one, must not be baked in.
                if let value = identity.value() {
                    #expect(!recipe.url.absoluteString.contains(value))
                }
            }
        }
    }

    /// Two identities on one recipe must not share a placeholder: the first
    /// substitution would consume both slots and the second would then find no
    /// placeholder and fail the whole probe.
    @Test func placeholdersAreDistinctWithinARecipe() throws {
        for recipe in identityRecipes {
            let placeholders = recipe.identities.map(\.placeholder)
            #expect(
                Set(placeholders).count == placeholders.count,
                "\(recipe.recipeID) reuses a placeholder across identities")
        }
    }

    /// A declared fallback must survive its own recipe's validation. It is only
    /// checked at substitution time, so a typo would otherwise sit in the
    /// registry looking fine and turn into a skipped probe the day the file it
    /// stands in for goes missing — the one day it was supposed to help.
    @Test func everyDeclaredFallbackWouldActuallySubstitute() throws {
        // A directory with nothing in it: every read fails, so what comes out is
        // the fallback or nothing.
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        for recipe in identityRecipes {
            for identity in recipe.identities {
                guard let fallback = identity.fallback else { continue }
                let resolved = identity.resolve(
                    URL(string: "https://example.com/?x=\(identity.placeholder)")!,
                    applicationSupportDirectory: empty, homeDirectory: empty)
                #expect(
                    resolved?.absoluteString == "https://example.com/?x=\(fallback)",
                    "\(recipe.recipeID)'s fallback '\(fallback)' fails its own validation")
            }
        }
    }

    /// The asymmetry that makes the two Codex identities safe, pinned so a later
    /// edit cannot quietly swap it. The machine id must keep skipping when it is
    /// unreadable — a synthesized one picks a stranger's rollout bucket. The plan
    /// must keep falling back — without it, a signed-out machine would lose
    /// ChatGPT coverage entirely rather than land on the cautious track.
    @Test func codexKeepsTheIDStrictAndThePlanForgiving() throws {
        let codex = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.openai.codex" })
        let byPlaceholder = Dictionary(
            uniqueKeysWithValues: codex.identities.map { ($0.placeholder, $0) })

        let machineID = try #require(byPlaceholder["__IDENTITY__"])
        #expect(machineID.fallback == nil, "a fabricated installation_id must never be sent")

        let plan = try #require(byPlaceholder["__PLANTYPE__"])
        #expect(
            plan.fallback == "unknown",
            "an unreadable plan must fall back to the value OpenAI's own doctor sends")
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
