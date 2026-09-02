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

    /// This host's architecture for `ElectronManifest.artifact(forArch:)`.
    /// Hard-coded rather than read from the environment: DuoUpdater is arm64-only
    /// (`App/project.yml`, `ARCHS:
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
              let manifest = ElectronManifest.parse(text) else {
            Log.source.notice(
                "electron: \(app.bundleID ?? "?", privacy: .public) manifest body did not parse")
            await RecipeHealth.shared.recordMiss(
                id: healthID, source: name, detail: "manifest fetched but did not parse")
            return nil
        }
        // Read exactly the manifest this bundle names. electron-updater does not
        // choose macOS manifests by architecture: Provider returns `-mac` for
        // darwin, and MacUpdater selects an arm64 entry from THIS manifest's
        // `files:` list. An adjacent `arm64-mac.yml` is therefore another channel,
        // read only by a build whose own `app-update.yml` says `channel: arm64`.
        // Probing that sibling moved a `channel: latest` install across release
        // trains whenever the two happened to publish the same version (#204).
        let resolvedURL = manifestURL

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
        // checked up front and `file` itself withheld as "detection-only, not an
        // error", rather than let three independently-derived optionals drift
        // apart below.
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
        // decision about the artifact record, not a sign the recipe (the manifest
        // read) is broken, so it does not affect the health verdict — same reasoning
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
