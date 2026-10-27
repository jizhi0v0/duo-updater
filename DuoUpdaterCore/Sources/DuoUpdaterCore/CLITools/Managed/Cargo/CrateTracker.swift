import Foundation

/// What `cargo install` records about every package it installed under a root
/// (design §2.6, CARGO-05/06/07): `.crates.toml` is the authority — one key
/// `"<name> <version> (<source>)"` per package, its binaries as the value —
/// and `.crates2.json` adds, under the same key, how it was built: features,
/// `version_req`, the rustc that built it. cargo rewrites v2 from v1 on every
/// load, so a package in v1 alone (written by cargo-binstall before a later
/// cargo run) is still a package, with defaults for the rest.
///
/// Measured with cargo 1.99.1 (2026-10-27, isolated `CARGO_HOME`): `cargo
/// install tokei --version 14.0.0 --features yaml` recorded `"tokei 14.0.0
/// (registry+https://github.com/rust-lang/crates.io-index)" = ["tokei"]`,
/// `features: ["yaml"]`, `version_req: "=14.0.0"`; a later `cargo install
/// tokei --features yaml` left 15.0.0 with `["yaml"]` and `version_req: null`.
enum CrateTracker {

    struct Package: Sendable, Equatable {
        let name: String
        let version: String
        /// "registry+https://github.com/rust-lang/crates.io-index",
        /// "sparse+https://index.crates.io/", "git+https://…#<rev>",
        /// "path+file:///…".
        let source: String
        let bins: [String]
        let features: [String]
        let allFeatures: Bool
        let noDefaultFeatures: Bool
        /// What `--version` asked for ("=14.0.0"); `cargo install <name>`
        /// drops it.
        let versionRequest: String?
        /// The rustc release that built it ("1.99.1").
        let rustc: String?

        /// Where the package came from, as far as the check cares.
        var origin: Origin { CrateTracker.origin(of: source) }
    }

    /// crates.io's index, by either protocol cargo records.
    static let cratesIO: Set<String> = [
        "registry+https://github.com/rust-lang/crates.io-index", "sparse+https://index.crates.io/",
    ]

    static func origin(of source: String) -> Origin {
        if cratesIO.contains(source) { return .cratesIO }
        if source.hasPrefix("git+") { return .git(String(source.dropFirst(4))) }
        if source.hasPrefix("path+") { return .path(String(source.dropFirst(5))) }
        return .otherRegistry(source)
    }

    enum Origin: Sendable, Equatable {
        case cratesIO
        case otherRegistry(String)
        case git(String)
        case path(String)
    }

    /// Every package in `v1`, with `v2`'s build facts where it has the key.
    static func packages(v1: String, v2: Data?) -> [Package] {
        let builds = v2.flatMap { try? JSONDecoder().decode(V2.self, from: $0) }?.installs ?? [:]
        return entries(v1).compactMap { key, bins in
            guard let (name, version, source) = split(key) else { return nil }
            let build = builds[key]
            return Package(
                name: name, version: version, source: source, bins: bins,
                features: build?.features ?? [], allFeatures: build?.allFeatures ?? false,
                noDefaultFeatures: build?.noDefaultFeatures ?? false, versionRequest: build?.versionRequest,
                rustc: build?.rustc.flatMap(release(of:)))
        }
    }

    /// `"<key>" = ["bin", …]` under `[v1]`, the array on one line or many, in
    /// file order.
    static func entries(_ toml: String) -> [(key: String, bins: [String])] {
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*=\s*\[([^\]]*)\]"#, options: [.anchorsMatchLines])
        else { return [] }
        let text = toml as NSString
        return pattern.matches(in: toml, range: NSRange(location: 0, length: text.length)).map { match in
            let key = text.substring(with: match.range(at: 1))
            let list = text.substring(with: match.range(at: 2))
            let bins = list.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }.filter { !$0.isEmpty }
            return (key, bins)
        }
    }

    /// `"tokei 14.0.0 (registry+…)"` → name, version, source.
    static func split(_ key: String) -> (String, String, String)? {
        let parts = key.split(separator: " ", maxSplits: 2)
        guard parts.count == 3, parts[2].hasPrefix("("), parts[2].hasSuffix(")") else { return nil }
        return (String(parts[0]), String(parts[1]), String(parts[2].dropFirst().dropLast()))
    }

    /// `rustc -vV`'s `release: 1.99.1` line.
    static func release(of rustc: String) -> String? {
        for line in rustc.split(whereSeparator: \.isNewline) where line.hasPrefix("release: ") {
            return String(line.dropFirst("release: ".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    struct V2: Decodable {
        let installs: [String: Build]
    }

    struct Build: Decodable {
        let versionRequest: String?
        let features: [String]?
        let allFeatures: Bool?
        let noDefaultFeatures: Bool?
        let rustc: String?

        enum CodingKeys: String, CodingKey {
            case versionRequest = "version_req"
            case features
            case allFeatures = "all_features"
            case noDefaultFeatures = "no_default_features"
            case rustc
        }
    }
}
