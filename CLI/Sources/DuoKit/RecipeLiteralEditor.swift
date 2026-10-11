import Foundation

// Rewrite the literal values of one changelog recipe in a family file.
//
// `duo autofix` never lets a model write Swift. The model answers with values — a
// URL, a pattern, a list of patterns — and this file is the only thing that turns
// them into source. It edits in place, and only when every value it replaces is a
// plain literal: a pattern shared through a constant (Firefox's five channels,
// Qoder's three apps) is refused rather than edited, because changing it would
// change recipes nobody asked about.
//
// The scanner below knows exactly as much Swift as the family files use: line and
// nested block comments, `"…"`, `"""…"""` and raw strings of any `#` depth.
// Anything it does not understand makes it refuse. The golden gate in
// `ChangelogAutofix` checks the result independently, so a mistake here costs a
// skipped fix, never a wrong one.

enum RecipeLiteralEditor {

    /// The values to write. A nil field is left as it is.
    struct Edit: Equatable, Sendable {
        var source: URL?
        var entryPattern: String?
        var itemPatterns: [String]?
    }

    struct Failure: Error, CustomStringConvertible, Equatable {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// `text` with the `index`-th element of the `changelogs:` array rewritten.
    ///
    /// `index` is the recipe's position in its `AppRecipeSet.changelogs`, and
    /// `count` that array's length; both come from the compiled registry, so a
    /// file whose array this scanner reads differently from the compiler is
    /// refused rather than edited at the wrong element. `bundleID` is checked
    /// against the element's own `bundleID:` literal for the same reason.
    static func apply(
        _ edit: Edit, toChangelogAt index: Int, count: Int, bundleID: String, in text: String
    ) throws -> String {
        let source = Array(text.unicodeScalars)
        let tokens = try Scanner(source).kinds()
        guard let arrayOpen = findArgument("changelogs", in: source, code: tokens) else {
            throw Failure("no `changelogs:` argument in the family file")
        }
        let elements = try splitTopLevel(source, from: arrayOpen, open: "[", close: "]", code: tokens)
        guard elements.count == count else {
            throw Failure("read \(elements.count) changelog elements, the registry has \(count)")
        }
        let element = elements[index]
        let call = trimmed(element, in: source, code: tokens)
        let prefix = "ChangelogRecipe("
        guard String(String.UnicodeScalarView(source[call.lowerBound..<min(call.upperBound, call.lowerBound + prefix.unicodeScalars.count)])) == prefix else {
            throw Failure("changelog element \(index) is not a `ChangelogRecipe(…)` call")
        }
        let parenOpen = call.lowerBound + prefix.unicodeScalars.count - 1
        let args = try splitTopLevel(source, from: parenOpen, open: "(", close: ")", code: tokens)
        var labelled: [String: Range<Int>] = [:]
        for arg in args {
            guard let (label, value) = labelAndValue(arg, in: source, code: tokens) else { continue }
            labelled[label] = value
        }
        guard let bundleRange = labelled["bundleID"],
              stringLiteralValue(source, bundleRange) == bundleID else {
            throw Failure("changelog element \(index) is not \(bundleID)'s")
        }

        var replacements: [(Range<Int>, String)] = []
        if let url = edit.source {
            guard let range = labelled["source"] else { throw Failure("no `source:` argument") }
            replacements.append((try urlLiteralContent(source, range), try plainLiteralBody(url.absoluteString)))
        }
        if let pattern = edit.entryPattern {
            guard let range = labelled["entryPattern"],
                  concatenatedValue(source, range, code: tokens) != nil else {
                throw Failure("`entryPattern:` is not a string literal")
            }
            replacements.append((range, try render(pattern, replacing: range, in: source)))
        }
        if let patterns = edit.itemPatterns {
            guard let range = labelled["itemPatterns"] else { throw Failure("no `itemPatterns:` argument") }
            let open = trimmed(range, in: source, code: tokens)
            guard source[open.lowerBound] == "[" else {
                throw Failure("`itemPatterns:` is not an array literal")
            }
            for element in try splitTopLevel(source, from: open.lowerBound, open: "[", close: "]", code: tokens)
            where concatenatedValue(source, trimmed(element, in: source, code: tokens), code: tokens) == nil {
                throw Failure("`itemPatterns:` holds something other than string literals")
            }
            guard !patterns.isEmpty else { throw Failure("`itemPatterns` may not be empty") }
            replacements.append((open, "[" + (try patterns.map(rawLiteral)).joined(separator: ", ") + "]"))
        }

        var out = source
        for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            out.replaceSubrange(range, with: Array(replacement.unicodeScalars))
        }
        return String(String.UnicodeScalarView(out))
    }

