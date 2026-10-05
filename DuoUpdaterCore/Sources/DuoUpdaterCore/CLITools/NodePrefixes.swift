import Foundation

/// One node prefix: a directory whose `lib/node_modules` is a global npm root and
/// whose `bin/` holds the links `npm install -g` makes.
public struct NodePrefix: Sendable, Equatable, Codable {

    /// Who laid the prefix out — and so whether its path says which node it is.
    public enum Source: String, Sendable, Codable, CaseIterable {
        /// Homebrew's `/opt/homebrew`, or `/usr/local` (Intel Homebrew, or the
        /// nodejs.org `.pkg`).
        case system
        /// `~/.nvm/versions/node/v<version>`.
        case nvm
        /// fnm's `node-versions/v<version>/installation`.
        case fnm
        /// `~/.local/share/mise/installs/node/<version>`.
        case mise
        /// `~/.asdf/installs/nodejs/<version>`.
        case asdf
        /// `~/.npm-global`, the prefix npm's docs suggest for `npm config set prefix`.
        case npmGlobal
        /// The `prefix=` in `~/.npmrc`.
        case npmrc
        /// bun's global install, `~/.bun/install/global`: its `node_modules` is the
        /// global root and `~/.bun/bin` its links. Not a node prefix at all — bun
        /// installs there, not npm — so discovery never lists it; `BunScanner`
        /// builds it, and its `layoutNodeVersion` is the node its packages are
        /// held against (`BunPackages`).
        case bun
    }

    public let path: String
    public let source: Source
    /// The node version the layout names — the version directory of nvm, fnm,
    /// mise and asdf, or the Homebrew keg `bin/node` links into. nil when the
    /// layout does not say; nothing was run to find it.
    public let layoutNodeVersion: String?

