import Foundation
import DuoUpdaterCore

// `duo verify`'s sweep of `SparkleFeedCatalog` — the addresses we hand out for
// apps whose own bundle does not give us a usable one.
//
// Why it is a registry at all (#324). The other four sweeps check recipes: a
// pattern that has to keep matching a page. This one checks an ADDRESS, and an
// address that has stopped working looks like nothing. `SparkleAppcastSource`
// answers a dead or unusable feed with nil, and every caller renders nil as "up
// to date" — which is the exact failure the superseding entry was added to fix,
// one address further along. The table's two halves fail that way for different
// reasons:
//
//   - a fill-in address is one the bundle never states, so if it moves there is
//     no second source of truth to fall back on;
//   - a superseding address overrides one the bundle DOES state, so it keeps
//     asserting our reading of a vendor's infrastructure over theirs until
//     somebody checks that the reading still holds.
//
// Split into a network half (`probe`/`read`) and a pure decision half
// (`classifyFeed`), the same split `AppStoreVerify` uses, so every judgement
// here can be exercised offline against fixtures.
//
// Never downloads an enclosure: the head item's download URL is checked for
// SHAPE only. Whether that artifact is still SERVED is a separate question with
// a separate cost, and the vendor sweep's `installURLNotFound` — a `Range:
// bytes=0-0` GET, raised only by the sweep and never by a check — is the
// precedent for how it would be answered if it is ever worth the request.
extension Verify {

