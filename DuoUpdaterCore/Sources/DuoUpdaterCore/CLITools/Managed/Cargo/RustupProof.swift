import Foundation

/// Which rustup bytes this process has proved rust-lang's (`RustRelease
/// .identify`), by sha256. The proof needs the network and an adapter's
/// `scan` may not use it, so `CargoAdapter.resolve` proves and records here,
/// and every later scan — the click's included — reads the record for the
/// bytes it hashes now. Bytes that changed are a different hash: unproved
/// until a check proves them again. A hash names one file forever, so nothing
/// here goes stale.
final class RustupProof: @unchecked Sendable {
    private let lock = NSLock()
    private var proved: [String: String] = [:]

    init() {}

    static let shared = RustupProof()

    /// The rustup version these bytes were proved to be; nil when they were not.
    func version(of sha256: String) -> String? {
        lock.withLock { proved[sha256.lowercased()] }
    }

    func record(_ sha256: String, version: String) {
        lock.withLock { proved[sha256.lowercased()] = version }
    }
}
