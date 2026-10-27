import Foundation

/// crates.io's sparse index (`https://index.crates.io/<ab>/<cd>/<name>`), the
/// file cargo itself reads (design §2.6, CARGO-09/12/13/14): one JSON object
/// per published version, **in publish order, not version order** — rand's
/// tail is `0.8.6, 0.10.2, 0.8.7, 0.9.5, 0.8.8, 0.10.3`
/// (`Fixtures/managed/cargo/index-rand-tail`, 2026-10-27). Served with an
/// ETag and `cache-control: public,max-age=600` (`curl -I`, 2026-10-27); no
/// rate limit, no token.
enum SparseIndex {

    static let root = URL(string: "https://index.crates.io/")!

    /// cargo's layout: `1/a`, `2/ab`, `3/a/abc`, `ab/cd/abcd…`, lower-cased.
    static func url(of crate: String) -> URL {
        let name = crate.lowercased()
        let path: String
        switch name.count {
        case 1: path = "1/\(name)"
        case 2: path = "2/\(name)"
        case 3: path = "3/\(name.prefix(1))/\(name)"
        default: path = "\(name.prefix(2))/\(name.dropFirst(2).prefix(2))/\(name)"
        }
        return root.appendingPathComponent(path)
    }

    struct Release: Sendable, Equatable {
        let version: String
        let yanked: Bool
        /// The package's `rust-version` ("1.85"), when it declares one.
        let rustVersion: String?
    }

    static func releases(_ data: Data) -> [Release] {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            guard let line = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)) else { return nil }
            return Release(version: line.vers, yanked: line.yanked ?? false, rustVersion: line.rustVersion)
        }
    }

    struct Line: Decodable {
        let vers: String
        let yanked: Bool?
        let rustVersion: String?

        enum CodingKeys: String, CodingKey {
            case vers, yanked
            case rustVersion = "rust_version"
        }
    }

    /// The newest release `cargo install <name>` picks with no `--version`:
    /// not yanked, not a pre-release (a `-` before any `+` build metadata),
    /// highest by version.
    static func newest(_ releases: [Release]) -> Release? {
        releases
            .filter { !$0.yanked && !isPrerelease($0.version) }
            .max { VersionComparator.compare(core($0.version), core($1.version)) == .orderedAscending }
    }

    static func isPrerelease(_ version: String) -> Bool {
        core(version).contains("-")
    }

    /// The version without its `+build` metadata, which semver orders by nothing.
    static func core(_ version: String) -> String {
        version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? version
    }

    /// Whether `rustc` ("1.99.1") is at least `rustVersion` ("1.85", "1.85.0").
    static func satisfies(rustc: String, rustVersion: String) -> Bool {
        VersionComparator.compare(rustc, rustVersion) != .orderedAscending
    }

    /// The index file for `crate`, revalidated every time (`URLRequest
    /// .versionFeedCachePolicy`): a 304 when nothing was published.
    static func fetch(_ crate: String) async throws -> Data {
        var request = URLRequest(url: url(of: crate))
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }

    enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        var description: String {
            switch self {
            case .http(404): return "crates.io's index has no such crate"
            case .http(let status): return "crates.io's index answered HTTP \(status)"
            }
        }
    }
}
