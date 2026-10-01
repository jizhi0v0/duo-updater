import Foundation

/// One copy of bub on this Mac, identified by **where it is**: the virtual
/// environment it is installed in.
///
/// bub (https://github.com/bubbuild/bub, PyPI `bub`) is a Python package, so an
/// install is a venv holding `bub-<version>.dist-info` and a `bin/bub` console
/// script whose shebang names that venv's own interpreter. Nothing is signed;
/// what makes an install trackable is the package metadata pip and uv both
/// write, which names the distribution and its version without running it.
///
/// `method` says which installer made the venv, and so which one may update it.
/// Only the official installer's venv is ever updated by DuoUpdater — with
/// `bub update bub`, the command bub documents for that venv. A venv made by
/// `uv tool` or pipx is reported and never touched: `bub update` syncs bub's own
/// uv project into whatever venv it runs from, which in another installer's venv
/// means a second installer writing behind the first one's back.
public struct BubInstall: Sendable, Equatable, Codable {

    /// Who made the venv, read from where it is — never from `PATH`, which a GUI
    /// process does not have.
    public enum Method: String, Sendable, Codable {
        /// `curl -fsSL https://bub.build/install.sh | bash`: `uv venv --python 3.12
        /// ~/.bub/.venv`, then `uv pip install --upgrade bub` into it, and
        /// `~/.local/bin/bub` linked to its `bin/bub`. The script writes
        /// `$HOME/.bub` literally — `BUB_HOME` moves bub's data, not this venv.
        case installer
        /// `uv tool install bub`: `~/.local/share/uv/tools/bub` (`uv tool dir`
        /// in a fresh HOME, uv 0.9.18, measured 2026-10-01), with a
        /// `uv-receipt.toml` beside the venv.
        case uvTool
        /// `pipx install bub`: `~/Library/Application Support/pipx/venvs/bub` —
        /// pipx 1.17.8's default on macOS (`pipx environment` in a fresh HOME,
        /// 2026-10-01) — or `~/.local/pipx/venvs/bub`, the fallback home pipx
        /// keeps using wherever it already exists.
        case pipx
    }

    /// Why the install cannot run, as opposed to being out of date.
    public enum Problem: String, Sendable, Codable {
        /// `bin/bub` is missing or not executable.
        case executableMissing
        /// `bin/python` points at nothing — the interpreter the venv was made
        /// from is gone (`uv python uninstall`, a removed Homebrew Python), so
        /// every console script in it fails before bub's code runs.
        case interpreterMissing
        /// No `bub-*.dist-info` in the venv: the package was uninstalled and the
        /// script left behind.
        case packageMissing
    }

    /// A `direct_url.json` in the dist-info (PEP 610), which pip and uv write only
    /// when the package came from somewhere other than an index. A PyPI install
    /// has none (measured 2026-10-01: `uv pip install bub==0.4.4` wrote `INSTALLER`,
    /// `METADATA`, `RECORD`, `REQUESTED`, `WHEEL`, `entry_points.txt`).
    public enum DirectSource: String, Sendable, Codable {
        /// `pip install -e` / `uv pip install -e`: a checkout, in place.
        case editable
        /// A git (or other VCS) URL.
        case vcs
        /// A local directory or file that is not editable.
        case localPath
        /// A wheel or sdist fetched from a URL rather than resolved from an index.
        case archive
    }

    /// The state of bub's own uv project, `~/.bub/bub-project`, which every
    /// `bub update` syncs from. Read only for the official installer's venv.
    public enum Project: String, Sendable, Codable {
        /// No `pyproject.toml` yet: `bub update` creates the project — `uv init`,
        /// then `uv add bub` — before it syncs. `uv init` writes the Python uv
        /// picks by default as the floor, and when that is newer than the venv's,
        /// the sync replaces the whole venv: measured on the user's Mac on
        /// 2026-10-01, the installer's 3.12 venv came back as 3.13
        /// (`requires-python = ">=3.13"`), bub 0.5.0 in it and running. The same
        /// happens to the same command run in a terminal; the workbench says so
        /// beside the click (`CLIToolPresentation.caution`).
        case absent
        /// The project depends on bub, so `bub update bub` can move it.
        case listsBub
        /// A `pyproject.toml` that does not depend on bub. bub's `_ensure_project`
        /// creates the file first and adds bub second, so a first `bub update`
        /// that fails in between — offline, measured 2026-10-01 with a dead proxy —
        /// leaves exactly this, and from then on `bub update bub` sees the file,
        /// skips creating it, syncs a project with no bub in it and exits 0
        /// having changed nothing ("Resolved 1 package … Audited", measured on
        /// the same HOME right after).
        case missingBub
    }

