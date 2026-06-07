import Foundation

/// Extracts a downloaded Sparkle archive and returns the `.app` bundle inside.
/// Supports the common formats: `.dmg` (hdiutil), `.zip` (ditto), and tarballs.
enum ArchiveExtractor {

    enum ExtractError: LocalizedError {
        case unsupported(String)
        case noAppFound
        case toolFailed(String, Int32, String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Unsupported archive type: .\(ext)"
            case .noAppFound: return "No .app bundle was found inside the archive."
            case .toolFailed(let tool, let code, let msg):
                return "\(tool) failed (\(code)): \(Self.condense(msg))"
            }
        }

        /// Boil a tool's raw stderr down to one short, legible line. `ditto`/`tar`
        /// fault per-file, so a single failure (most often a full disk) prints the
        /// same reason hundreds of times — surfaced verbatim that wall of text both
        /// reads as noise and, in the workbench, blows the window's min-height up.
        /// Collapse the common "out of space" case to one clear sentence; otherwise
        /// keep the first few distinct lines, capped.
        private static func condense(_ raw: String) -> String {
            let lines = raw.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if lines.contains(where: { $0.localizedCaseInsensitiveContains("No space left on device") }) {
                return "not enough disk space to extract the update — free up space and try again"
            }
            var seen = Set<String>()
            var kept: [String] = []
            for line in lines where seen.insert(line).inserted {
                kept.append(line)
                if kept.count == 3 { break }
            }
            let joined = kept.isEmpty ? "(no output)" : kept.joined(separator: "; ")
            return joined.count > 300 ? String(joined.prefix(300)) + "…" : joined
        }
    }

    /// Extract `archive` into a fresh temp dir and return the contained `.app`.
    /// `workDir` is the caller-owned scratch directory to clean up afterward.
    static func extractApp(from archive: URL, workDir: URL) throws -> URL {
        let ext = archive.pathExtension.lowercased()
        switch ext {
        case "dmg":
            return try fromDMG(archive, workDir: workDir)
        case "zip":
            return try fromZip(archive, workDir: workDir)
        case "gz", "bz2", "xz", "tar", "tbz", "tgz":
            return try fromTar(archive, workDir: workDir)
        case "app":
            return archive  // already an app (rare, but possible)
        default:
            throw ExtractError.unsupported(ext)
        }
    }

    // MARK: dmg

    private static func fromDMG(_ dmg: URL, workDir: URL) throws -> URL {
        let mountPoint = workDir.appendingPathComponent("mnt-\(dmg.lastPathComponent)")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = try run("/usr/bin/hdiutil", [
            "attach", dmg.path,
            "-nobrowse", "-readonly", "-noverify",
            "-mountpoint", mountPoint.path
        ])
        guard attach.code == 0 else {
            throw ExtractError.toolFailed("hdiutil attach", attach.code, attach.err)
        }
        defer { detach(mountPoint) }

        guard let appInMount = firstApp(in: mountPoint) else {
            throw ExtractError.noAppFound
        }
        // Copy the app out of the read-only mount into our work dir.
        let dest = workDir.appendingPathComponent(appInMount.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        let copy = try run("/usr/bin/ditto", [appInMount.path, dest.path])
        guard copy.code == 0 else {
            throw ExtractError.toolFailed("ditto", copy.code, copy.err)
        }
        return dest
    }

    // MARK: zip

    private static func fromZip(_ zip: URL, workDir: URL) throws -> URL {
        let dest = workDir.appendingPathComponent("unzipped")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let r = try run("/usr/bin/ditto", ["-x", "-k", zip.path, dest.path])
        guard r.code == 0 else {
            throw ExtractError.toolFailed("ditto -x -k", r.code, r.err)
        }
        guard let app = firstApp(in: dest) else { throw ExtractError.noAppFound }
        return app
    }

    // MARK: tar

    private static func fromTar(_ tar: URL, workDir: URL) throws -> URL {
        let dest = workDir.appendingPathComponent("untarred")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let r = try run("/usr/bin/tar", ["-xf", tar.path, "-C", dest.path])
        guard r.code == 0 else {
            throw ExtractError.toolFailed("tar", r.code, r.err)
        }
        guard let app = firstApp(in: dest) else { throw ExtractError.noAppFound }
        return app
    }

    // MARK: helpers

    /// First `.app` at the top level of a directory (recurse one level for the
    /// occasional archive that nests the app in a subfolder).
    ///
    /// Selection is deterministic (entries sorted by name, not the unspecified
    /// `contentsOfDirectory` order) and rejects symlinks — a member named
    /// `Foo.app` that is actually a symlink could otherwise point the gates, and
    /// then a privileged swap, at an arbitrary location. We also confirm the
    /// chosen bundle resolves to a path *inside* `dir`, so a `..`/symlink member
    /// that escaped extraction can't be returned as "the app".
    private static func firstApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        let dirBase = dir.resolvingSymlinksInPath().standardizedFileURL.path

        func isUsableApp(_ url: URL) -> Bool {
            guard url.pathExtension == "app" else { return false }
            // Reject symlinks (a real .app bundle is a directory, not a link).
            let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if vals?.isSymbolicLink == true { return false }
            if vals?.isDirectory != true { return false }
            // Must resolve to within the extraction dir.
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            return resolved == dirBase || resolved.hasPrefix(dirBase + "/")
        }

        func sortedEntries(of url: URL) -> [URL] {
            (try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ))?.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        }

        let entries = sortedEntries(of: dir)
        if let top = entries.first(where: isUsableApp) { return top }
        for sub in entries where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            && (try? sub.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true {
            if let nested = sortedEntries(of: sub).first(where: isUsableApp) {
                return nested
            }
        }
        return nil
    }

    /// Detach a mounted image, retrying once after a short pause: a `ditto` that
    /// just finished copying can leave the volume momentarily busy, and a single
    /// `-force` detach then fails, leaking the mount and blocking workDir cleanup.
    private static func detach(_ mountPoint: URL) {
        if (try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]))?.code == 0 {
            return
        }
        Thread.sleep(forTimeInterval: 0.5)
        _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    /// Reference holder so a background pipe-drain can publish its result back to
    /// the caller without Swift 6 flagging a captured-`var` mutation. Single writer
    /// (the drain closure), read only after a `DispatchGroup` barrier, so the
    /// `@unchecked` is sound.
    private final class DataBox: @unchecked Sendable { var data = Data() }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) throws
        -> (code: Int32, out: String, err: String)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        // Watchdog: a wedged `hdiutil attach` on a malformed/maliciously-crafted dmg
        // (or a pathological `ditto`/`tar`) can block indefinitely, freezing the
        // install actor with no way out. SIGTERM at the cap, then SIGKILL shortly
        // after if it ignores that (a stuck process can hold its stdout write end
        // open, so the drain below would never return) — SIGKILL closes the pipe and
        // unblocks the read for sure. Same pattern as the lsappinfo guard.
        let pid = process.processIdentifier
        let term = DispatchWorkItem { process.terminate() }
        let kill = DispatchWorkItem { Foundation.kill(pid, SIGKILL) }
        // 5-min ceiling: generous enough that a large Electron-bundle extraction on
        // a slow disk finishes well within it, short enough that a true hang doesn't
        // wedge the install indefinitely.
        DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: term)
        DispatchQueue.global().asyncAfter(deadline: .now() + 305, execute: kill)
        // Drain both pipes CONCURRENTLY. Reading stdout to EOF first and only then
        // stderr deadlocks when the child fills stderr's ~64KB buffer while stdout
        // is still open (tar/hdiutil/ditto on a corrupt or pathological archive can
        // emit large stderr): the child blocks on its stderr write(), stdout never
        // reaches EOF, and we block forever. Read stderr on a background queue so
        // both buffers drain in parallel.
        let errBox = DataBox()
        let errQueue = DispatchQueue(label: "com.duoupdater.archiveextractor.stderr")
        let errDone = DispatchGroup()
        errDone.enter()
        let errHandle = errPipe.fileHandleForReading
        errQueue.async {
            errBox.data = errHandle.readDataToEndOfFile()
            errDone.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        let errData = errBox.data
        process.waitUntilExit()
        term.cancel()
        kill.cancel()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
