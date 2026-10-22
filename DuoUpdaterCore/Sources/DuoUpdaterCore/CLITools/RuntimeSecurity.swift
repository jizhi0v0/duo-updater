import Foundation

/// What the runtimes' own publishers say about an installed Node.js or PHP:
/// newer releases nodejs.org marks as security releases, PHP security
/// advisories whose fix is newer than the install, and the end of a line's
/// support. Shared by the workbench and `duo check`, which only word it.
///
/// Every notice is a statement of what the publisher published, never a verdict
/// that the install is exposed: index.json says a release is a security release,
/// not which installs a fix applies to; an advisory names the version that fixes
/// it, not whether the installed build reaches the vulnerable code. Anything the
/// rules can't read exactly — a version that isn't `x.y.z`, a release index that
/// doesn't list the install, an advisory entry naming several versions — gives
/// no notice rather than a guess.
public enum RuntimeSecurityNotice: Sendable, Equatable {
    /// Releases of the install's major newer than it that nodejs.org's
    /// `index.json` marks `"security": true`; the latest of them, and its date.
    case nodeSecurityReleases(installed: String, count: Int, latest: String, latestDate: String)
    /// nodejs/Release's `schedule.json` puts the major's `end` before today.
    case nodeEndOfLife(major: String, date: String)
    /// php-src advisories whose fix on the install's branch is newer than it;
    /// `fixed` is the highest of those fixes.
    case phpAdvisories(installed: String, fixed: String, advisories: [PHPAdvisoryReference])
    /// php.net's `branches.php` says the branch is `eol`; `date` is its
    /// `security_support_end`.
    case phpEndOfLife(branch: String, date: String)

    /// nodejs.org's announcement of a Node.js release.
    public static func nodeReleaseURL(_ version: String) -> URL {
        URL(string: "https://nodejs.org/en/blog/release/v\(version)/")!
    }

    /// The notice in English, for `duo`.
    public var englishSummary: String {
        switch self {
        case .nodeSecurityReleases(_, let count, let latest, _):
            return "\(count) security release\(count == 1 ? "" : "s") since (latest \(latest))"
                + " — \(Self.nodeReleaseURL(latest).absoluteString)"
        case .nodeEndOfLife(_, let date):
            return "end of life since \(date) (nodejs/Release schedule)"
        case .phpAdvisories(let installed, let fixed, let advisories):
            let ids = advisories.map(\.label).joined(separator: ", ")
            return "\(installed) is older than \(fixed), which fixes \(ids) (php.net/GitHub advisory)"
        case .phpEndOfLife(let branch, let date):
            return "PHP \(branch) reached end of security support on \(date)"
        }
    }
}

/// One php-src advisory a PHP notice names.
public struct PHPAdvisoryReference: Sendable, Equatable {
    /// The CVE, or the GHSA id when GitHub published none.
    public let id: String
    /// As GitHub publishes it (`critical`, `high`…); nil when it has none.
    public let severity: String?
    public let url: URL

    public init(id: String, severity: String?, url: URL) {
        self.id = id
        self.severity = severity
        self.url = url
    }

    /// `CVE-2026-109618 (critical)`.
    public var label: String { severity.map { "\(id) (\($0))" } ?? id }
}

/// A version written exactly `major.minor.patch`, digits only — the only shape
/// the rules compare. `26.12.1`, `v26.12.1`; never `8.5.0RC1`, `HEAD-1a2b3c4`
/// or `8.3.8.`.
struct RuntimeVersionTriple: Comparable, Hashable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        let bare = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var string: String { "\(major).\(minor).\(patch)" }

    static func < (a: Self, b: Self) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

// MARK: - The publishers' data

/// `https://nodejs.org/dist/index.json`: every release, with its `security` flag.
public struct NodeReleaseIndex: Sendable, Equatable {
    struct Release: Sendable, Equatable {
        let version: RuntimeVersionTriple
        let date: String
        let security: Bool
    }

    let releases: [Release]

    /// nil when the body isn't the array of releases; a release whose version
    /// or `security` can't be read is left out.
    public init?(json: Data) {
        guard let array = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        releases = array.compactMap { entry in
            guard let text = entry["version"] as? String, text.hasPrefix("v"),
                  let version = RuntimeVersionTriple(text),
                  let security = entry["security"] as? Bool
            else { return nil }
            return Release(version: version, date: (entry["date"] as? String) ?? "", security: security)
        }
        guard !releases.isEmpty else { return nil }
    }

