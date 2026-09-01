import Foundation

/// Resolves updates for apps that ship an electron-builder `app-update.yml`, by
/// reading the same `*-mac.yml` manifest the app's own updater reads.
///
/// This is the electron counterpart of `SparkleAppcastSource`, and it is a
/// *mechanism*, not a table: it carries no per-app addresses, exactly as that one
/// carries none. Every app it covers is covered by the same reviewed rule —
/// which is what keeps "the apps DuoUpdater supports" a property of the code
/// rather than of whichever bundles happen to be on a given Mac.
///
/// **Placed last in `SourceStack`, after the vendor probe.** That is deliberate
/// and temporary. Eight of the nine Electron apps on the development machine
/// already have hand-written recipes whose install specs pick a particular asset
/// (an arm64 zip, a universal dmg), and jumping ahead of them would silently swap
/// the artifact those installs fetch. Sitting last, this source can only add
/// coverage where nothing else answers; a recipe is retired by *deleting it* once
/// this source has been shown to resolve that app correctly, one at a time, which
/// is the same order Bartender/ImageOptim/Vivaldi arrived at when their bundles
/// turned out to declare their own Sparkle feeds.
///
/// What it deliberately does not do: construct an address. `provider: github` and
/// `provider: s3` state no URL, and Termius is the reason guessing one is not
/// allowed — see `ElectronUpdateConfig.manifestURL`.
///
/// **Not covered by `duo verify`'s nightly sweep, and cannot be with the sweep's
/// current shape.** `Registry` (`CLI/Sources/DuoKit/Finding.swift`) enumerates
/// `vendor` / `github` / `changelog` because each of those has a table in the
/// repo to walk. This source has no table — its addresses live inside whatever
/// `app-update.yml` happens to be sitting in a bundle on the machine running the
/// check, which is exactly what makes it a mechanism rather than a registry (see
/// above). A `duo verify` pass has no bundles to read that file from, so there is
/// nothing to enumerate. Covering it would mean walking a list of installed
/// bundles instead of a registry — a different mechanism, and a separate piece of
/// work, not something to bolt on here. Until that exists, `RecipeHealth` (see
/// `latestVersion(for:)`) is this source's only failure signal.
public struct ElectronManifestSource: UpdateSource {
    public let name = "Electron"

    private let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    /// This host's architecture, for both `ElectronManifest.artifact(forArch:)`
    /// and the path-fallback-trust check below. Hard-coded rather than read from
    /// the environment: DuoUpdater is arm64-only (`App/project.yml`, `ARCHS:
    /// arm64` — a product decision, not a build detail), so there is no Intel
    /// host to branch on.
    private static let hostArch = "arm64"

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard let config = app.electronUpdate, let manifestURL = config.manifestURL else {
            return nil
        }
        // A bundle id when the scanner found one, the manifest address otherwise
        // (mirrors the `?` this source already logs) — either way a stable key
        // `RecipeHealth`'s diagnostics can list this manifest under.
        let healthID = app.bundleID ?? manifestURL.absoluteString

        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 15
        // Same reasoning as `SparkleAppcastSource`: a static manifest behind a CDN
        // that stamps a long max-age would otherwise stay "fresh" forever and the
        // app would go quietly blind to new releases.
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")

