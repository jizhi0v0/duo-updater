import Foundation

/// The apps pipx keeps (`pipx install`, one venv each) as managed rows, moved
/// by pipx's own `pipx upgrade <venv>` (plans/cli-managers-redesign.md §4.4).
///
/// What was measured, with pipx 1.11.1 (Python 3.9) and 1.18.4 (Python 3.12)
/// in isolated homes (2026-10-27; the fixtures under
/// `Tests/…/Fixtures/managed/pipx/` are their files and output):
/// - **Roots**: pipx ≥1.15.1 keeps its venvs in `~/Library/Application
///   Support/pipx/venvs`, older ones in `~/.local/pipx/venvs` — which a newer
///   pipx keeps using wherever it already exists (PX-04). Both are scanned;
///   the upgrade of a venv in the root its pipx would not pick by itself is
///   run with `PIPX_HOME` naming that root.
/// - **Scan, disk only**: each venv's `pipx_metadata.json` (`PipxMetadata`):
///   the package, its version, what it was installed from
///   (`package_or_url`), `pinned`, the venv's Python.
/// - **Check, no spawn**: PyPI's JSON per venv (`PyPIProject`), at most eight
///   at once, the newest its Python can install. pipx's own `list --outdated`
///   (≥1.15.1) answers the same and ignores the specifier too, but would run
///   pipx, which is a Python script nothing verifies.
/// - **What `pipx upgrade` does** (PX-14/15, measured on 1.18.4): it ignores
///   and then drops the recorded specifier — `httpie==3.2.1` upgraded to 3.2.4
///   and `package_or_url` became `httpie` (D7: offered, with the row's warning
///   first); `pipx pin` is the only pin it keeps ("Not upgrading pinned
///   package cowsay. Run `pipx unpin cowsay` to unpin it.", exit 0); a venv
///   from a local path or URL is left as it is (exit 0, "is unchanged … no
///   package index was checked") — reported here as not on an index; an
///   unknown venv exits 1.
/// - **Who may run it (D5)**: a Homebrew keg's pipx (`/opt/homebrew/bin/pipx`,
///   `/usr/local/bin/pipx` into `Cellar/pipx/<version>` with its install
///   receipt) gets the one-click, by the keg rule; a pipx that pip or `uv tool`
///   installed (`~/.local/bin/pipx`, a script in a venv) has nothing to verify,
///   so its command is handed out to copy (D5.2).
public struct PipxAdapter: ManagerAdapter {

    public static let id = ManagerID("pipx")

    public static let descriptor = ManagerDescriptor(
        id: id, displayName: "pipx", signer: nil, logo: "cli-pipx",
        // The teal of the X in pipx's own logo (pypa/pipx `logo.svg`).
        tint: .rgb(red: 0x00 / 255, green: 0xCB / 255, blue: 0xA3 / 255), lane: "pipx")

    public var descriptor: ManagerDescriptor { Self.descriptor }

    public struct Host: Sendable {
        /// A file's bytes, nil when there is none. Blocking.
        public var contents: @Sendable (String) -> Data?
        /// The names in a directory, nil when it cannot be listed. Blocking.
        public var directories: @Sendable (String) -> [String]?
        /// A file's modification date. Blocking.
        public var modified: @Sendable (String) -> Date?
        /// Where a symlink chain ends (the path itself when it is none); nil
        /// when nothing is there. Blocking.
        public var resolve: @Sendable (String) -> String?
        public var isQuarantined: @Sendable (String) -> Bool
        /// PyPI's JSON document for a project; throws when it did not answer.
        public var pypi: @Sendable (String) async throws -> Data

        public init(
            contents: @escaping @Sendable (String) -> Data?,
            directories: @escaping @Sendable (String) -> [String]?,
            modified: @escaping @Sendable (String) -> Date?,
            resolve: @escaping @Sendable (String) -> String?,
            isQuarantined: @escaping @Sendable (String) -> Bool,
            pypi: @escaping @Sendable (String) async throws -> Data
        ) {
            self.contents = contents
            self.directories = directories
            self.modified = modified
            self.resolve = resolve
            self.isQuarantined = isQuarantined
            self.pypi = pypi
        }

        public static let live = Host(
            contents: { FileManager.default.contents(atPath: $0) },
            directories: { try? FileManager.default.contentsOfDirectory(atPath: $0) },
            modified: { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date },
            resolve: { path in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            },
            isQuarantined: { CLIToolTrust.hasQuarantine(URL(fileURLWithPath: $0)) },
            pypi: { try await PyPIProject.fetch($0) })
    }

