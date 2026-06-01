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
                return "\(tool) failed (\(code)): \(msg)"
            }
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
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
        }

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
    private static func firstApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        if let top = entries.first(where: { $0.pathExtension == "app" }) {
            return top
        }
        for sub in entries where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let nested = try? fm.contentsOfDirectory(
                at: sub, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ).first(where: { $0.pathExtension == "app" }) {
                return nested
            }
        }
        return nil
    }

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
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
