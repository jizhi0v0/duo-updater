import Foundation
import DuoUpdaterCore

// Download every installer a vendor recipe or GitHub rule resolves, and read it
// the way the install route does — `ArtifactInspection` — on a machine where none
// of the apps are installed.
//
// `duo verify` deliberately never downloads an installer, so a failure that only
// the bytes can show reaches no report: WorkBuddy CN's bundle id changed at 5.5.4
// and the sweep stayed green for three weeks (#1030). This is the other half.
// It is meant for a hosted runner, where the download costs nothing; it holds one
// archive per host in flight and deletes each as soon as it has been read.
//
// For now it only reports. Comparing against what an earlier run saw, and filing
// issues, come after a first run has shown what the noise looks like.

public struct InstallVerifyOptions: Sendable {
    public init() {}
    public var only: [String] = []
    public var hostConcurrency = 3
    public var allowStaleBinary = false
    public var githubToken: String?
    public var jsonPath: URL?
    public var markdownPath: URL?
    /// Read and update what each installer was the first time it was seen
    /// (`InstallIdentities`). Without it every run is judged on its own.
    public var identitiesPath: URL?
    /// Read and update failure streaks and issue numbers, as `duo verify
    /// --baseline` does — a file of its own, since the two jobs run on
    /// different machines and each commits what it writes.
    public var baselinePath: URL?
    /// Write the results as `duo verify --report` does, for `duo reconcile`.
    public var findingsPath: URL?
}

public enum InstallVerify {

    public enum Status: String, Codable, Sendable {
        /// Downloaded, every check that runs without an installed copy passed.
        case ok
        /// Downloaded and readable, but not what the recipe says it installs.
        case warn
        /// A gate refused it, or it could not be fetched or unpacked.
        case failed
        /// The recipe resolved no installer to download.
        case unresolved
        /// Never fetched — see `detail`.
        case skipped
    }

    public struct Item: Codable, Sendable {
        public var recipeID: String
        public var registry: String
        public var bundleID: String
        public var probeHost: String
        public var version: String?
        public var url: String?
        public var finalHost: String?
        public var kind: String?
        public var status: Status
        public var stage: ArtifactInspection.Stage?
        public var detail: String?
        /// The status a server refused the download with, if that is why it failed.
        public var httpStatus: Int?
        public var warnings: [String] = []
        public var notes: [String] = []
        public var bytes: Int64 = 0
        public var seconds: Double = 0
        public var identity: ArtifactInspection.Identity?
        public var packageTeamIdentifier: String?
    }

    public struct Report: Codable, Sendable {
        public var generatedAt: Date
        public var seconds: Double
        public var bytes: Int64
        /// The least free space the scratch volume had when sampled — before
        /// each item, and again once its archive and unpacked app are both on
        /// disk, just before they are deleted. What decides how many downloads
        /// can safely be in flight.
        public var minimumFreeBytes: Int64?
        public var hostConcurrency: Int
        public var items: [Item]
    }

    /// What one recipe asks to be downloaded.
    struct Target: Sendable {
        let recipeID: String
        let registry: String
        let bundleID: String
        let probeHost: String
        let resolve: @Sendable () async -> ProbeOutcome
    }

