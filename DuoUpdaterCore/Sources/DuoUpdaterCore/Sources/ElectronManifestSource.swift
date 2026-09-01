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

        let (data, response) = try await session.versionFeedData(
            for: request, label: "Electron \(app.name)")
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Degrade rather than throw, which is where this parts company with
            // `SparkleAppcastSource`. A `SUFeedURL` is an address the app states
            // and expects to work, so a non-200 there is a fault worth surfacing.
            // An `app-update.yml` `url` is a build-time constant that vendors
            // routinely outgrow — Antigravity, BaiduNetdisk and OpenLens all point
            // at addresses that 404 today while their apps update fine by other
            // means. Sitting last in the stack, throwing would put an error row on
            // apps whose real state is "no coverage yet".
            //
            // `.notice`, not `.info`: `.info` from a third-party subsystem is
            // never written to disk (see `Log.swift`), so this line would not
            // survive to be read after the fact. And `RecipeHealth` gets told too
            // — this source went unrepresented there entirely (#195); a manifest
            // address that has drifted onto a 404 is exactly the standing miss
            // the diagnostics sweep exists to surface.
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
        // Guarded on the two manifests naming the SAME version, which is what
        // makes this an architecture choice rather than a train change; a sibling
        // that disagrees is left alone for a person. Costs one extra request per
        // check for apps on the default channel, and none for a bundle that
        // already named its architecture (Typeless ships `channel: arm64`, so the
        // manifest above IS the arm64 one).
        //
        // `try?` used to collapse "no sibling" and "could not tell" into the same
        // nil (#194): a 403 (Canva, observed) or a timeout answered exactly like a
        // clean 404, and either one left `artifact(forArch:)` free to fall back to
        // the DEFAULT manifest's top-level `path` — which, on this shape, is the
        // Intel build. Only a *confirmed* 404 is proof there is no split; anything
        // else must not be allowed to stand in for that proof, which is what
        // `pathFallbackIsTrustworthy` below enforces.
        var pathFallbackIsTrustworthy = true
        if Self.mayProbeArchSibling(manifestURL) {
            switch await Self.archSibling(
                of: manifestURL, matching: manifest.version, session: session
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
        // detect this release but cannot install it", which is an honest row; the
        // three install fields move together so a download can never be offered
        // without the checksum and kind that gate it.
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

        // The manifest resolved to a real version either way — that is what
        // `RecipeHealth` tracks. Withholding the artifact above is a safety
        // decision about THIS host's architecture, not a sign the recipe (the
        // manifest read) is broken, so it does not affect the health verdict —
        // same reasoning `GitHubReleasesSource` gives its own `archIncompatible`
        // rows no miss.
        await RecipeHealth.shared.recordSuccess(id: healthID, source: name)
        return RemoteVersion(
            shortVersion: manifest.version,
            version: nil,
            downloadURL: file.flatMap {
                URL(string: $0.url, relativeTo: resolvedURL.deletingLastPathComponent())?
                    .absoluteURL
            },
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
    /// 2026-09-01), a body that will not parse, or a version that has moved on
    /// — is silence, not an answer, and must not be allowed to stand in for one.
    enum ArchSiblingOutcome: Equatable {
        case resolved(url: URL, manifest: ElectronManifest)
        case confirmedAbsent
        case indeterminate
    }

    /// Probes the `arm64-mac.yml` beside `manifest`.
    private static func archSibling(
        of manifest: URL, matching version: String, session: URLSession
    ) async -> ArchSiblingOutcome {
        let sibling = manifest.deletingLastPathComponent()
            .appendingPathComponent("arm64-mac.yml")
        var request = URLRequest(url: sibling)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
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
