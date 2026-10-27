import Darwin
import Foundation

/// D15's guarantee for a managed update that may be stopped: what the vendor's
/// command may write is cloned before it starts, and put back if it is stopped,
/// so a stop leaves the manager exactly as it was — the old version, its
/// receipts, links and records — whatever the command had reached.
///
/// Clones only (`clonefile(2)`, APFS): a directory is cloned whole, in one
/// call, and costs its metadata, not its bytes. Where a path cannot be cloned —
/// another volume, a file system without clones — `take` throws, and the
/// update runs to completion as before D15: a full copy of a venv or a
/// toolchain before every update would cost more than the stop is worth.
///
/// The paths are the adapter's (`ManagerAdapter.interruption`), measured per
/// manager: plans/cli-managers-redesign.md §13.4.
struct ManagedSnapshot: Sendable {
    /// One path the command may write: cloned when it existed, else only
    /// remembered as absent, so `restore` removes what the command made there.
    struct Entry: Sendable, Equatable {
        let path: String
        /// The clone, nil when the path did not exist.
        let clone: String?
    }

    enum Failure: Error, Equatable {
        /// Two paths where one is inside the other: restoring the outer one
        /// would undo the inner one's restore, or the other way round.
        case overlapping(String, String)
        /// `clonefile` refused (errno): another volume, or no clones there.
        case notCloned(String, Int32)
        case noScratch(String)
    }

    let directory: String
    let entries: [Entry]

    /// Clone each of `paths` that exists into a scratch directory on its
    /// volume. Throws, having removed what it cloned, when any one cannot be.
    static func take(_ paths: [String]) throws -> ManagedSnapshot {
        let paths = paths.map { ($0 as NSString).standardizingPath }
        for a in paths {
            for b in paths where a != b && b.hasPrefix(a + "/") {
                throw Failure.overlapping(a, b)
            }
        }
        guard let first = paths.first else { return ManagedSnapshot(directory: "", entries: []) }
        let directory: String
        do {
            // On the volume of the paths: a clone cannot cross volumes.
            directory = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask,
                appropriateFor: URL(fileURLWithPath: first), create: true).path
        } catch {
            throw Failure.noScratch("\(error)")
        }
        var entries: [Entry] = []
        for (index, path) in paths.enumerated() {
            var info = stat()
            guard lstat(path, &info) == 0 else {
                entries.append(Entry(path: path, clone: nil))
                continue
            }
            let clone = directory + "/\(index)"
            guard clonefile(path, clone, UInt32(CLONE_NOFOLLOW)) == 0 else {
                let code = errno
                try? FileManager.default.removeItem(atPath: directory)
                throw Failure.notCloned(path, code)
            }
            entries.append(Entry(path: path, clone: clone))
        }
        return ManagedSnapshot(directory: directory, entries: entries)
    }

    /// Put every path back as `take` found it: a clone swapped in for what is
    /// there now, a path that was absent removed. Runs only once the command
    /// and every process of its group have exited. Returns the paths it could
    /// not put back, with why; empty when all are back.
    func restore() -> [String] {
        var failed: [String] = []
        for entry in entries {
            let now = exists(entry.path)
            guard let clone = entry.clone else {
                if now, (try? FileManager.default.removeItem(atPath: entry.path)) == nil {
                    failed.append("\(entry.path): could not remove what the stopped command made")
                }
                continue
            }
            if now {
                // Atomic: at every instant the path is either what the command
                // left or the clone, never missing.
                guard renamex_np(clone, entry.path, UInt32(RENAME_SWAP)) == 0 else {
                    failed.append("\(entry.path): \(String(cString: strerror(errno)))")
                    continue
                }
                // The swap left the command's version where the clone was.
                try? FileManager.default.removeItem(atPath: clone)
            } else {
                let parent = (entry.path as NSString).deletingLastPathComponent
                try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                if rename(clone, entry.path) != 0 {
                    failed.append("\(entry.path): \(String(cString: strerror(errno)))")
                }
            }
        }
        return failed
    }

    /// The command finished, or was never started: the clones go.
    func discard() {
        guard !directory.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: directory)
    }

    private func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
