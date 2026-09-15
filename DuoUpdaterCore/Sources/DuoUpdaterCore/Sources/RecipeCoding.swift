import Foundation

/// How every type an `AppRecipeSet` stores is written as JSON. This comment is the
/// one place the convention is stated; the conformances are in
/// `RecipeCodableConformances.swift` (and `ChangelogRecipe.swift`, whose conformance
/// predates this file).
///
/// Nothing in the shipping app or `duo` decodes a recipe from JSON yet. This exists
/// so recipe data can later live in files without the format being invented while
/// the data is moved.
///
/// ## Shapes
///
/// - **A struct** is an object whose keys are its stored property names, exactly.
///   `RecipeCodableTests` holds every struct's `CodingKeys` to its stored
///   properties by reflection.
/// - **An enum with no associated values** is a string: its raw value when it has
///   one (`ReleaseChannel`, `GitHubCandidateScope`, …), else its case name
///   (`VendorInstallerKind`, `HostArch`).
/// - **An enum with associated values** (`VendorProbeRecipe.Mode`,
///   `VendorInstallSpec.URLSource`, `ProbeIdentity.Encoding`,
///   `ProbeIdentity.Location`, `ChannelArtifactProof`) is an object tagged by
///   `"kind"`, whose value is the Swift case name, plus that case's payload under
///   names given on each conformance. Every case of such an enum uses the object
///   form, payloadless ones included (`{"kind": "responseBody"}`), so one enum
///   never has two shapes. A payload value's key is its Swift label where it has
///   one (`zipEntryPlist(entry:key:)` → `entry`, `key`), except
///   `recipeAnchor(_:in:)`, whose `in` set is written as `fields`; an unlabelled
///   value's key is named on its conformance (`pattern`, `template`, `url`,
///   `path`). `RecipeCodableTests` pins both, with one JSON literal per case.
///   Example: `{"kind": "bodyPatternRelative", "pattern": "…", "base": "https://…"}`.
/// - **A `[ChannelProofKey: ChannelArtifactProof]` table** is an array of
///   `{"bundleID": …, "channel": …, "proof": {…}}`, sorted by bundle id then
///   channel (`ChannelProofTable`). JSON object keys must be strings, and the
///   standard encoding of a dictionary with struct keys is a flat alternating array.
/// - **A request body** is the body's text. `ChangelogRecipe.requestBody` is `Data`
///   in Swift; one that is not valid UTF-8 fails to encode rather than turning
///   into base64 nobody can review.
///
/// ## Decoding is strict
///
/// - An absent key takes the Swift initializer's default. The default is read off
///   a value built by that initializer, not restated here, so the two cannot
///   disagree.
/// - An **unknown key** is an error, at any depth. A misspelt optional key would
///   otherwise be silently ignored, where the same misspelling in Swift source is
///   a compile error.
/// - An explicit **`null`** is an error for a property that is not optional. For an
///   optional property it means `nil`. That includes the one optional whose
///   default is not nil, `ChangelogRecipe.maxEntries` (default 40): `null` there is
///   "keep every entry", and the encoder writes it, so `nil` round-trips.
/// - Errors are `DecodingError`s carrying the coding path of the offending key.
///
/// ## Encoding
///
/// Every non-optional property is written. An optional is written when it is
/// non-nil, and as `null` when it is nil but its default is not.
///
/// Output is deterministic only with `JSONEncoder.OutputFormatting.sortedKeys`.
/// The conformances sort what they control (a `recipeAnchor`'s field set, a
/// channel-proof table), but a `[String: String]` property such as
/// `requestHeaders` is written in the dictionary's iteration order, which Swift's
/// per-process hash seeding changes from one run to the next.
///
/// ## Trade-offs, stated so nobody rediscovers them
///
/// - **Swift names are the format.** A tag is a case name and a key is a property
///   name, so renaming a case or a stored property is a breaking change to every
///   JSON file that uses it. It fails loudly, at decode time (an unknown key or
///   kind) — not at review time, where the rename looks like a refactor.
/// - **Strict means old readers refuse new files.** A build that predates a key
///   rejects a file that uses it. For recipe data bundled with the build that
///   is the point; for anything fetched remotely later it is an open design
///   question, not something this convention answers.
/// - **`VendorInstallSpec` has `kind` twice.** Its own `"kind"` is the archive
///   format (`"zip"`, `"dmg"`, …); the `"kind"` inside its `urlSource` object is
///   that enum's tag. Same word, two levels, unrelated meanings.
enum RecipeCoding {

