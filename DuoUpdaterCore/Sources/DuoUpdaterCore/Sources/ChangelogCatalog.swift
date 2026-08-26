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
    static let pages: [String: URL] = [
        // Ghostty — auto_updates cask, no Sparkle feed; official release notes.
        "com.mitchellh.ghostty": URL(string: "https://ghostty.org/docs/install/release-notes")!,
        // Ollama — auto_updates cask, Electron app; GitHub releases.
        "com.electron.ollama": URL(string: "https://github.com/ollama/ollama/releases")!,
        // CodexBar — plain Homebrew cask (no inline notes); GitHub releases.
        "com.steipete.codexbar": URL(string: "https://github.com/steipete/CodexBar/releases")!,
        // Surge Mac — official release-notes page; the public changelog site is
        // JS-backed, so we point the fallback web view at the vendor page itself.
        "com.nssurge.surge-mac": URL(string: "https://nssurge.com/support/mac/release-notes")!,
        // ChatWise — the live structured notes come from the releases JSON, but
        // we still want an explicit fallback page when the lazy fetch/parser
        // misses or the update check hasn't populated a remote changelog URL yet.
        "app.chatwise": URL(string: "https://chatwise.app/changelog")!,
        // Longbridge Desktop — the structured recipe follows the exact version
        // page. Keep the English release-notes index as a web fallback while an
        // update result or a freshly added recipe has not populated yet.
        "com.longbridge.app.desktop": URL(string: "https://longbridge.com/desktop/release-notes/")!,
        // WhatsApp — iOS-on-Mac (kind=software); MAS source scrapes the Mac page
        // for version comparison, but `remote` may be nil at render time if the
        // check hasn't finished. This catalog entry ensures the Mac App Store page
        // always shows as changelog fallback regardless of check timing.
        // `?platform=mac` redirects correctly regardless of storefront region.
        // Key MUST be lowercase — `url(forBundleID:)` lowercases its argument
        // before the lookup, so a mixed-case key here is simply unreachable. This
        // one was `net.whatsapp.WhatsApp` and never resolved; `keysAreLowercased`
        // now guards the whole table.
        "net.whatsapp.whatsapp": URL(string: "https://apps.apple.com/app/id310633997?platform=mac")!,

    ]

    /// The curated changelog page for an app, if we have one. Case-insensitive on
    /// bundleID — ids are conventionally lowercase but not guaranteed, and we'd
    /// rather match than miss on a stray capital.
    public static func url(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return pages[bundleID.lowercased()]
    }
}
