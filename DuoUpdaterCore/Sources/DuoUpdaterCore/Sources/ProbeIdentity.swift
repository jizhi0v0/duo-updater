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
/// narrow case of *the machine's own identity*, and it carries the rules that
/// make sending that identity safe:
///
///   - **Never a credential.** An id that also authenticates (a license key, a
///     bearer token) must not come through here — those apps stay out of the
///     swept registries entirely (`RegistrySecurity`, and the Alcove/CleanShot
///     precedent). This is for identifiers that select a rollout bucket and
///     grant nothing.
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
    }

    /// Path to the file, relative to `~/Library/Application Support`.
    public let applicationSupportPath: String

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

    public init(
        applicationSupportPath: String,
        encoding: Encoding,
        validationPattern: String,
        placeholder: String = "__IDENTITY__"
    ) {
        self.applicationSupportPath = applicationSupportPath
        self.encoding = encoding
        self.validationPattern = validationPattern
        self.placeholder = placeholder
    }

    /// Cap on the file we'll read. An identity file is tens of bytes; anything
    /// larger means we're pointed at the wrong file and should not try to parse
    /// (let alone transmit) it.
    static let maxFileBytes = 4096

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
        fileManager: FileManager = .default
    ) -> String? {
        let appSupport = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupport else { return nil }
        let fileURL = appSupport.appendingPathComponent(applicationSupportPath, isDirectory: false)

        guard let data = try? Data(contentsOf: fileURL),
              data.count <= Self.maxFileBytes else { return nil }

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
        }
        guard !decoded.isEmpty,
              decoded.unicodeScalars.allSatisfy(Self.allowedCharacters.contains),
              decoded.range(of: "^(?:\(validationPattern))$", options: .regularExpression) != nil
        else { return nil }
        return decoded
    }

    /// `url` with `placeholder` replaced by the machine's identifier, or nil when
    /// the identifier is unavailable. Returns nil (rather than the untouched URL)
    /// when the placeholder isn't present either — a recipe that declares an
    /// identity but never uses it is a mistake, and silently probing the
    /// unpersonalized URL would hide it.
    public func resolve(
        _ url: URL,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let text = url.absoluteString
        guard text.contains(placeholder),
              let value = value(
                applicationSupportDirectory: applicationSupportDirectory,
                fileManager: fileManager)
        else { return nil }
        return URL(string: text.replacingOccurrences(of: placeholder, with: value))
    }
}