    /// The venv: the install's identity.
    public let path: String
    public let method: Method
    /// The venv's `bin/bub`, which is what runs `bub update`.
    public let executable: String
    /// The dist-info's `Version:`. nil when there is no single `bub` dist-info to
    /// read.
    public let version: String?
    public let problem: Problem?
    /// Set when the package did not come from an index.
    public let directSource: DirectSource?
    /// Only for `.installer`; nil for the others, and when the manifest could not
    /// be read.
    public let project: Project?

    public init(
        path: String, method: Method, executable: String, version: String?,
        problem: Problem? = nil, directSource: DirectSource? = nil, project: Project? = nil
    ) {
        self.path = path
        self.method = method
        self.executable = executable
        self.version = version
        self.problem = problem
        self.directSource = directSource
        self.project = project
    }
}

/// Finds bub installs by looking where each installer puts its venv.
///
/// Network-free and never runs bub or Python: the version is the dist-info's
/// `METADATA`, the rest is the layout.
public struct BubScanner: Sendable {

    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// The official installer's venv, `~/.bub/.venv`.
    var installerVenv: URL { home.appendingPathComponent(".bub/.venv") }
    /// bub's own uv project, beside that venv. `BUB_HOME` or `BUB_PROJECT` would
    /// move it, but a GUI process cannot see the shell's environment, and neither
    /// can the `bub update` it starts — so the project the one-click syncs is this
    /// one. A user who keeps their project elsewhere gets a second one here on the
    /// first click (not measured how their own project then behaves).
    var project: URL { home.appendingPathComponent(".bub/bub-project") }

    /// Each conventional venv with the method that put it there, in the order
    /// they are listed.
    var candidates: [(URL, BubInstall.Method)] {
        [
            (installerVenv, .installer),
            (home.appendingPathComponent(".local/share/uv/tools/bub"), .uvTool),
            (home.appendingPathComponent("Library/Application Support/pipx/venvs/bub"), .pipx),
            (home.appendingPathComponent(".local/pipx/venvs/bub"), .pipx),
        ]
    }

    /// Every install found, each venv at most once. Blocking file-system work:
    /// keep it off the cooperative pool.
    public func scan() -> [BubInstall] {
        var seen = Set<String>()
        return candidates.compactMap { venv, method in
            guard seen.insert(venv.resolvingSymlinksInPath().path).inserted else { return nil }
            return install(at: venv, method: method)
        }
    }