    /// A coding key for any string, for reading keys a type does not declare.
    struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Throws for the first key in `decoder`'s object that is not in `allowed`.
    static func rejectUnknownKeys(in decoder: Decoder, allowed: [String]) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(allowed)
        for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue })
        where !known.contains(key.stringValue) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [key],
                debugDescription: "unknown key `\(key.stringValue)`; expected one of: "
                    + allowed.joined(separator: ", ")))
        }
    }

    static func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(
        in decoder: Decoder, allowed: Keys.Type
    ) throws {
        try rejectUnknownKeys(in: decoder, allowed: Keys.allCases.map(\.stringValue))
    }

    /// Reads the `"kind"` tag of an enum object, then refuses any key that is not
    /// `"kind"` or one of that case's payload names. Returns the container to read
    /// the payload from.
    static func taggedObject<Kind: RawRepresentable & CaseIterable>(
        _ kind: Kind.Type, in decoder: Decoder, payload: (Kind) -> [String]
    ) throws -> (Kind, KeyedDecodingContainer<AnyKey>) where Kind.RawValue == String {
        let container = try decoder.container(keyedBy: AnyKey.self)
        let tagKey = AnyKey("kind")
        let tag = try container.decode(String.self, forKey: tagKey)
        guard let value = Kind(rawValue: tag) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [tagKey],
                debugDescription: "unknown kind `\(tag)`; expected one of: "
                    + Kind.allCases.map(\.rawValue).joined(separator: ", ")))
        }
        try rejectUnknownKeys(in: decoder, allowed: ["kind"] + payload(value))
        return (value, container)
    }

    /// The UTF-8 text of a request body, or an encoding error naming the key.
    static func text(of body: Data, at codingPath: [CodingKey]) throws -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            throw EncodingError.invalidValue(body, .init(
                codingPath: codingPath,
                debugDescription: "request body is not valid UTF-8, so it has no text form"))
        }
        return text
    }
}

extension KeyedDecodingContainer {
    /// A non-optional property with a default: absent → `default`, `null` → error.
    func decode<T: Decodable>(
        _ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T
    ) throws -> T {
        guard contains(key) else { return defaultValue() }
        if try decodeNil(forKey: key) {
            throw DecodingError.valueNotFound(T.self, .init(
                codingPath: codingPath + [key],
                debugDescription: "`\(key.stringValue)` cannot be null; "
                    + "omit the key to take its default"))
        }
        return try decode(T.self, forKey: key)
    }

    /// An optional property: absent → `default`, `null` → nil.
    func decodeOptional<T: Decodable>(
        _ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T?
    ) throws -> T? {
        guard contains(key) else { return defaultValue() }
        if try decodeNil(forKey: key) { return nil }
        return try decode(T.self, forKey: key)
    }
}

extension KeyedEncodingContainer {
    /// Writes `value` when non-nil; writes `null` when it is nil but the default
    /// is not, so decoding does not quietly restore the default.
    mutating func encodeOptional<T: Encodable>(
        _ value: T?, forKey key: Key, defaultIsNil: Bool
    ) throws {
        if let value {
            try encode(value, forKey: key)
        } else if !defaultIsNil {
            try encodeNil(forKey: key)
        }
    }
}
