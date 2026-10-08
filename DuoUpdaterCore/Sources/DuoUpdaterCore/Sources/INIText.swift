import Foundation

/// The INI reading the file-backed channel bindings share: CapCut's Qt
/// `QSettings` files and OBS's libobs `config_t` file are both `[Section]` +
/// `key=value` text, and a second hand-rolled copy of this loop is how one of
/// them would end up quietly accepting a key from the wrong section.
enum INIText {

    /// Both apps' files are a handful of lines; the cap is there so a path that
    /// turns out to be something else entirely is not read into memory wholesale.
    static func read(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1024
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// First value of `key` in `[section]`, or nil.
    ///
    /// Section-aware on purpose. A bare "does the text contain key=value" scan
    /// would keep answering if the vendor moved the key under some other heading
    /// — silently escalating a stable user to a prerelease track, which is the
    /// one direction a channel resolver is not allowed to get wrong.
    static func value(of key: String, inSection section: String, of text: String) -> String? {
        let header = "[\(section)]"
        var inSection = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line.caseInsensitiveCompare(header) == .orderedSame
                continue
            }
            guard inSection, let separator = line.firstIndex(of: "=") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard name.caseInsensitiveCompare(key) == .orderedSame else { continue }
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            // QSettings quotes values it considers to need it, and CapCut's own
            // `looki_settings` is full of them (`LookiDomainKey="https://…"`). No
            // key either binding reads is quoted today — but a quoted
            // `"capcutpc_beta"` would silently stop matching the token and read as
            // a stable build.
            guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"")
            else { return value }
            return String(value.dropFirst().dropLast())
        }
        return nil
    }
}
