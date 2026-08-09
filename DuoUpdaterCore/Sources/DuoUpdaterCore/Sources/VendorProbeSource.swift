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
        let outcome = await probeOutcome(
            recipe, allowInstall: !app.prefersVendorProbeOverToolbox)
        // Record recipe health so a vendor changing their page surfaces in
        // diagnostics rather than silently degrading the app to "unknown". A
        // transient miss is cleared by the next successful check (success/miss are
        // compared by recency), so this only flags consistently-broken recipes.
        if outcome.remote != nil {
            await RecipeHealth.shared.recordSuccess(id: bundleID, source: name)
        } else {
            await RecipeHealth.shared.recordMiss(
                id: bundleID, source: name,
                detail: outcome.failure.map { "\($0.kind): \($0.detail)" }
                    ?? "probe resolved no version")
        }
        return outcome.remote
    }

    /// Run one recipe and report everything that happened, including the parts
    /// `latestVersion(for:)` discards.
    ///
    /// This lives on `VendorProbeSource` rather than in a verification tool on
    /// purpose: it must share the exact same redirect-blocking session, browser
    /// user agent, cache policy and HTTPS normalization as the shipping path. A
    /// reimplementation elsewhere would drift and start reporting failures the
    /// app never sees — and, worse, passes for recipes the app can't actually
    /// resolve.
    public func probeDiagnostic(_ recipe: VendorProbeRecipe) async -> ProbeOutcome {
        await probeOutcome(recipe, allowInstall: true)
    }

    /// What a mode's fetch step yields on success: the text the version pattern
    /// runs against, the download URL that text resolved to, and the status code.
    private struct FetchedBody {
        let text: String
        let resolvedDownload: URL?
        let status: Int?
    }

    /// Run one recipe. Returns nil (→ "unknown") on any non-confident outcome.
    /// `allowInstall` false forces a detection-only result even when the recipe
    /// carries an install spec — used for apps whose install another channel owns
    /// (Toolbox-managed), where we want the version but not an in-place swap.
    ///
    /// Never throws: every failure is captured as a `ProbeFailure` on the
    /// outcome, so callers that only want the version read `outcome.remote` and
    /// get exactly the old best-effort `nil`.
    func probeOutcome(_ recipe: VendorProbeRecipe, allowInstall: Bool = true) async -> ProbeOutcome {
        let started = DispatchTime.now()
        func elapsed() -> Int {
            Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        }
        func fail(_ failure: ProbeFailure, status: Int? = nil, sample: String? = nil) -> ProbeOutcome {
            ProbeOutcome(
                recipeID: recipe.recipeID, bundleID: recipe.bundleID, channel: recipe.channel,
                remote: nil, failure: failure, httpStatus: status,
                bodySample: sample, elapsedMs: elapsed())
        }

        let body: FetchedBody
        switch await fetchBody(recipe) {
        case .failure(let failure):
            // A status-code failure is worth keeping the code for even though
            // there's no body to sample.
            if case .httpStatus(let code) = failure { return fail(failure, status: code) }
            return fail(failure)
        case .success(let fetched):
            body = fetched
        }

        let sample = ProbeOutcome.sample(body.text)

        // Default to the first match (the app's own field, which structured
        // bodies list first); only ascending-order feeds opt into highest-wins.
        let extractor = recipe.selectHighest
            ? VendorProbeRecipe.highestVersion
            : VendorProbeRecipe.extractVersion
        guard let version = extractor(body.text, recipe.versionPattern) else {
            // Symmetric with `GitHubReleasesSource`, which has logged its
            // pattern misses since day one. A probe that fetched fine and matched
            // nothing is the exact shape of a vendor rewriting their page, and
            // until now it left no trace in the log at all.
            Log.source.error(
                "vendor probe \(recipe.bundleID, privacy: .public) [\(recipe.channel.rawValue, privacy: .public)]: \(body.text.utf8.count) bytes fetched, none matched /\(recipe.versionPattern, privacy: .public)/")
            return fail(
                .versionPatternNoMatch(sampleBytes: body.text.utf8.count),
                status: body.status, sample: sample)
        }

        // Optional clean marketing string to show instead of an ugly build id
        // (e.g. Android Studio's "2026.1.2 RC 1" vs "AI-261.…"). Display only; the
        // build still drives the comparison. From the same body, so first-match.
        let display = recipe.displayVersionPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: body.text, pattern: $0)
        }

        var warnings: [ProbeWarning] = []
        var remote: RemoteVersion

        // If this recipe knows how to install in place, resolve the installer URL
        // (and any checksum) now — from the same body we already have. A failure
        // here just falls back to detection-only; it never blocks the version.
        if allowInstall, let spec = recipe.install {
            if let plan = try? await resolveInstall(spec, body: body.text) {
                remote = Self.makeRemoteVersion(
                    recipe: recipe, version: version, install: spec, plan: plan,
                    resolvedDownload: body.resolvedDownload, display: display)
                // A recipe that names a checksum pattern but no longer matches one
                // still installs — unverified. Silent today; flag it.
                if spec.checksumPattern != nil, plan.checksum == nil {
                    warnings.append(.checksumPatternNoMatch)
                }
            } else {
                // Version still reads, one-click is dead. The app shows this app
                // as up-to-date-detectable but no longer installable, with no
                // signal anywhere — so name it.
                warnings.append(.installURLUnresolved)
                remote = Self.makeRemoteVersion(
                    recipe: recipe, version: version, install: nil, plan: nil,
                    resolvedDownload: body.resolvedDownload, display: display)
            }
        } else {
            remote = Self.makeRemoteVersion(
                recipe: recipe, version: version, install: nil, plan: nil,
                resolvedDownload: body.resolvedDownload, display: display)
        }

        return ProbeOutcome(
            recipeID: recipe.recipeID, bundleID: recipe.bundleID, channel: recipe.channel,
            remote: remote, failure: nil, warnings: warnings,
            httpStatus: body.status, bodySample: sample, elapsedMs: elapsed())
    }

    /// The per-mode fetch half of a probe, with each `return nil` in the original
    /// replaced by the specific reason it happened.
    private func fetchBody(_ recipe: VendorProbeRecipe) async -> Result<FetchedBody, ProbeFailure> {
        switch recipe.mode {
        case .redirectFilename:
            var request = URLRequest(url: recipe.url)
            request.timeoutInterval = 15
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            if recipe.followRedirects {
                // HEAD + follow: the version lives in the final resolved URL's
                // filename (e.g. "ToDesk_4.7.6.0.dmg").
                request.httpMethod = "HEAD"
                let response: URLResponse
                do { (_, response) = try await session.data(for: request) }
                catch { return .failure(Self.transportFailure(error)) }
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.nonHTTPResponse)
                }
                guard (200..<400).contains(http.statusCode) else {
                    return .failure(.httpStatus(http.statusCode))
                }
                guard let finalURL = response.url else {
                    return .failure(.malformedResolvedURL("response carried no final URL"))
                }
                return .success(FetchedBody(
                    text: finalURL.lastPathComponent, resolvedDownload: finalURL,
                    status: http.statusCode))
            } else {
                // GET + don't follow: read the version out of the 3xx `Location`
                // header itself (following would just download the target). Some
                // endpoints — e.g. Claude's `dmg/latest/redirect` — 307 only on
                // GET, reject HEAD with 405, and expose the version nowhere but
                // the Location path, so `text` is the full redirect target.
                request.httpMethod = "GET"
                let response: URLResponse
                do { (_, response) = try await Self.noRedirectSession.data(for: request) }
                catch { return .failure(Self.transportFailure(error)) }
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.nonHTTPResponse)
                }
                guard (300..<400).contains(http.statusCode) else {
                    return .failure(.httpStatus(http.statusCode))
                }
                guard let location = http.value(forHTTPHeaderField: "Location") else {
                    return .failure(.redirectMissingLocation)
                }
                guard let finalURL = URL(string: location, relativeTo: recipe.url)?.absoluteURL
                else { return .failure(.malformedResolvedURL(location)) }
                return .success(FetchedBody(
                    text: finalURL.absoluteString, resolvedDownload: finalURL,
                    status: http.statusCode))
            }

        case .responseBody:
            var request = URLRequest(url: recipe.url)
            request.timeoutInterval = 15
            request.cachePolicy = URLRequest.versionFeedCachePolicy
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            // When not following redirects we want the 3xx itself (its small body
            // / Location), so widen the accepted range and use the blocking session.
            let activeSession = recipe.followRedirects ? session : Self.noRedirectSession
            let okRange = recipe.followRedirects ? (200..<300) : (200..<400)
            let data: Data
            let response: URLResponse
            do { (data, response) = try await activeSession.data(for: request) }
            catch { return .failure(Self.transportFailure(error)) }
            guard let http = response as? HTTPURLResponse else {
                return .failure(.nonHTTPResponse)
            }
            guard okRange.contains(http.statusCode) else {
                return .failure(.httpStatus(http.statusCode))
            }
            return .success(FetchedBody(
                text: String(decoding: data, as: UTF8.self),
                resolvedDownload: recipe.downloadURL ?? recipe.url,
                status: http.statusCode))

        case .zipEntryPlist(let entry, let key):
            // The version lives in a bundled Info.plist inside a (small) zip —
            // see `Mode.zipEntryPlist`. We extract the one entry and read `key`;
            // `text` becomes that value so the shared `versionPattern` validates
            // it exactly like any other mode.
            return await zipEntryPlistValue(url: recipe.url, entry: entry, key: key)
                .map { FetchedBody(
                    text: $0, resolvedDownload: recipe.downloadURL ?? recipe.url,
                    status: nil) }
        }
    }

    /// Classify a thrown networking error. `URLError` covers DNS, TLS, timeouts
    /// and dropped connections — all "try again", never "fix the recipe".
    private static func transportFailure(_ error: Error) -> ProbeFailure {
        let urlError = error as? URLError
        return .transport(
            urlErrorCode: urlError?.errorCode ?? (error as NSError).code,
            urlError?.localizedDescription ?? error.localizedDescription)
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
        display: String? = nil
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
                changelogURL: recipe.changelogURL
            )
        }

        return RemoteVersion(
            shortVersion: shortVersion,
            version: buildVersion,
            downloadURL: recipe.downloadURL ?? resolvedDownload,
            sourceName: sourceName,
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
            request.cachePolicy = URLRequest.versionFeedCachePolicy
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
    /// Info.plist tracks the latest client version. Every failure degrades the
    /// probe to "unknown" rather than guessing; the `Result` says which one.
    private func zipEntryPlistValue(
        url: URL, entry: String, key: String
    ) async -> Result<String, ProbeFailure> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { return .failure(Self.transportFailure(error)) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.nonHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.httpStatus(http.statusCode))
        }

        // `unzip` needs a seekable file (the zip's central directory lives at the
        // end), so stage the archive in a temp file and extract just the one entry
        // to stdout. The entry is a small plist — well under the pipe buffer — so a
        // read-then-wait can't deadlock.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vendorprobe-\(UUID().uuidString).zip")
        do { try data.write(to: tmp) }
        catch { return .failure(.archiveExtractionFailed("cannot stage archive: \(error.localizedDescription)")) }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", tmp.path, entry]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() }
        catch { return .failure(.archiveExtractionFailed("cannot run unzip: \(error.localizedDescription)")) }
        let plistData = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            return .failure(.archiveExtractionFailed(
                "unzip exited \(proc.terminationStatus) extracting '\(entry)'"))
        }
        guard !plistData.isEmpty else {
            return .failure(.archiveExtractionFailed("'\(entry)' extracted empty"))
        }

        // Parse as a property list (Spotify's is a binary plist, `bplist00`) and
        // read the requested key as a string.
        guard
            let obj = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil),
            let dict = obj as? [String: Any]
        else { return .failure(.archiveExtractionFailed("'\(entry)' is not a property list")) }
        guard let value = dict[key] as? String else {
            return .failure(.plistKeyMissing(entry: entry, key: key))
        }
        return .success(value)
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