    public static func run(_ options: InstallVerifyOptions) async -> Int32 {
        if case .stale(let reason) = SourceStamp.verdict() {
            guard options.allowStaleBinary else {
                die(SourceStamp.complaint(reason), code: 2)
            }
            print("\n  ⚠︎ \(reason).\n    Running anyway because --allow-stale-binary was passed.\n")
        }

        var token = options.githubToken
        if token == nil { token = await GitHubToken.resolve() }
        let github = GitHubReleasesSource(token: token)
        let vendor = VendorProbeSource()

        var identities: InstallIdentities?
        if let path = options.identitiesPath {
            do { identities = try InstallIdentities.load(from: path) } catch {
                die("""
                    could not read \(path.path): \(error)
                    Refusing to run: starting over would record today's installers as \
                    correct whatever they are. Restore the file from git.
                    """, code: 2)
            }
        }

        var targets: [Target] = []
        var skipped: [Item] = []
        var selector = VerifyOptions()
        selector.only = options.only
        for recipe in Verify.filtered(VendorProbeRegistry.recipes, selector)
        where recipe.install != nil {
            let host = recipe.url.host ?? "-"
            // Never fetched by `duo verify` either: its URL, headers and body would
            // all flow into a report.
            if RegistrySecurity.isCredentialBearing(bundleID: recipe.bundleID) {
                skipped.append(Item(
                    recipeID: recipe.recipeID, registry: "vendor", bundleID: recipe.bundleID,
                    probeHost: host, status: .skipped, detail: "credential-bearing — never fetched"))
                continue
            }
            targets.append(Target(
                recipeID: recipe.recipeID, registry: "vendor", bundleID: recipe.bundleID,
                probeHost: host,
                resolve: { await vendor.probeDiagnostic(recipe) }))
        }
        for rule in Verify.filtered(GitHubReleaseRegistry.rules, selector)
        where rule.installAssetPattern != nil {
            targets.append(Target(
                recipeID: rule.recipeID, registry: "github", bundleID: rule.bundleID,
                probeHost: "api.github.com",
                resolve: { await github.resolveDiagnostic(rule) }))
        }
        guard !targets.isEmpty else {
            die("nothing to verify — no recipe with an installer matches "
                + options.only.joined(separator: ", "), code: 2)
        }

        print("""

          duo verify-install
          \(targets.count) installers  (\(skipped.count) skipped)  \
        \(options.hostConcurrency) hosts at a time
          ─────────────────────────────────────────────
        """)

        let started = Date()
        let disk = FreeSpaceWatermark()
        await disk.sample()
        let inspected = await byHost(targets, concurrency: options.hostConcurrency) { target in
            await disk.sample()
            let item = await verify(target, disk: disk)
            print(line(item))
            return item
        }
        var items = (inspected + skipped).sorted { $0.recipeID < $1.recipeID }
        if var store = identities, let path = options.identitiesPath {
            let now = Date()
            for index in items.indices {
                compare(&items[index], with: &store, at: now)
            }
            // Each item's line went out as it finished; identity is judged only
            // once every download is in, so its verdict needs its own lines.
            let changed = items.filter { $0.warnings.contains { $0.hasPrefix("identityChanged:") } }
            if !changed.isEmpty {
                print("\n  identity changes since first seen:")
                for item in changed { print(line(item)) }
            }
            store.prune(keeping: liveRecipeIDs())
            do { try store.save(to: path) } catch {
                die("could not write \(path.path): \(error.localizedDescription)", code: 1)
            }
        }
        if options.baselinePath != nil || options.findingsPath != nil {
            var baseline = options.baselinePath.map(Baseline.load) ?? Baseline()
            let findings = items.map(finding)
            for finding in findings { _ = baseline.reconcile(finding) }
            baseline.updatedAt = Date()
            _ = baseline.prune(keeping: Set(liveRecipeIDs().map(findingID)))
            do {
                if let path = options.baselinePath { try baseline.save(to: path) }
                if let path = options.findingsPath { try DuoKit.Report.json(findings, to: path) }
            } catch {
                die("could not write the baseline or findings: \(error.localizedDescription)", code: 1)
            }
        }
        let report = Report(
            generatedAt: Date(), seconds: Date().timeIntervalSince(started),
            bytes: items.reduce(0) { $0 + $1.bytes },
            minimumFreeBytes: await disk.minimum, hostConcurrency: options.hostConcurrency,
            items: items)

        let summary = summaryText(report)
        print(summary)
        if let path = options.jsonPath {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do { try encoder.encode(report).write(to: path) } catch {
                die("could not write \(path.path): \(error.localizedDescription)", code: 1)
            }
        }
        if let path = options.markdownPath {
            do { try markdown(report).write(to: path, atomically: true, encoding: .utf8) } catch {
                die("could not write \(path.path): \(error.localizedDescription)", code: 1)
            }
        }
        return items.contains { $0.status == .failed || $0.status == .warn } ? 1 : 0
    }

