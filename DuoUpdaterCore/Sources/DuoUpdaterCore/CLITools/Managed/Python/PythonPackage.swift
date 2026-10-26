import Foundation

/// What a venv says about one installed distribution, read from disk without
/// running Python: the `<name>-<version>.dist-info` directory pip and uv both
/// write (`BubScanner.metadata`'s reading), its `METADATA` headers, and its
/// `direct_url.json` (PEP 610) when it came from somewhere other than an index.
public struct PythonDistribution: Sendable, Equatable {
    public let name: String
    public let version: String
    /// `Project-URL: Label, URL` lines, in order, and `Home-page:`.
    public let projectURLs: [(label: String, url: String)]
    /// The PEP 610 source when not an index: "editable", "vcs", "local path",
    /// "direct URL".
    public let directSource: String?

    public static func == (a: PythonDistribution, b: PythonDistribution) -> Bool {
        a.name == b.name && a.version == b.version && a.directSource == b.directSource
            && a.projectURLs.map(\.label) == b.projectURLs.map(\.label) && a.projectURLs.map(\.url) == b.projectURLs.map(\.url)
    }

    /// PEP 503's normalized form: lower case, runs of `-_.` as one `-`.
    public static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[-_.]+", with: "-", options: .regularExpression)
    }

    /// The distribution `name` in the venv at `venv`: its single dist-info
    /// under `lib/python*/site-packages`. Nil when there is none, or more than
    /// one (an interrupted install: which one Python imports is not ours to
    /// guess). `contents` and `directories` are the adapter's disk seams.
    static func read(
        _ name: String, venv: String, contents: (String) -> Data?, directories: (String) -> [String]?
    ) -> PythonDistribution? {
        let wanted = normalize(name)
        var found: [PythonDistribution] = []
        let lib = venv + "/lib"
        for python in (directories(lib) ?? []).sorted() where python.hasPrefix("python") {
            let sitePackages = lib + "/" + python + "/site-packages"
            for entry in (directories(sitePackages) ?? []).sorted() where entry.hasSuffix(".dist-info") {
                // `black-23.12.1.dist-info`; the name half may be spelled with
                // `_` for `-` (`typing_extensions-4.16.0`).
                let stem = String(entry.dropLast(".dist-info".count))
                guard let dash = stem.lastIndex(of: "-"), normalize(String(stem[..<dash])) == wanted else { continue }
                let distInfo = sitePackages + "/" + entry
                let headers = Self.headers(contents(distInfo + "/METADATA"))
                guard headers.name.map(normalize) ?? wanted == wanted else { continue }
                let version = headers.version ?? String(stem[stem.index(after: dash)...])
                guard !version.isEmpty else { continue }
                found.append(PythonDistribution(
                    name: headers.name ?? name, version: version, projectURLs: headers.urls,
                    directSource: Self.directSource(contents(distInfo + "/direct_url.json"))))
            }
        }
        return found.count == 1 ? found[0] : nil
    }

    /// The core metadata headers, which end at the first blank line.
    static func headers(_ data: Data?) -> (name: String?, version: String?, urls: [(label: String, url: String)]) {
        guard let data else { return (nil, nil, []) }
        var name: String?, version: String?
        var urls: [(String, String)] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { break }
            func value(_ header: String) -> String? {
                guard line.lowercased().hasPrefix(header.lowercased() + ":") else { return nil }
                let rest = line.dropFirst(header.count + 1).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? nil : rest
            }
            if let v = value("Name") { name = v }
            else if let v = value("Version") { version = v }
            else if let v = value("Project-URL") {
                let parts = v.split(separator: ",", maxSplits: 1)
                if parts.count == 2 {
                    urls.append((parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces)))
                }
            } else if let v = value("Home-page") {
                urls.append(("Homepage", v))
            }
        }
        return (name, version, urls)
    }

    /// PEP 610's three shapes, as `BubScanner.directSource` reads them.
    static func directSource(_ data: Data?) -> String? {
        guard let data else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let dir = json["dir_info"] as? [String: Any] {
            return (dir["editable"] as? Bool) == true ? "editable" : "local path"
        }
        if json["vcs_info"] != nil { return "vcs" }
        if json["archive_info"] != nil {
            return (json["url"] as? String)?.hasPrefix("file:") == true ? "local path" : "direct URL"
        }
        return "direct URL"
    }
}

/// Which GitHub repository a Python project's release notes are in, from the
/// project URLs its metadata (or PyPI's `info.project_urls`) names — design
/// §4.2's rule (UV-27): labels tried in the order Changelog, Repository,
/// Source, Source Code, GitHub, Homepage, then any other; the URL must be
/// `github.com/<owner>/<repo>`, and owner or repo must be the project's own
/// name — a sampled project (ansible) points its URLs at another's
/// repository, and a wrong repository's notes are worse than none.
public enum ProjectURLRepo {

    static let labelOrder = ["changelog", "repository", "source", "source code", "github", "homepage"]

    public static func repository(
        _ urls: [(label: String, url: String)], project: String
    ) -> (owner: String, repo: String)? {
        let rank: (String) -> Int = { label in
            labelOrder.firstIndex(of: label.lowercased().trimmingCharacters(in: .whitespaces)) ?? labelOrder.count
        }
        let wanted = squash(project)
        for entry in urls.enumerated().sorted(by: { (rank($0.element.label), $0.offset) < (rank($1.element.label), $1.offset) }) {
            guard let components = URLComponents(string: entry.element.url),
                  let host = components.host?.lowercased(), host == "github.com" || host == "www.github.com"
            else { continue }
            let parts = components.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let owner = parts[0]
            var repo = parts[1]
            if repo.hasSuffix(".git") { repo.removeLast(4) }
            guard !owner.isEmpty, !repo.isEmpty else { continue }
            if squash(repo) == wanted || squash(owner) == wanted { return (owner, repo) }
        }
        return nil
    }