    /// The releases of `installed`'s major that are newer than it and marked
    /// security releases. Nothing unless the index lists `installed` itself: an
    /// install the index doesn't know (a nightly, a build of its own) can't be
    /// placed in its line.
    func securityNotice(installed: String) -> RuntimeSecurityNotice? {
        guard let x = RuntimeVersionTriple(installed), releases.contains(where: { $0.version == x }) else { return nil }
        let newer = releases.filter { $0.version.major == x.major && $0.version > x && $0.security }
        guard let latest = newer.max(by: { $0.version < $1.version }) else { return nil }
        return .nodeSecurityReleases(
            installed: x.string, count: newer.count, latest: latest.version.string, latestDate: latest.date)
    }
}

/// `https://raw.githubusercontent.com/nodejs/Release/main/schedule.json`: each
/// line's dates, keyed `v24`.
public struct NodeReleaseSchedule: Sendable, Equatable {
    /// `v24` → `2028-04-30`.
    let ends: [String: String]

    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        var ends: [String: String] = [:]
        for (line, value) in object {
            guard let end = (value as? [String: Any])?["end"] as? String, isISODay(end) else { continue }
            ends[line] = end
        }
        guard !ends.isEmpty else { return nil }
        self.ends = ends
    }

    /// The line's end of life when it is before `today`; nothing for a line the
    /// schedule doesn't list.
    func endOfLifeNotice(installed: String, today: String) -> RuntimeSecurityNotice? {
        guard let x = RuntimeVersionTriple(installed), let end = ends["v\(x.major)"], end < today else { return nil }
        return .nodeEndOfLife(major: String(x.major), date: end)
    }
}

/// `https://www.php.net/releases/branches.php`: each branch's support state.
public struct PHPBranches: Sendable, Equatable {
    struct Branch: Sendable, Equatable {
        /// `stable`, `security` or `eol`; nil where php.net gives none.
        let state: String?
        /// `security_support_end`'s day, `2025-12-31`.
        let securitySupportEnd: String?
    }

    /// `8.4` → its entry.
    let branches: [String: Branch]

    public init?(json: Data) {
        guard let array = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        var branches: [String: Branch] = [:]
        for entry in array {
            guard let name = entry["branch"] as? String else { continue }
            let end = (entry["security_support_end"] as? String).map { String($0.prefix(10)) }
            branches[name] = Branch(state: entry["state"] as? String, securitySupportEnd: end.flatMap { isISODay($0) ? $0 : nil })
        }
        guard !branches.isEmpty else { return nil }
        self.branches = branches
    }
}

/// The published advisories of `php/php-src`
/// (`GET /repos/php/php-src/security-advisories`), every page.
public struct PHPAdvisories: Sendable, Equatable {
    struct Advisory: Sendable, Equatable {
        let reference: PHPAdvisoryReference
        /// Each `vulnerabilities[]` entry's `patched_versions`, where it is one
        /// exact version. An entry naming several (`8.1.29, 8.2.20, 8.3.8`) is
        /// left out: which of them is its range's isn't written down.
        let patched: [RuntimeVersionTriple]
    }

    let advisories: [Advisory]

