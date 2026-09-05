import Foundation
import DuoUpdaterCore

// `duo verify`'s Mac App Store sweep. See `MacAppStoreProbeRegistry`'s doc
// comment in DuoUpdaterCore for why this registry exists and how its cases
// were picked.
//
// Unlike the vendor/GitHub/changelog sweeps, this one never asserts a
// specific version value — every check here is about SHAPE: did the lookup
// answer with the `kind` we declared, does the product page still carry the
// JSON shelf the production parser depends on, does a batched lookup agree
// with a single one about what an app IS (not what version it's at).
//
// Split into a network half (`probe`) and a pure decision half
// (`classifyAppStore`), the same shape `Verify.classify(_:registry:...)` uses
// for the other three sweeps — so the decision logic can be unit-tested
// without a live endpoint.
extension Verify {

    static func sweepAppStore(
        _ cases: [MacAppStoreProbeCase], options: VerifyOptions
    ) async -> [Finding] {
        guard !cases.isEmpty else { return [] }
        // A fixed region, never the sweeping machine's own storefront — see
        // `MacAppStoreProbeCase.region`.
        let source = MacAppStoreSource(region: "us")

        // One batched lookup across every case's bundle id, in the same
        // request shape `prewarm(_:)` makes — this is what check 5 (batch ≡
        // single) compares each case's own single lookup against.
        //
        // ⚠️ It must SAY SO when it can't run. The first version used `try?`
        // and let `batch` go nil, which skipped check 5 for every case in the
        // run and printed output identical to "check 5 ran and passed" — a
        // guard that disappears exactly when the thing it guards is
        // unreachable, which is the failure shape the rest of this branch went
        // out of its way to remove. An empty (non-nil) batch is the same
        // problem wearing a different hat: every case would then compare a
        // real single result against "absent" and report `broken`, dressing an
        // infra failure as a registry break.
        var findings: [Finding] = []
        var batch: [String: AppStoreLookupShape?]?
        do {
            let fetched = try await source.verifyBatchLookup(
                bundleIDs: cases.map(\.bundleID), region: "us")
            if fetched.isEmpty {
                findings.append(Finding(
                    recipeID: MacAppStoreProbeRegistry.batchRecipeID, registry: .appStore, bundleID: "-",
                    channel: "-", status: FindingStatus.infra,
                    failureDetail: "batched lookup returned nothing for \(cases.count) bundle ids — check 5 (batch ≡ single) did not run",
                    endpointHost: "itunes.apple.com", elapsedMs: 0))
            } else {
                batch = fetched
            }
        } catch {
            findings.append(Finding(
                recipeID: MacAppStoreProbeRegistry.batchRecipeID, registry: .appStore, bundleID: "-",
                channel: "-", status: FindingStatus.infra,
                failureDetail: "batched lookup failed (\(error.localizedDescription)) — check 5 (batch ≡ single) did not run",
                endpointHost: "itunes.apple.com", elapsedMs: 0))
        }

        for (index, probeCase) in cases.enumerated() {
            if index > 0 {
                try? await Task.sleep(
                    for: options.perHostDelay + .milliseconds(Int.random(in: 0...100)))
            }
            var attempt = 0
            var finding = await probe(probeCase, source: source, batch: batch)
            while attempt < options.infraRetries, finding.status == .infra {
                attempt += 1
                try? await Task.sleep(for: .seconds(attempt))
                finding = await probe(probeCase, source: source, batch: batch)
            }
            findings.append(finding)
        }
        return findings
    }

