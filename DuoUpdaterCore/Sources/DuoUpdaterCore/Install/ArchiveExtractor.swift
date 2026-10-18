import Foundation

/// Extracts a downloaded Sparkle archive and returns the `.app` bundle inside.
/// Supports the common formats: `.dmg` (`DiskImageMount`), `.zip` (ditto), and tarballs.
///
/// Public for `duo diff`, which unpacks two releases the same way an install would.
public enum ArchiveExtractor {

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
    ///
    /// Cancelling the calling task tears down the `ditto`/`tar` it is waiting on
    /// and throws `CancellationError`. That is safe because each of those tools
    /// writes only into `workDir`, which the caller removes whatever the outcome.
    /// The DMG is the one thing that must not outlive a cancel, and it does not:
    /// `DiskImageMount`'s attach and detach are `.runToCompletion` children of
    /// their own, and `fromDMG` detaches in a `defer`, which also runs when the
    /// copy out was cut short. A DMG left mounted because a cancel landed between
    /// attach and detach is exactly what must not happen.
    public static func extractApp(from archive: URL, workDir: URL) async throws -> URL {
        let ext = archive.pathExtension.lowercased()
        switch ext {
        case "dmg":
            return try await fromDMG(archive, workDir: workDir)
        case "zip":
            return try await fromZip(archive, workDir: workDir)
        case "gz", "bz2", "xz", "tar", "tbz", "tgz":
            return try await fromTar(archive, workDir: workDir)
        case "app":
            return archive  // already an app (rare, but possible)
        default:
            throw ExtractError.unsupported(ext)
        }
    }

    /// Unpack `archive` into `dest` and return nothing — no search for a bundle.
    ///
    /// For a package that does not carry a `.app` at all, so `extractApp`'s
    /// `noAppFound` would be the wrong answer rather than a failure:
    /// `ContentsPayload` uses this on both levels of a vendor update whose
    /// payload is a bare `Contents` directory, and does its own, stricter, look
    /// at what came out.
    ///
    /// Archives only. A dmg is rejected rather than mounted: mounting is what
    /// `fromDMG` exists for, it needs a `defer`ed detach to be safe, and no
    /// vendor ships this shape in one — an unsupported extension here is a
    /// recipe bug, and should read as one.
    ///
    /// Cancellable like `extractApp`, for the same reason: it writes only into
    /// `dest`, which every caller passes as its own scratch directory.
    public static func unpack(_ archive: URL, into dest: URL) async throws {
        switch archive.pathExtension.lowercased() {
        case "zip":
            let r = try await run("/usr/bin/ditto", ["-x", "-k", archive.path, dest.path])
            guard r.code == 0 else {
                throw ExtractError.toolFailed("ditto -x -k", r.code, r.err)
            }
        case "gz", "bz2", "xz", "tar", "tbz", "tgz":
            let r = try await run("/usr/bin/tar", ["-xf", archive.path, "-C", dest.path])
            guard r.code == 0 else { throw ExtractError.toolFailed("tar", r.code, r.err) }
        case let ext:
            throw ExtractError.unsupported(ext)
        }
    }

    // MARK: dmg

    private static func fromDMG(_ dmg: URL, workDir: URL) async throws -> URL {
        let mountPoint = workDir.appendingPathComponent("mnt-\(dmg.lastPathComponent)")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        if case .failure(let failure) = try await DiskImageMount.attach(dmg, at: mountPoint) {
            throw ExtractError.toolFailed(failure.tool, failure.code, failure.stderr)
        }
        // Detached on every path out. The `defer` sees a cancelled task as
        // cancelled (SE-0493), which is why `DiskImageMount.detach` takes its
        // retry pause in a detached task rather than trusting `Task.sleep` here.
        defer { await DiskImageMount.detach(mountPoint, image: dmg) }
        return try await copyApp(outOf: mountPoint, into: workDir)
    }

    private static func copyApp(outOf mountPoint: URL, into workDir: URL) async throws -> URL {
        guard let appInMount = firstApp(in: mountPoint) else {
            throw ExtractError.noAppFound
        }
        // Copy the app out of the read-only mount into our work dir.
        let dest = workDir.appendingPathComponent(appInMount.lastPathComponent)
        // A leftover here is a whole app bundle, so its removal is off the pool.
        await removeItemOffCooperativePool(at: dest)
        let copy = try await run("/usr/bin/ditto", [appInMount.path, dest.path])
        guard copy.code == 0 else {
            throw ExtractError.toolFailed("ditto", copy.code, copy.err)
        }
        return dest
    }

    // MARK: zip

    private static func fromZip(_ zip: URL, workDir: URL) async throws -> URL {
        let dest = workDir.appendingPathComponent("unzipped")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let r = try await run("/usr/bin/ditto", ["-x", "-k", zip.path, dest.path])
        guard r.code == 0 else {
            throw ExtractError.toolFailed("ditto -x -k", r.code, r.err)
        }
        guard let app = firstApp(in: dest) else { throw ExtractError.noAppFound }
        return app
    }

    // MARK: tar

    private static func fromTar(_ tar: URL, workDir: URL) async throws -> URL {
        let dest = workDir.appendingPathComponent("untarred")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let r = try await run("/usr/bin/tar", ["-xf", tar.path, "-C", dest.path])
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

    /// Run one extraction tool, capturing both streams, and wait for it.
    ///
    /// Watchdog: a pathological `ditto`/`tar` can block indefinitely, freezing the
    /// install actor with no way out. SIGTERM at 300 s, SIGKILL at 305 s if it
    /// ignores that — generous enough that a large Electron-bundle extraction on a
    /// slow disk finishes well within it, short enough that a true hang doesn't
    /// wedge the install indefinitely. `code` is the signal number when it came to
    /// that, as `Process.terminationStatus` reported it, so the "failed (15)" in
    /// `ExtractError.toolFailed` reads the same.
    ///
    /// Both pipes drain concurrently (`ChildProcess` always does): tar/ditto
    /// on a corrupt or pathological archive can emit more than a pipe
    /// buffer of stderr while stdout is still open.
    ///
    /// Torn down when the caller is cancelled (SIGTERM, then SIGKILL after the
    /// grace), and throws `CancellationError` — see `extractApp` for why that is
    /// safe for every tool it runs.
    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) async throws
        -> (code: Int32, out: String, err: String)
    {
        let outcome = try await ChildProcess.run(
            launchPath, args,
            deadline: .init(terminateAfter: .seconds(300), killAfter: .seconds(305)),
            onCancel: .terminateChild)
        return (
            outcome.terminationStatus,
            String(data: outcome.standardOutput, encoding: .utf8) ?? "",
            String(data: outcome.standardError, encoding: .utf8) ?? ""
        )
    }
}