    /// One page body each. nil when any page isn't an array of advisories.
    public init?(pages: [Data]) {
        var advisories: [Advisory] = []
        for page in pages {
            guard let array = try? JSONSerialization.jsonObject(with: page) as? [[String: Any]] else { return nil }
            for entry in array {
                guard (entry["state"] as? String) == "published", entry["withdrawn_at"] is NSNull || entry["withdrawn_at"] == nil,
                      let ghsa = entry["ghsa_id"] as? String,
                      let link = entry["html_url"] as? String, let url = URL(string: link),
                      url.scheme == "https", url.host == "github.com"
                else { continue }
                let cve = (entry["cve_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let severity = (entry["severity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let patched = ((entry["vulnerabilities"] as? [[String: Any]]) ?? []).compactMap { v -> RuntimeVersionTriple? in
                    guard let text = v["patched_versions"] as? String else { return nil }
                    return RuntimeVersionTriple(text.trimmingCharacters(in: .whitespaces))
                }
                advisories.append(Advisory(
                    reference: PHPAdvisoryReference(id: cve ?? ghsa, severity: severity, url: url), patched: patched))
            }
        }
        self.advisories = advisories
    }
}

/// The publishers' data as last fetched, each nil when there is no copy fresh
/// enough to speak from (`RuntimeSecurityFeeds`).
public struct RuntimeSecurityData: Sendable, Equatable {
    public var nodeReleases: NodeReleaseIndex?
    public var nodeSchedule: NodeReleaseSchedule?
    public var phpBranches: PHPBranches?
    public var phpAdvisories: PHPAdvisories?

    public init(
        nodeReleases: NodeReleaseIndex? = nil, nodeSchedule: NodeReleaseSchedule? = nil,
        phpBranches: PHPBranches? = nil, phpAdvisories: PHPAdvisories? = nil
    ) {
        self.nodeReleases = nodeReleases
        self.nodeSchedule = nodeSchedule
        self.phpBranches = phpBranches
        self.phpAdvisories = phpAdvisories
    }
}

// MARK: - The rules

public enum RuntimeSecurityRules {

    /// A Node.js install at exactly `version`: its newer security releases,
    /// then its line's end of life.
    public static func node(version: String, data: RuntimeSecurityData, today: String) -> [RuntimeSecurityNotice] {
        [data.nodeReleases?.securityNotice(installed: version),
         data.nodeSchedule?.endOfLifeNotice(installed: version, today: today)].compactMap { $0 }
    }

    /// A PHP install at exactly `version`: the advisories whose fix on its own
    /// branch is newer, then — for a branch php.net calls `eol` — that. An `eol`
    /// branch can still have one: php.net shipped 8.1.34 for advisories that
    /// list `< 8.1.34`, so an 8.1.33 is told both that 8.1.34 fixes them and
    /// that 8.1 is past support. A branch `branches.php` doesn't list, or a
    /// `branches.php` too old to speak from, gets nothing — whether it is still
    /// supported is exactly what isn't known.
    public static func php(version: String, data: RuntimeSecurityData) -> [RuntimeSecurityNotice] {
        guard let v = RuntimeVersionTriple(version), let branches = data.phpBranches else { return [] }
        let name = "\(v.major).\(v.minor)"
        guard let branch = branches.branches[name] else { return [] }
        var notices = phpAdvisories(v, data.phpAdvisories)
        if branch.state == "eol", let end = branch.securitySupportEnd {
            notices.append(.phpEndOfLife(branch: name, date: end))
        }
        return notices
    }

    private static func phpAdvisories(_ v: RuntimeVersionTriple, _ advisories: PHPAdvisories?) -> [RuntimeSecurityNotice] {
        guard let advisories else { return [] }
        // Only the entry on the install's own branch: one advisory lists a fix
        // per branch, and 8.4.27 is not older than 8.4.27 because 8.5.12 exists.
        var applying: [(reference: PHPAdvisoryReference, fixed: RuntimeVersionTriple)] = []
        for advisory in advisories.advisories {
            let onBranch = advisory.patched.filter { $0.major == v.major && $0.minor == v.minor }
            guard let fixed = onBranch.max(), v < fixed else { continue }
            applying.append((advisory.reference, fixed))
        }
        guard let fixed = applying.map(\.fixed).max() else { return [] }
        let rank = ["critical": 0, "high": 1, "medium": 2, "moderate": 2, "low": 3]
        let references = applying.map(\.reference).sorted {
            let (a, b) = (rank[$0.severity ?? ""] ?? 4, rank[$1.severity ?? ""] ?? 4)
            return a != b ? a < b : $0.id < $1.id
        }
        return [.phpAdvisories(installed: v.string, fixed: fixed.string, advisories: references)]
    }
}

// MARK: - What is installed

/// One Node.js or PHP whose exact version its layout names, in the rules' scope:
/// a homebrew/core `node`, `node@NN`, `php` or `php@X.Y`, or a Node.js version
/// directory of nvm, fnm, mise or asdf. Electron apps, single-executable apps,
/// a node inside an app bundle, a nodejs.org `.pkg` and anything else whose
/// version would have to be guessed are not.
public struct RuntimeInstall: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case node
        case php
    }

