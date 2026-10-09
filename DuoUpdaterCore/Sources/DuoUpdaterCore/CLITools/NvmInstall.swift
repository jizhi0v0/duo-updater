import Foundation

/// nvm itself — not the node versions it keeps, which are npm prefixes
/// (`NodePrefixes`) — as its install script leaves it, identified by **its
/// `nvm.sh`**: `~/.nvm/nvm.sh` or `~/.config/nvm/nvm.sh`.
///
/// The layout, from the vendor's installer (`curl -o-
/// https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash`,
/// read 2026-10-09):
/// - It installs into `$NVM_DIR`, else `$XDG_CONFIG_HOME/nvm` when that is set,
///   else `~/.nvm`. An app sees neither variable, so the two defaults are
///   looked at (`~/.config/nvm` being XDG's own default for `XDG_CONFIG_HOME`).
/// - With git it makes a shallow clone of the tag; without, it downloads
///   `nvm.sh`, `nvm-exec` and `bash_completion` bare. Either way `nvm.sh` is a
///   file of the directory. It edits shell profiles and leaves no receipt.
/// - Homebrew's nvm lives in its keg and asks the user to create the directory
///   themselves; on this Mac (2026-10-09) `~/.nvm/nvm.sh` was a link to
///   `/opt/homebrew/opt/nvm/libexec/nvm.sh`, which resolves into
///   `Cellar/nvm/0.40.8`. Such an `nvm.sh` — one that resolves out of its
///   directory — is that package's, not this group's, and is not listed.
/// - nvm is shell scripts: no signature, no published checksum.
///
/// The version is read out of `nvm.sh` — its `nvm --version` case — never by
/// running it, and never by asking git.
public struct NvmInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// No `nvm --version` case in `nvm.sh`, or several that disagree.
        case versionUnreadable
    }

    public enum Layout: String, Sendable, Codable {
        /// A git checkout, as the installer leaves it when git is there.
        case git
        /// The bare files, as the installer leaves them without git.
        case script
    }

    /// `~/.nvm/nvm.sh` or `~/.config/nvm/nvm.sh`: the row's identity.
    public let path: String
    public let version: String?
    public let layout: Layout
    public let problem: Problem?

    public init(path: String, version: String?, layout: Layout = .git, problem: Problem? = nil) {
        self.path = path
        self.version = version
        self.layout = layout
        self.problem = problem
    }
}

/// Finds nvm where its installer puts it. Network-free, and nothing is run.
public struct NvmScanner: Sendable {

    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var directories: [String] { [home.path + "/.nvm", home.path + "/.config/nvm"] }

    /// Each install, `~/.nvm` first; a directory that is the other one (a link)
    /// is listed once. Blocking: files are stat'd and read.
    public func scan() -> [NvmInstall] {
        var seen: Set<String> = []
        var installs: [NvmInstall] = []
        for directory in directories {
            guard let canonical = LuvusScanner.canonicalPath(directory), seen.insert(canonical).inserted,
                  let install = read(directory: directory, canonical: canonical)
            else { continue }
            installs.append(install)
        }
        return installs
    }

    /// Blocking.
    func read(directory: String, canonical: String) -> NvmInstall? {
        let path = directory + "/nvm.sh"
        // Only an `nvm.sh` of the directory's own: one that resolves anywhere
        // else (Homebrew's keg) belongs to whatever put it there.
        guard let file = LuvusScanner.canonicalPath(path), file == canonical + "/nvm.sh",
              let attributes = try? FileManager.default.attributesOfItem(atPath: file),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let data = FileManager.default.contents(atPath: file)
        else { return nil }
        let version = Self.version(in: String(decoding: data, as: UTF8.self))
        let layout: NvmInstall.Layout = FileManager.default.fileExists(atPath: directory + "/.git") ? .git : .script
        return NvmInstall(path: path, version: version, layout: layout,
                          problem: version == nil ? .versionUnreadable : nil)
    }

    /// The version `nvm --version` prints: the `nvm_echo '<version>'` of its
    /// `"--version" | "-v")` case (`"--version")` alone before 0.36), read
    /// 2026-10-09 in v0.35.3, v0.38.0, v0.39.7, v0.40.7, v0.40.8 and Homebrew's
    /// 0.40.8. Anchored on the case, because `nvm.sh` has sixteen other
    /// `nvm_echo '…'` lines (colour codes, `'0;31m'`).
    static func version(in text: String) -> String? {
        let pattern = #""--version"(?: \| "-v")?\)\s*nvm_echo '(\d{1,4}\.\d{1,4}\.\d{1,4})'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let found = Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
        return found.count == 1 ? found.first : nil
    }
}
