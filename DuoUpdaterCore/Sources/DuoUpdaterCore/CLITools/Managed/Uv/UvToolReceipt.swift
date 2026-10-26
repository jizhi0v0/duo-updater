import Foundation

/// What `uv tool install` wrote beside a tool's venv, `uv-receipt.toml`, as far
/// as the managed row needs it (UV-06/07/08/28). uv 0.13.4 wrote, for
/// `uv tool install 'black>=23,<24'` (2026-10-27):
///
///     [tool]
///     requirements = [{ name = "black", specifier = ">=23,<24" }]
///     entrypoints = [
///         { name = "black", install-path = "…/.local/bin/black", from = "black" },
///         …
///     ]
///
/// with `python = "3.12"` under `[tool]` when `--python` was passed, and a
/// `[tool.options]` table (`exclude-newer`, indexes) when options were. Not a
/// TOML parser: the inline tables of `requirements` are read for their quoted
/// `name` and `specifier`, the rest by `key = "value"` lines.
struct UvToolReceipt: Sendable, Equatable {
    /// The requirement that named the tool: its PEP 508 name and specifier,
    /// nil for an unpinned `uv tool install ruff`.
    let requirement: (name: String, specifier: String?)
    /// `[tool.options] exclude-newer`: uv resolves nothing uploaded after it
    /// (honoured by `--outdated` from 0.11.0, UV-14c).
    let excludeNewer: String?
    let python: String?
    /// Where the tool came from when not an index: "a local path", "git", "a
    /// URL" — a requirement table with `path`, `directory`, `git` or `url`
    /// (uv 0.13.4 wrote `{ name = "cowsay", path = "….whl" }` for a wheel).
    var source: String? = nil
    /// `constraints`/`overrides` naming the tool (`uv tool install -c`):
    /// `uv tool upgrade` resolves inside them (`upgrade.rs`), so they narrow
    /// the request like a specifier does.
    var narrowedBy: String? = nil

    static func == (a: UvToolReceipt, b: UvToolReceipt) -> Bool {
        a.requirement.name == b.requirement.name && a.requirement.specifier == b.requirement.specifier
            && a.excludeNewer == b.excludeNewer && a.python == b.python && a.source == b.source
            && a.narrowedBy == b.narrowedBy
    }