    public enum Origin: Sendable, Equatable, Hashable {
        /// `formula` is the rack's name (`node@22`); `keg` the keg `opt/<formula>`
        /// links to, links resolved.
        case homebrew(formula: String, keg: String)
        /// A version manager's prefix (`NodePrefix.path`).
        case manager(NodePrefix.Source, prefix: String)
    }

    public let kind: Kind
    public let version: String
    public let origin: Origin

    public init(kind: Kind, version: String, origin: Origin) {
        self.kind = kind
        self.version = version
        self.origin = origin
    }

    /// The formula's name for a Homebrew install; nil otherwise.
    public var formula: String? {
        if case .homebrew(let formula, _) = origin { return formula }
        return nil
    }

    /// Every one installed: Homebrew's under `brewRoot`, then the managers'.
    public static func installed(home: URL, brewRoot: URL?) -> [RuntimeInstall] {
        (brewRoot.map(homebrew(root:)) ?? []) + nodeManagers(NodePrefixes(home: home))
    }

    /// The prefix of the Homebrew `brew` the app runs (`HomebrewInstaller.brewPath`).
    public static var defaultBrewRoot: URL? {
        HomebrewInstaller.brewPath().map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent() }
    }

    /// The node and php formulae `<root>/opt` links to: in use, from homebrew/core
    /// by the keg's own `INSTALL_RECEIPT.json` (`source.tap`), not built from
    /// HEAD (`source.spec`), at a release version. A third-party tap's `php@8.4`
    /// has the same rack name as homebrew/core's, so the receipt, not the name,
    /// says whose it is.
    static func homebrew(root: URL) -> [RuntimeInstall] {
        let fm = FileManager.default
        let opt = root.appendingPathComponent("opt")
        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        return ((try? fm.contentsOfDirectory(atPath: opt.path)) ?? []).sorted().compactMap { name in
            guard let kind = formulaKind(name) else { return nil }
            let keg = opt.appendingPathComponent(name).resolvingSymlinksInPath()
            let components = keg.pathComponents
            guard components.count == rootComponents.count + 3,
                  Array(components.prefix(rootComponents.count)) == rootComponents,
                  components[rootComponents.count] == "Cellar", components[rootComponents.count + 1] == name,
                  let receipt = try? Data(contentsOf: keg.appendingPathComponent("INSTALL_RECEIPT.json")),
                  let object = try? JSONSerialization.jsonObject(with: receipt) as? [String: Any],
                  let source = object["source"] as? [String: Any],
                  source["tap"] as? String == "homebrew/core",
                  (source["spec"] as? String) != "head"
            else { return nil }
            var version = components[rootComponents.count + 2]
            if let underscore = version.lastIndex(of: "_"),
               !version[version.index(after: underscore)...].isEmpty,
               version[version.index(after: underscore)...].allSatisfy(\.isNumber) {
                version = String(version[..<underscore])
            }
            guard RuntimeVersionTriple(version) != nil else { return nil }
            return RuntimeInstall(kind: kind, version: version, origin: .homebrew(formula: name, keg: keg.path))
        }
    }

    /// `node`, `node@22`, `php`, `php@8.4`; nil for any other name.
    static func formulaKind(_ name: String) -> Kind? {
        func digits(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }
        if name == "node" { return .node }
        if name == "php" { return .php }
        if name.hasPrefix("node@"), digits(name.dropFirst(5)) { return .node }
        if name.hasPrefix("php@") {
            let parts = name.dropFirst(4).split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 2, parts.allSatisfy(digits) { return .php }
        }
        return nil
    }

    /// Each node version directory of nvm, fnm, mise and asdf that holds a
    /// `bin/node`, at the version the directory names.
    static func nodeManagers(_ prefixes: NodePrefixes) -> [RuntimeInstall] {
        prefixes.discover([.nvm, .fnm, .mise, .asdf]).compactMap { prefix in
            guard let version = prefix.layoutNodeVersion, RuntimeVersionTriple(version) != nil,
                  FileManager.default.fileExists(atPath: prefix.url.appendingPathComponent("bin/node").path)
            else { return nil }
            return RuntimeInstall(kind: .node, version: version, origin: .manager(prefix.source, prefix: prefix.path))
        }
    }
}

