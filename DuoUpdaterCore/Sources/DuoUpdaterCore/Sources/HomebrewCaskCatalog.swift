import Foundation

/// A cask's `depends_on.macos` constraint, as the JSON API renders it.
///
/// Three shapes: `{">=": ["27"]}`, `{"==": ["11",…,"26"]}` (a membership test with
/// gaps, not a range) and `<=`, which the catalog does not currently use at all.
/// A present-but-empty `{}` means no constraint and parses to `nil` — that is the
/// majority. Values are bare numeric majors.
///
/// Counts, the `<=` caveat and the rest of the 2026-09-15 measurement:
/// `docs/engine-notes/homebrew-cask-catalog.md` §1.
public struct CaskMacOSRequirement: Sendable, Equatable {
    public enum Comparison: String, Sendable, Equatable {
        case atLeast = ">="
        case atMost = "<="
        case exactly = "=="
    }

    public let comparison: Comparison
    /// The declared versions, verbatim and in the order the API listed them.
    public let versions: [String]

    public init(comparison: Comparison, versions: [String]) {
        self.comparison = comparison
        self.versions = versions
    }

    /// Whether a host running `hostOSVersion` (e.g. `"27.0.1"`) may install this
    /// cask. Takes the host as an argument rather than reading `ProcessInfo`, so
    /// the rule is a pure function and its test does not measure whatever Mac it
    /// runs on.
    ///
    /// The declared side is a *major* (`"26"`), while the host side is a full
    /// triple (`"26.1.2"`). `>=` is a floor, and goes through the shared floor
    /// predicate (see the branch). `==` and `<=` truncate the host to as many
    /// components as the declaration carries before comparing: comparing the
    /// untruncated host would make `== 26` false on every macOS 26 point release,
    /// which is the opposite of what brew means by it.
    ///
    /// Fails **open** — an unparseable or empty declaration admits everyone.
    /// Getting this wrong in the other direction would hide a cask from the index
    /// entirely, which is the bug this type exists to fix.
    public func admits(_ hostOSVersion: String) -> Bool {
        let declared = versions.filter { $0.contains(where: \.isNumber) }
        guard !declared.isEmpty else { return true }
        guard Self.leadingNumber(hostOSVersion) != nil else { return true }

        switch comparison {
        case .exactly:
            // Not a floor, so not `canRun`: it is membership of the host's major in
            // a list with gaps, which a minimum cannot express. Same for `<=`.
            return declared.contains { Self.truncated(hostOSVersion, toComponentsOf: $0) == $0 }
        case .atLeast:
            // A floor, so it asks the same predicate install-time gate 6 asks
            // (`HostOS` lists the sites and says why they must not disagree).
            // Padding the declaration with zeros is what truncating the host used
            // to approximate. Compared over a grid of hosts and declarations when
            // this switched, they differed in two shapes, both now decided the
            // way gate 6 decides them:
            //  - a declaration with a non-`.` separator (`"13-1"`): truncation
            //    split on `.` only, the comparator also on `- _ + space ( )`, so
            //    13.2.0 was refused. It is admitted now.
            //  - a host with trailing text (`"27.0.0-beta"` vs `"27"`): refused
            //    now, admitted before. Unreachable — the host is always
            //    `HostOS.numericVersion()` — so deliberately not guarded.
            // The fail-open guards above stay: `canRun` alone fails closed on a
            // host with no number, which would hide the cask.
            //
            // A `>=` list is one element in every measured case; "at least the
            // lowest of them" is the reading that keeps a hypothetical multi-entry
            // list from excluding a host each single element would admit.
            return declared.contains {
                SignatureVerifier.canRun(minimumSystemVersion: $0, on: hostOSVersion)
            }
        case .atMost:
            return declared.contains {
                VersionComparator.compare(Self.truncated(hostOSVersion, toComponentsOf: $0), $0)
                    != .orderedDescending
            }
        }
    }

    /// `("26.1.2", toComponentsOf: "26")` → `"26"`; `("10.15.7", "10.15")` → `"10.15"`.
    private static func truncated(_ version: String, toComponentsOf declared: String) -> String {
        let want = declared.split(separator: ".").count
        let have = version.split(separator: ".")
        guard have.count > want else { return version }
        return have.prefix(want).joined(separator: ".")
    }

