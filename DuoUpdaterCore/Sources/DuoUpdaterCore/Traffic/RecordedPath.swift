import Foundation

/// The path as it is allowed to reach disk.
///
/// ``RequestEvent/path`` drops the query because credentials live there, and
/// says so. A credential in a *path segment* was left alone, and
/// ``CredentialBearingURL`` names that gap in its own documentation: "a secret
/// embedded in the path rather than the query slips through. It is the backstop,
/// not the plan."
///
/// **Why this is not `Redactor`.** The obvious repair — send the path through
/// the general scrubber — was measured against 590 distinct paths from a real
/// store and is a net loss. It rewrites 9 of them and all 9 are build hashes
/// (VS Code, Cursor, Claude, WeChat DevTools), because the rule that fires is
/// "32+ hex characters" and a commit SHA is exactly that. Meanwhile the rules
/// that would catch a secret — `name=value`, and the known token shapes — mostly
/// cannot fire in a path at all, since a path has no `=`. `Redactor` is built to
/// be over-eager for text that is about to be *published*; this text is a
/// diagnostic record whose entire job is to say which file was fetched, and a
/// redaction here is permanent.
///
/// So the rule is narrow on purpose, and it is two rules:
///
/// 1. **A known token shape, anywhere.** `ghp_…`, a JWT, `sk-ant-…`. These are
///    unambiguous and matched none of the 590.
/// 2. **An opaque value in a segment that a neighbouring segment labels as a
///    credential.** `/presignedTokenAuth/<uuid>/…` goes; `/license/issue-token`
///    stays, because `issue-token` is an endpoint name and not opaque.
///
/// It is the *opacity* test that carries the safety, not the label: `1Password`
/// contains the word "password" and labels the segment after it, but a version
/// number is not opaque so nothing is lost. Without that test this rule would
/// eat real paths.
///
/// **What it still misses**, stated because a backstop that is believed to be a
/// wall is worse than no backstop: an opaque credential in an *unlabelled*
/// segment is indistinguishable from a build hash, and this deliberately keeps
/// build hashes. Nothing here makes it safe for a recipe to put a secret in a
/// path.
public enum RecordedPath {

    /// The path of `url`, with anything the rules above recognise replaced.
    ///
    /// Applied at the point of recording rather than of display: the concern is
    /// a plaintext file under Application Support that every backup copies, so
    /// "never written" is the only version of this that holds.
    public static func redacted(_ url: URL) -> String {
        redacted(path: url.path)
    }

    static func redacted(path: String) -> String {
        // Split preserving the shape: a leading "/" yields an empty first field,
        // and rebuilding by joining puts every separator back exactly as it was.
        var parts = path.components(separatedBy: "/")

        for index in parts.indices {
            if containsKnownTokenShape(parts[index]) {
                parts[index] = Redactor.placeholder
                continue
            }
            // Labelled by the segment before it. Only backwards: `/token/<value>`
            // is how these read, and looking forwards as well would let a
            // trailing filename like `…/auth.json` condemn the hash before it.
            let previous = index > 0 ? parts[index - 1] : ""
            if isCredentialLabel(previous), isOpaque(parts[index]) {
                parts[index] = Redactor.placeholder
            }
        }
        return parts.joined(separator: "/")
    }

    // MARK: - The two tests

    /// Shapes that are a credential wherever they appear. Deliberately not the
    /// whole of ``Redactor``'s list: the "32+ hex" rule is the one that eats
    /// build hashes, and it is left out.
    private static let tokenShapes: [NSRegularExpression] = [
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,
        #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
        #"sk-ant-[A-Za-z0-9_-]{20,}"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static func containsKnownTokenShape(_ segment: String) -> Bool {
        let range = NSRange(segment.startIndex..., in: segment)
        return tokenShapes.contains { $0.firstMatch(in: segment, range: range) != nil }
    }

    /// Whether a segment reads as naming a credential.
    ///
    /// Words are taken from ``CredentialBearingURL/sensitiveNames`` so there is
    /// one list rather than two that drift, but the *matching* is looser here
    /// than the query-parameter matching there, and it has to be: a parameter is
    /// named `api_key`, while a path segment is named `presignedTokenAuth`. That
    /// one is real — it is how the recorded JetBrains artifact redirect names the
    /// segment holding a per-request UUID — and it has no separators at all, so
    /// the separator-delimited tail match that serves query parameters cannot
    /// see it. Splitting on case as well as on separators does.
    ///
    /// The looseness is affordable only because the neighbouring segment still
    /// has to be opaque; on its own it would match `1Password`.
    private static func isCredentialLabel(_ segment: String) -> Bool {
        words(in: segment).contains { CredentialBearingURL.sensitiveNames.contains($0) }
    }

    /// Lowercased words, split on `_`, `-`, `.` and on a lower→upper boundary.
    private static func words(in segment: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for character in segment {
            if character == "_" || character == "-" || character == "." {
                if !current.isEmpty { words.append(current.lowercased()); current = "" }
                previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower {
                words.append(current.lowercased())
                current = ""
            }
            current.append(character)
            previousWasLower = character.isLowercase || character.isNumber
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }

    /// Whether a segment carries no meaning a reader could use — the property
    /// that separates a token from an endpoint name or a version.
    ///
    /// A UUID counts whatever its length. Otherwise it takes both length and a
    /// mix of letters and digits, which is what keeps `issue-token`, `stable`,
    /// `.lastSuccessful` and `1.46388.1` out of it.
    static func isOpaque(_ segment: String) -> Bool {
        if isUUID(segment) { return true }
        guard segment.count >= 16 else { return false }
        guard segment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else { return false }
        return segment.contains(where: \.isLetter) && segment.contains(where: \.isNumber)
    }

    private static func isUUID(_ segment: String) -> Bool {
        UUID(uuidString: segment) != nil
    }
}