    /// The network half: fetch everything `classifyAppStore` needs for one
    /// case, then hand the verdict to it. Never itself decides `.ok`/`.warn`/
    /// `.broken` — every judgment call lives in `classifyAppStore` so it can
    /// be exercised offline.
    private static func probe(
        _ probeCase: MacAppStoreProbeCase, source: MacAppStoreSource,
        batch: [String: AppStoreLookupShape?]?
    ) async -> Finding {
        let started = Date()
        func elapsed() -> Int { Int(Date().timeIntervalSince(started) * 1000) }
        func infra(_ detail: String) -> Finding {
            Finding(
                recipeID: probeCase.recipeID, registry: .appStore, bundleID: probeCase.bundleID,
                channel: probeCase.route.rawValue, status: FindingStatus.infra, failureDetail: detail,
                endpointHost: "apps.apple.com", elapsedMs: elapsed())
        }

        let single: AppStoreLookupShape?
        do {
            single = try await source.verifyLookup(bundleID: probeCase.bundleID, region: probeCase.region)
        } catch {
            return infra("lookup failed: \(error)")
        }
        guard let single else {
            return Finding(
                recipeID: probeCase.recipeID, registry: .appStore, bundleID: probeCase.bundleID,
                channel: probeCase.route.rawValue, status: .broken,
                failureDetail: "lookup returned zero results for bundleId=\(probeCase.bundleID) "
                    + "in \(probeCase.region) — delisted, or the bundle id changed",
                endpointHost: "apps.apple.com", elapsedMs: elapsed())
        }

        let pageShape: AppStorePageShapeCheck
        do {
            switch probeCase.route {
            case .nativeMac, .iosOnMac:
                pageShape = try await source.verifyVersionPageShape(
                    trackId: probeCase.trackId, region: probeCase.region)
            case .wrappedIOS:
                pageShape = try await source.verifyMacCompatPageShape(
                    trackId: probeCase.trackId, region: probeCase.region)
            }
        } catch {
            return infra("page fetch threw: \(error)")
        }

        var trackViewCheck: AppStoreProbeObservation.TrackViewCheck?
        if probeCase.route == .nativeMac {
            do {
                if let url = try await source.verifyTrackViewURL(
                    bundleID: probeCase.bundleID, region: probeCase.region) {
                    let hostOK = url.scheme == "https" && url.host == "apps.apple.com"
                    let namesThisTrackId =
                        url.path.split(separator: "/").last == "id\(probeCase.trackId)"
                    let macMarker = (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems ?? []).contains {
                            ($0.name == "mt" && $0.value == "12")
                                || ($0.name == "platform" && $0.value == "mac")
                        }
                    let zeroRedirects = hostOK
                        ? try await source.verifyZeroRedirect(url).zeroRedirects
                        : false
                    trackViewCheck = AppStoreProbeObservation.TrackViewCheck(
                        url: url, hostOK: hostOK, zeroRedirects: zeroRedirects,
                        namesThisTrackId: namesThisTrackId, carriesMacMarker: macMarker)
                }
            } catch {
                return infra("trackViewUrl fetch threw: \(error)")
            }
        }

        let batchEntry: AppStoreLookupShape?? = batch.map { $0[probeCase.bundleID] ?? nil }

        let observation = AppStoreProbeObservation(
            single: single, pageShape: pageShape, trackViewCheck: trackViewCheck, batchEntry: batchEntry)
        let verdict = classifyAppStore(probeCase, observation)
        return Finding(
            recipeID: probeCase.recipeID, registry: .appStore, bundleID: probeCase.bundleID,
            channel: probeCase.route.rawValue, status: verdict.status, version: nil,
            warnings: verdict.warnings, endpointHost: "apps.apple.com", elapsedMs: elapsed())
    }