    // MARK: - writing literals

    /// How many characters of a pattern go in one literal of a concatenation,
    /// which with the indentation keeps a line near the house width of 100.
    static let chunkLength = 64

    /// `value` in the shape of the expression it replaces: one literal for one
    /// literal, or for a `+` concatenation over several lines — most patterns in
    /// the family files are written that way to stay readable — the same layout
    /// at the same indentation. The result is read back before it is returned.
    static func render(_ value: String, replacing range: Range<Int>, in s: [Unicode.Scalar]) throws -> String {
        let old = String(String.UnicodeScalarView(s[range]))
        let rendered: String
        if let newline = old.firstIndex(of: "\n") {
            let indent = old[old.index(after: newline)...].prefix { $0 == " " || $0 == "\t" }
            rendered = try chunks(of: value).map(rawLiteral).joined(separator: "\n\(indent)+ ")
        } else {
            rendered = try rawLiteral(value)
        }
        let scalars = Array(rendered.unicodeScalars)
        guard concatenatedValue(scalars, 0..<scalars.count, code: try Scanner(scalars).kinds()) == value
        else { throw Failure("the rewritten literal does not read back as the value") }
        return rendered
    }

    /// `value` cut into pieces of about `chunkLength`, for a reviewer to read.
    ///
    /// Where it can, a piece ends just before a `<` or a `(` in the second half of
    /// the width, so a tag or a group starts a line instead of being cut through
    /// (`(?<b"# + #"ody>` reads as two broken halves). Never after a backslash,
    /// so no piece ends in what looks like half an escape. Any cut is correct —
    /// the pieces are joined back by `+` — so this is layout only.
    static func chunks(of value: String) -> [String] {
        let characters = Array(value)
        var pieces: [String] = []
        var start = 0
        while characters.count - start > chunkLength {
            var end = start + chunkLength
            let floor = start + chunkLength / 2
            if let natural = (floor...end).reversed().first(where: { i in
                (characters[i] == "<" || characters[i] == "(") && characters[i - 1] != "\\"
            }) {
                end = natural
            }
            while end < characters.count, characters[end - 1] == "\\" { end += 1 }
            pieces.append(String(characters[start..<end]))
            start = end
        }
        if start < characters.count || pieces.isEmpty { pieces.append(String(characters[start...])) }
        return pieces
    }

    /// `value` as a single-line raw string literal, with the fewest `#` that keep
    /// it from ending early or reading as an escape or an interpolation.
    static func rawLiteral(_ value: String) throws -> String {
        guard !value.contains(where: \.isNewline) else {
            throw Failure("a pattern with a line break cannot be written as one literal")
        }
        var hashes = 1
        while true {
            let delimiter = String(repeating: "#", count: hashes)
            if !value.contains("\"" + delimiter) && !value.contains("\\" + delimiter) {
                return delimiter + "\"" + value + "\"" + delimiter
            }
            hashes += 1
        }
    }