    public init(path: String, source: Source, layoutNodeVersion: String?) {
        self.path = path
        self.source = source
        self.layoutNodeVersion = layoutNodeVersion
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Where the node version managers and npm put global prefixes, read from the
/// layout alone — never from `PATH`, which a GUI process does not have, and never
/// by running anything.
///
/// Shared by Claude Code's npm install detection and the npm packages group, so
/// a manager added here is seen by both. fnm joined on 2026-10-02: this Mac's fnm
/// prefixes (`~/.local/share/fnm/node-versions/{v22.21.1,v24.12.0}/installation`)
/// were invisible to both before.
public struct NodePrefixes: Sendable {

    /// What Claude Code has always scanned, plus fnm.
    public static let claudeCodeSources: [NodePrefix.Source] = [.system, .nvm, .fnm, .npmGlobal]

    let home: URL
    let systemPrefixes: [URL]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemPrefixes: [URL] = [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")]
    ) {
        self.home = home
        self.systemPrefixes = systemPrefixes
    }

    /// Every prefix of `sources`, in that order; within a source, sorted by
    /// directory name. A prefix may be listed even when it holds nothing — the
    /// callers look inside. Not deduplicated: a caller that can meet one prefix
    /// under two names (an `~/.npmrc` prefix that is also `~/.npm-global`) does that.
    public func discover(_ sources: [NodePrefix.Source] = NodePrefix.Source.allCases) -> [NodePrefix] {
        sources.flatMap(prefixes)
    }

    func prefixes(_ source: NodePrefix.Source) -> [NodePrefix] {
        switch source {
        case .system:
            return systemPrefixes.map {
                NodePrefix(path: $0.path, source: .system, layoutNodeVersion: Self.kegVersion(ofNodeIn: $0))
            }
        case .nvm:
            return versionDirectories(home.appendingPathComponent(".nvm/versions/node"), source: .nvm)
        case .fnm:
            // fnm's own default (`directories.rs`, 2026-10-02): `$XDG_DATA_HOME/fnm`,
            // else `~/.fnm` from older releases, else on macOS
            // `~/Library/Application Support/fnm`. All three are looked in, since
            // a machine can keep versions in a root fnm no longer prefers.
            let roots = [".local/share/fnm", ".fnm", "Library/Application Support/fnm"]
            return roots.flatMap {
                versionDirectories(
                    home.appendingPathComponent($0).appendingPathComponent("node-versions"),
                    source: .fnm, subpath: "installation")
            }
        case .mise:
            return versionDirectories(home.appendingPathComponent(".local/share/mise/installs/node"), source: .mise)
        case .asdf:
            return versionDirectories(home.appendingPathComponent(".asdf/installs/nodejs"), source: .asdf)
        case .npmGlobal:
            return [NodePrefix(path: home.appendingPathComponent(".npm-global").path, source: .npmGlobal,
                               layoutNodeVersion: nil)]
        case .npmrc:
            guard let prefix = Self.npmrcPrefix(in: home.appendingPathComponent(".npmrc"), home: home)
            else { return [] }
            return [NodePrefix(path: prefix, source: .npmrc, layoutNodeVersion: nil)]
        case .bun:
            return []
        }
    }

    /// One prefix per version directory under `root`. nvm keeps only real
    /// directories there; mise also keeps alias links (`24` → `24.13.0`,
    /// `latest`), which would list one prefix twice, so links are skipped for
    /// every manager but nvm — whose listing stays exactly what Claude Code read.
    func versionDirectories(_ root: URL, source: NodePrefix.Source, subpath: String? = nil) -> [NodePrefix] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().compactMap { name in
            let directory = root.appendingPathComponent(name)
            if source != .nvm {
                guard !name.hasPrefix("."),
                      (try? fm.destinationOfSymbolicLink(atPath: directory.path)) == nil
                else { return nil }
            }
            let prefix = subpath.map { directory.appendingPathComponent($0) } ?? directory
            return NodePrefix(path: prefix.path, source: source, layoutNodeVersion: Self.versionName(name))
        }
    }

    /// `v24.13.0` and `24.13.0` both name 24.13.0; anything else names nothing.
    static func versionName(_ name: String) -> String? {
        let bare = name.hasPrefix("v") ? String(name.dropFirst()) : name
        return NpmVersion(bare) == nil ? nil : bare
    }

    /// The Homebrew keg a prefix's node is — `<prefix>/Cellar/node/<v>` or
    /// `node@<n>/<v>`, holding brew's `INSTALL_RECEIPT.json` — for a prefix that
    /// is Homebrew's own (`/opt/homebrew`, `/usr/local`); nil otherwise.
    /// `resolvedNode` is `<prefix>/bin/node` with its links followed.
    static func homebrewKeg(
        ofNode resolvedNode: URL, prefix: URL, homebrewRoots: [String] = ["/opt/homebrew", "/usr/local"]
    ) -> String? {
        let root = prefix.resolvingSymlinksInPath().pathComponents
        guard homebrewRoots.contains(where: { URL(fileURLWithPath: $0).pathComponents == root }) else { return nil }
        let components = resolvedNode.pathComponents
        guard components.count == root.count + 5, Array(components.prefix(root.count)) == root,
              components[root.count] == "Cellar",
              components[root.count + 1] == "node" || components[root.count + 1].hasPrefix("node@"),
              components.suffix(2) == ["bin", "node"]
        else { return nil }
        let keg = NSString.path(withComponents: Array(components.prefix(root.count + 3)))
        let receipt = (keg as NSString).appendingPathComponent("INSTALL_RECEIPT.json")
        return FileManager.default.fileExists(atPath: receipt) ? keg : nil
    }

    /// The version of the Homebrew keg `<prefix>/bin/node` links into
    /// (`../Cellar/node/26.10.0_1/bin/node` → `26.10.0`; `node@22` alike), or nil.
    /// The `_1` is Homebrew's rebuild counter, not part of node's version.
    static func kegVersion(ofNodeIn prefix: URL) -> String? {
        let node = prefix.appendingPathComponent("bin/node")
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: node.path)) != nil else { return nil }
        let components = node.resolvingSymlinksInPath().pathComponents
        guard let cellar = components.firstIndex(of: "Cellar"), cellar + 2 < components.count,
              components[cellar + 1] == "node" || components[cellar + 1].hasPrefix("node@")
        else { return nil }
        var version = components[cellar + 2]
        if let underscore = version.lastIndex(of: "_"), version[version.index(after: underscore)...].allSatisfy(\.isNumber) {
            version = String(version[..<underscore])
        }
        return NpmVersion(version) == nil ? nil : version
    }

    /// The `prefix` an npmrc sets, `~` and `${HOME}` expanded, or nil.
    ///
    /// npmrc is ini: `key = value`, `;` and `#` comments, a value optionally
    /// quoted. npm expands `${VAR}` in values; only `HOME` is expanded here — the
    /// app has no shell environment to take any other variable from.
    static func npmrcPrefix(in file: URL, home: URL) -> String? {
        guard let value = npmrcValue("prefix", in: file) else { return nil }
        var path = value.replacingOccurrences(of: "${HOME}", with: home.path)
        if path == "~" {
            path = home.path
        } else if path.hasPrefix("~/") {
            path = home.path + path.dropFirst(1)
        }
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// The last value an npmrc gives `key`, unquoted; nil when the file or the
    /// key is missing.
    static func npmrcValue(_ key: String, in file: URL) -> String? {
        npmrcEntries(in: file).last { $0.key == key }?.value
    }

    /// Every `key = value` line of an npmrc, in order.
    static func npmrcEntries(in file: URL) -> [(key: String, value: String)] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#"),
                  let equals = line.firstIndex(of: "=") else { return nil }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            return key.isEmpty ? nil : (key, value)
        }
    }
}

