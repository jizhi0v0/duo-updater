import Foundation

/// A stable per-machine identifier an app keeps on disk, which its vendor's
/// version endpoint requires before it will answer *for this install*.
///
/// Some vendors don't publish one "latest version" — they publish a staged
/// rollout, and the only endpoint that says what **this** machine is entitled to
/// takes the app's own device id. Probing such an endpoint with a synthesized id
/// is worse than not probing at all: the id picks a rollout bucket, so a made-up
/// one lands in a bucket unrelated to this machine and gets both failure modes —
/// a held-back bucket hides a real update, an ahead bucket offers one the app's
/// own updater will never apply. Reading the id the app already wrote removes
/// both: the answer is, by construction, the answer the app itself would get.
///
/// So this is not a general "put a variable in the URL" hook. It exists for the
/// narrow case of *what the vendor's rollout keys on*, and it carries the rules
/// that make sending that safe:
///
///   - **Never a credential.** An id that also authenticates (a license key, a
///     bearer token) must not come through here — those apps stay out of the
///     swept registries entirely (`RegistrySecurity`, and the Alcove/CleanShot
///     precedent). This is for values that select a rollout bucket and grant
///     nothing.
///
///     Reading a non-credential value *out of* a file that also holds
///     credentials is the one nearby case this allows, and only under
///     `.jwtClaim`, which can reach exactly one claim by an explicit path and
///     can return nothing else. ChatGPT's `plan_type` is the instance: it lives
///     in `~/.codex/auth.json` beside real tokens, but the claim itself
///     authenticates nothing — it names a rollout track. The tokens in that file
///     are never parsed, never held beyond the read, and cannot be what
///     `.jwtClaim` yields. See `VendorProbeRegistry`'s Codex recipe for why the
///     value is needed at all.
///   - **Never recorded.** The value is substituted into the request URL inside
///     the fetch and nowhere else: it is not stored on the recipe, not on
///     `ProbeOutcome`, and not logged. Everything the verify sweep persists —
///     `recipe.url` (still the placeholder), the endpoint *host*, the response
///     body sample — is written before or without the substitution, so the id
///     can never reach `verify/report.json` or a public GitHub issue.
///   - **Absent is fine.** No file (the app isn't installed, or has never run)
///     yields nil, which the source reports as `.notApplicable` — "this recipe
///     doesn't cover this machine", the same status as a channel mismatch. A
///     sweep on a machine without the app skips it instead of filing a bug.
///
///     A `fallback` changes that answer for values where the vendor defines a
///     "don't know" of its own: absence then substitutes that literal rather
///     than skipping the recipe. Only for values the endpoint *tolerates* being
///     wrong — a machine id has no such value (a made-up one picks a stranger's
///     bucket), so identity recipes leave `fallback` nil and keep skipping.
public struct ProbeIdentity: Sendable {

    /// How the identifier is stored in the file. Apps rarely write a bare value.
    public enum Encoding: Sendable {
        /// The file's whole contents (whitespace-trimmed) are the value.
        case plain
        /// The contents are base64; decode, then trim. Claude's `ant-did` is a
        /// UUID wrapped this way.
        case base64
        /// The contents are a JSON object; take this key's string value. ChatGPT
        /// keeps its rollout id alongside an unrelated flag, in
        /// `com.openai.codex/production-appcast-bootstrap.json`:
        /// `{"backendAppcastEnabled":true,"installationId":"…"}`. A non-string
        /// value, a missing key, or anything that isn't an object yields nil —
        /// the same "doesn't look like itself" answer the other cases give.
        case jsonKey(String)
        /// The contents are a JSON object holding a JWT; walk `tokenPath` to the
        /// token string, decode its payload, then walk `claimPath` to the claim.
        /// ChatGPT's plan lives two levels down in a namespaced claim:
        /// `tokens.access_token` → `"https://api.openai.com/auth"` →
        /// `chatgpt_plan_type`.
        ///
        /// Deliberately narrow: both paths are literal, so this reaches exactly
        /// the one claim a recipe names and can yield nothing else — no
        /// enumeration, no wildcard, and no way to return the token it decoded.
        /// Signature is not verified because nothing here trusts the claim: it
        /// is a hint about which rollout track to *ask* about, and the answer
        /// comes from the vendor either way.
        case jwtClaim(tokenPath: [String], claimPath: [String])
    }

