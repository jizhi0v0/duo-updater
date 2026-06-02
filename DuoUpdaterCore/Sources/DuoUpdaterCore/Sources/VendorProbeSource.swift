import Foundation

/// Last-resort source for apps with a self-baked auto-updater and no App Store,
/// Sparkle, or Homebrew coverage. For each such app we maintain a bespoke
/// "probe recipe" (see `VendorProbeRecipe`) that reads the latest version
/// straight from the vendor's own download endpoint.
///
/// Wired as the **final** source in the checker so it only runs when the three
/// standard sources have all missed — vendor probes are slow, fragile, and
/// should never pre-empt a reliable source.
///
/// Best-effort by design: any failure (network, redirect, parse) degrades
/// silently to "unknown". It never throws to the engine and never reports a
/// version it isn't confident about, so it can't produce a false "update
/// available" or a spurious error.
public struct VendorProbeSource: UpdateSource {
    public let name = "Vendor"

    /// Keyed by bundle id → the recipes for that id, one per release channel.
    /// Most apps have a single (stable) recipe; channels that share a bundle id
    /// (e.g. Android Studio stable + Canary) list several and are disambiguated
    /// by the installed app's detected channel.
    private let recipes: [String: [VendorProbeRecipe]]
    private let session: URLSession
    /// A session that does NOT follow redirects, for recipes whose endpoint 302s
    /// to a large binary (we want the redirect's `Location`/body, not the file).
    private let noRedirectSession: URLSession

