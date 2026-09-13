import Foundation

/// Hand-curated changelog pages keyed by bundle identifier, for apps whose update
/// source ships no inline notes and no `changelogURL` of its own.
///
/// Two kinds of app land here:
///   - apps with no update source at all — an `auto_updates` Homebrew cask
///     (Ghostty, Ollama) defers out of `HomebrewCaskSource` by design, so it has
///     no `RemoteVersion` to hang a URL on (see the brew auto_updates note); and
///   - apps whose source produced a `RemoteVersion` but no curated URL — a plain
///     Homebrew cask like CodexBar (Homebrew gives us no inline release notes).
///
/// The changelog UI consults this as the LAST fallback, *after* any
/// source-supplied `changelogURL`, so it never overrides a feed's own notes.
/// Keeping it out of the update sources is deliberate: changelog availability is
/// orthogonal to whether (and how) we can install an update — an app we refuse to
/// update through brew (because it self-updates) can still show its release notes.
public enum ChangelogCatalog {
    /// bundleID (lowercased) → changelog page.
    static let pages: [String: URL] =
        AppRecipeIndex.merged(\.changelogPages, into: "ChangelogCatalog.pages")

    /// The curated changelog page for an app, if we have one. Case-insensitive on
    /// bundleID — ids are conventionally lowercase but not guaranteed, and we'd
    /// rather match than miss on a stray capital.
    public static func url(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return pages[bundleID.lowercased()]
    }
}