/// Where pnpm keeps what it installs globally, by its own defaults — read from
/// the layout, like the node prefixes above, never from `PNPM_HOME`, which a
/// GUI process does not have.
public enum GlobalPackageHomes {
    /// pnpm's home on macOS, `~/Library/pnpm`: `globalDir` defaults to
    /// `~/Library/pnpm/global` and `globalBinDir` to `~/Library/pnpm/bin`, or
    /// both under `$XDG_DATA_HOME/pnpm` when that is set (pnpm.io
    /// `settings/other.md`, read 2026-10-06). Measured 2026-10-06: pnpm 10.34.6
    /// put the command in the home itself, 11.28.4 and 12.9.1 in `bin`.
    public static func pnpm(home: URL) -> URL { home.appendingPathComponent("Library/pnpm") }

    /// Every pnpm project under pnpm's home, in every layout — measured in
    /// scratch homes with pnpm 10.34.6, 11.28.4 and 12.9.1 on 2026-10-06:
    /// - pnpm 10 and older: `global/<layout version>` (`global/5`); each
    ///   `node_modules/<name>` links into `.pnpm`.
    /// - pnpm 11 and later: `global/v11/<hash>`, a link to the install group's
    ///   real directory; each `node_modules/<name>` links into the shared
    ///   `store/v11/links`. Updating the package with the same pnpm kept the
    ///   hash and moved the link (`isolated`); pnpm 12 replaced pnpm 11's group
    ///   with one of its own.
    ///
    /// Both can be there after an upgrade: pnpm 11.28.4's `ls -g` in a home with
    /// only a pnpm 10 project says "No global packages found".
    public static func pnpmProjects(in pnpmHome: URL) -> [(project: URL, isolated: Bool)] {
        let global = pnpmHome.appendingPathComponent("global")
        let fm = FileManager.default
        var projects: [(project: URL, isolated: Bool)] = []
        for entry in ((try? fm.contentsOfDirectory(atPath: global.path)) ?? []).sorted() {
            let directory = global.appendingPathComponent(entry)
            if !entry.isEmpty, entry.allSatisfy(\.isNumber) {
                projects.append((directory, false))
            } else if entry.hasPrefix("v"), let layout = Int(entry.dropFirst()), layout >= 11 {
                // Only the hash links are installs, not the group directories
                // they point at (nor `pnpm-workspace.yaml` beside them). Each
                // update measured removed the old group's directory; one no link
                // points at would not be an install anyway.
                for group in ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() {
                    let link = directory.appendingPathComponent(group)
                    guard (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil else { continue }
                    projects.append((link, true))
                }
            }
        }
        return projects
    }
}