    /// Where the file lives. Most apps keep their id under Application Support;
    /// ChatGPT keeps its account state in a dotfile under the home directory.
    public enum Location: Sendable {
        /// Path relative to `~/Library/Application Support`.
        case applicationSupport(String)
        /// Path relative to the user's home directory.
        case home(String)
    }

    /// Where to read the value from.
    public let location: Location

    /// How to turn the file's bytes into the value.
    public let encoding: Encoding

    /// Regex the decoded value must match **in full**. This is the recipe
    /// author's statement of what the id looks like; a file that has been
    /// rewritten into some other format is rejected rather than sent.
    public let validationPattern: String

    /// The literal token in the recipe's `url` that the value replaces.
    ///
    /// Must survive `URL(string:)` unchanged, which rules out the obvious
    /// `{identity}` — braces are not URL-legal, so the URL stores them
    /// percent-encoded and a literal search for the token then misses. The
    /// default is built from unreserved characters only.
    public let placeholder: String

    /// Literal to substitute when the file is missing or doesn't parse, instead
    /// of failing the probe. Nil (the default) keeps the strict behaviour: an
    /// unreadable value skips the recipe. Must satisfy the same character
    /// backstop and pattern as a read value — it goes on the wire identically.
    public let fallback: String?

    /// Cap on this file. The default suits an identity file, which is tens of
    /// bytes; a recipe reading a claim out of a larger document raises it
    /// deliberately. Above the cap we stop rather than parse (let alone
    /// transmit) something we're evidently pointed at by mistake.
    public let maxBytes: Int

    public init(
        location: Location,
        encoding: Encoding,
        validationPattern: String,
        placeholder: String = "__IDENTITY__",
        fallback: String? = nil,
        maxBytes: Int = ProbeIdentity.maxFileBytes
    ) {
        self.location = location
        self.encoding = encoding
        self.validationPattern = validationPattern
        self.placeholder = placeholder
        self.fallback = fallback
        self.maxBytes = maxBytes
    }

    /// Convenience for the common case: a file under Application Support.
    public init(
        applicationSupportPath: String,
        encoding: Encoding,
        validationPattern: String,
        placeholder: String = "__IDENTITY__",
        fallback: String? = nil,
        maxBytes: Int = ProbeIdentity.maxFileBytes
    ) {
        self.init(
            location: .applicationSupport(applicationSupportPath), encoding: encoding,
            validationPattern: validationPattern, placeholder: placeholder,
            fallback: fallback, maxBytes: maxBytes)
    }

    /// Default cap on the file we'll read. An identity file is tens of bytes.
    public static let maxFileBytes = 4096

    /// Where the file is, written the way a person would say it — for the
    /// `.notApplicable` message, which must name a path but never a value.
    public var displayPath: String {
        switch location {
        case .applicationSupport(let path): return "~/Library/Application Support/\(path)"
        case .home(let path): return "~/\(path)"
        }
    }

    /// What this reaches INSIDE the file, written as a path. Pairs with
    /// `displayPath` so `RegistrySecurity` can allow-list a specific read out of
    /// a file that also holds credentials, rather than the whole file — the
    /// distinction that matters when the file is `~/.codex/auth.json`.
    ///
    /// Only ever compared against a literal in that allow-list, so the exact
    /// spelling is arbitrary; what it must be is *distinct* — two different
    /// reads must never render alike.
    public var readPath: String {
        switch encoding {
        case .plain: return "<whole file>"
        case .base64: return "<whole file, base64>"
        case .jsonKey(let key): return key
        case .jwtClaim(let tokenPath, let claimPath):
            return tokenPath.joined(separator: ".") + " → " + claimPath.joined(separator: ".")
        }
    }

