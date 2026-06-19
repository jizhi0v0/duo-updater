import Foundation

extension String {
    /// Map an arbitrary string to a filesystem-safe filename token: keep
    /// alphanumerics and `.`/`-`/`_`, replace every other character (path
    /// separators, spaces, colons, …) with `_`, and never return empty. Shared by
    /// the on-disk caches so the rule lives in one place rather than re-implemented
    /// per cache. Note `/` is always replaced, so a token can never introduce a path
    /// separator when appended as a single path component.
    var filesystemSafeToken: String {
        let safe = unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == "." || c == "-" || c == "_" { return c }
            return "_"
        }
        let joined = String(safe)
        return joined.isEmpty ? "_" : joined
    }
}
