import Foundation
import DuoUpdaterCore

// `duo verify`'s sweep of MyGo feeds (`MyGoFeedCatalog`). `MyGoUpdateSource` is a
// mechanism, like `SparkleAppcastSource`: its addresses live in whatever binaries
// a machine has, so a nightly run on a machine with none of them has nothing to
// walk. The catalog is the audited apps' feeds and keys, kept for this sweep
// alone.
//
// Per entry, through production code:
//   1. the feed resolves to a complete release (`MyGoUpdateSource`, the tagged
//      `{version}` form included);
//   2. the archive is still served — one `Range: bytes=0-0` GET, the Sparkle
//      sweep's `probeEnclosure` and its verdicts;
//   3. the vendor still signs with the recorded key — the smallest signed file
//      of the release (a patch, usually 0.16–1.3 MB) is downloaded and verified
//      (`MyGoUpdateSource.checkKey`). A rotated key keeps detection working and
//      ends every one-click, so nothing else would notice it.
//
// Split into a network half (`probeMyGo`) and a decision half (`classifyMyGo`),
// as `FeedVerify` is, so every verdict can be exercised offline.
extension MyGoFeedCatalog.Entry: VerifySelectable {}

extension Verify {

    static var myGoCases: [MyGoFeedCatalog.Entry] { MyGoFeedCatalog.entries }

    static func sweepMyGo(_ entries: [MyGoFeedCatalog.Entry], options: VerifyOptions) async -> [Finding] {
        let source = MyGoUpdateSource(githubToken: options.githubToken)
        var findings: [Finding] = []
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                try? await Task.sleep(
                    for: options.perHostDelay + .milliseconds(Int.random(in: 0...100)))
            }
            var attempt = 0
            var finding = await probeMyGo(entry, source: source, requestsAlready: 0)
            while attempt < options.infraRetries, finding.status == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                finding = await probeMyGo(entry, source: source, requestsAlready: finding.attempts)
            }
            findings.append(finding)
        }
        return findings
    }

    /// The network half: resolve the feed, ask for the archive's first byte and
    /// check the key, then hand what came back to `classifyMyGo`.
    private static func probeMyGo(
        _ entry: MyGoFeedCatalog.Entry, source: MyGoUpdateSource, requestsAlready: Int
    ) async -> Finding {
        let started = Date()
        // An installed copy as `MyGoUpdateSource` sees one, minus the binary: the
        // version only decides `status`, which this sweep does not read.
        let app = InstalledApp(
            name: entry.bundleID, bundleID: entry.bundleID, shortVersion: "0", buildVersion: "0",
            path: URL(fileURLWithPath: "/nonexistent/\(entry.bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil, myGoUpdate: entry.config)
        var requests = entry.config.isTagged ? 2 : 1
        let observation: MyGoObservation
        do {
            guard let remote = try await source.latestVersion(for: app) else {
                observation = MyGoObservation(resolve: .failed(nil, detail: "no answer"))
                return finding(entry, observation, requestsAlready + requests, started)
            }
            var enclosure: SparkleEnclosureAnswer?
            if let archive = remote.downloadURL {
                enclosure = await SparkleAppcastSource().probeEnclosure(archive)
                requests += 1
            }
            let key = await source.checkKey(remote, publicKey: entry.publicKey)
            switch key {
            case .noSignedFile, .tooLarge: break
            default: requests += 1
            }
            observation = MyGoObservation(
                resolve: .read(version: remote.shortVersion ?? "", archive: remote.downloadURL),
                enclosure: enclosure, key: key)
        } catch let failure as MyGoUpdateSource.Failure {
            observation = MyGoObservation(
                resolve: .failed(failure, detail: failure.errorDescription ?? "\(failure)"))
        } catch {
            observation = MyGoObservation(resolve: .failed(nil, detail: error.localizedDescription))
        }
        return finding(entry, observation, requestsAlready + requests, started)
    }

    private static func finding(
        _ entry: MyGoFeedCatalog.Entry, _ observation: MyGoObservation, _ attempts: Int,
        _ started: Date
    ) -> Finding {
        let verdict = classifyMyGo(observation)
        return Finding(
            recipeID: entry.recipeID, registry: .myGo, bundleID: entry.bundleID,
            channel: ReleaseChannel.stable.rawValue,
            status: verdict.status, version: verdict.version, warnings: verdict.warnings,
            endpointHost: URL(string: entry.feed)?.host ?? "-",
            attempts: attempts, elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// What one entry's reads mean. Warnings are written `<claim> — <explanation>`
    /// with a fixed claim, for `Reconcile.reason` and `Finding.signature`, as in
    /// `classifyFeed`.
    static func classifyMyGo(
        _ observation: MyGoObservation
    ) -> (status: FindingStatus, version: String?, warnings: [String]) {
        let version: String
        let archive: URL?
        switch observation.resolve {
        case .failed(let failure, let detail):
            switch failure {
            // The feed answered with something MyGo's own updater would refuse,
            // or a tagged feed found no release: the vendor's doing, not the
            // network's.
            case .manifestIncomplete?, .manifestUnreadable?, .noTaggedRelease?, .taggedFeedMalformed?:
                return (.broken, nil, [
                    "mygoFeedUnusable — the feed linked into the app did not resolve to a "
                        + "complete release, so the app is neither detected nor installable "
                        + "(\(detail))",
                ])
            // Never `.broken` on its own: an address that does not answer is the
            // network's word until `Baseline.isInfraReportable` says otherwise.
            default:
                return (.infra, nil, [
                    "mygoFeedUnreachable — the feed linked into the app did not answer "
                        + "(\(detail))",
                ])
            }
        case .read(let v, let a):
            version = v
            archive = a
        }

        var warnings: [String] = []
        if let answer = observation.enclosure,
           let warning = enclosureWarning(answer, host: archive?.host) {
            warnings.append(warning)
        }
        switch observation.key {
        case .verified?, nil:
            break
        case .invalid(let file)?:
            return (.broken, version, warnings + [
                "mygoKeyMismatch — the release is not signed with the key the installed app "
                    + "carries, so every one-click of it fails; the vendor may have rotated "
                    + "its key (\(file.lastPathComponent))",
            ])
        case .noSignedFile?:
            return (.broken, version, warnings + [
                "mygoNothingSigned — neither the archive nor any patch carries a signature, "
                    + "so no one-click can verify it",
            ])
        case .tooLarge(let file, let bytes)?:
            warnings.append(
                "mygoKeyNotChecked — the smallest signed file is \(bytes) bytes, over the "
                    + "sweep's download cap (\(file.lastPathComponent))")
        case .unreachable(let file, let detail)?:
            // Accuses nobody, like a transient enclosure answer.
            warnings.append(
                ProbeWarning.installURLTransient(status: nil).display
                    + " (key check: \(file.lastPathComponent), \(detail))")
        }
        let transientKind = ProbeWarning.installURLTransient(status: nil).kind
        let actionable = warnings.filter { !$0.hasPrefix(transientKind) }
        return (actionable.isEmpty ? .ok : .warn, version, warnings)
    }
}

/// What the live reads of one catalog entry saw — no verdict. See
/// `Verify.classifyMyGo`.
struct MyGoObservation: Sendable {
    enum Resolve: Sendable {
        case read(version: String, archive: URL?)
        /// `failure` is nil for a transport error or an unexpected nil.
        case failed(MyGoUpdateSource.Failure?, detail: String)
    }

    let resolve: Resolve
    var enclosure: SparkleEnclosureAnswer?
    var key: MyGoKeyCheck?
}