        // Degrade rather than throw, which is where this parts company with
        // `SparkleAppcastSource`. A `SUFeedURL` is an address the app states and
        // expects to work, so a fault reaching it is worth surfacing. An
        // `app-update.yml` `url` is a build-time constant that vendors routinely
        // outgrow — Antigravity, BaiduNetdisk and OpenLens all point at addresses
        // that 404 today while their apps update fine by other means. Sitting
        // last in the stack, throwing would put an error row on apps whose real
        // state is "no coverage yet".
        //
        // Covers the TRANSPORT failure (timeout, DNS, TLS, connection refused —
        // anything `data(for:)` itself throws for) as well as the non-2xx status
        // handled just below. Only the status branch used to degrade: a plain
        // timeout reaching `manifestURL` propagated out of `latestVersion`
        // untouched and produced exactly the error row this paragraph says it
        // avoids — the two failure shapes read identically to a vendor (this
        // source could not reach their manifest) and must read identically here.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.versionFeedData(
                for: request, label: "Electron \(app.name)")
        } catch {
            // `.notice`, not `.info`: `.info` from a third-party subsystem is
            // never written to disk (see `Log.swift`).
            Log.source.notice(
                "electron: \(app.bundleID ?? "?", privacy: .public) manifest fetch failed: \(error.localizedDescription, privacy: .public)")
            await RecipeHealth.shared.recordMiss(
                id: healthID, source: name,
                detail: "manifest fetch failed: \(error.localizedDescription)")
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // `RecipeHealth` gets told too — this source went unrepresented there
            // entirely (#195); a manifest address that has drifted onto a 404 is
            // exactly the standing miss the diagnostics sweep exists to surface.
            Log.source.notice(
                "electron: \(app.bundleID ?? "?", privacy: .public) manifest returned \(http.statusCode, privacy: .public)")
            await RecipeHealth.shared.recordMiss(
                id: healthID, source: name, detail: "manifest returned HTTP \(http.statusCode)")
            return nil
        }
        guard let text = String(data: data, encoding: .utf8),
              var manifest = ElectronManifest.parse(text) else {
            Log.source.notice(
                "electron: \(app.bundleID ?? "?", privacy: .public) manifest body did not parse")
            await RecipeHealth.shared.recordMiss(
                id: healthID, source: name, detail: "manifest fetched but did not parse")
            return nil
        }
        var resolvedURL = manifestURL

        // A vendor that publishes `arm64-mac.yml` beside the default manifest has
        // split its release by architecture, and the DEFAULT one is then the x64
        // build. Notion is why this is a resolution step and not a warning: its
        // `latest-mac.yml` names `Notion-7.31.3.zip` (126 MB) and its
        // `arm64-mac.yml` names `Notion-arm64-7.31.3.zip` (121 MB) — the first
        // carries no architecture token at all, so nothing about the filename
        // reveals that it is Intel. The sibling's existence is the only signal.
        //
        // GUARDED ON THE TWO MANIFESTS NAMING THE SAME VERSION (restored; #203
        // proposed dropping this, then was withdrawn — the premise didn't hold,
        // see below). A sibling that resolves to a DIFFERENT version is not this
        // host's architecture choice — it is a different release train, and
        // adopting it moves the user onto that train, not just onto arm64:
        //
        // - electron-updater does not select `*-mac.yml` by architecture on
        //   macOS at all. `Provider.getChannelFilePrefix()` only appends
        //   `-${arch}` on Linux; on darwin it always returns `-mac`, no
        //   architecture suffix. Architecture selection happens INSIDE the
        //   manifest instead — `MacUpdater.ts` checks `process.arch === "arm64"`
        //   and picks the matching `files:` entry. So `arm64-mac.yml` is not a
        //   standard electron-updater path; only a build whose OWN
        //   `app-update.yml` names `channel: arm64` ever reads it. (electron-userland/electron-builder:
        //   `packages/electron-updater/src/providers/Provider.ts`,
        //   `packages/electron-updater/src/MacUpdater.ts`; see also
        //   electron-builder issue #6643.)
        // - Confirmed directly on Notion's real arm64 build (2026-09-01,
        //   `Notion-arm64-7.32.0.zip`, downloaded whole, length matched
        //   Content-Length byte for byte): its OWN `Contents/Resources/app-update.yml`
        //   carries `channel: arm64`, while the machine's installed 7.31.3
        //   (`universal`) carries `channel: latest`. Installing the arm64 build
        //   would move this user from the `latest` track to the `arm64` track —
        //   ONE-WAY, since after that both Notion's own updater and this source
        //   read `arm64-mac.yml` from then on. That is exactly the "train
        //   change" the equality guard exists to refuse.
        //
        // So on a real drift (Notion's two tracks were four days apart,
        // 2026-08-27 vs. 2026-08-31, when this was checked), the correct answer
        // is NOT "adopt whichever one resolves" — it is "report the version on
        // the track the user is actually on" (`latest`, here 7.31.3, which is
        // also what Notion's own updater would install), while withholding the
        // artifact because that track's manifest is x86_64-only and DuoUpdater
        // is arm64-only. That is exactly #194's failure closure below, doing its
        // job — a version-mismatched sibling reads as `.indeterminate`, which
        // makes `pathFallbackIsTrustworthy` false, which withholds the
        // x86_64 `path` artifact. No further action needed for that case.
        //
        // Real gap this leaves, tracked separately (deliberately out of scope
        // here): `mayProbeArchSibling`'s whole premise — that a vendor
        // publishing `arm64-mac.yml` means it split ITS release by architecture,
        // and the default manifest is the x64 half — is an inference, not
        // something electron-updater's own mechanism guarantees. Costs one extra
        // request per check for apps on the default channel, and none for a
        // bundle that already named its architecture (Typeless ships `channel:
        // arm64`, so the manifest above IS the arm64 one).
        //
        // `try?` used to collapse "no sibling" and "could not tell" into the same
        // nil (#194): a 403 (Canva, observed) or a timeout answered exactly like a
        // clean 404, and either one left `artifact(forArch:)` free to fall back to
        // the DEFAULT manifest's top-level `path` — which, on this shape, is the
        // Intel build. Only a *confirmed* 404 is proof there is no split; anything
        // else — including a sibling that answers but names a different version —
        // must not be allowed to stand in for that proof, which is what
        // `pathFallbackIsTrustworthy` below enforces.
        var pathFallbackIsTrustworthy = true
        if Self.mayProbeArchSibling(manifestURL) {
            switch await Self.archSibling(
                of: manifestURL, matching: manifest.version,
                label: "Electron \(app.name) arch-sibling", session: session
            ) {
            case .resolved(let url, let sibling):
                manifest = sibling
                resolvedURL = url
            case .confirmedAbsent:
                break  // No split published — trusting `path` is correct.
            case .indeterminate:
                pathFallbackIsTrustworthy = false
            }
        }

        // MARKETING ONLY, and `version:` is the one string the manifest carries.
        // Leaving the build side nil is the point: an Electron bundle's
        // `CFBundleVersion` is whatever the packager felt like (Canva's is
        // `3601922.398772706` against a marketing `1.124.1`), so offering it as a
        // build to compare would invite exactly the cross-namespace read
        // `VersionComparator` refuses to make. Marketing-to-marketing is the only
        // comparison this manifest can support, and it is the one electron-updater
        // itself makes.
        //
        // The artifact is chosen by ARCHITECTURE, never by the manifest's
        // top-level `path` — see `ElectronManifest.artifact(forArch:)` and the
        // ChatWise case that made it necessary. A nil artifact means "we can
        // detect this release but cannot install it", which is an honest row.
        var file = manifest.artifact(forArch: Self.hostArch)
        if !pathFallbackIsTrustworthy, let candidate = file,
           Self.isTopLevelPathFallback(candidate, arch: Self.hostArch) {
            // The winning artifact carries no arch/universal token of its own —
            // the only way `artifact(forArch:)` returns that is the top-level
            // `path` branch — and the sibling probe that would vouch for it came
            // back inconclusive. Withhold the install fields rather than risk
            // handing an Apple-silicon Mac the Intel build; the version itself is
            // still real and still reported below.
            Log.source.notice(
                "electron: \(app.bundleID ?? "?", privacy: .public) arch sibling probe was inconclusive (not a confirmed 404) — withholding the top-level path artifact rather than risk an Intel install")
            file = nil
        }

        // The three install fields below (`downloadURL` / `vendorInstallerKind` /
        // `expectedSHA512`) are meant to move together — all present or all nil —
        // so a download can never be offered without the checksum and kind that
        // gate it. That claim used to be stated but not enforced: each field was
        // derived independently from `file`, which does not actually guarantee
        // it (flagged in #201's review). Two ways they can drift apart:
        //
        // - VERIFIED, and the reachable one: a `files:` entry can name a `url:`
        //   with no `sha512:` line under it, which leaves `expectedSHA512` nil
        //   while `downloadURL`/`vendorInstallerKind` still resolve —
        //   `VendorInstaller`'s `if let expected` then silently skips the
        //   integrity check it would otherwise run. See
        //   `aFilesEntryMissingItsChecksumWithholdsAllThreeFields` for a fixture
        //   that reaches this through the real code path.
        // - DEFENSIVE, not currently reachable: in principle `URL(string:
        //   relativeTo:)` failing on `file.url` would leave `downloadURL` nil
        //   while `vendorInstallerKind` still resolves from the raw string's
        //   extension — `VendorInstaller` then throws `noDownloadURL` for a row
        //   `UpdatePolicy` read as installable. Checked anyway: this Foundation's
        //   URL parser turned out to be far more lenient than that reasoning
        //   assumed (percent-encodes spaces, NUL bytes, even most malformed
        //   percent sequences on this toolchain — only an EMPTY string reliably
        //   returns nil, and `artifact(forArch:)`'s own guards already keep an
        //   empty string from ever becoming the chosen `file.url`). Kept as a
        //   guard against relying on URL-parser leniency as a contract rather
        //   than an observation, not because it is known to fire today.
        //
        // Either half-complete combination reads as "installable" to
        // `UpdatePolicy` and then fails downstream, so both preconditions are
        // checked up front and `file` itself withheld — same "detection-only,
        // not an error" shape as the two withholding branches above — rather
        // than let three independently-derived optionals drift apart below.
        let resolvedDownloadURL = file.flatMap {
            URL(string: $0.url, relativeTo: resolvedURL.deletingLastPathComponent())?.absoluteURL
        }
        if let candidate = file, resolvedDownloadURL == nil || candidate.sha512 == nil {
            Log.source.notice(
                "electron: \(app.bundleID ?? "?", privacy: .public) chosen artifact is missing a URL that resolves or a checksum — withholding install fields rather than offer a half-verified download")
            file = nil
        }

        // The manifest resolved to a real version either way — that is what
        // `RecipeHealth` tracks. Withholding the artifact above is a safety
        // decision about THIS host's architecture (or about the artifact record
        // itself being incomplete), not a sign the recipe (the manifest read) is
        // broken, so it does not affect the health verdict — same reasoning
        // `GitHubReleasesSource` gives its own `archIncompatible` rows no miss.
        await RecipeHealth.shared.recordSuccess(id: healthID, source: name)
        return RemoteVersion(
            shortVersion: manifest.version,
            version: nil,
            downloadURL: file == nil ? nil : resolvedDownloadURL,
            downloadSize: file?.size,
            sourceName: name,
            vendorInstallerKind: Self.kind(of: file?.url),
            expectedSHA512: file?.sha512,
            publishedAt: ReleaseDate.parse(manifest.releaseDate))
    }

    /// Whether the arch sibling may be probed at all — true ONLY for the default
    /// `latest-mac.yml`.
    ///
    /// electron-builder puts the release channel and the architecture in the same
    /// `channel:` slot, so the filename is the only place the two are
    /// distinguishable, and getting this wrong crosses trains rather than
    /// architectures: a bundle on `channel: beta` resolves `beta-mac.yml`, and
    /// probing `arm64-mac.yml` beside it would offer that user the STABLE build
    /// whenever the two happened to agree on a version number. Narrow is correct
    /// here — an app that named its own architecture (`channel: arm64`, which
    /// Typeless ships) has already answered the question, and an app on a named
    /// channel is not asking it.
    static func mayProbeArchSibling(_ manifest: URL) -> Bool {
        manifest.lastPathComponent == "latest-mac.yml"
    }

    /// What probing for the `arm64-mac.yml` sibling found. Three-way, not
    /// optional, because two of the failure shapes must not be treated alike
    /// (#194): only ``confirmedAbsent`` is proof the vendor never split the
    /// release by architecture. Everything else — a transport failure, a
    /// non-2xx/non-404 status (Canva's sibling answers 403, observed
    /// 2026-09-01), a body that will not parse, or (see the long comment at the
    /// call site — #203 was filed then withdrawn on this point) a version that
    /// disagrees with the default manifest's — is silence, not an answer, and
    /// must not be allowed to stand in for one.
    enum ArchSiblingOutcome: Equatable {
        case resolved(url: URL, manifest: ElectronManifest)
        case confirmedAbsent
        case indeterminate
    }

    /// Probes the `arm64-mac.yml` beside `manifest`.
    ///
    /// Goes through `versionFeedData(for:label:)`, the same gateway-retry path
    /// the default manifest fetch uses, rather than a bare `data(for:)` (#203). A
    /// transient 502/503/504 used to read as `.indeterminate` here — costing an
    /// arch-safe artifact for a blip that the DEFAULT manifest's own fetch would
    /// have retried away — while the identical status on that default fetch
    /// self-healed one line up. One flaky moment and "the vendor genuinely
    /// doesn't publish a sibling" must not collapse into the same outcome; that
    /// asymmetry was #194's own lesson, applied here to the retry policy instead
    /// of the status-code handling.
    private static func archSibling(
        of manifest: URL, matching version: String, label: String, session: URLSession
    ) async -> ArchSiblingOutcome {
        let sibling = manifest.deletingLastPathComponent()
            .appendingPathComponent("arm64-mac.yml")
        var request = URLRequest(url: sibling)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.versionFeedData(
            for: request, label: label),
              let http = response as? HTTPURLResponse else {
            // Transport failure or a non-HTTP response — not proof of anything.
            return .indeterminate
        }
        if http.statusCode == 404 {
            // The one outcome that actually proves there is no arch split: a
            // definitive "no such file" from the same host that answered the
            // default manifest.
            return .confirmedAbsent
        }
        // `parsed.version == version` — see the long comment at the call site
        // (restored after #203 proposed and then withdrew dropping this): a
        // sibling that answers but names a DIFFERENT version is a different
        // release train, not this host's architecture choice, and adopting it
        // would move the user onto that train permanently.
        guard (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8),
              let parsed = ElectronManifest.parse(text),
              parsed.version == version else {
            return .indeterminate
        }
        return .resolved(url: sibling, manifest: parsed)
    }

    /// Whether the winning artifact came from the manifest's top-level `path`
    /// fallback rather than an entry in `files:` that names an architecture (or
    /// `universal`) of its own.
    ///
    /// Does not re-walk `ElectronManifest.artifact(forArch:)`'s branches or
    /// re-read `manifest.path` — it mirrors their order at the one point that
    /// matters here: `artifact(forArch:)` only ever returns a `File` whose url
    /// carries neither token when it took the fallback branch, so the absence of
    /// both is itself the proof.
    static func isTopLevelPathFallback(_ file: ElectronManifest.File, arch: String) -> Bool {
        !file.url.localizedCaseInsensitiveContains(arch)
            && !file.url.localizedCaseInsensitiveContains("universal")
    }

    /// The archive kind, from the chosen artifact's own extension.
    /// electron-builder publishes `.zip` as the primary macOS artifact
    /// (Squirrel.Mac requires it), with a `.dmg` beside it for humans.
    static func kind(of path: String?) -> VendorInstallerKind? {
        guard let path else { return nil }
        switch (path as NSString).pathExtension.lowercased() {
        case "zip": return .zip
        case "dmg": return .dmg
        case "pkg": return .pkg
        default: return nil
        }
    }
}
