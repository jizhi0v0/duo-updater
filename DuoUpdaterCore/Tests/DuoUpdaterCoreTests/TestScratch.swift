import Foundation

/// The one directory every ad-hoc fixture in this target is made under, removed
/// when the test process exits.
///
/// A dozen helpers used to mint their own `$TMPDIR/<name>-<UUID>` directory per
/// test and then remove only the bundle or the file inside it — or nothing at
/// all. By 2026-10-30 the mini's temporary directory held 205,312 entries, most
/// of them these: 49,528 `probe-identity-`, 39,904 `SparkleSignedFeedTests-`,
/// 37,638 `one-click-gate-`, 15,704 `qoder-identity-`, and five more families
/// behind them. Finder held 40 of those directories open and sat at 148% CPU
/// beside an `fseventsd` at 76%, on the churn of a directory with that many
/// entries; restarting Finder without fixing the leak brought it straight back.
///
/// One root keeps a killed run to a single leftover directory instead of dozens,
/// and a run that exits normally to none. A test that wants its fixture gone
/// sooner still removes it itself: this is the floor, not a replacement.
enum TestScratch {

    static let root: URL = {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-test-fixtures-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // `atexit` takes a C function pointer, so the closure may not capture:
        // read the static back instead, as `DuoStateDirectory` does.
        atexit { try? FileManager.default.removeItem(at: TestScratch.root) }
        return root
    }()

    /// A fresh path named `prefix-<UUID>` for a directory; the caller creates it.
    static func directory(_ prefix: String) -> URL {
        root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    /// A fresh path named `prefix-<UUID>` for a file in the root itself.
    static func file(_ prefix: String) -> URL {
        root.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    }
}