    let home: URL
    let host: Host
    let homebrewRoots: [String]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, host: .live)
    }

    public init(home: URL, host: Host, homebrewRoots: [String] = ["/opt/homebrew", "/usr/local"]) {
        self.home = home
        self.host = host
        self.homebrewRoots = homebrewRoots
    }

    /// The first pipx whose default home is `~/Library/Application Support/pipx`
    /// (PX-03 corrected).
    static let applicationSupportSince = "1.15.1"

    // MARK: - Where

    var applicationSupportRoot: String { home.path + "/Library/Application Support/pipx" }
    var legacyRoot: String { home.path + "/.local/pipx" }
    /// pip's and `uv tool`'s place for the script.
    var userBinary: String { home.path + "/.local/bin/pipx" }

    // MARK: - ManagerAdapter

    public func scan() async -> ManagedScan {
        let host = self.host
        let descriptor = self.descriptor
        let candidates = [applicationSupportRoot, legacyRoot]
        let found: [(root: String, items: [ManagedItem], states: [String: String])] = await offCooperativePool {
            candidates.compactMap { root -> (String, [ManagedItem], [String: String])? in
                let venvs = root + "/venvs"
                guard let names = host.directories(venvs) else { return nil }
                var items: [ManagedItem] = []
                var states: [String: String] = [:]
                for name in names.sorted() where !name.hasPrefix(".") && !name.contains(ManagerID.identitySeparator) {
                    let venv = venvs + "/" + name
                    let metadataPath = venv + "/pipx_metadata.json"
                    guard let data = host.contents(metadataPath), let metadata = PipxMetadata.parse(data) else { continue }
                    let distribution = PythonDistribution.read(
                        metadata.package, venv: venv, contents: host.contents, directories: host.directories)
                    let item = Self.item(
                        venv: name, path: venv, root: root, metadata: metadata, distribution: distribution,
                        descriptor: descriptor)
                    items.append(item)
                    let stamp = host.modified(metadataPath).map { String(Int($0.timeIntervalSince1970)) } ?? "-"
                    states[item.identity] = [metadata.packageOrURL, metadata.version ?? "-", metadata.pinned ? "pinned" : "-", stamp]
                        .joined(separator: "|")
                }
                return items.isEmpty ? nil : (root, items, states)
            }
        }
        guard !found.isEmpty else { return .empty }
        let binary = await offCooperativePool { self.locateBinary() }
        var states: [String: String] = [:]
        for part in found { states.merge(part.states) { a, _ in a } }
        return ManagedScan(
            roots: found.map { ManagedRoot(manager: Self.id, path: $0.root, binary: binary) },
            items: found.flatMap(\.items), states: states)
    }

    public func check(_ scan: ManagedScan) async -> [ManagedVerdict] {
        let fetch = host.pypi
        var blocked: [ManagedVerdict] = []
        var asked: [ManagedItem] = []
        for item in scan.items {
            if let reason = Self.notIndexed(item) {
                blocked.append(ManagedVerdict(item: item, vendorWouldUpgrade: nil, blocker: .notIndexed(reason)))
            } else if item.installed == nil {
                blocked.append(ManagedVerdict(item: item, vendorWouldUpgrade: nil))
            } else {
                asked.append(item)
            }
        }
        let answers: [String: ManagedVerdict] = await withTaskGroup(of: ManagedVerdict.self) { group in
            var pending = asked[...]
            var results: [String: ManagedVerdict] = [:]
            func start(_ item: ManagedItem) {
                group.addTask {
                    let python = Self.python(of: item)
                    let blocker: ManagedVerdict.Blocker
                    do {
                        let data = try await fetch(Self.package(of: item))
                        if let document = PyPIProject.parse(data),
                           let newest = PyPIProject.newest(in: document, python: python) {
                            let answered = item.with(latestOverall: newest)
                            return ManagedVerdict(item: answered, vendorWouldUpgrade: Self.wouldUpgrade(answered))
                        }
                        blocker = .channelUnreadable("PyPI lists no release of \(item.name) this venv's Python can install")
                    } catch {
                        blocker = .channelUnreadable("PyPI did not answer for \(item.name): \(error)")
                    }
                    return ManagedVerdict(item: item, vendorWouldUpgrade: nil, blocker: blocker)
                }
            }
            for _ in 0..<UvToolAdapter.parallelFetches { if let next = pending.popFirst() { start(next) } }
            while let verdict = await group.next() {
                results[verdict.item.identity] = verdict
                if let next = pending.popFirst() { start(next) }
            }
            return results
        }
        let blockedByIdentity = Dictionary(blocked.map { ($0.item.identity, $0) }, uniquingKeysWith: { a, _ in a })
        return scan.items.compactMap { answers[$0.identity] ?? blockedByIdentity[$0.identity] }
    }

    /// `pipx upgrade <venv>`, with `PIPX_HOME` when the venv is in the root
    /// this pipx would not pick by itself (or its version is unknown).
    public func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
        guard let binary = root.binary else { return nil }
        var environment: [String: String] = [:]
        if defaultRoot(of: binary.version) != root.path { environment["PIPX_HOME"] = root.path }
        // `~/.local/bin` first: a venv whose backend is uv finds that uv there.
        let command = CLIToolCommand(
            executable: binary.path, arguments: ["upgrade", item.key],
            pathPrefix: home.path + "/.local/bin:" + (binary.path as NSString).deletingLastPathComponent)
        return (command, environment)
    }

    /// `pipx unpin <venv>`: the only pin pipx keeps (PX-15). Copied, never run.
    public func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand? {
        guard let binary = root.binary, item.request?.kind == .exact else { return nil }
        return CLIToolCommand(executable: binary.path, arguments: ["unpin", item.key], pathPrefix: nil)
    }

    public func reread(_ item: ManagedItem) async -> String? {
        let host = self.host
        let path = item.installPath
        return await offCooperativePool {
            host.contents(path + "/pipx_metadata.json").flatMap(PipxMetadata.parse)?.version
        }
    }

    public func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog {
        try await ManagedNotes.fetch(item.notes, force: force)
    }

    // MARK: - The parts

    /// The root a pipx of `version` uses with no `PIPX_HOME`: an existing
    /// `~/.local/pipx` always; else Application Support from 1.15.1. Nil when
    /// the version is unknown.
    func defaultRoot(of version: String?) -> String? {
        if host.directories(legacyRoot) != nil { return legacyRoot }
        guard let version else { return nil }
        return VersionComparator.isNewer(Self.applicationSupportSince, than: version) ? legacyRoot : applicationSupportRoot
    }

    /// Homebrew's pipx first — it is the one the keg rule lets run — then the
    /// one pip or `uv tool` put in `~/.local/bin`. Blocking.
    func locateBinary() -> ManagedRoot.Binary? {
        for prefix in homebrewRoots {
            let link = prefix + "/bin/pipx"
            guard let resolved = host.resolve(link), let version = kegVersion(resolved, prefix: prefix) else { continue }
            let trust: ManagedRoot.Trust = host.isQuarantined(resolved) ? .quarantined : .homebrewKeg
            return ManagedRoot.Binary(path: link, version: version, trust: trust)
        }
        guard let resolved = host.resolve(userBinary) else { return nil }
        // `<venv>/bin/pipx`: the venv's own dist-info says which pipx it is.
        let venv = ((resolved as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let version = PythonDistribution.read("pipx", venv: venv, contents: host.contents, directories: host.directories)?.version
        let trust: ManagedRoot.Trust = host.isQuarantined(resolved) ? .quarantined : .untrusted(nil)
        return ManagedRoot.Binary(path: userBinary, version: version, trust: trust)
    }

    /// `<prefix>/Cellar/pipx/1.8.0_1/bin/pipx` with the keg's
    /// `INSTALL_RECEIPT.json` → "1.8.0" (`NodePrefixes.homebrewKeg`'s rule).
    func kegVersion(_ resolved: String, prefix: String) -> String? {
        let root = URL(fileURLWithPath: prefix).pathComponents
        let components = URL(fileURLWithPath: resolved).pathComponents
        guard components.count >= root.count + 4, Array(components.prefix(root.count)) == root,
              components[root.count] == "Cellar", components[root.count + 1] == "pipx"
        else { return nil }
        let keg = NSString.path(withComponents: Array(components.prefix(root.count + 3)))
        guard host.contents(keg + "/INSTALL_RECEIPT.json") != nil else { return nil }
        var version = components[root.count + 2]
        if let underscore = version.lastIndex(of: "_"), version[version.index(after: underscore)...].allSatisfy(\.isNumber) {
            version = String(version[..<underscore])
        }
        return version
    }

    static func item(
        venv: String, path: String, root: String, metadata: PipxMetadata, distribution: PythonDistribution?,
        descriptor: ManagerDescriptor
    ) -> ManagedItem {
        var facts: [ManagedItem.Fact] = []
        if let python = metadata.python { facts.append(.python(python)) }
        if metadata.packageOrURL != metadata.package { facts.append(.note("installed from \(metadata.packageOrURL)")) }
        var effects: [ManagedItem.Effect] = [.oldRemoved]
        // pipx drops the recorded specifier on upgrade (D7): said before the click.
        if PipxMetadata.carriesSpecifier(metadata.packageOrURL, package: metadata.package) {
            effects.append(.dropsSpecifier(metadata.packageOrURL))
        }
        return ManagedItem(
            descriptor: descriptor, root: root, key: venv, name: venv,
            installPath: path, shape: .package,
            request: metadata.pinned ? ManagedItem.Request(kind: .exact, spelled: metadata.version ?? "pinned") : nil,
            installed: metadata.version ?? distribution?.version,
            backend: metadata.backend,
            notes: distribution.flatMap { UvToolAdapter.notes($0.projectURLs, project: metadata.package) },
            effects: effects, facts: facts)
    }

    static func python(of item: ManagedItem) -> String? {
        item.facts.lazy.compactMap { fact -> String? in
            if case .python(let version) = fact { return version } else { return nil }
        }.first
    }

    /// The PyPI project a venv was installed from: its package, which the
    /// key (the venv's name, maybe with a `--suffix`) may not be.
    static func package(of item: ManagedItem) -> String {
        for fact in item.facts {
            if case .note(let text) = fact, text.hasPrefix("installed from ") {
                let spec = String(text.dropFirst("installed from ".count))
                return PipxMetadata.requirementName(spec) ?? item.name
            }
        }
        return item.name
    }

    /// Why a venv's release cannot be asked of an index: it came from a path,
    /// a URL or a checkout (`package_or_url`, PX-10 — pipx skips these too).
    static func notIndexed(_ item: ManagedItem) -> String? {
        for fact in item.facts {
            if case .note(let text) = fact, text.hasPrefix("installed from "),
               !PipxMetadata.isIndexRequirement(String(text.dropFirst("installed from ".count))) {
                return "\(item.name) was installed from \(text.dropFirst("installed from ".count))"
            }
        }
        return nil
    }

    /// `pipx upgrade` moves an unpinned venv to the newest whatever its
    /// specifier said; a `pipx pin`ned one never.
    static func wouldUpgrade(_ item: ManagedItem) -> Bool? {
        if item.request?.kind == .exact { return false }
        guard let installed = item.installed, let latest = item.latestOverall else { return nil }
        if let a = PythonVersion(latest), let b = PythonVersion(installed) { return a > b }
        return VersionComparator.isNewer(latest, than: installed)
    }
}

/// A venv's `pipx_metadata.json` (= one `pipx list --json` entry; metadata
/// versions 0.2 through 0.12, PX-07/08). pipx 1.18.4 wrote, for `pipx install
/// httpie==3.2.1` on Python 3.12: `main_package.package` "httpie",
/// `package_or_url` "httpie==3.2.1", `package_version` "3.2.1", `pinned`
/// false, `python_version` "Python 3.12.15", `backend` "pip".
struct PipxMetadata: Sendable, Equatable {
    let package: String
    let packageOrURL: String
    let version: String?
    let pinned: Bool
    /// "3.12.15", from "Python 3.12.15".
    let python: String?
    let backend: String?

    static func parse(_ data: Data) -> PipxMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let main = json["main_package"] as? [String: Any],
              let package = main["package"] as? String, !package.isEmpty
        else { return nil }
        let python = (json["python_version"] as? String).map {
            $0.hasPrefix("Python ") ? String($0.dropFirst("Python ".count)) : $0
        }
        return PipxMetadata(
            package: package, packageOrURL: main["package_or_url"] as? String ?? package,
            version: (main["package_version"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            pinned: main["pinned"] as? Bool ?? false, python: python.flatMap { $0.isEmpty ? nil : $0 },
            backend: json["backend"] as? String)
    }

    /// A PEP 508 requirement on an index — `ruff`, `httpie==3.2.1`,
    /// `black[d]>=23` — as opposed to a path, URL or `name @ url`.
    static func isIndexRequirement(_ spec: String) -> Bool {
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.contains(" @ "), !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("."), !trimmed.hasPrefix("~"), !trimmed.hasPrefix("git+")
        else { return false }
        return requirementName(trimmed) != nil
    }

    /// The name a requirement starts with: `httpie==3.2.1` → "httpie".
    static func requirementName(_ spec: String) -> String? {
        let name = spec.trimmingCharacters(in: .whitespaces).prefix { $0.isLetter || $0.isNumber || "._-".contains($0) }
        return name.isEmpty ? nil : String(name)
    }

    /// Whether `package_or_url` says more than the bare name: a specifier or
    /// extras pipx drops on upgrade (PX-14).
    static func carriesSpecifier(_ packageOrURL: String, package: String) -> Bool {
        guard isIndexRequirement(packageOrURL), let name = requirementName(packageOrURL) else { return false }
        let rest = packageOrURL.trimmingCharacters(in: .whitespaces).dropFirst(name.count)
        return !rest.trimmingCharacters(in: .whitespaces).isEmpty
            && PythonDistribution.normalize(name) == PythonDistribution.normalize(package)
    }
}