    private static func leadingNumber(_ version: String) -> Int? {
        Int(version.prefix { $0.isNumber })
    }

    /// Parse the `depends_on` object of one cask. `nil` when there is no `macos`
    /// key, when it renders as `{}` (the majority — see the type's doc comment),
    /// or when its shape is not one we recognise.
    /// One requirement per cask, so a hypothetical `{">=": ["13"], "<=": ["15"]}`
    /// is refused outright (→ `nil`, i.e. admits everyone) instead of silently
    /// keeping half of it. Not merely a style choice: iterating the dictionary and
    /// returning the first hit would make *which* half survives depend on Swift's
    /// per-process hash seed, so the same catalog would index differently between
    /// launches. No such cask exists today (measured: the catalog has no `<=` at
    /// all) — this is about the shape being defined, not about a live case.
    static func parse(dependsOn: Any?) -> CaskMacOSRequirement? {
        guard let dependsOn = dependsOn as? [String: Any],
              let macos = dependsOn["macos"] as? [String: Any] else { return nil }
        var found: CaskMacOSRequirement?
        for (op, value) in macos {
            guard let comparison = Comparison(rawValue: op) else { continue }
            let versions: [String]
            if let many = value as? [Any] {
                versions = many.compactMap { $0 as? String }
            } else if let one = value as? String {
                versions = [one]
            } else {
                continue
            }
            guard !versions.isEmpty else { continue }
            guard found == nil else { return nil }
            found = CaskMacOSRequirement(comparison: comparison, versions: versions)
        }
        return found
    }
}

/// How an update to one cask can be applied from here.
public enum CaskInstallKind: Sendable, Equatable {
    /// brew installs it unattended: a dragged `.app`, or an installer `script`
    /// brew runs itself.
    case brew
    /// We download the official package and hand it to the system installer —
    /// the cask has no route brew can run for us unattended (see
    /// `HomebrewCaskCatalog.installKind`).
    case package
    /// Neither: the installer needs a person and the download holds no package
    /// `PackageInstaller` can reach. Offered as an update, never installed.
    case detectionOnly
}

/// One cask's relevant fields.
public struct CaskEntry: Sendable {
    public let token: String
    public let version: String
    public let url: URL?
    public let autoUpdates: Bool
    /// How an update to this cask can be applied from here (see `CaskInstallKind`).
    public let installKind: CaskInstallKind
    /// The cask's `depends_on.macos`, when it states one. `nil` means "runs
    /// anywhere", which is what the catalog says for the large majority.
    public let macOS: CaskMacOSRequirement?

    public init(
        token: String,
        version: String,
        url: URL?,
        autoUpdates: Bool,
        installKind: CaskInstallKind,
        macOS: CaskMacOSRequirement? = nil
    ) {
        self.token = token
        self.version = version
        self.url = url
        self.autoUpdates = autoUpdates
        self.installKind = installKind
        self.macOS = macOS
    }

    /// Whether this cask's own constraint admits the given host. No constraint
    /// admits everyone.
    func admits(_ hostOSVersion: String) -> Bool {
        macOS?.admits(hostOSVersion) ?? true
    }

    /// Which of several casks claiming one key this Mac should be offered:
    /// catalog order decides, but only among the casks it can actually install —
    /// the first admitted entry, else the first entry, so a host outside every
    /// cask's window still gets an answer instead of a hole.
    ///
    /// The **only** copy of that rule. It used to exist twice, once here as a
    /// derived `CaskIndex.byAppFilename` / `byBundleID` and once inside
    /// `HomebrewCaskSource`, and the index copy had no production consumer at all
    /// — deleting it changed nothing a user could see, which also meant every
    /// mutation aimed at it was evidence about dead code.
    static func preferred(among entries: [CaskEntry], hostOSVersion: String) -> CaskEntry? {
        entries.first { $0.admits(hostOSVersion) } ?? entries.first
    }
}