    static func sweepFeeds(
        _ cases: [SparkleFeedCatalog.VerificationCase], options: VerifyOptions
    ) async -> [Finding] {
        guard !cases.isEmpty else { return [] }
        let source = SparkleAppcastSource()

        // Sequential with the same inter-request delay every other sweep uses.
        // Today's entries sit on a host each, so the delay buys nothing between
        // them — but a table this small has no parallelism worth having either,
        // and a superseding entry's two reads go to the same host back to back,
        // which is the pair the delay is actually for.
        var findings: [Finding] = []
        for (index, entry) in cases.enumerated() {
            if index > 0 {
                try? await Task.sleep(
                    for: options.perHostDelay + .milliseconds(Int.random(in: 0...100)))
            }
            // Requests, not probes: a retried entry has cost the endpoint every
            // one of them, and `Finding.attempts` is documented as the number
            // that cannot understate what the sweep spent. Carried forward from
            // each probe rather than multiplied out, because a probe that gave
            // up after an unreachable live read spent one request, not two.
            var attempt = 0
            var finding = await probe(entry, source: source, requestsAlready: 0)
            while attempt < options.infraRetries, finding.status == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                finding = await probe(
                    entry, source: source, requestsAlready: finding.attempts)
            }
            findings.append(finding)
        }
        return findings
    }

    /// The network half: read the address the catalog hands out, plus — for a
    /// superseding entry — the dead address it overrides, and hand both to
    /// `classifyFeed`. Decides nothing itself.
    private static func probe(
        _ entry: SparkleFeedCatalog.VerificationCase, source: SparkleAppcastSource,
        requestsAlready: Int
    ) async -> Finding {
        let started = Date()
        let live = await read(entry.feed, bundleID: entry.bundleID, source: source)
        // Two requests for a superseding entry, one for a fill-in. The second is
        // what makes the entry's own expiry condition mechanical rather than a
        // note in a comment: it is only justified for as long as the address it
        // overrides is genuinely behind.
        //
        // Skipped when the live read already failed: `classifyFeed` returns from
        // its `.unreachable` branch without ever looking at this one, and the
        // retry loop above would otherwise spend three extra requests on a host
        // that is down — the one moment it should be asking for less, not more.
        var declared: FeedObservation.Fetch?
        var requestsSpent = 1
        if let deadAddress = entry.declared, case .read = live {
            declared = await read(deadAddress, bundleID: entry.bundleID, source: source)
            requestsSpent += 1
        }

        let verdict = classifyFeed(entry, FeedObservation(live: live, declared: declared))
        return Finding(
            recipeID: entry.recipeID, registry: .feed, bundleID: entry.bundleID,
            channel: entry.kind.rawValue, status: verdict.status, version: verdict.version,
            // The LIVE address's host: it is the one an app is pointed at, and
            // the one a nightly triage should route by. The dead address is
            // named in full inside the warning that complains about it, which
            // is what a reader needs when the two share a host.
            warnings: verdict.warnings, endpointHost: entry.feed.host ?? "-",
            attempts: requestsAlready + requestsSpent,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
    }

    private static func read(
        _ url: URL, bundleID: String, source: SparkleAppcastSource
    ) async -> FeedObservation.Fetch {
        do {
            switch try await source.readFeed(url, bundleID: bundleID) {
            case .success(let reading): return .read(reading)
            case .failure(.badStatus(let code)):
                return .unreachable(httpStatus: code, detail: "HTTP \(code)")
            }
        } catch {
            return .unreachable(httpStatus: nil, detail: error.localizedDescription)
        }
    }

    /// What one entry's live reads mean, as a verdict the report can carry.
    ///
    /// Warnings are written `<claim> — <explanation>`: `Reconcile.reason` takes
    /// the claim as the issue title, and `Finding.signature` keys on the first
    /// 40 characters, so every claim here is fixed text long enough that a
    /// version or a count moving cannot change the signature.
    static func classifyFeed(
        _ entry: SparkleFeedCatalog.VerificationCase, _ observation: FeedObservation
    ) -> (status: FindingStatus, version: String?, warnings: [String]) {
        let live: SparkleFeedReading
        switch observation.live {
        case .read(let reading):
            live = reading
        case .unreachable(_, let detail):
            // Never `.broken`. An address that does not answer is the network's
            // word until it has been the network's word for a week, which is
            // what `Baseline.isInfraReportable` is for.
            return (.infra, nil, [
                "feedUnreachable — the address this catalog entry hands out did not answer "
                    + "(\(detail))",
            ])
        }

        // The feed answered. Everything below is about whether what came back
        // can still do the job the entry was added to do.
        var warnings: [String] = []

        if live.itemCount == 0 {
            return (.broken, nil, [
                "feedParsedToZeroItems — the address answered, with a body carrying no "
                    + "appcast items at all (\(live.byteCount) bytes). An app fed this "
                    + "address sees no update and no error.",
            ])
        }

        guard live.usableCount > 0 else {
            // The silent one. `latestVersion` returns nil here and the row reads
            // as up to date — the same shape as the frozen feed that made a
            // superseding entry necessary in the first place.
            let capped = live.itemsDeclaringMaximumSystemVersion
            return (.broken, nil, [
                "everyItemFilteredOut — the feed parsed \(live.itemCount) items and none of "
                    + "them survive the channel, OS-bound and architecture filters for a "
                    + "default-channel install on macOS \(live.osVersion)"
                    + (capped > 0
                        ? " — \(capped) of them declare a maximum system version"
                        : ""),
            ])
        }

        // The marketing string is what the baseline's monotonicity check reads,
        // and it is the only field on this side that may be compared against the
        // installed copy's own `CFBundleShortVersionString` (`RemoteVersion`
        // sets `marketingMatchesBundle` for exactly this source). A feed that
        // stops publishing it moves `evaluate` onto its build branch and leaves
        // the baseline nothing it may record without changing namespaces
        // mid-history, so the version goes nil rather than silently becoming a
        // build number.
        guard let marketing = live.headShortVersion, !marketing.isEmpty else {
            warnings.append(
                "headItemNamesNoMarketingVersion — the newest usable item declares no "
                    + "sparkle:shortVersionString, so this feed can no longer be compared "
                    + "against an installed copy's marketing version"
                    + (live.headBuildVersion.map { " (build \($0))" } ?? ""))
            return (.warn, nil, warnings)
        }

        // Detection still works without a usable enclosure; installing does not.
        // Same call as the vendor sweep's `installURLUnresolved`, which is a
        // warning for the same reason.
        if let enclosure = live.headEnclosure {
            if enclosure.scheme?.hasPrefix("http") != true || enclosure.host == nil {
                warnings.append(
                    "headEnclosureIsNotAbsolute — the newest usable item's download URL did "
                        + "not resolve to an absolute http(s) address, so the update can be "
                        + "detected but never installed (\(enclosure.absoluteString))")
            }
        } else {
            warnings.append(
                "headItemHasNoEnclosure — the newest usable item carries no download URL, so "
                    + "the update can be detected but never installed")
        }

        // A superseding entry's expiry condition, made mechanical: it is only
        // justified while the address it overrides is behind the one it points
        // at.
        //
        // An empty dead side is NOT that condition failing — it is the condition
        // at its strongest. A dead address that has stopped offering anything a
        // default-channel install could use (a retired path answering with a
        // landing page, or a vendor capping its last uncapped build the way PDF
        // Expert's feed already caps three of four) offers strictly less than
        // when the entry was written. Reading `isNewer`'s fail-closed `false`
        // as a complaint there would file an issue every night against the one
        // entry behaving perfectly.
        //
        // What DOES still complain is two non-empty sides that cannot be ranked
        // — a dead feed naming only a build against a live feed naming only a
        // marketing string. `VersionComparator` refuses to cross those
        // namespaces, and "we can no longer show this entry is justified" is
        // worth being told however it became true.
        if case .read(let dead)? = observation.declared {
            let liveSide = VersionSide(marketing: marketing, build: live.headBuildVersion)
            let deadSide = VersionSide(
                marketing: dead.headShortVersion, build: dead.headBuildVersion)
            if !deadSide.isEmpty, !VersionComparator.isNewer(liveSide, than: deadSide) {
                // Named in full, not by host. `Finding.endpointHost` carries
                // the LIVE address's host, and nothing requires the two halves
                // of an entry to differ in more than their path — today's pair
                // shares a host and differs only there — so the host alone
                // would not tell a reader which address this is about.
                warnings.append(
                    "supersededAddressIsNoLongerBehind — the address this entry redirects "
                        + "away from can no longer be shown to be older than the one it "
                        + "redirects to, which is the entry's whole justification "
                        + "(\(entry.declared?.absoluteString ?? "?") at "
                        + "\(deadSide.text(withBuild: true)), "
                        + "live \(liveSide.text(withBuild: true)))")
            }
        }

        return (warnings.isEmpty ? .ok : .warn, marketing, warnings)
    }
}

/// What the live reads of one catalog entry saw — fetch only, no verdict. See
/// `Verify.classifyFeed(_:_:)`.
struct FeedObservation: Sendable {
    enum Fetch: Sendable {
        case read(SparkleFeedReading)
        /// Nothing parseable came back. `httpStatus` is nil when the request
        /// never got an answer at all.
        case unreachable(httpStatus: Int?, detail: String)
    }

    /// The address `AppScanner` writes onto the row.
    let live: Fetch
    /// The dead address a superseding entry matches on. Nil for a fill-in,
    /// which overrides nothing and so has no second address to read.
    let declared: Fetch?
}