// MARK: - The report

/// Every install with a notice, as the workbench and `duo check` look them up.
public struct RuntimeSecurityReport: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let install: RuntimeInstall
        public let notices: [RuntimeSecurityNotice]

        public init(install: RuntimeInstall, notices: [RuntimeSecurityNotice]) {
            self.install = install
            self.notices = notices
        }
    }

    /// Only installs with at least one notice, in the order they were found.
    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// The rules over `installs`. `today` is `yyyy-MM-dd`.
    public init(installs: [RuntimeInstall], data: RuntimeSecurityData, today: String) {
        entries = installs.compactMap { install in
            let notices = switch install.kind {
            case .node: RuntimeSecurityRules.node(version: install.version, data: data, today: today)
            case .php: RuntimeSecurityRules.php(version: install.version, data: data)
            }
            return notices.isEmpty ? nil : Entry(install: install, notices: notices)
        }
    }

    /// A Homebrew formula's notices, by the name `brew leaves` prints for a
    /// homebrew/core formula (bare: `node`, `php@8.4`).
    public func notices(forFormula name: String) -> [RuntimeSecurityNotice] {
        entries.first { $0.install.formula == name }?.notices ?? []
    }

    /// The notices of the node an npm prefix runs: a version manager's prefix
    /// by its path, Homebrew's by the keg its `bin/node` resolves into.
    public func nodeNotices(forPrefix prefix: NodePrefix, homebrewKeg: String?) -> [RuntimeSecurityNotice] {
        nodeEntry(forPrefix: prefix, homebrewKeg: homebrewKeg)?.notices ?? []
    }

    /// The node install an npm prefix runs, with its notices; nil without any.
    public func nodeEntry(forPrefix prefix: NodePrefix, homebrewKeg: String?) -> Entry? {
        entries.first { entry in
            guard entry.install.kind == .node else { return false }
            switch entry.install.origin {
            case .manager(_, let path): return path == prefix.path
            case .homebrew(_, let keg):
                guard let homebrewKeg else { return false }
                return URL(fileURLWithPath: homebrewKeg).resolvingSymlinksInPath().path == keg
            }
        }
    }

    /// `duo check`'s lines, one per install: `nvm node 24.13.0: …`, `brew php
    /// 8.4.26: …`, each advisory's link on a detail line under a PHP one, and
    /// under an nvm or fnm node the command that installs its latest security
    /// release (`NodeUpgradeCommand`). `packagesByPrefix`: the global packages'
    /// names under each prefix path, for what fnm leaves behind.
    public func englishLines(packagesByPrefix: [String: [String]] = [:]) -> [String] {
        entries.flatMap { entry -> [String] in
            let install = entry.install
            let label: String
            switch install.origin {
            case .homebrew(let formula, _): label = "brew \(formula) \(install.version)"
            case .manager(let source, _): label = "\(source.rawValue) node \(install.version)"
            }
            var lines = ["  \(label): " + entry.notices.map(\.englishSummary).joined(separator: "; ")]
            for notice in entry.notices {
                guard case .phpAdvisories(_, _, let advisories) = notice else { continue }
                lines += advisories.map { "      \($0.id): \($0.url.absoluteString)" }
            }
            if case .manager(_, let prefix) = install.origin,
               let upgrade = NodeUpgradeCommand(
                   entry, packages: packagesByPrefix[URL(fileURLWithPath: prefix).standardizedFileURL.path] ?? []) {
                lines.append("      to update it yourself: \(upgrade.command)")
                if let left = upgrade.englishPackagesLeftBehind { lines.append("      \(left)") }
                if let replaced = upgrade.englishReplacedDefault { lines.append("      \(replaced)") }
            }
            return lines
        }
    }
}