/// Two lookup tables over the cask catalog: by `.app` filename (the primary,
/// most reliable key) and by bundle identifier (a fallback for casks that
/// install via `pkg` and so declare no `.app` artifact, e.g. AweSun).
///
/// Both keep **every** cask claiming a key, in catalog order. Picking one is the
/// caller's job (`HomebrewCaskSource`), because the pick needs two facts the
/// catalog does not have: the host's macOS version and which cask the Caskroom
/// actually holds. Indexing is therefore host-independent — a pure function of
/// the catalog bytes.
struct CaskIndex: Sendable {
    /// Every cask installing each `.app` filename, in catalog order.
    let allByAppFilename: [String: [CaskEntry]]
    /// Every cask declaring each bundle id, in catalog order.
    let allByBundleID: [String: [CaskEntry]]
}

/// Loads the full Homebrew Cask catalog from formulae.brew.sh once and indexes
/// it by the `.app` filename each cask installs (e.g. "TablePlus.app"), plus a
/// bundle-identifier fallback drawn from each cask's `uninstall: quit:` field.
///
/// The catalog is ~2 MB (measured at 2007 KB on 2026-09-05; see `load`), so we
/// fetch and parse it a single time and reuse the index for every app in a
/// check run.
public actor HomebrewCaskCatalog {
    public static let shared = HomebrewCaskCatalog()

    private var index: CaskIndex?
    private var indexLoadedAt: Date?
    private var loadTask: Task<CaskIndex, Error>?
    /// A failed refresh should not make every subsequent lookup immediately retry
    /// the same ~2 MB request. While this is in the future, a stale index remains
    /// usable and `isExpired` treats it as fresh enough to serve.
    private var retryRefreshAfter: Date?

    /// How long a loaded index is reused before being refetched.
    ///
    /// The index used to be memoized for the life of the process. That's fine for
    /// a CLI and wrong for a menu-bar app that runs for weeks: every Homebrew-
    /// sourced app stayed pinned to whatever the catalog said the day the app
    /// launched, reporting "up to date" forever with no error — the same silent
    /// shape as a stale HTTP cache (see ``URLRequest/versionFeedCachePolicy``),
    /// and immune to that fix because the in-memory index short-circuits the
    /// request entirely.
    ///
    /// Six hours, not minutes: the refetch is the full ~2 MB whenever the catalog
    /// actually changed (which is most of the time — brew publishes constantly),
    /// so this trades a few hours of staleness for bounded background traffic.
    /// Only paid on machines that have casks installed at all; `HomebrewCaskSource`
    /// declines before touching the catalog when the Caskroom is empty.
    static let indexTTL: TimeInterval = 6 * 60 * 60
    static let failedRefreshRetryDelay: TimeInterval = 5 * 60

    /// Test seam: an index seeded via `init(testIndex:)` never expires, so
    /// offline tests don't reach the network partway through.
    private var indexNeverExpires = false

    private let session: URLSession
    public init(session: URLSession = .updates) {
        self.session = session
    }

    /// Test seam: seed a fixed index so source-level tests run offline instead of
    /// fetching the ~2 MB live catalog.
    init(testIndex: CaskIndex) {
        self.session = .shared
        self.index = testIndex
        self.indexNeverExpires = true
    }

    /// Test seam for an expired, previously-good index plus a controlled session.
    init(session: URLSession, staleTestIndex: CaskIndex, loadedAt: Date) {
        self.session = session
        self.index = staleTestIndex
        self.indexLoadedAt = loadedAt
    }

    /// Every cask installing this `.app` filename, in catalog order. There is no
    /// single-answer sibling on purpose: choosing needs the host's macOS version
    /// and the Caskroom's contents, neither of which the catalog has, so the pick
    /// lives at the one call site that holds both (`HomebrewCaskSource`, via
    /// `CaskEntry.preferred(among:hostOSVersion:)`).
    public func entries(forAppFilename filename: String) async throws -> [CaskEntry] {
        try await loadedIndex().allByAppFilename[filename.lowercased()] ?? []
    }

    /// Every cask declaring this bundle id, in catalog order — the fallback key
    /// for casks with no `.app` artifact, and the one a caller uses to pick among
    /// a bundle's channel casks (`utm` / `utm@beta`).
    public func entries(forBundleID bundleID: String) async throws -> [CaskEntry] {
        try await loadedIndex().allByBundleID[bundleID.lowercased()] ?? []
    }

    private func loadedIndex() async throws -> CaskIndex {
        if let index, !isExpired { return index }
        // Coalesce concurrent callers onto a single in-flight load.
        if let loadTask { return try await resolve(loadTask) }

        let task = Task { try await Self.fetchAndIndex(session: session) }
        loadTask = task
        return try await resolve(task)
    }

    /// Resolve the shared refresh for both its creator and every coalesced caller.
    /// Keeping success/failure handling here is important: callers that merely join
    /// the task must receive the same stale-on-error fallback as the creator.
    private func resolve(_ task: Task<CaskIndex, Error>) async throws -> CaskIndex {
        do {
            let idx = try await task.value
            if loadTask == task {
                index = idx
                indexLoadedAt = Date()
                retryRefreshAfter = nil
                loadTask = nil
            }
            return idx
        } catch {
            if loadTask == task {
                loadTask = nil
                retryRefreshAfter = Date().addingTimeInterval(Self.failedRefreshRetryDelay)
            }
            // A refetch that fails keeps serving the last good index rather than
            // dropping every Homebrew row to "unknown" on one bad network moment.
            if let index { return index }
            throw error
        }
    }

    private var isExpired: Bool {
        guard !indexNeverExpires else { return false }
        if let retryRefreshAfter, Date() < retryRefreshAfter { return false }
        guard let indexLoadedAt else { return true }
        return Date().timeIntervalSince(indexLoadedAt) >= Self.indexTTL
    }

    private static func fetchAndIndex(session: URLSession) async throws -> CaskIndex {
        let url = URL(string: "https://formulae.brew.sh/api/cask.json")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")

        // `.catalog`, not `.versionCheck`: this one request is the whole cask
        // index — measured at 2.1 MB, i.e. larger than every version feed in a
        // full sweep put together. Filed under the same purpose as a 4 KB appcast
        // it would hide inside a bucket it single-handedly dominates.
        // Attributed to no app, deliberately. This runs inside whichever app's
        // check happened to find the catalog cold, and filing 2.1 MB against
        // that app would read as "Anki cost 2.1 MB" when the next fifty apps
        // ride on the same copy. The same reasoning as the self-update: a shared
        // fetch belongs to nobody, and nobody is an answer the column can give.
        let (data, response) = try await RequestAttribution.withApp(nil) {
            try await session.versionFeedData(
                for: request, label: "Homebrew cask catalog", purpose: .catalog)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CaskError.badStatus(http.statusCode)
        }

        return try index(fromCatalogJSON: data)
    }

    /// The whole indexing rule, as a pure function of the catalog bytes — so it
    /// can be replayed against a fixture built from real response bodies, with no
    /// network and nothing read off the machine running it.
    static func index(fromCatalogJSON data: Data) throws -> CaskIndex {
        // artifacts is a heterogeneous array, so walk the JSON manually rather
        // than fighting Codable over its shape.
        guard let casks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CaskError.malformed
        }

        var byApp: [String: [CaskEntry]] = [:]
        var allByBundle: [String: [CaskEntry]] = [:]
        for cask in casks {
            guard
                let token = cask["token"] as? String,
                let version = cask["version"] as? String,
                version != "latest"
            else { continue }

            let entry = CaskEntry(
                token: token,
                version: version,
                url: (cask["url"] as? String).flatMap { URL(string: $0) },
                autoUpdates: (cask["auto_updates"] as? Bool) ?? false,
                installKind: installKind(
                    artifacts: cask["artifacts"], url: cask["url"] as? String),
                macOS: CaskMacOSRequirement.parse(dependsOn: cask["depends_on"])
            )

            // Both keys keep every declaring cask, in catalog order. Keeping the
            // alternatives instead of dropping all but the first is what lets
            // `HomebrewCaskSource` resolve the cask that is actually *installed*,
            // and the one this Mac can run, rather than whichever token sorted
            // first (the `onyx` / `onyx@beta` split, issue #638):
            // `docs/engine-notes/homebrew-cask-catalog.md` §2.
            for appName in appFilenames(in: cask["artifacts"]) {
                byApp[appName.lowercased(), default: []].append(entry)
            }
            for bundleID in bundleIDs(in: cask["artifacts"]) {
                allByBundle[bundleID.lowercased(), default: []].append(entry)
            }
        }
        return CaskIndex(allByAppFilename: byApp, allByBundleID: allByBundle)
    }

    /// Extract the `.app` filenames from a cask's `artifacts` array. Each app
    /// artifact looks like `{"app": ["Foo.app", {"target": "..."}]}`.
    private static func appFilenames(in artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [Any] else { return [] }
        var names: [String] = []
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any],
                  let apps = dict["app"] as? [Any] else { continue }
            for app in apps {
                if let name = app as? String, name.hasSuffix(".app") {
                    names.append(name)
                }
            }
        }
        return names
    }

    /// For what brew cannot install for us unattended — a `pkg` artifact (brew
    /// runs `/usr/sbin/installer` under `/usr/bin/sudo`), an `installer` that is
    /// `manual` (brew only prints "open …", and `brew upgrade` skips such casks
    /// outright) or a `script` with `sudo: true` — `.package` only when
    /// `PackageInstaller` can reach a package in the download, else
    /// `.detectionOnly`. Everything else, `.brew`. The sudo there has no terminal
    /// to ask on, gets `-A` only when `SUDO_ASKPASS` is set, and finds no cached
    /// credential, because `brew.sh` runs `sudo --reset-timestamp` first. Read in
    /// brew 7.0.6: `cask/artifact/pkg.rb`, `cask/artifact/installer.rb`,
    /// `cask/upgrade.rb`, `system_command.rb`, `brew.sh`.
    ///
    /// Unless Touch ID is on for sudo (`pam_tid` in `/etc/pam.d/sudo_local`;
    /// the template macOS ships has it commented out). Then the sudo does not
    /// fail: it puts up a Touch ID prompt for a bare `sudo`, with nothing saying
    /// which app or update asked. Seen on 2026-09-26: a `brew uninstall --cask`
    /// run with no terminal went through once the prompt was approved. Still not
    /// a route for these: most Macs fail after the download, the rest get an
    /// unexplained root prompt in the middle of Update All, and brew's route
    /// skips `PackageInstaller`'s Team ID and destination checks.
    ///
    /// A `script` without `sudo` is `.brew`: brew runs it itself in the
    /// installer artifact's `install_phase`, on `brew install --cask` as on
    /// `brew upgrade`. Sending it to `PackageInstaller`, which looks for a `.pkg`
    /// in the download, failed while what the cask installs through is the
    /// script's executable: an installer `.app`, a shell script or a program in
    /// the archive, never a `.pkg`, for all 24 such casks on 2026-09-26 (read off
    /// the catalog; the downloads were not opened). quarkclouddrive's update
    /// failed there with "did not contain an installer package" (issue #877).
    ///
    /// The same failure awaited most of the casks that need a person, after the
    /// whole download: on 2026-09-26, 16 non-`auto_updates` casks with a `.app`
    /// or `uninstall: quit:` to match on had such an installer and no `pkg`
    /// artifact, and 3 of them named a package `packageIsReachable` accepts —
    /// pivy-app, datadog-agent, qsync-client (read off the catalog; the downloads
    /// were not opened).
    ///
    /// And for a `pkg` artifact, which used to be `.package` whatever the url:
    /// on 2026-09-26, 12 of the 110 such casks (same filter) are out of reach —
    /// nine in a `.zip`, one in a `.7z`, wch-ch34x-usb-serial-driver's in a
    /// folder, paragon-extfs's inside an installer `.app` on its `.dmg`. Their
    /// updates downloaded in full, then failed with "did not contain an
    /// installer package" (read off the catalog; the downloads were not opened).
    private static func installKind(artifacts: Any?, url: String?) -> CaskInstallKind {
        guard let artifacts = artifacts as? [Any] else { return .brew }
        var needsPerson = false
        var packages: [String] = []
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any] else { continue }
            if let pkg = dict["pkg"] {
                needsPerson = true
                packages += (pkg as? [Any])?.compactMap { $0 as? String } ?? []
            }
            if let installer = dict["installer"] {
                // Anything but a list of unprivileged scripts needs a person, as
                // every `installer` was taken to before #877.
                guard let entries = installer as? [Any] else {
                    needsPerson = true
                    continue
                }
                if !entries.allSatisfy(isUnprivilegedScript) { needsPerson = true }
                packages += entries.compactMap {
                    ($0 as? [String: Any])?["manual"] as? String
                }
            }
        }
        guard needsPerson else { return .brew }
        return packageIsReachable(url: url, packages: packages)
            ? .package : .detectionOnly
    }

    /// Whether `PackageInstaller` would find a package in this cask's download:
    /// the download itself is one, or it is a disk image with one at its top
    /// level. `resolveInstaller` mounts a `.dmg` and nothing else (a `.zip` is
    /// handed on as is and refused by `verifyOpenable`), and `preferredPackage`
    /// lists only the image's root — so a `pkg` or `manual` path with a `/` in it
    /// is out of reach even inside a `.dmg`. What the catalog *names*: whether
    /// the image really holds that file is only known after the download.
    ///
    /// A url with no extension is judged like a `.dmg`: the file is named by
    /// the server's `Content-Disposition`, which the catalog does not carry, so
    /// only a package with no folder in its path can be reached, whether it
    /// arrives bare or at an image's top level. On 2026-09-26, HEAD on the five
    /// such `pkg` casks gave three that arrive as a `.pkg` or `.dmg`
    /// (ecodms-client, meta-quest-remote-desktop, infocert-sign) and two as a
    /// `.zip`. wch-ch34x-usb-serial-driver names its package inside a folder,
    /// so it is detection-only. lg-onscreen-control does not, so it stays on
    /// the package route, where its update still fails after the download.
    private static func packageIsReachable(url: String?, packages: [String]) -> Bool {
        guard let ext = url.flatMap(URL.init(string:))?.pathExtension.lowercased()
        else { return false }
        if packageExtensions.contains(ext) { return true }
        guard ext == "dmg" || ext.isEmpty else { return false }
        return packages.contains {
            !$0.contains("/")
                && packageExtensions.contains(($0 as NSString).pathExtension.lowercased())
        }
    }

    /// What `PackageInstaller.verifyOpenable` accepts.
    private static let packageExtensions: Set<String> = ["pkg", "mpkg"]

    /// `{"script": {"executable": …}}` without `sudo: true`, or the bare
    /// `{"script": "path"}` form brew also accepts (which cannot ask for sudo).
    private static func isUnprivilegedScript(_ entry: Any) -> Bool {
        guard let script = (entry as? [String: Any])?["script"] else { return false }
        if script is String { return true }
        guard let options = script as? [String: Any] else { return false }
        return (options["sudo"] as? Bool) != true
    }

    /// Extract bundle identifiers a cask declares in its `uninstall: quit:`
    /// field — the app(s) Homebrew tells to quit before removal, which is the
    /// app's own bundle id. Reliable and specific (unlike `pkgutil`/`launchctl`
    /// receipts, which also list helpers), so it's a safe fallback key.
    /// `quit` may be a single string or an array.
    private static func bundleIDs(in artifacts: Any?) -> [String] {
        guard let artifacts = artifacts as? [Any] else { return [] }
        var ids: [String] = []
        for artifact in artifacts {
            guard let dict = artifact as? [String: Any],
                  let uninstalls = dict["uninstall"] as? [Any] else { continue }
            for uninstall in uninstalls {
                guard let u = uninstall as? [String: Any] else { continue }
                if let one = u["quit"] as? String {
                    ids.append(one)
                } else if let many = u["quit"] as? [Any] {
                    ids.append(contentsOf: many.compactMap { $0 as? String })
                }
            }
        }
        return ids
    }

    enum CaskError: Error { case badStatus(Int), malformed }
}
