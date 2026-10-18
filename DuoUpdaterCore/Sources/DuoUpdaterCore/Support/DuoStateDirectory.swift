import Foundation

/// Where DuoUpdater keeps its own on-disk state — the traffic log, the release
/// timeline, the changelog cache, formula release notes, the Tauri crate-proof
/// cache, and rollback backups.
///
/// This exists so a second DuoUpdater process can be pointed somewhere else.
/// The nightly `duo verify` sweep runs on the same machine and as the same user
/// as the menu-bar app, so without a redirect it writes the changelog cache and
/// traffic log the running app is reading — a scan of 152 recipes would poison
/// a cache that exists to answer "what did this app ship last time I looked".
///
/// Only *our* state moves. Directories we read that belong to other apps
/// (Squirrel staging, Alfred's preferences, the Toolbox inventory) resolve
/// Application Support directly and must keep doing so — they are facts about
/// the machine, not state we own.
public enum DuoStateDirectory {

    /// The container to place DuoUpdater's state directories inside. Callers
    /// append their own subpath (`com.duoupdater.app/traffic.json`,
    /// `DuoUpdater/Backups`, …) exactly as they did against Application Support,
    /// so an override relocates every store at once without renaming anything.
    ///
    /// `DUO_STATE_DIR` wins when set to a non-empty path. It is read fresh on
    /// every access rather than cached: tests set it per-case, and the cost is a
    /// dictionary lookup against operations that are already touching disk.
    public static var base: URL {
        if let override = ProcessInfo.processInfo.environment["DUO_STATE_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// The caches counterpart of ``base``: `~/Library/Caches`, or
    /// `$DUO_STATE_DIR/Caches` when the state directory is redirected.
    ///
    /// For data we can lose at any moment and simply fetch again — today only
    /// the half-finished downloads `ResumableDownloadStore` keeps. Apple's file
    /// system guide describes Caches as "cached data that can be regenerated as
    /// needed" that "apps should never rely on", which is exactly a partial
    /// download's contract: losing one costs a re-download, never correctness.
    /// The app and `duo` resolve the same directory (neither is sandboxed, so
    /// there is no per-app container), which is what lets one resume what the
    /// other left behind.
    ///
    /// Redirected with ``base`` rather than on its own so the nightly `duo
    /// verify` sweep, pointed elsewhere by `DUO_STATE_DIR`, keeps its partials
    /// out of the running app's directory too.
    public static var cachesBase: URL {
        if let override = ProcessInfo.processInfo.environment["DUO_STATE_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// The one directory a test process's stores write their scratch state under,
    /// removed when the process exits.
    ///
    /// Each store used to mint its own `duo-<store>-tests-<UUID>` directly in
    /// `$TMPDIR` and leave it there: one per test process for the shared stores,
    /// one per *instance* for the CLI tools' digest files. Measured 2026-10-12 on
    /// the mini, which also hosts the CI runner: ~1,900 such directories, nothing
    /// ever removing them. They now nest under this root instead, keeping the
    /// per-process and per-instance UUIDs they had, and an `atexit` handler takes
    /// the whole root with it — a full `swift test` of this package left no root
    /// behind (2026-10-12), so the runner does leave through `exit`. A test
    /// process that is killed skips `atexit` and leaves its root behind — one
    /// directory, not dozens.
    static let testProcessScratchRoot: URL = {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-test-process-\(UUID().uuidString)", isDirectory: true)
        atexit { try? FileManager.default.removeItem(at: DuoStateDirectory.testProcessScratchRoot) }
        return root
    }()

    /// Whether this process is a test host, for the stores that must never
    /// write into the developer's own state even when `DUO_STATE_DIR` is unset.
    ///
    /// Moved here from `EventStore`, which used to be the only store that
    /// needed this question. `TauriProofStore` needs the identical check now,
    /// and leaving it where it was would have meant a second, private copy of
    /// the same few lines — exactly the drift this repository's own rules warn
    /// about. `EventStore.defaultFileURL()` still decides *whether* to redirect
    /// itself (see the comment there for why that decision stays local rather
    /// than moving into `base` above); only the "is this a test process"
    /// question moved.
    ///
    /// Both runners are named because they differ: SwiftPM runs the suite as
    /// `swiftpm-testing-helper` with no XCTest environment at all (measured),
    /// while Xcode uses `xctest` and an `.xctest` bundle.
    static var isTestProcess: Bool {
        let name = ProcessInfo.processInfo.processName
        return name == "swiftpm-testing-helper" || name == "xctest"
            || Bundle.main.bundleURL.pathExtension == "xctest"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