    /// Lower case with every `-_.` gone: `typing_extensions` ≈ `typing-extensions`.
    static func squash(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// PyPI's JSON API for one project (`https://pypi.org/pypi/<name>/json`):
/// the newest release a venv's Python can install, and the project URLs.
///
/// Measured 2026-10-27: the document is every release with its files — 14 KB
/// for cowsay, 922 KB for black, 6.2 MB for ruff (1.1 MB on the wire,
/// gzipped) — served `cache-control: max-age=900` with an ETag, and a
/// conditional GET answers 304. The app's in-memory cache keeps bodies under
/// about 2 MB (`URLSession.updatesCacheCapacity`'s 5 % rule), so most
/// re-checks are a 304; ruff's is fetched whole each time.
public enum PyPIProject {

    public static let base = URL(string: "https://pypi.org/pypi/")!

    public static func url(of project: String) -> URL {
        base.appendingPathComponent(project).appendingPathComponent("json")
    }

    /// The parts of the document a check reads.
    public struct Document: Sendable, Equatable {
        /// `info.version`: the newest final release, as PyPI picks it.
        public let latest: String
        /// `info.requires_python` of that release.
        public let latestRequiresPython: String?
        /// Every release with files, its `requires_python` (the files' own,
        /// which may differ from release to release), its earliest upload, and
        /// whether every file is yanked.
        public let releases: [Release]
        public let projectURLs: [(label: String, url: String)]

        public struct Release: Sendable, Equatable {
            public let version: String
            public let requiresPython: String?
            public let uploaded: Date?
            public let yanked: Bool
        }

        public static func == (a: Document, b: Document) -> Bool {
            a.latest == b.latest && a.latestRequiresPython == b.latestRequiresPython && a.releases == b.releases
                && a.projectURLs.map(\.label) == b.projectURLs.map(\.label) && a.projectURLs.map(\.url) == b.projectURLs.map(\.url)
        }
    }

    public static func parse(_ data: Data) -> Document? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any], let latest = info["version"] as? String, !latest.isEmpty
        else { return nil }
        let urls = ((info["project_urls"] as? [String: Any]) ?? [:])
            .compactMap { key, value in (value as? String).map { (label: key, url: $0) } }
            .sorted { $0.label < $1.label }
        var releases: [Document.Release] = []
        let dates = ISO8601DateFormatter()
        for (version, files) in (json["releases"] as? [String: Any]) ?? [:] {
            guard let files = files as? [[String: Any]], !files.isEmpty else { continue }
            let requires = files.compactMap { $0["requires_python"] as? String }.first { !$0.isEmpty }
            let uploaded = files.compactMap { file -> Date? in
                // "2023-12-22T15:26:25.123456Z": the microseconds dropped, the
                // seconds are all an `exclude-newer` cut-off needs.
                guard let text = file["upload_time_iso_8601"] as? String else { return nil }
                let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
                return dates.date(from: whole)
            }.min()
            let yanked = files.allSatisfy { ($0["yanked"] as? Bool) == true }
            releases.append(Document.Release(version: version, requiresPython: requires, uploaded: uploaded, yanked: yanked))
        }
        releases.sort { $0.version < $1.version }
        return Document(
            latest: latest, latestRequiresPython: (info["requires_python"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            releases: releases, projectURLs: urls)
    }

    /// The newest release a venv on `python` would get: PyPI's `info.version`
    /// when its `requires_python` lets that Python in and it was uploaded by
    /// `uploadedBefore` (uv's `exclude-newer`), else the newest final,
    /// unyanked release that passes both. A `requires_python` this cannot read
    /// lets everything in, as pip does. Nil when nothing passes, or `python`
    /// is unknown and the latest has a requirement.
    public static func newest(in document: Document, python: String?, uploadedBefore: Date? = nil) -> String? {
        let interpreter = python.flatMap(PythonVersion.init)
        func admits(_ requirement: String?) -> Bool? {
            guard let requirement, let specifier = PythonSpecifier(requirement) else { return true }
            guard let interpreter else { return nil }
            return specifier.allows(interpreter)
        }
        let latestRelease = document.releases.first { $0.version == document.latest }
        if admits(document.latestRequiresPython ?? latestRelease?.requiresPython) == true,
           uploadedBefore == nil || (latestRelease?.uploaded).map({ $0 <= uploadedBefore! }) == true {
            return document.latest
        }
        let candidates = document.releases.compactMap { release -> (PythonVersion, Document.Release)? in
            guard !release.yanked, let version = PythonVersion(release.version), !version.isPrerelease else { return nil }
            return (version, release)
        }.sorted { $0.0 > $1.0 }
        for (_, release) in candidates {
            guard admits(release.requiresPython) == true else { continue }
            if let cutoff = uploadedBefore, let uploaded = release.uploaded, uploaded > cutoff { continue }
            return release.version
        }
        return nil
    }

    /// The document, fetched through the app's session and revalidated every
    /// time (`URLRequest.versionFeedCachePolicy`): a cached copy is never the
    /// answer without the server's 304.
    public static func fetch(_ project: String) async throws -> Data {
        var request = URLRequest(url: url(of: project))
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        public var description: String {
            switch self {
            case .http(404): return "PyPI has no such project"
            case .http(let status): return "PyPI answered HTTP \(status)"
            }
        }
    }
}