/// The command that installs a version manager's node's latest security
/// release, for the user to copy and run — never run here. nvm and fnm keep
/// each version in a directory of its own, so there is no upgrade in place:
/// the newer version is installed beside the old one (which stays), and the
/// global packages moved where the manager can.
///
/// - nvm (README, "Migrating Global Packages While Installing"):
///   `nvm install <latest> --reinstall-packages-from=<installed>`, then
///   `nvm alias default <latest>` only when `$NVM_DIR/alias/default` is on
///   the installed version's line and won't follow the install by itself:
///   the installed version exactly, or an `lts/…` alias that resolves to its
///   major. `alias/lts/*` holds `lts/<codename>`, whose file holds a version,
///   and nvm rewrites those to the newest *published* release whenever it
///   lists the remote versions — which an online `nvm install` does — so after
///   installing the security release such a default can name a release that
///   isn't installed, and the moved packages fall off `PATH`. The replaced
///   alias is said (`replacedNvmDefault`). A partial version (`24`), `node`
///   or `stable` resolves against the *installed* versions and follows on its
///   own; one on another line, `system`, or another exact version is the
///   user's choice and is left alone.
/// - fnm (`docs/commands.md`): `fnm install <latest>`, then `fnm default
///   <latest>` when fnm's `aliases/default` link (`alias.rs`: a link to the
///   version's installation directory) points at the installed version. fnm
///   documents no way to move global packages, so they are named instead.
/// - mise, asdf: their docs give no command that installs a version and moves
///   the global packages from another, so none is offered.
///
/// Only for newer security releases of the same major: an end of life alone
/// gets none, since its way out is another major.
public struct NodeUpgradeCommand: Sendable, Equatable {
    public let command: String
    /// The installed and latest versions.
    public let installed: String
    public let latest: String
    /// Global packages under the installed version the command doesn't move
    /// (fnm's); empty for nvm, which moves them.
    public let packagesLeftBehind: [String]
    /// nvm's default before the command, when it was an alias rather than an
    /// exact version (`lts/*`), and the command sets it to `latest`.
    public let replacedNvmDefault: String?

    /// nil unless the install is an nvm or fnm node with a
    /// `.nodeSecurityReleases` notice. `packages`: the global packages' names
    /// under its prefix.
    public init?(_ entry: RuntimeSecurityReport.Entry, packages: [String]) {
        guard entry.install.kind == .node, case .manager(let source, let prefix) = entry.install.origin,
              let latest = entry.notices.lazy.compactMap({ notice -> String? in
                  if case .nodeSecurityReleases(_, _, let latest, _) = notice { return latest }
                  return nil
              }).first
        else { return nil }
        let installed = entry.install.version
        let prefixURL = URL(fileURLWithPath: prefix)
        switch source {
        case .nvm:
            // `<NVM_DIR>/versions/node/v<installed>`.
            let nvmDir = prefixURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            var command = "nvm install \(latest) --reinstall-packages-from=\(installed)"
            var replaced: String?
            switch Self.nvmDefault(in: nvmDir, installed: installed) {
            case .installed:
                command += " && nvm alias default \(latest)"
            case .ltsOnLine(let alias):
                command += " && nvm alias default \(latest)"
                replaced = alias
            case .leftAlone, .none:
                break
            }
            self.init(command: command, installed: installed, latest: latest, packagesLeftBehind: [],
                      replacedNvmDefault: replaced)
        case .fnm:
            // `<fnm dir>/node-versions/v<installed>/installation`.
            let fnmDir = prefixURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            var command = "fnm install \(latest)"
            if Self.fnmDefault(in: fnmDir, isPrefix: prefixURL) { command += " && fnm default \(latest)" }
            self.init(command: command, installed: installed, latest: latest, packagesLeftBehind: packages,
                      replacedNvmDefault: nil)
        default:
            return nil
        }
    }

    init(command: String, installed: String, latest: String, packagesLeftBehind: [String], replacedNvmDefault: String?) {
        self.command = command
        self.installed = installed
        self.latest = latest
        self.packagesLeftBehind = packagesLeftBehind
        self.replacedNvmDefault = replacedNvmDefault
    }

    /// `duo`'s sentence for `packagesLeftBehind`; nil when there are none.
    /// "Include": the list is the packages the app lists — those with a
    /// command, and Claude Code — not every package in the prefix.
    public var englishPackagesLeftBehind: String? {
        guard !packagesLeftBehind.isEmpty else { return nil }
        return "Global packages that stay with \(installed) include: \(packagesLeftBehind.joined(separator: ", ")). "
            + "Reinstall them under \(latest) with npm install -g."
    }

    /// `duo`'s sentence for `replacedNvmDefault`; nil when nothing was replaced.
    public var englishReplacedDefault: String? {
        replacedNvmDefault.map { "nvm's default was \($0); this sets it to \(latest)." }
    }