    /// The receipt of the tool in directory `tool` (its name); nil when it
    /// names no requirement at all.
    static func parse(_ data: Data, tool: String) -> UvToolReceipt? {
        let text = String(decoding: data, as: UTF8.self)
        let requirements = inlineTables(after: "requirements", in: text)
        let wanted = PythonDistribution.normalize(tool)
        var tables = requirements.compactMap { table -> (String, String?, String?)? in
            guard let name = value("name", in: table) else { return nil }
            let source: String?
            if value("git", in: table) != nil { source = "git" }
            else if value("url", in: table) != nil { source = "a URL" }
            else if value("path", in: table) != nil || value("directory", in: table) != nil { source = "a local path" }
            else { source = nil }
            return (name, value("specifier", in: table), source)
        }
        // uv 0.2.20–0.2.31 wrote PEP 508 strings (`["cowsay==5.0"]`), which
        // 0.13.4 still reads.
        if tables.isEmpty {
            tables = quotedStrings(after: "requirements", in: text).compactMap { requirement in
                guard let name = PipxMetadata.requirementName(requirement) else { return nil }
                if requirement.contains("@") || requirement.contains("://") { return (name, nil, "a URL") }
                let specifier = requirement.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                return (name, specifier.isEmpty ? nil : specifier, nil)
            }
        }
        guard let requirement = tables.first(where: { PythonDistribution.normalize($0.0) == wanted }) ?? tables.first
        else { return nil }
        let narrowing = (inlineTables(after: "constraints", in: text) + inlineTables(after: "overrides", in: text))
            .filter { value("name", in: $0).map(PythonDistribution.normalize) == PythonDistribution.normalize(requirement.0) }
            .compactMap { value("specifier", in: $0) }
        var section = ""
        var excludeNewer: String?
        var python: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line; continue }
            if section == "[tool.options]", let v = value("exclude-newer", in: line, anchored: true) { excludeNewer = v }
            if section == "[tool]", let v = value("python", in: line, anchored: true) { python = v }
        }
        return UvToolReceipt(
            requirement: (requirement.0, requirement.1.flatMap { $0.isEmpty ? nil : $0 }),
            excludeNewer: excludeNewer, python: python, source: requirement.2,
            narrowedBy: narrowing.isEmpty ? nil : narrowing.joined(separator: ","))
    }

    /// The quoted strings of the array `key = [ … ]`.
    static func quotedStrings(after key: String, in text: String) -> [String] {
        guard let start = text.range(of: #"(?m)^\s*"# + key + #"\s*=\s*\["#, options: .regularExpression) else { return [] }
        var strings: [String] = []
        var current: String?
        for character in text[start.upperBound...] {
            if character == "\"" {
                if let done = current { strings.append(done); current = nil } else { current = "" }
            } else if current != nil {
                current?.append(character)
            } else if character == "]" {
                break
            }
        }
        return strings
    }

    /// The `{ … }` tables of the array `key = [ … ]`, which may span lines.
    static func inlineTables(after key: String, in text: String) -> [String] {
        guard let start = text.range(of: #"(?m)^\s*"# + key + #"\s*=\s*\["#, options: .regularExpression) else { return [] }
        var tables: [String] = []
        var current: String?
        var inString = false
        var depth = 0
        for character in text[start.upperBound...] {
            if character == "\"" { inString.toggle() }
            if !inString {
                if character == "{" { depth += 1; if depth == 1 { current = ""; continue } }
                if character == "}" {
                    depth -= 1
                    if depth == 0, let done = current { tables.append(done); current = nil; continue }
                }
                if character == "]", depth == 0 { break }
            }
            current?.append(character)
        }
        return tables
    }

    /// The quoted value of `key` in `text`: `name = "black"`. `anchored` reads
    /// a whole `key = "value"` line only.
    static func value(_ key: String, in text: String, anchored: Bool = false) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = (anchored ? "^" : #"(?:^|[\s,{])"#) + escaped + #"\s*=\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    /// `==0.6.0` (one clause, no wildcard): held where it is (`.exact`);
    /// anything else that narrows (`>=23,<24`, `~=1.2`, `==1.*`) is a range;
    /// no specifier, nothing to follow but the newest.
    var request: ManagedItem.Request? {
        if let narrowedBy {
            let spelled = [requirement.specifier, narrowedBy].compactMap { $0 }.joined(separator: ",")
            return ManagedItem.Request(kind: .range, spelled: spelled)
        }
        guard let specifier = requirement.specifier else { return nil }
        let clauses = specifier.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if clauses.count == 1, let clause = clauses.first, clause.hasPrefix("==") || clause.hasPrefix("==="),
           !clause.hasSuffix(".*") {
            return ManagedItem.Request(kind: .exact, spelled: specifier)
        }
        return ManagedItem.Request(kind: .range, spelled: specifier)
    }

    /// `exclude-newer` as a date: an RFC 3339 instant, or a bare day (uv
    /// reads `2024-03-25` as the end of that day, UTC).
    var excludeNewerDate: Date? { excludeNewer.flatMap(Self.date(excludeNewer:)) }

    static func date(excludeNewer: String) -> Date? {
        // `--exclude-newer P1100D` wrote "2023-10-22T17:16:21.688846Z"; the
        // formatter reads no fraction, and seconds are all a cut-off needs.
        let whole = excludeNewer.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        if let instant = ISO8601DateFormatter().date(from: whole) { return instant }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: excludeNewer).map { $0.addingTimeInterval(24 * 60 * 60 - 1) }
    }
}

/// `uv tool list --outdated` (uv ≥0.10.10): `name vX [latest: Y]` for each
/// outdated tool, each followed by `- <executable>` lines; a current tool is
/// not listed. Measured on uv 0.13.4, 2026-10-27, three tools on Python 3.9:
///
///     black v23.12.1 [latest: 25.11.0]
///     - black
///     - blackd
///     cowsay v5.0 [latest: 6.1]
///     - cowsay
///
/// Its latest is the newest the tool's Python can install, ignoring the
/// receipt's specifier (UV-10/13). Offline it fails — exit 2, "Request failed
/// after 3 retries in 6.7s", nothing on stdout — so an empty list with exit 0
/// means every tool is current.
enum UvToolOutdated {
    static func parse(_ stdout: Data) -> [String: (installed: String, latest: String)] {
        var found: [String: (String, String)] = [:]
        let regex = try? NSRegularExpression(pattern: #"^(\S+) v(\S+) \[latest: ([^\]\s]+)\]\s*$"#)
        for raw in String(decoding: stdout, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard !line.hasPrefix("- "), let regex,
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line), let installed = Range(match.range(at: 2), in: line),
                  let latest = Range(match.range(at: 3), in: line)
            else { continue }
            found[PythonDistribution.normalize(String(line[name]))] = (String(line[installed]), String(line[latest]))
        }
        return found
    }
}