    /// The five checks the design brief calls for, run against one case's
    /// already-fetched answers. Pure — no I/O — so it can be unit-tested
    /// directly against fixture `AppStoreProbeObservation` values.
    ///
    ///  1. `single.kind`/`single.trackId` match what the registry declared.
    ///  2/3. `pageShape` — the product page the declared route depends on
    ///     still carries the JSON shape `extractMacVersionInfo`/
    ///     `extractMacCompatible` parses.
    ///  4. (native-Mac cases only) `trackViewCheck` — `trackViewUrl` is still
    ///     an `https://apps.apple.com` URL reachable with zero redirects.
    ///  5. `batchEntry` — a batched lookup agrees with the single lookup on
    ///     `kind`/`trackId`. Never compared on version, which two lookups in
    ///     the same minute can legitimately disagree on (WhatsApp, measured
    ///     2026-09-04 — see `MacAppStoreProbeRegistry`).
    static func classifyAppStore(
        _ probeCase: MacAppStoreProbeCase, _ observation: AppStoreProbeObservation
    ) -> (status: FindingStatus, warnings: [String]) {
        // Escalate-only: a later check must never downgrade an earlier one's
        // verdict.
        var status: FindingStatus = .ok
        func escalate(_ candidate: FindingStatus) {
            let order: [FindingStatus] = [.ok, .warn, .infra, .broken]
            if order.firstIndex(of: candidate)! > order.firstIndex(of: status)! { status = candidate }
        }
        var warnings: [String] = []
        let single = observation.single

        // 1. kind/trackId drift silently reroutes
        //    `MacAppStoreSource.resolve(result:app:region:)` to a different
        //    branch than the one this case exercises.
        if single.kind != probeCase.expectedKind {
            escalate(.broken)
            warnings.append(
                "kindMismatch: registry declares \(probeCase.expectedKind), lookup answered "
                    + "\(single.kind ?? "nil") — this app now routes to a different resolve() branch")
        }
        if single.trackId != probeCase.trackId {
            escalate(.broken)
            warnings.append(
                "trackIdMismatch: registry has \(probeCase.trackId), lookup answered "
                    + "\(single.trackId.map(String.init) ?? "nil")")
        }

        // 2/3. The product-page shape the declared route's scrape depends on.
        switch observation.pageShape {
        case .reachable(let found):
            if !found {
                escalate(.broken)
                switch probeCase.route {
                case .nativeMac, .iosOnMac:
                    warnings.append(
                        "versionShelfNotFound: page fetched fine, but extractMacVersionInfo found no "
                            + "mostRecentVersion shelf — the parser and the live page have drifted apart")
                case .wrappedIOS:
                    warnings.append(
                        "compatFlagNotFound: page fetched fine, but extractMacCompatible found no "
                            + "isIOSBinaryMacOSCompatible flag")
                }
            }
        case .unreachable(let code):
            escalate(.infra)
            warnings.append(
                "pageUnreachable: could not fetch the App Store product page"
                    + (code.map { " (HTTP \($0))" } ?? ""))
        }

        // 4. trackViewUrl's zero-redirect premise — only present at all for
        //    the route that actually trusts it (`nativeMacVersion`'s
        //    `validatedProductPageURL` call).
        if let trackViewCheck = observation.trackViewCheck {
            if !trackViewCheck.hostOK {
                escalate(.broken)
                warnings.append(
                    "trackViewUrlHostChanged: \(trackViewCheck.url.absoluteString) is no longer an "
                        + "https apps.apple.com URL — validatedProductPageURL will reject it and fall "
                        + "back to the constructed URL, paying its redirect every time")
            } else if !trackViewCheck.namesThisTrackId {
                escalate(.warn)
                warnings.append(
                    "trackViewUrlNoLongerNamesThisId: \(trackViewCheck.url.absoluteString) does not "
                        + "end in id\(probeCase.trackId) — validatedProductPageURL rejects it and "
                        + "falls back to the constructed URL, paying its redirect every time")
            } else if !trackViewCheck.carriesMacMarker {
                escalate(.warn)
                warnings.append(
                    "trackViewUrlLostItsMacMarker: \(trackViewCheck.url.absoluteString) carries "
                        + "neither mt=12 nor platform=mac — validatedProductPageURL rejects it and "
                        + "falls back to the constructed URL, paying its redirect every time")
            } else if !trackViewCheck.zeroRedirects {
                // Not `.broken`: `validatedProductPageURL` already falls back
                // safely when this URL fails the check it does at request
                // time — this only means A2 quietly stopped saving the
                // redirect it exists to save.
                escalate(.warn)
                warnings.append(
                    "trackViewUrlNowRedirects: following it no longer lands with zero redirects "
                        + "— A2's saved-301 premise no longer holds for this app")
            }
        }

        // 5. batch ≡ single, on SHAPE only — never on version.
        if let batchEntry = observation.batchEntry {
            if batchEntry != single {
                escalate(.broken)
                warnings.append(
                    "batchDisagreesWithSingle: batched lookup answered kind="
                        + "\(batchEntry?.kind ?? "nil")/trackId=\(batchEntry?.trackId.map(String.init) ?? "nil"), "
                        + "single lookup answered kind=\(single.kind ?? "nil")/trackId="
                        + "\(single.trackId.map(String.init) ?? "nil") — A3's negative-cache premise "
                        + "no longer holds")
            }
        }

        return (status, warnings)
    }
}

/// What one live probe learned about a case — fetch only, no verdict. See
/// `Verify.classifyAppStore(_:_:)`.
struct AppStoreProbeObservation: Sendable {
    let single: AppStoreLookupShape
    let pageShape: AppStorePageShapeCheck
    /// nil for routes that don't trust `trackViewUrl` (only `.nativeMac` does).
    let trackViewCheck: TrackViewCheck?
    /// Outer optional: did the batch lookup run at all (nil = it failed to
    /// fetch, or this sweep never made one — check 5 is skipped). Inner
    /// optional: what it answered for THIS bundle id (nil = the store didn't
    /// have it) — same convention `AppStoreLookupCache` uses.
    let batchEntry: AppStoreLookupShape??

    struct TrackViewCheck: Sendable {
        let url: URL
        let hostOK: Bool
        let zeroRedirects: Bool
        /// Mirrors the OTHER two conditions `validatedProductPageURL` applies.
        /// Host and zero-redirects alone left two thirds of the guard
        /// unmonitored: a `trackViewUrl` that lost its `mt=12` stays on
        /// apps.apple.com and stays zero-redirect, so this check would have
        /// gone on passing while production rejected every URL and silently
        /// paid the 301 the optimisation exists to save.
        let namesThisTrackId: Bool
        let carriesMacMarker: Bool
    }
}