    /// What `<nvmDir>/alias/default` holds, as the command treats it.
    enum NvmDefault: Equatable {
        /// The installed version, `24.13.0` or `v24.13.0`.
        case installed
        /// An `lts/…` alias, as written, that resolves to the installed
        /// version's major.
        case ltsOnLine(String)
        /// Anything the command leaves as it is: another exact version, an
        /// `lts/…` on another major, a partial version, `node`, `stable`,
        /// `system`.
        case leftAlone
    }

    /// nil when there is no default (or it can't be read): none is set then.
    static func nvmDefault(in nvmDir: URL, installed version: String) -> NvmDefault? {
        guard let alias = readAlias("default", in: nvmDir) else { return nil }
        if alias == version || alias == "v" + version { return .installed }
        guard alias.hasPrefix("lts/"), let installed = RuntimeVersionTriple(version),
              let resolved = resolveLTS(alias, in: nvmDir), resolved.major == installed.major
        else { return .leftAlone }
        return .ltsOnLine(alias)
    }

    /// `lts/*` → `lts/krypton` → `v24.13.0`, through `<nvmDir>/alias/`; nil
    /// when the chain doesn't end in an exact version within a few steps.
    /// `lts/-N` has no file: nvm (`nvm_normalize_lts`) takes the (N+1)th name
    /// from the end of `ls alias/lts` — `lts/-1` is the line before the newest
    /// — and refuses one that lands on `*`.
    static func resolveLTS(_ alias: String, in nvmDir: URL) -> RuntimeVersionTriple? {
        var name = alias
        for _ in 0..<4 {
            if let back = Self.ltsOffset(name) {
                let names = ((try? FileManager.default.contentsOfDirectory(
                    atPath: nvmDir.appendingPathComponent("alias/lts").path)) ?? []).sorted()
                guard back < names.count, names[names.count - 1 - back] != "*" else { return nil }
                name = "lts/" + names[names.count - 1 - back]
            }
            guard let next = readAlias(name, in: nvmDir) else { return nil }
            if let version = RuntimeVersionTriple(next) { return version }
            guard next.hasPrefix("lts/") else { return nil }
            name = next
        }
        return nil
    }

    /// `lts/-1` → 1, as nvm accepts it (`lts/-[1-9][0-9]*`); nil otherwise.
    static func ltsOffset(_ name: String) -> Int? {
        guard name.hasPrefix("lts/-") else { return nil }
        let digits = name.dropFirst(5)
        guard let first = digits.first, first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    private static func readAlias(_ name: String, in nvmDir: URL) -> String? {
        guard let text = try? String(contentsOf: nvmDir.appendingPathComponent("alias/\(name)"), encoding: .utf8)
        else { return nil }
        let alias = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return alias.isEmpty ? nil : alias
    }

    /// Whether `<fnmDir>/aliases/default` links to `prefix`.
    static func fnmDefault(in fnmDir: URL, isPrefix prefix: URL) -> Bool {
        let link = fnmDir.appendingPathComponent("aliases/default")
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        let target = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent())
        return target.standardizedFileURL.resolvingSymlinksInPath().path
            == prefix.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// `yyyy-MM-dd`.
func isISODay(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    return parts.count == 3 && parts.map(\.count) == [4, 2, 2]
        && parts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
}

extension CLIToolStatus {
    /// The global npm package this install is, and the node prefix it is
    /// installed under, standardized: an npm package's row, or Claude Code's
    /// npm install, which has a row of its own (`NpmScanner.excluded`) and is
    /// named by its npm package, the name `npm install -g` takes. nil for
    /// anything else. What a `NodeUpgradeCommand` leaves behind is listed from it.
    public var npmPackage: (name: String, prefix: String)? {
        switch detail {
        case .npm(let package):
            return (package.install.name, URL(fileURLWithPath: package.install.prefix.path).standardizedFileURL.path)
        case .claudeCode(let claudeCode):
            guard claudeCode.install.method == .npm, let prefix = claudeCode.install.nodePrefix else { return nil }
            return ("@anthropic-ai/claude-code", URL(fileURLWithPath: prefix).standardizedFileURL.path)
        default:
            return nil
        }
    }
}
