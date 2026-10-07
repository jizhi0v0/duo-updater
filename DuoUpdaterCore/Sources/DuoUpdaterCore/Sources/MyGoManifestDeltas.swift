import Foundation

/// Pulls MyGo delta updates out of a vendor probe's response body.
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
enum MyGoManifestDeltas {

    private struct Manifest: Decodable {
        let version: String
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
}