    /// Cancels every redirect so the 3xx response is returned as-is.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// A browser-like UA — several vendor sites reject unfamiliar agents.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public init(
        recipes: [VendorProbeRecipe] = VendorProbeRegistry.recipes,
        session: URLSession = .shared
    ) {
        // Group by bundle id; each group holds that id's per-channel recipes.
        self.recipes = Dictionary(grouping: recipes, by: { $0.bundleID })
        self.session = session
        self.noRedirectSession = URLSession(
            configuration: .ephemeral,
            delegate: RedirectBlocker(),
            delegateQueue: nil)
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // A Toolbox-managed JetBrains IDE updates through Toolbox. Probing the
        // vendor endpoint here would offer a cross-channel install — exactly what
        // we forbid — so defer to Toolbox even when a recipe matches the bundle.
        guard !app.isToolboxManaged else { return nil }
        guard let bundleID = app.bundleID, let candidates = recipes[bundleID] else {
            return nil  // no recipe for this app — not applicable
        }
        // Channel gate: pick the recipe whose channel matches the installed app's,
        // and refuse if none does. When channels share a bundle id (e.g. Android
        // Studio's stable and Canary both carry `com.google.android.studio`), this
        // selects the right endpoint; when only a stable recipe exists, a detected
        // Beta/Canary install finds no match and is skipped rather than offered —
        // and one-click installed — a cross-channel build. Better "unknown" than
        // crossing channels.
        guard let recipe = candidates.first(where: { $0.channel == app.releaseChannel }) else {
            Log.source.info(
                "vendor probe skip \(bundleID, privacy: .public): no recipe for app channel \(app.releaseChannel.rawValue, privacy: .public)")
            return nil
        }
        // Swallow every failure: a probe that can't answer must look like "this
        // source doesn't apply", not like an error or a confident result.
        return (try? await probe(recipe)) ?? nil
    }

    /// Run one recipe. Returns nil (→ "unknown") on any non-confident outcome.
    private func probe(_ recipe: VendorProbeRecipe) async throws -> RemoteVersion? {
        let text: String
        let resolvedDownload: URL?

        switch recipe.mode {
        case .redirectFilename:
            var request = URLRequest(url: recipe.url)
            request.timeoutInterval = 15
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            if recipe.followRedirects {
                // HEAD + follow: the version lives in the final resolved URL's
                // filename (e.g. "ToDesk_4.7.6.0.dmg").
                request.httpMethod = "HEAD"
                let (_, response) = try await session.data(for: request)
                guard
                    let http = response as? HTTPURLResponse,
                    (200..<400).contains(http.statusCode),
                    let finalURL = response.url
                else { return nil }
                text = finalURL.lastPathComponent
                resolvedDownload = finalURL
            } else {
                // GET + don't follow: read the version out of the 3xx `Location`
                // header itself (following would just download the target). Some
                // endpoints — e.g. Claude's `dmg/latest/redirect` — 307 only on
                // GET, reject HEAD with 405, and expose the version nowhere but
                // the Location path, so `text` is the full redirect target.
                request.httpMethod = "GET"
                let (_, response) = try await noRedirectSession.data(for: request)
                guard
                    let http = response as? HTTPURLResponse,
                    (300..<400).contains(http.statusCode),
                    let location = http.value(forHTTPHeaderField: "Location"),
                    let finalURL = URL(string: location, relativeTo: recipe.url)?.absoluteURL
                else { return nil }
                text = finalURL.absoluteString
                resolvedDownload = finalURL
            }

        case .responseBody:
            var request = URLRequest(url: recipe.url)
            request.timeoutInterval = 15
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            // When not following redirects we want the 3xx itself (its small body
            // / Location), so widen the accepted range and use the blocking session.
            let activeSession = recipe.followRedirects ? session : noRedirectSession
            let okRange = recipe.followRedirects ? (200..<300) : (200..<400)
            let (data, response) = try await activeSession.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                okRange.contains(http.statusCode)
            else { return nil }

            text = String(decoding: data, as: UTF8.self)
            resolvedDownload = recipe.downloadURL ?? recipe.url
        }

        // Default to the first match (the app's own field, which structured
        // bodies list first); only ascending-order feeds opt into highest-wins.
        let extractor = recipe.selectHighest
            ? VendorProbeRecipe.highestVersion
            : VendorProbeRecipe.extractVersion
        guard let version = extractor(text, recipe.versionPattern) else { return nil }

        // If this recipe knows how to install in place, resolve the installer URL
        // (and any checksum) now — from the same body we already have. A failure
        // here just falls back to detection-only; it never blocks the version.
        if let spec = recipe.install,
           let plan = try? await resolveInstall(spec, body: text) {
            return RemoteVersion(
                shortVersion: version,
                version: nil,
                downloadURL: plan.url,
                sourceName: name,
                // pkg → hand to the system installer; archives → in-place swap.
                requiresManualInstaller: spec.kind == .pkg,
                vendorInstallerKind: spec.kind,
                expectedSHA512: plan.checksum,
                downloadHeaders: spec.requestHeaders,
                changelogURL: recipe.changelogURL
            )
        }

        return RemoteVersion(
            shortVersion: version,
            version: nil,
            downloadURL: recipe.downloadURL ?? resolvedDownload,
            sourceName: name,
            // No install spec: detection only — the user downloads by hand.
            requiresManualInstaller: true,
            changelogURL: recipe.changelogURL
        )
    }

    /// Resolve an install spec into a concrete (url, checksum) pair. The body is
    /// the probe response we already fetched, reused for `bodyPattern` extraction.
    private func resolveInstall(
        _ spec: VendorInstallSpec, body: String
    ) async throws -> (url: URL, checksum: String?)? {
        let checksum = spec.checksumPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: body, pattern: $0)
        }

        switch spec.urlSource {
        case .fixed(let url):
            return (Self.preferHTTPS(url), checksum)

        case .bodyPattern(let pattern):
            guard
                let raw = VendorProbeRecipe.extractVersion(from: body, pattern: pattern),
                let url = URL(string: raw)
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyPatternLast(let pattern):
            guard
                let raw = VendorProbeRecipe.lastMatch(from: body, pattern: pattern),
                let url = URL(string: raw)
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyPatternRelative(let pattern, let base):
            guard
                let raw = VendorProbeRecipe.extractVersion(from: body, pattern: pattern),
                let url = URL(string: raw, relativeTo: base)?.absoluteURL
            else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .bodyTemplate(let template, let fields):
            var filled = template
            for (i, pattern) in fields.enumerated() {
                guard let value = VendorProbeRecipe.extractVersion(from: body, pattern: pattern)
                else { return nil }
                filled = filled.replacingOccurrences(of: "{\(i)}", with: value)
            }
            guard let url = URL(string: filled) else { return nil }
            return (Self.preferHTTPS(url), checksum)

        case .redirect(let url):
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 15
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (_, response) = try await session.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<400).contains(http.statusCode),
                let finalURL = response.url
            else { return nil }
            return (Self.preferHTTPS(finalURL), checksum)
        }
    }

    /// Upgrade an `http://` download URL to `https://`. Our vendor hosts all
    /// support TLS, and App Transport Security blocks plain-http loads anyway;
    /// if a host somehow lacked https the download would just fail and degrade to
    /// detection-only — never wrong data. (VLC's appcast lists http mirrors.)
    private static func preferHTTPS(_ url: URL) -> URL {
        guard url.scheme == "http",
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        comps.scheme = "https"
        return comps.url ?? url
    }
}
