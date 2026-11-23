import Darwin
import Foundation

struct MulticaBinary: Sendable, Equatable {
    enum Architecture: String, Sendable {
        case arm64, amd64
    }

    let version: String?
    let architecture: Architecture

    static func read(at url: URL) -> MulticaBinary? {
        let architecture: Architecture
        switch ClaudeCodeRelease.platform(of: url) {
        case "darwin-arm64": architecture = .arm64
        case "darwin-x64": architecture = .amd64
        default: return nil
        }

        let module = "github.com/multica-ai/multica/server"
        guard let info = GoBuildInfo.read(at: url), info.packagePath == module + "/cmd/multica",
              info.main?.path == module, info.main?.replacement == nil
        else { return nil }

        // Go quotes a build setting with spaces. GoReleaser passes -X and the
        // assignment as separate words inside those outer quotes.
        let prefix = "main.version="
        var flags = (info.linkerFlags ?? "")[...]
        if flags.hasPrefix("\""), flags.hasSuffix("\"") { flags = flags.dropFirst().dropLast() }
        let words = flags.split(whereSeparator: \.isWhitespace)
        let versions = zip(words, words.dropFirst()).compactMap { option, argument -> String? in
            guard option == "-X", argument.hasPrefix(prefix) else { return nil }
            let version = argument.dropFirst(prefix.count)
            let value = version.hasPrefix("v") ? version.dropFirst() : version
            return value.isEmpty ? nil : String(value)
        }
        let version = versions.count == 1 ? versions.first : nil
        return MulticaBinary(version: version, architecture: architecture)
    }
}

public struct MulticaInstall: Sendable, Equatable {
    public let path: String
    let executable: String
    let binary: MulticaBinary
    let file: MulticaFileStamp
    let directory: CLIToolProcesses.FileID
    let linked: Bool
    let writable: Bool
    let quarantined: Bool

    public var version: String? { binary.version }
    var target: CLIToolProcesses.Target { .init(executable: executable) }

    var canReplace: Bool { !linked && writable && !quarantined && file.links == 1 }
}

/// Detect a rename and in-place edits, including changes made while an archive
/// is downloading. lstat is used at the original path, including at commit.
struct MulticaFileStamp: Sendable, Equatable {
    let identity: CLIToolProcesses.FileID
    let links: UInt16
    let owner: uid_t
    let group: gid_t
    let mode: mode_t
    let bytes: off_t
    let changedSeconds: Int
    let changedNanoseconds: Int

    init?(_ info: stat) {
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0,
              info.st_size <= MulticaArchive.maximumExecutableBytes, info.st_mode & 0o111 != 0
        else { return nil }
        identity = .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
        links = info.st_nlink
        owner = info.st_uid
        group = info.st_gid
        mode = info.st_mode
        bytes = info.st_size
        changedSeconds = info.st_ctimespec.tv_sec
        changedNanoseconds = info.st_ctimespec.tv_nsec
    }

    static func read(at path: String) -> Self? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Self(info)
    }
}

struct MulticaScanner: Sendable {
    let home: URL
    let directories: [URL]

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemDirectory: URL = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        customDirectory: String? = ProcessInfo.processInfo.environment["MULTICA_BIN_DIR"]
    ) {
        self.home = home
        var directories = [systemDirectory, home.appendingPathComponent(".local/bin", isDirectory: true)]
        if let customDirectory, customDirectory.hasPrefix("/") {
            directories.append(URL(fileURLWithPath: customDirectory, isDirectory: true).standardizedFileURL)
        }
        self.directories = directories
    }

    private var paths: [String] {
        directories.map { $0.appendingPathComponent("multica").path }
    }

    func scan() -> [MulticaInstall] {
        var found: [MulticaInstall] = []
        for path in paths {
            guard let install = read(path) else { continue }
            if let index = found.firstIndex(where: { $0.executable == install.executable }) {
                if found[index].linked && !install.linked { found[index] = install }
            } else {
                found.append(install)
            }
        }
        return found
    }

    func reread(_ path: String) -> MulticaInstall? {
        guard paths.contains(path) else { return nil }
        return read(path)
    }

    private func read(_ path: String) -> MulticaInstall? {
        guard let executable = CLIToolProcesses.realpath(path),
              !externallyOwned(path), !externallyOwned(executable),
              let file = MulticaFileStamp.read(at: executable),
              let binary = MulticaBinary.read(at: URL(fileURLWithPath: executable)),
              let directory = CLIToolProcesses.fileID((executable as NSString).deletingLastPathComponent),
              CLIToolProcesses.realpath(path) == executable,
              MulticaFileStamp.read(at: executable) == file
        else { return nil }

        let parent = (executable as NSString).deletingLastPathComponent
        let linked = MulticaFileStamp.read(at: path) != file
        let writable = file.owner == geteuid() && (file.mode & 0o7000) == 0
            && access(executable, W_OK) == 0 && access(parent, W_OK | X_OK) == 0
        return MulticaInstall(
            path: path, executable: executable, binary: binary, file: file, directory: directory,
            linked: linked, writable: writable,
            quarantined: CLIToolTrust.hasQuarantine(URL(fileURLWithPath: executable)))
    }

    private func externallyOwned(_ path: String) -> Bool {
        let components = path.lowercased().split(separator: "/")
        let canonicalHome = CLIToolProcesses.realpath(home.path) ?? home.path
        let cargo = CLIToolProcesses.realpath(home.appendingPathComponent(".cargo").path) ?? canonicalHome + "/.cargo"
        return components.contains("cellar") || components.contains(where: { $0.hasSuffix(".app") })
            || path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/nix/store/")
            || path.hasPrefix(cargo + "/") || path.contains("/mise/installs/")
    }
}