    /// The install in `venv`, or nil when there is none — no venv, a venv with
    /// neither bub's script nor its package, or one that lives inside an app.
    func install(at venv: URL, method: BubInstall.Method) -> BubInstall? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: venv.appendingPathComponent("pyvenv.cfg").path) else { return nil }
        let executable = venv.appendingPathComponent("bin/bub")
        let distInfos = Self.bubDistInfos(in: venv)
        let hasScript = fm.fileExists(atPath: executable.path)
        guard hasScript || !distInfos.isEmpty else { return nil }
        // An app that ships bub in a venv of its own updates it with itself;
        // see `ClaudeCodeScanner.owningApp`.
        guard ClaudeCodeScanner.owningApp(of: venv.path) == nil,
              ClaudeCodeScanner.owningApp(of: executable.path) == nil
        else { return nil }

        let problem: BubInstall.Problem?
        if distInfos.isEmpty {
            problem = .packageMissing
        } else if !fm.isExecutableFile(atPath: executable.path) {
            problem = .executableMissing
        } else if !fm.isExecutableFile(atPath: venv.appendingPathComponent("bin/python").resolvingSymlinksInPath().path) {
            problem = .interpreterMissing
        } else {
            problem = nil
        }
        // Two `bub` dist-infos side by side is an interrupted install; which one
        // Python imports is not ours to guess.
        let distInfo = distInfos.count == 1 ? distInfos[0] : nil
        return BubInstall(
            path: venv.path, method: method, executable: executable.path,
            version: distInfo.flatMap(Self.version(of:)),
            problem: problem,
            directSource: distInfo.flatMap(Self.directSource(of:)),
            project: method == .installer ? projectState() : nil)
    }

    // MARK: - Package metadata

    /// The `bub-<version>.dist-info` directories in the venv's `site-packages`,
    /// for whichever `lib/python3.*` the venv has. The name is checked against
    /// `METADATA` too: a plugin's dist-info is `bub_web_search-0.0.2.dist-info`
    /// (underscores, measured), which the prefix already excludes, but a
    /// directory name alone is not the distribution's word for itself.
    static func bubDistInfos(in venv: URL) -> [URL] {
        let fm = FileManager.default
        let lib = venv.appendingPathComponent("lib")
        let pythons = ((try? fm.contentsOfDirectory(atPath: lib.path)) ?? []).filter { $0.hasPrefix("python") }.sorted()
        return pythons.flatMap { python -> [URL] in
            let sitePackages = lib.appendingPathComponent(python).appendingPathComponent("site-packages")
            let names = ((try? fm.contentsOfDirectory(atPath: sitePackages.path)) ?? []).sorted()
            return names
                .filter { $0.hasPrefix("bub-") && $0.hasSuffix(".dist-info") }
                .map { sitePackages.appendingPathComponent($0) }
                .filter { metadata($0)?.name == "bub" }
        }
    }

    /// `Name:` (normalized as PEP 503 does) and `Version:` from the core metadata
    /// headers, which end at the first blank line.
    static func metadata(_ distInfo: URL) -> (name: String, version: String?)? {
        guard let text = try? String(contentsOf: distInfo.appendingPathComponent("METADATA"), encoding: .utf8)
        else { return nil }
        var name: String?
        var version: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { break }
            if line.hasPrefix("Name:") {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Version:") {
                version = line.dropFirst(8).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let name else { return nil }
        let normalized = name.lowercased().replacingOccurrences(
            of: "[-_.]+", with: "-", options: .regularExpression)
        return (normalized, version.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `METADATA`'s version, else the one in the directory name.
    static func version(of distInfo: URL) -> String? {
        if let version = metadata(distInfo)?.version { return version }
        let name = distInfo.deletingPathExtension().lastPathComponent
        let version = String(name.dropFirst("bub-".count))
        return version.isEmpty ? nil : version
    }

    /// PEP 610's three shapes: `dir_info` (with `editable`), `vcs_info`,
    /// `archive_info`.
    static func directSource(of distInfo: URL) -> BubInstall.DirectSource? {
        guard let data = try? Data(contentsOf: distInfo.appendingPathComponent("direct_url.json")) else {
            return nil
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let dir = json["dir_info"] as? [String: Any] {
            return (dir["editable"] as? Bool) == true ? .editable : .localPath
        }
        if json["vcs_info"] != nil { return .vcs }
        if json["archive_info"] != nil {
            return (json["url"] as? String)?.hasPrefix("file:") == true ? .localPath : .archive
        }
        // A direct_url.json we cannot read still says "not from an index".
        return .archive
    }

    // MARK: - bub's project

    /// nil when the manifest is there but cannot be read: nothing to say either way.
    func projectState() -> BubInstall.Project? {
        let manifest = project.appendingPathComponent("pyproject.toml")
        guard let text = try? String(contentsOf: manifest, encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: manifest.path) ? nil : .absent
        }
        return Self.dependsOnBub(text) ? .listsBub : .missingBub
    }

    /// Whether `[project].dependencies` names `bub` — `"bub>=0.5.0"` is what
    /// `uv add bub` writes (measured). Plugins (`bub-web-search>=0.0.2`) are other
    /// names. Not a TOML parser: the array's quoted strings are collected up to
    /// the first `]` outside quotes, so an extra (`"bub-x[a]"`) does not end it
    /// early.
    static func dependsOnBub(_ pyproject: String) -> Bool {
        guard let start = pyproject.range(of: #"(?m)^\s*dependencies\s*=\s*\["#, options: .regularExpression)
        else { return false }
        var requirements: [String] = []
        var current: String?
        for character in pyproject[start.upperBound...] {
            if character == "\"" {
                if let done = current { requirements.append(done); current = nil } else { current = "" }
            } else if current != nil {
                current?.append(character)
            } else if character == "]" {
                break
            }
        }
        return requirements.contains { requirement in
            let name = requirement.trimmingCharacters(in: .whitespaces)
                .prefix { $0.isLetter || $0.isNumber || "._-".contains($0) }
            return name.lowercased().replacingOccurrences(of: "[-_.]+", with: "-", options: .regularExpression) == "bub"
        }
    }
}
