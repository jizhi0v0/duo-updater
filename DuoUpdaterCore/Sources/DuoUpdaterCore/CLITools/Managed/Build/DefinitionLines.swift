import Foundation

/// What pyenv and rbenv share (design §4.7/§4.8): versions built from source
/// into `<root>/versions/<x.y.z>`, one row per minor (D1), the newest known
/// read from the build plugin's definition files on disk — no network, no
/// spawn — and moved by `<manager> install <x.y.z>`, which builds the new
/// patch beside the old.
enum DefinitionLines {

    /// One version name: "3.12.15", "3.13.9t" (pyenv's free-threaded builds
    /// are their own line). Pre-releases, `-dev`, other implementations
    /// (`pypy3.10-7.3.17`, `jruby-9.4.9.0`) and plugin envs are no line.
    struct Patch {
        let version: String
        /// "3.12", "3.13t".
        let line: String
        /// "3.12.15" without the `t`: what versions compare on.
        let release: String

        init?(_ name: String) {
            var text = Substring(name)
            var suffix = ""
            if text.hasSuffix("t") {
                text = text.dropLast()
                suffix = "t"
            }
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
            else { return nil }
            version = name
            line = "\(parts[0]).\(parts[1])" + suffix
            release = String(text)
        }
    }

    /// The newest definition of each line among `names`.
    static func newest(_ names: [String]) -> [String: Patch] {
        var newest: [String: Patch] = [:]
        for name in names {
            guard let patch = Patch(name) else { continue }
            if let known = newest[patch.line], !VersionComparator.isNewer(patch.release, than: known.release) { continue }
            newest[patch.line] = patch
        }
        return newest
    }

    /// One item per line among `names` (the entries of `<root>/versions`), at
    /// its newest patch, with the newest definition as `latestOverall` — read
    /// here, from disk, so the click's command names the same version the
    /// check did. A directory without any of its interpreters (`interpreters`,
    /// below the version's directory) is one a build is still writing:
    /// unreadable.
    static func items(
        names: [String], root: String, title: String, interpreters: [String],
        definitions: [String]?, knownBy: String?, global: String?, descriptor: ManagerDescriptor,
        exists: (String) -> Bool
    ) -> [ManagedItem] {
        var lines: [String: [Patch]] = [:]
        for name in names {
            guard let patch = Patch(name) else { continue }
            lines[patch.line, default: []].append(patch)
        }
        let latest = definitions.map { newest($0) }
        return lines.sorted { VersionComparator.compare($0.key, $1.key) == .orderedDescending }.map { line, patches in
            let ordered = patches.sorted { VersionComparator.compare($0.release, $1.release) == .orderedDescending }
            let newest = ordered[0]
            let directory = root + "/versions/" + newest.version
            let older = ordered.dropFirst().map(\.version)
            var facts: [ManagedItem.Fact] = []
            if !older.isEmpty { facts.append(.alsoInstalled(older)) }
            if let global, patches.contains(where: { $0.version == global }) { facts.append(.defaultAlias(global)) }
            if let knownBy { facts.append(.asKnownBy(knownBy)) }
            return ManagedItem(
                descriptor: descriptor, root: root, key: line, name: "\(title) \(line)", installPath: directory,
                shape: .line, installed: interpreters.contains { exists(directory + "/" + $0) } ? newest.version : nil,
                latestOverall: latest?[line]?.version, alsoInstalled: older,
                effects: [.compilesFromSource, .oldKept(for: nil)], facts: facts)
        }
    }

    /// The scan's answer as verdicts: a newer definition → offered; none of
    /// the line's own → current as far as these definitions know; no line
    /// with any definition (`definitionsFound` false: none were read) →
    /// unreadable.
    static func verdicts(_ items: [ManagedItem], definitionsFound: Bool, plugin: String) -> [ManagedVerdict] {
        items.map { item in
            guard let installed = item.installed else { return ManagedVerdict(item: item, vendorWouldUpgrade: nil) }
            guard definitionsFound else {
                return ManagedVerdict(item: item, vendorWouldUpgrade: nil,
                                      blocker: .channelUnreadable("\(plugin)'s definitions were not found"))
            }
            guard let latest = item.latestOverall, let a = Patch(latest),
                  let b = Patch(installed)
            else { return ManagedVerdict(item: item, vendorWouldUpgrade: false) }
            return ManagedVerdict(item: item, vendorWouldUpgrade: VersionComparator.isNewer(a.release, than: b.release))
        }
    }

    /// `version="2.8.14"` in a checkout's `libexec/<manager>---version`.
    static func scriptVersion(_ data: Data?) -> String? {
        guard let data else { return nil }
        for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("version=\"") else { continue }
            let value = line.dropFirst("version=\"".count).prefix { $0 != "\"" }
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    /// The first line of `<root>/version`: the global selection.
    static func global(_ data: Data?) -> String? {
        guard let data else { return nil }
        let first = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first
        let value = first?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? nil : value
    }

    /// The deadline of a build: python-build took 1:58 for 3.12.15 here.
    static let deadline = ChildProcess.Deadline(terminateAfter: .seconds(20 * 60), killAfter: .seconds(20 * 60 + 30))
}
