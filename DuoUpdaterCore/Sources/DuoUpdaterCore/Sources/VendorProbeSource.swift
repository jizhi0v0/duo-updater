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
    static let sourceName = "Vendor"
    public let name = VendorProbeSource.sourceName

    /// Keyed by bundle id → the recipes for that id, one per release channel.
    /// Most apps have a single (stable) recipe; channels that share a bundle id
    /// (e.g. Android Studio stable + Canary) list several and are disambiguated
    /// by the installed app's detected channel.
    private let recipes: [String: [VendorProbeRecipe]]
    private let session: URLSession

    /// Cancels every redirect so the 3xx response is returned as-is. No stored
    /// state, so `@unchecked Sendable` is safe and required for the static below.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate,
        @unchecked Sendable
    {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// Session that does NOT follow redirects, shared across all
    /// ``VendorProbeSource`` instances and refreshes. Allocated once — creating
    /// a new `URLSession` per `init` (which happens on every ``AppListModel``
    /// `recheck`) discarded the connection pool and forced cold TCP handshakes
    /// on every retry.
    ///
    /// Cookie acceptance is disabled: the session is process-lifetime static, so
    /// any `Set-Cookie` headers from a 3xx vendor endpoint would otherwise
    /// accumulate for the entire run.
    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }()

    /// A browser-like UA — several vendor sites reject unfamiliar agents.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public init(
        recipes: [VendorProbeRecipe] = VendorProbeRegistry.recipes,
        session: URLSession = .updates
    ) {
        // Group by bundle id; each group holds that id's per-channel recipes.
        self.recipes = Dictionary(grouping: recipes, by: { $0.bundleID })
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // A Toolbox-managed JetBrains IDE updates through Toolbox. Probing the
        // vendor endpoint here would offer a cross-channel install — exactly what
        // we forbid — so defer to Toolbox even when a recipe matches the bundle.
        // The exception is an app our recipe tracks more reliably than Toolbox's
        // own verdict (Android Studio Canary/Beta, where Toolbox's local cache is
        // flaky/cross-track); see `InstalledApp.prefersVendorProbeOverToolbox`.
        guard !app.isToolboxManaged || app.prefersVendorProbeOverToolbox else {
            return nil
        }
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
        //
        // For a Toolbox-managed app we only borrowed the probe to learn the version
        // RELIABLY (Toolbox's cache is flaky — see `prefersVendorProbeOverToolbox`);
        // the INSTALL must still go through Toolbox, never an in-place bundle swap
        // that would desync Toolbox's state and (for Android Studio) drag a ~1.5 GB
        // dmg off a drop-prone CDN. So resolve detection-only here.
        let resolved = (try? await probe(recipe, allowInstall: !app.prefersVendorProbeOverToolbox)) ?? nil
        // Record recipe health so a vendor changing their page surfaces in
        // diagnostics rather than silently degrading the app to "unknown". A
        // transient miss is cleared by the next successful check (success/miss are
        // compared by recency), so this only flags consistently-broken recipes.
        if resolved != nil {
            await RecipeHealth.shared.recordSuccess(id: bundleID, source: name)
        } else {
            await RecipeHealth.shared.recordMiss(
                id: bundleID, source: name, detail: "probe resolved no version")
        }
        return resolved
    }

    /// Run one recipe. Returns nil (→ "unknown") on any non-confident outcome.
    /// `allowInstall` false forces a detection-only result even when the recipe
    /// carries an install spec — used for apps whose install another channel owns
    /// (Toolbox-managed), where we want the version but not an in-place swap.
    private func probe(_ recipe: VendorProbeRecipe, allowInstall: Bool = true) async throws -> RemoteVersion? {
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
                let (_, response) = try await Self.noRedirectSession.data(for: request)
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
            let activeSession = recipe.followRedirects ? session : Self.noRedirectSession
            let okRange = recipe.followRedirects ? (200..<300) : (200..<400)
            let (data, response) = try await activeSession.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                okRange.contains(http.statusCode)
            else { return nil }

            text = String(decoding: data, as: UTF8.self)
            resolvedDownload = recipe.downloadURL ?? recipe.url

        case .zipEntryPlist(let entry, let key):
            // The version lives in a bundled Info.plist inside a (small) zip —
            // see `Mode.zipEntryPlist`. We extract the one entry and read `key`;
            // `text` becomes that value so the shared `versionPattern` validates
            // it exactly like any other mode. Any failure → nil → "unknown".
            guard let value = try await zipEntryPlistValue(
                url: recipe.url, entry: entry, key: key)
            else { return nil }
            text = value
            resolvedDownload = recipe.downloadURL ?? recipe.url
        }

        // Default to the first match (the app's own field, which structured
        // bodies list first); only ascending-order feeds opt into highest-wins.
        let extractor = recipe.selectHighest
            ? VendorProbeRecipe.highestVersion
            : VendorProbeRecipe.extractVersion
        guard let version = extractor(text, recipe.versionPattern) else { return nil }

        // Optional clean marketing string to show instead of an ugly build id
        // (e.g. Android Studio's "2026.1.2 RC 1" vs "AI-261.…"). Display only; the
        // build still drives the comparison. From the same body, so first-match.
        let display = recipe.displayVersionPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: text, pattern: $0)
        }

        // Optional authoritative publish time, from the same body (first match, so
        // it belongs to the entry `versionPattern` matched). An unparseable or
        // missing date is not a failure — it just means the Release Log falls back
        // to its estimated "≈" window, exactly as for recipes with no pattern.
        let publishedAt = ReleaseDate.parse(
            recipe.publishedAtPattern.flatMap {
                VendorProbeRecipe.extractVersion(from: text, pattern: $0)
            })

        // If this recipe knows how to install in place, resolve the installer URL
        // (and any checksum) now — from the same body we already have. A failure
        // here just falls back to detection-only; it never blocks the version.
        if allowInstall, let spec = recipe.install,
           let plan = try? await resolveInstall(spec, body: text) {
            return Self.makeRemoteVersion(
                recipe: recipe, version: version, install: spec, plan: plan,
                resolvedDownload: resolvedDownload, display: display,
                publishedAt: publishedAt)
        }

        return Self.makeRemoteVersion(
            recipe: recipe, version: version, install: nil, plan: nil,
            resolvedDownload: resolvedDownload, display: display,
            publishedAt: publishedAt)
    }

    /// Assemble the `RemoteVersion` a recipe yields from an already-extracted
    /// version (and, when installing, a resolved download plan). Pure and offline
    /// so the version-routing contract — in particular `versionIsBuild`, which
    /// decides whether the engine compares against the installed marketing or
    /// build version — is unit-testable without hitting the network.
    static func makeRemoteVersion(
        recipe: VendorProbeRecipe,
        version: String,
        install spec: VendorInstallSpec?,
        plan: (url: URL, checksum: String?)?,
        resolvedDownload: URL?,
        display: String? = nil,
        publishedAt: Date? = nil
    ) -> RemoteVersion {
        // A build-number recipe routes the value into `version` (compared against
        // the installed `CFBundleVersion`); `shortVersion` stays nil so a build
        // string can never be mismatched against a shorter marketing version —
        // UNLESS the recipe supplies an explicit display string (a clean marketing
        // version), in which case it rides in `shortVersion` for the UI only. The
        // engine still compares builds: `evaluate` prefers `version` whenever the
        // installed app has a `buildVersion`, which a `versionIsBuild` app always
        // does — so a display marketing string here never drives the comparison.
        let shortVersion = recipe.versionIsBuild ? display : version
        let buildVersion = recipe.versionIsBuild ? version : nil

        if let spec, let plan {
            return RemoteVersion(
                shortVersion: shortVersion,
                version: buildVersion,
                downloadURL: plan.url,
                sourceName: sourceName,
                // pkg → hand to the system installer; archives → in-place swap.
                requiresManualInstaller: spec.kind == .pkg,
                vendorInstallerKind: spec.kind,
                expectedSHA512: plan.checksum,
                downloadHeaders: spec.requestHeaders,
                changelogURL: recipe.changelogURL,
                publishedAt: publishedAt
            )
        }

        return RemoteVersion(
            shortVersion: shortVersion,
            version: buildVersion,
            downloadURL: recipe.downloadURL ?? resolvedDownload,
            sourceName: sourceName,
            // No install spec: detection only — the user downloads by hand.
            requiresManualInstaller: true,
            changelogURL: recipe.changelogURL,
            publishedAt: publishedAt
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

    /// Download a (small) zip and read one property-list entry's string value —
    /// the runtime behind `Mode.zipEntryPlist`. Used for vendors (Spotify) whose
    /// only cheap version surface is a stub-installer archive whose bundled app's
    /// Info.plist tracks the latest client version. Returns nil on any failure so
    /// the probe degrades to "unknown" rather than guessing.
    private func zipEntryPlistValue(
        url: URL, entry: String, key: String
    ) async throws -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else { return nil }

        // `unzip` needs a seekable file (the zip's central directory lives at the
        // end), so stage the archive in a temp file and extract just the one entry
        // to stdout. The entry is a small plist — well under the pipe buffer — so a
        // read-then-wait can't deadlock.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendorprobe-\(UUID().uuidString).zip")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", tmp.path, entry]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let plistData = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, !plistData.isEmpty else { return nil }

        // Parse as a property list (Spotify's is a binary plist, `bplist00`) and
        // read the requested key as a string.
        guard
            let obj = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil),
            let dict = obj as? [String: Any],
            let value = dict[key] as? String
        else { return nil }
        return value
    }

    /// Upgrade/normalize download URLs to HTTPS. Our vendor hosts all support TLS,
    /// and App Transport Security blocks plain-http loads anyway; if a host
    /// somehow lacked https the download would just fail and degrade to
    /// detection-only — never wrong data. VLC's appcast points at the
    /// `get.videolan.org` mirror gateway, which may redirect to plaintext mirrors;
    /// the same archive is available directly from VideoLAN's HTTPS archive host.
    private static func preferHTTPS(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        if comps.host?.lowercased() == "get.videolan.org",
           comps.path.hasPrefix("/vlc/") {
            comps.host = "downloads.videolan.org"
            comps.path = "/pub/videolan" + comps.path
        }
        guard comps.scheme == "http" else { return comps.url ?? url }
        comps.scheme = "https"
        return comps.url ?? url
    }
}