    // MARK: - one installer

    static func verify(_ target: Target, disk: FreeSpaceWatermark) async -> Item {
        let started = Date()
        var item = await inspect(target, disk: disk)
        item.seconds = Date().timeIntervalSince(started)
        return item
    }

    private static func inspect(_ target: Target, disk: FreeSpaceWatermark) async -> Item {
        var item = Item(
            recipeID: target.recipeID, registry: target.registry, bundleID: target.bundleID,
            probeHost: target.probeHost, status: .unresolved)

        let outcome = await target.resolve()
        guard let remote = outcome.remote else {
            item.detail = outcome.failure.map { "\($0.kind): \($0.detail)" } ?? "the probe answered nothing"
            return item
        }
        item.version = remote.displayVersion
        item.kind = remote.vendorInstallerKind.map { "\($0)" }
        guard let url = remote.downloadURL, remote.vendorInstallerKind != nil else {
            let said = outcome.warnings.map(\.display)
            item.detail = said.isEmpty ? "the probe resolved no installer" : said.joined(separator: "; ")
            return item
        }
        item.url = url.absoluteString

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "duo-verify-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workDir) }
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            item.status = .failed
            item.detail = "could not create a scratch directory: \(error.localizedDescription)"
            return item
        }

        let bundleName = target.bundleID.split(separator: ".").last.map(String.init) ?? "App"
        let inspection = await ArtifactInspection.inspect(
            remote, bundleName: bundleName, workDir: workDir)
        // Here, not after returning: the archive and the unpacked app are both
        // still in `workDir`, and the `defer` above deletes them on the way out.
        await disk.sample()
        switch inspection {
        case .failure(let failure):
            item.status = .failed
            item.stage = failure.stage
            item.detail = failure.message
            item.bytes = failure.bytes
            item.httpStatus = failure.httpStatus
        case .success(let inspected):
            item.bytes = inspected.bytes
            item.finalHost = inspected.finalHost
            item.identity = inspected.identity
            item.packageTeamIdentifier = inspected.packageTeamIdentifier
            item.notes = inspected.notes
            item.warnings = warnings(
                identity: inspected.identity, remote: remote, recipeBundleID: target.bundleID)
            item.notes += notes(identity: inspected.identity, remote: remote)
            item.status = item.warnings.isEmpty ? .ok : .warn
        }
        return item
    }

    /// Hold one item's download against what was recorded for its recipe. Only
    /// a download that was read counts: a failed or unresolved one says nothing
    /// about the vendor's identity, and must neither record nor clear anything.
    static func compare(_ item: inout Item, with store: inout InstallIdentities, at date: Date) {
        guard item.status == .ok || item.status == .warn,
              let observed = InstallIdentities.observed(
                  identity: item.identity, packageTeamIdentifier: item.packageTeamIdentifier,
                  version: item.version, at: date)
        else { return }
        let changes = store.record(item.recipeID, observed)
        guard !changes.isEmpty else { return }
        let since = store.entries[item.recipeID].map {
            " (recorded at \($0.lastSeenVersion ?? "?"), \($0.lastSeenAt.formatted(.iso8601.year().month().day())))"
        } ?? ""
        item.warnings.append("identityChanged: " + changes.joined(separator: "; ") + since)
        item.status = .warn
    }

    /// This command's id for a recipe in `Baseline` and on an issue. Namespaced
    /// like every registry's, so it cannot share a streak or an issue with the
    /// sweep's own finding for the same recipe.
    static func findingID(_ recipeID: String) -> String { "install:" + recipeID }

    /// An item as `Baseline` and `Reconcile` read a finding.
    ///
    /// - A download that stopped at the network is `infra`: a vendor CDN that
    ///   drops a long transfer from a US data centre (Baidu Netdisk, run
    ///   37876975684: "The network connection was lost" after 252 MB) is not a
    ///   broken recipe, and only a run of them is news. So is a 5xx, a 408 and a
    ///   429 — the server is there and may answer next time.
    /// - A download the server refused (any other 4xx — the asset was deleted or
    ///   renamed) is `broken`: waiting out the infra window would take days and
    ///   then file it as an unreachable host, which it is not.
    /// - A gate that refused the bytes — digest, unpacking, signature — is
    ///   `broken`.
    /// - Unresolved is `skipped`: resolving the installer is `duo verify`'s
    ///   finding to file, and filing it here as well would open a second issue.
    /// - No version: `Baseline` would hold it to the last one and repeat the
    ///   sweep's own "went backwards" check under a second id.
    static func finding(_ item: Item) -> Finding {
        let status: FindingStatus
        switch item.status {
        case .ok: status = .ok
        case .warn: status = .warn
        case .failed:
            status = item.stage == .download && !isRefusal(item.httpStatus) ? .infra : .broken
        case .unresolved, .skipped: status = .skipped
        }
        let host = item.finalHost ?? item.url.flatMap { URL(string: $0)?.host } ?? item.probeHost
        return Finding(
            recipeID: findingID(item.recipeID), registry: .install, bundleID: item.bundleID,
            channel: "-", status: status,
            failureKind: item.stage.map { "install.\($0.rawValue)" },
            failureDetail: item.status == .failed ? item.detail : nil,
            warnings: item.warnings, endpointHost: host,
            elapsedMs: Int(item.seconds * 1000))
    }

    /// A status that says the request itself is wrong rather than the moment.
    static func isRefusal(_ status: Int?) -> Bool {
        guard let status else { return false }
        return (400..<500).contains(status) && status != 408 && status != 429
    }

    /// Every recipe this command could download, whatever `--only` says — what
    /// the identity store keeps entries for.
    static func liveRecipeIDs() -> Set<String> {
        Set(VendorProbeRegistry.recipes.filter { $0.install != nil }.map(\.recipeID)
            + GitHubReleaseRegistry.rules.filter { $0.installAssetPattern != nil }.map(\.recipeID))
    }

    /// What an installed copy's gates would refuse, judged from the download
    /// alone.
    static func warnings(
        identity: ArtifactInspection.Identity?, remote: RemoteVersion, recipeBundleID: String
    ) -> [String] {
        guard let identity else { return [] }
        var out: [String] = []
        // Recipes are keyed by the bundle id an installed copy reports, so a
        // download that carries another one is either a vendor rename (#1030) or
        // a recipe resolving some other product's installer. Gate 4 refuses both.
        let downloaded = identity.bundleIdentifier ?? identity.signedIdentifier
        if let downloaded, downloaded != recipeBundleID {
            out.append("bundleIDMismatch: the download is \(downloaded), the recipe is keyed by \(recipeBundleID)")
        }
        // Gate 3 refuses a download without a Team unless the route is digest-only.
        if identity.teamIdentifier == nil, remote.installTrust == .developerID {
            out.append("noTeamIdentifier: the download is not Developer ID signed")
        }
        return out
    }

    /// Worth reading but not, on its own, a fault.
    static func notes(identity: ArtifactInspection.Identity?, remote: RemoteVersion) -> [String] {
        guard let identity, let probed = remote.shortVersion, let bundled = identity.shortVersion,
              probed != bundled else { return [] }
        return ["versionDiffers: the probe said \(probed), the bundle says \(bundled)"]
    }

    // MARK: - plumbing

    /// One installer at a time per host, up to `concurrency` hosts at once —
    /// the same politeness as `Verify.byHost`, and the same bound on how many
    /// archives sit on disk together.
    static func byHost(
        _ targets: [Target], concurrency: Int,
        work: @escaping @Sendable (Target) async -> Item
    ) async -> [Item] {
        let groups = Dictionary(grouping: targets, by: \.probeHost).values
            .sorted { $0[0].probeHost < $1[0].probeHost }
        var items: [Item] = []
        var next = 0
        await withTaskGroup(of: [Item].self) { group in
            func addNext() {
                guard next < groups.count else { return }
                let batch = groups[next]
                next += 1
                group.addTask {
                    var out: [Item] = []
                    for target in batch { out.append(await work(target)) }
                    return out
                }
            }
            for _ in 0..<min(max(1, concurrency), groups.count) { addNext() }
            for await produced in group {
                items.append(contentsOf: produced)
                addNext()
            }
        }
        return items
    }

    actor FreeSpaceWatermark {
        private(set) var minimum: Int64?
        func sample() {
            // Asked of the file system each time: a `URL`'s resource values are
            // cached on the value, and a fresh read is the whole point here.
            guard let attributes = try? FileManager.default.attributesOfFileSystem(
                      forPath: NSTemporaryDirectory()),
                  let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value
            else { return }
            minimum = min(minimum ?? free, free)
        }
    }

    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    static func line(_ item: Item) -> String {
        let mark: String
        switch item.status {
        case .ok: mark = "✓"
        case .warn: mark = "⚠"
        case .failed: mark = "✗"
        case .unresolved: mark = "?"
        case .skipped: mark = "-"
        }
        var parts = ["  \(mark) \(item.recipeID)"]
        if let version = item.version { parts.append(version) }
        if item.bytes > 0 { parts.append(megabytes(item.bytes)) }
        parts.append(String(format: "%.0fs", item.seconds))
        if let identity = item.identity {
            parts.append("\(identity.bundleIdentifier ?? "?") / \(identity.teamIdentifier ?? "no team")")
        } else if let team = item.packageTeamIdentifier {
            parts.append("pkg / \(team)")
        }
        var out = parts.joined(separator: "  ")
        if let stage = item.stage { out += "\n      \(stage.rawValue): \(item.detail ?? "")" }
        else if let detail = item.detail { out += "\n      \(detail)" }
        for warning in item.warnings { out += "\n      \(warning)" }
        return out
    }

    static func counts(_ report: Report) -> [(Status, Int)] {
        [Status.ok, .warn, .failed, .unresolved, .skipped].map { status in
            (status, report.items.filter { $0.status == status }.count)
        }
    }

    static func summaryText(_ report: Report) -> String {
        let tally = counts(report).map { "\($0.0.rawValue) \($0.1)" }.joined(separator: "  ")
        let disk = report.minimumFreeBytes.map { "  lowest free disk \(megabytes($0))" } ?? ""
        return """

          ─────────────────────────────────────────────
          \(tally)
          \(megabytes(report.bytes)) in \(String(format: "%.0f", report.seconds))s\(disk)
        """
    }

    static func markdown(_ report: Report) -> String {
        var out = "## duo verify-install\n\n"
        out += counts(report).map { "**\($0.0.rawValue)** \($0.1)" }.joined(separator: " · ")
        out += "\n\n\(megabytes(report.bytes)) downloaded in \(String(format: "%.0f", report.seconds)) s"
        out += ", \(report.hostConcurrency) hosts at a time"
        if let free = report.minimumFreeBytes { out += ", lowest free disk \(megabytes(free))" }
        out += "\n\n"
        let flagged = report.items.filter { $0.status != .ok }
        if !flagged.isEmpty {
            out += "| recipe | status | stage | detail |\n|---|---|---|---|\n"
            for item in flagged {
                let detail = ([item.detail].compactMap { $0 } + item.warnings + item.notes)
                    .joined(separator: "; ")
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\n", with: " ")
                out += "| `\(item.recipeID)` | \(item.status.rawValue) | \(item.stage?.rawValue ?? "") | \(detail) |\n"
            }
            out += "\n"
        }
        let largest = report.items.sorted { $0.bytes > $1.bytes }.prefix(10).filter { $0.bytes > 0 }
        if !largest.isEmpty {
            out += "### Largest\n\n| recipe | size | time |\n|---|---|---|\n"
            for item in largest {
                out += "| `\(item.recipeID)` | \(megabytes(item.bytes)) | \(String(format: "%.0f", item.seconds)) s |\n"
            }
        }
        return out
    }
}