    /// The characters a value may contain, regardless of what
    /// `validationPattern` allows. These are URL-unreserved, so substituting the
    /// value into a query needs no escaping and cannot smuggle in a second
    /// parameter, a path segment, or a different host. A structural backstop
    /// under the per-recipe pattern, not a replacement for it.
    static let allowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Read and validate the identifier, or nil when it isn't there / doesn't
    /// look like itself. All filesystem access is best-effort — a missing,
    /// oversized, or malformed file yields nil, never a throw.
    public func value(
        applicationSupportDirectory: URL? = nil,
        homeDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let fileURL: URL
        switch location {
        case .applicationSupport(let path):
            let appSupport = applicationSupportDirectory
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            guard let appSupport else { return nil }
            fileURL = appSupport.appendingPathComponent(path, isDirectory: false)
        case .home(let path):
            let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
            fileURL = home.appendingPathComponent(path, isDirectory: false)
        }

        guard let data = try? Data(contentsOf: fileURL),
              data.count <= maxBytes else { return nil }

        let raw = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded: String
        switch encoding {
        case .plain:
            decoded = raw
        case .base64:
            guard let bytes = Data(base64Encoded: raw) else { return nil }
            decoded = String(decoding: bytes, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .jsonKey(let key):
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let fields = object as? [String: Any],
                  let value = fields[key] as? String else { return nil }
            decoded = value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .jwtClaim(let tokenPath, let claimPath):
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let token = Self.string(at: tokenPath, in: object),
                  let payload = Self.jwtPayload(token),
                  let value = Self.string(at: claimPath, in: payload) else { return nil }
            decoded = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Self.accept(decoded, matching: validationPattern)
    }

    /// The shared gate every value passes, whether read or fallen back to.
    private static func accept(_ value: String, matching pattern: String) -> String? {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy(allowedCharacters.contains),
              value.range(of: "^(?:\(pattern))$", options: .regularExpression) != nil
        else { return nil }
        return value
    }

    /// Walk a literal key path through nested JSON objects to a string leaf.
    /// Anything that isn't an object at a step, a missing key, or a non-string
    /// leaf yields nil.
    private static func string(at path: [String], in object: Any) -> String? {
        guard !path.isEmpty else { return nil }
        var current = object
        for key in path {
            guard let fields = current as? [String: Any], let next = fields[key] else { return nil }
            current = next
        }
        return current as? String
    }

    /// A JWT's payload, decoded as JSON. Base64url (the `-`/`_` alphabet, padding
    /// omitted) is what JWT uses and what `Data(base64Encoded:)` does not accept,
    /// so translate before decoding. The signature is neither read nor checked —
    /// see `.jwtClaim` for why nothing here needs to trust the payload.
    private static func jwtPayload(_ token: String) -> Any? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let bytes = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: bytes)
    }

    /// `url` with `placeholder` replaced by the machine's identifier, or nil when
    /// the identifier is unavailable. Returns nil (rather than the untouched URL)
    /// when the placeholder isn't present either — a recipe that declares an
    /// identity but never uses it is a mistake, and silently probing the
    /// unpersonalized URL would hide it.
    public func resolve(
        _ url: URL,
        applicationSupportDirectory: URL? = nil,
        homeDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let text = url.absoluteString
        guard text.contains(placeholder) else { return nil }
        let read = value(
            applicationSupportDirectory: applicationSupportDirectory,
            homeDirectory: homeDirectory, fileManager: fileManager)
        // A fallback stands in for an unreadable value, but is held to the same
        // gate — a recipe author's typo must not reach the wire either.
        guard let value = read
            ?? fallback.flatMap({ Self.accept($0, matching: validationPattern) })
        else { return nil }
        return URL(string: text.replacingOccurrences(of: placeholder, with: value))
    }
}