    /// The inside of a plain `"…"` for a URL. Anything that would need escaping
    /// is refused: a URL that needs it is not one this should be writing.
    static func plainLiteralBody(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: {
            $0 == "\"" || $0 == "\\" || $0.properties.isWhitespace || $0.value < 0x20
        }) else {
            throw Failure("the URL contains a character that would need escaping")
        }
        return value
    }

    // MARK: - reading the call

    /// The range of the characters between the quotes of `URL(string: "…")!`.
    private static func urlLiteralContent(_ s: [Unicode.Scalar], _ range: Range<Int>) throws -> Range<Int> {
        let text = String(String.UnicodeScalarView(s[range]))
        let pattern = #"^\s*URL\(string:\s*"([^"\\]*)"\)!\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let inner = Range(match.range(at: 1), in: text)
        else {
            throw Failure("`source:` is not a plain `URL(string: \"…\")!`")
        }
        let start = range.lowerBound + text.unicodeScalars.distance(
            from: text.unicodeScalars.startIndex, to: inner.lowerBound)
        return start..<(start + text[inner].unicodeScalars.count)
    }

    /// The value of a single string literal, plain or raw, or nil when the range
    /// holds anything else. Escapes in a plain literal are refused rather than
    /// decoded; only raw literals carry patterns in the family files.
    static func stringLiteralValue(_ s: [Unicode.Scalar], _ range: Range<Int>) -> String? {
        let text = String(String.UnicodeScalarView(s[range]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hashes = text.prefix(while: { $0 == "#" }).count
        let delimiter = String(repeating: "#", count: hashes)
        let open = delimiter + "\""
        let close = "\"" + delimiter
        guard text.hasPrefix(open), text.hasSuffix(close), text.count >= open.count + close.count,
              !text.hasPrefix(delimiter + "\"\"\"")
        else { return nil }
        let inner = String(text.dropFirst(open.count).dropLast(close.count))
        if hashes == 0, inner.contains("\\") || inner.contains("\"") { return nil }
        if hashes > 0, inner.contains(close) || inner.contains("\\" + delimiter) { return nil }
        return inner
    }

    /// The value of `range` when it is one string literal, or several joined with
    /// `+`; nil for anything else. A comment inside the expression is refused too,
    /// by the same two guards (it is neither a literal nor a `+`): rewriting the
    /// expression would delete it.
    static func concatenatedValue(_ s: [Unicode.Scalar], _ range: Range<Int>, code: [Kind]) -> String? {
        var out = ""
        var wantLiteral = true
        var i = range.lowerBound
        while i < range.upperBound {
            if code[i] == .code, s[i].properties.isWhitespace { i += 1; continue }
            if wantLiteral {
                guard code[i] == .string else { return nil }
                var j = i
                while j < range.upperBound, code[j] == .string { j += 1 }
                guard let value = stringLiteralValue(s, i..<j) else { return nil }
                out += value
                i = j
                wantLiteral = false
            } else {
                guard code[i] == .code, s[i] == "+" else { return nil }
                i += 1
                wantLiteral = true
            }
        }
        return wantLiteral ? nil : out
    }

    private static func findArgument(
        _ label: String, in s: [Unicode.Scalar], code: [Kind]
    ) -> Int? {
        let needle = Array((label + ":").unicodeScalars)
        var i = 0
        while i + needle.count <= s.count {
            if code[i..<(i + needle.count)].allSatisfy({ $0 == .code }),
               Array(s[i..<(i + needle.count)]) == needle,
               i == 0 || !isIdentifier(s[i - 1]) {
                var j = i + needle.count
                while j < s.count, code[j] == .comment || s[j].properties.isWhitespace { j += 1 }
                return j < s.count && s[j] == "[" ? j : nil
            }
            i += 1
        }
        return nil
    }

    /// The top-level elements between `s[from]` (an `open`) and its match, split
    /// on commas outside nested brackets, strings and comments. A trailing comma
    /// leaves no empty element.
    private static func splitTopLevel(
        _ s: [Unicode.Scalar], from: Int, open: Unicode.Scalar, close: Unicode.Scalar,
        code: [Kind]
    ) throws -> [Range<Int>] {
        precondition(s[from] == open)
        var depth = 0
        var start = from + 1
        var parts: [Range<Int>] = []
        var i = from
        while i < s.count {
            defer { i += 1 }
            guard code[i] == .code else { continue }
            switch s[i] {
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth == 0 {
                    guard s[i] == close else { throw Failure("unbalanced brackets") }
                    parts.append(start..<i)
                    return parts.filter { !isBlank($0, in: s, code: code) }
                }
            case "," where depth == 1:
                parts.append(start..<i)
                start = i + 1
            default:
                break
            }
        }
        throw Failure("unbalanced brackets")
    }

    private static func labelAndValue(
        _ range: Range<Int>, in s: [Unicode.Scalar], code: [Kind]
    ) -> (String, Range<Int>)? {
        let body = trimmed(range, in: s, code: code)
        var i = body.lowerBound
        while i < body.upperBound, code[i] == .code, isIdentifier(s[i]) { i += 1 }
        guard i > body.lowerBound, i < body.upperBound, code[i] == .code, s[i] == ":"
        else { return nil }
        let label = String(String.UnicodeScalarView(s[body.lowerBound..<i]))
        return (label, trimmed((i + 1)..<body.upperBound, in: s, code: code))
    }

    /// `range` without leading and trailing whitespace and comments.
    private static func trimmed(_ range: Range<Int>, in s: [Unicode.Scalar], code: [Kind]) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, code[lower] == .comment || s[lower].properties.isWhitespace && code[lower] == .code {
            lower += 1
        }
        while upper > lower,
              code[upper - 1] == .comment || s[upper - 1].properties.isWhitespace && code[upper - 1] == .code {
            upper -= 1
        }
        return lower..<upper
    }

    private static func isBlank(_ range: Range<Int>, in s: [Unicode.Scalar], code: [Kind]) -> Bool {
        trimmed(range, in: s, code: code).isEmpty
    }

    private static func isIdentifier(_ c: Unicode.Scalar) -> Bool {
        c == "_" || c.properties.isAlphabetic || ("0"..."9").contains(c)
    }

    // MARK: - the scanner

    enum Kind { case code, comment, string }

    /// What each scalar of `s` is part of. A literal's delimiters count as
    /// `string` too, so nothing inside or around a literal reads as structure.
    struct Scanner {
        let s: [Unicode.Scalar]
        init(_ s: [Unicode.Scalar]) { self.s = s }

        func kinds() throws -> [Kind] {
            var kind = [Kind](repeating: .code, count: s.count)
            var i = 0
            while i < s.count {
                let start = i
                if at(i, "//") {
                    while i < s.count, s[i] != "\n" { i += 1 }
                    for k in start..<i { kind[k] = .comment }
                } else if at(i, "/*") {
                    var depth = 0
                    repeat {
                        if at(i, "/*") { depth += 1; i += 2 }
                        else if at(i, "*/") { depth -= 1; i += 2 }
                        else { i += 1 }
                    } while depth > 0 && i < s.count
                    guard depth == 0 else { throw Failure("unterminated block comment") }
                    for k in start..<i { kind[k] = .comment }
                } else if (s[i] == "#" || s[i] == "\""), let end = try stringEnd(from: i) {
                    for k in start..<end { kind[k] = .string }
                    i = end
                } else {
                    i += 1
                }
            }
            return kind
        }

        private func at(_ i: Int, _ literal: String) -> Bool {
            let l = Array(literal.unicodeScalars)
            return i + l.count <= s.count && Array(s[i..<(i + l.count)]) == l
        }

        /// The index just past a string literal starting at `i`, or nil when `i`
        /// is a `#` that does not open one (`#if`, `#filePath`).
        private func stringEnd(from i: Int) throws -> Int? {
            var j = i
            while j < s.count, s[j] == "#" { j += 1 }
            let hashes = j - i
            guard j < s.count, s[j] == "\"" else { return nil }
            let delimiter = String(repeating: "#", count: hashes)
            let multiline = at(j, "\"\"\"")
            let quote = multiline ? "\"\"\"" : "\""
            j += quote.unicodeScalars.count
            let closing = quote + delimiter
            while j < s.count {
                if hashes == 0, s[j] == "\\" { j += 2; continue }
                if at(j, closing) { return j + closing.unicodeScalars.count }
                if !multiline, s[j] == "\n" { throw Failure("unterminated string literal") }
                j += 1
            }
            throw Failure("unterminated string literal")
        }
    }
}
