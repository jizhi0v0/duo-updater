import Foundation

/// Reads what a MyGo update manifest says about the release a vendor probe
/// resolved: its delta updates, and the signature of its archive.
///
/// A MyGo app (`github.com/egoist/mygo`) reads an `update-<os>-<arch>.json`
/// manifest: one release (`version`, `url`, `size`, `signature`, …), a
/// `deltas[]` of `{from, url, size, signature}` that each turn the app of
/// version `from` into this one, and a `previous[]` of older archives. Moshi Go
/// is the case in hand; its recipe already reads this body for the version.
///
/// Same safety story as `VendorAppcastDeltas`: patches are returned only when the
/// manifest's own top-level `version` is the version the probe resolved, so a
/// patch can never be for a release other than the one being installed. Anything
/// that does not decode as this shape yields nothing, and the full archive is
/// always correct. A body that only looks like it (a `deltas` array of some other
/// vendor's format) costs at most one failed patch: `MyGoDelta` refuses a file
/// without its magic, and the install retries with the full archive.
enum MyGoManifest {

    private struct Manifest: Decodable {
        let version: String
        let url: String?
        let signature: String?
        let deltas: [Delta]?
    }

    private struct Delta: Decodable {
        let from: String
        let url: String
        let size: Int64?
        let signature: String?
    }

    /// Patches published for exactly `version`, or empty. Relative URLs resolve
    /// against `feedURL`, as MyGo's own updater resolves them against the manifest.
    ///
    /// `publicKey` is the recipe's `myGoPublicKey`; each patch carries it with its
    /// own `signature`, and `DeltaApplier.reconstruct` checks the pair.
    static func patches(
        inBody body: String, forVersion version: String, feedURL: URL? = nil,
        publicKey: String? = nil
    ) -> [DeltaPatch] {
        guard body.contains("\"deltas\""),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(body.utf8)),
              manifest.version == version
        else { return [] }
        return (manifest.deltas ?? []).compactMap { delta in
            guard !delta.from.isEmpty,
                  let url = URL(string: delta.url, relativeTo: feedURL)?.absoluteURL,
                  url.scheme == "https"
            else { return nil }
            return DeltaPatch(
                fromBuild: delta.from, url: url, size: delta.size, edSignature: delta.signature,
                format: .myGo, toVersion: manifest.version, publicKey: publicKey)
        }
    }

    /// The manifest's signature of the archive at `url`, or nil.
    ///
    /// MyGo signs the archive's SHA-256 with Ed25519 (`update.Verify`), and the
    /// installer checks it against the recipe's `myGoPublicKey`. Returned only
    /// when the manifest's own `version` is the one the probe resolved AND its
    /// `url` (resolved against `feedURL`) is exactly the file about to be
    /// downloaded: a signature is evidence about one file, and pairing it with
    /// any other would fail the install of a good download or, worse, describe
    /// bytes we never fetch. `previous[]` repeats `url`/`signature` for older
    /// archives and is never read.
    static func archiveSignature(
        inBody body: String, forVersion version: String, url: URL, feedURL: URL? = nil
    ) -> String? {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(body.utf8)),
              manifest.version == version,
              let published = manifest.url,
              URL(string: published, relativeTo: feedURL)?.absoluteURL == url.absoluteURL,
              let signature = manifest.signature, !signature.isEmpty
        else { return nil }
        return signature
    }
}
