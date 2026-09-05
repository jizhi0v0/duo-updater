import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// `Verify.classifyAppStore` is the pure decision half of `duo verify`'s App
/// Store sweep (`Verify.probe` does the network half and is not exercised
/// here — see `AppStoreVerify.swift`'s doc comment for the split, which
/// mirrors `Verify.classify(_:registry:...)` for the other three sweeps).
///
/// Fixture cases are pulled FROM `MacAppStoreProbeRegistry.cases` rather than
/// hand-built here, so a case's `route`/`expectedKind` can't drift between
/// the registry and what these tests assume about it.
@Suite struct AppStoreVerifyClassificationTests {

    private func nativeMacCase() throws -> MacAppStoreProbeCase {
        try #require(MacAppStoreProbeRegistry.cases.first { $0.route == .nativeMac },
                      "the registry no longer has a .nativeMac case to test against")
    }

    private func iosOnMacCase() throws -> MacAppStoreProbeCase {
        try #require(MacAppStoreProbeRegistry.cases.first { $0.route == .iosOnMac },
                      "the registry no longer has a .iosOnMac case to test against")
    }

    private func wrappedIOSCase() throws -> MacAppStoreProbeCase {
        try #require(MacAppStoreProbeRegistry.cases.first { $0.route == .wrappedIOS },
                      "the registry no longer has a .wrappedIOS case to test against")
    }

    /// Everything answering exactly what the case declares — the baseline a
    /// single mutation is then applied to.
    private func passingObservation(for probeCase: MacAppStoreProbeCase) -> AppStoreProbeObservation {
        let single = AppStoreLookupShape(kind: probeCase.expectedKind, trackId: probeCase.trackId)
        let trackViewCheck = probeCase.route == .nativeMac
            ? AppStoreProbeObservation.TrackViewCheck(
                // Carries `mt=12` and ends in `id<trackId>` because the
                // baseline observation has to satisfy EVERY condition
                // `validatedProductPageURL` applies — a fixture that only met
                // the host check would make the two new branches of check 4
                // unreachable from here, which is the tests-measuring-the-
                // fixture trap rather than the code.
                url: URL(string: "https://apps.apple.com/us/app/x/id\(probeCase.trackId)?mt=12&uo=4")!,
                hostOK: true, zeroRedirects: true,
                namesThisTrackId: true, carriesMacMarker: true)
            : nil
        return AppStoreProbeObservation(
            single: single, pageShape: .reachable(found: true),
            trackViewCheck: trackViewCheck, batchEntry: .some(single))
    }

    // MARK: - baseline

    /// Every field agreeing with the registry is `.ok` with no warnings —
    /// the fixture every mutation below starts from.
    @Test func allFieldsAgreeingIsOK() throws {
        let probeCase = try nativeMacCase()
        let verdict = Verify.classifyAppStore(probeCase, passingObservation(for: probeCase))
        #expect(verdict.status == .ok)
        #expect(verdict.warnings.isEmpty)
    }

    // MARK: - check 1: kind / trackId

    /// Mutation: `single.kind` no longer matches `expectedKind` — the live
    /// equivalent of Apple reclassifying a listing. Verified red by hand:
    /// deleting the `single.kind != probeCase.expectedKind` branch in
    /// `classifyAppStore` (CLI/Sources/DuoKit/AppStoreVerify.swift) makes
    /// this pass with `.ok` instead of `.broken` — confirmed before writing
    /// this comment.
    @Test func kindMismatchIsBroken() throws {
        let probeCase = try nativeMacCase()
        var observation = passingObservation(for: probeCase)
        observation = AppStoreProbeObservation(
            single: AppStoreLookupShape(kind: "software", trackId: probeCase.trackId),
            pageShape: observation.pageShape, trackViewCheck: observation.trackViewCheck,
            batchEntry: observation.batchEntry)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.contains { $0.hasPrefix("kindMismatch:") })
    }

    /// Mutation: `single.trackId` disagrees with the registry — a stale
    /// registered id, or Apple issuing a new one.
    @Test func trackIdMismatchIsBroken() throws {
        let probeCase = try nativeMacCase()
        let observation = AppStoreProbeObservation(
            single: AppStoreLookupShape(kind: probeCase.expectedKind, trackId: probeCase.trackId + 1),
            pageShape: .reachable(found: true), trackViewCheck: nil, batchEntry: nil)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.contains { $0.hasPrefix("trackIdMismatch:") })
    }

    // MARK: - check 2/3: product-page shape

    /// Mutation: the page fetched (2xx) but the production parser
    /// (`extractMacVersionInfo`) found nothing — A2's main silent-failure
    /// mode. Message differs by route (`versionShelfNotFound` vs.
    /// `compatFlagNotFound`), so this is run for all three routes.
    @Test func pageFetchedButShapeNotFoundIsBroken() throws {
        for probeCase in [try nativeMacCase(), try iosOnMacCase(), try wrappedIOSCase()] {
            var observation = passingObservation(for: probeCase)
            observation = AppStoreProbeObservation(
                single: observation.single, pageShape: .reachable(found: false),
                trackViewCheck: observation.trackViewCheck, batchEntry: observation.batchEntry)
            let verdict = Verify.classifyAppStore(probeCase, observation)
            #expect(verdict.status == .broken, "\(probeCase.bundleID)")
            let expectedPrefix = probeCase.route == .wrappedIOS ? "compatFlagNotFound:" : "versionShelfNotFound:"
            #expect(verdict.warnings.contains { $0.hasPrefix(expectedPrefix) }, "\(probeCase.bundleID)")
        }
    }

    /// Mutation: the page itself could not be fetched (transport error / non-
    /// 2xx) — infra, not broken, since nothing here accuses the parser.
    @Test func pageUnreachableIsInfraNotBroken() throws {
        let probeCase = try nativeMacCase()
        let observation = AppStoreProbeObservation(
            single: AppStoreLookupShape(kind: probeCase.expectedKind, trackId: probeCase.trackId),
            pageShape: .unreachable(httpStatus: 503), trackViewCheck: nil, batchEntry: nil)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .infra)
        #expect(verdict.warnings.contains { $0.hasPrefix("pageUnreachable:") && $0.contains("503") })
    }

    // MARK: - check 4: trackViewUrl (native-Mac only)

    /// Mutation: `trackViewUrl`'s host is no longer `apps.apple.com` —
    /// `validatedProductPageURL` would reject it. `.broken`: this is a
    /// premise changing under us, not a transient hiccup.
    @Test func trackViewUrlHostChangedIsBroken() throws {
        let probeCase = try nativeMacCase()
        var observation = passingObservation(for: probeCase)
        observation = AppStoreProbeObservation(
            single: observation.single, pageShape: observation.pageShape,
            trackViewCheck: .init(
                url: URL(string: "https://example.com/redirected")!, hostOK: false, zeroRedirects: false,
                namesThisTrackId: false, carriesMacMarker: false),
            batchEntry: observation.batchEntry)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.contains { $0.hasPrefix("trackViewUrlHostChanged:") })
    }

    /// Mutation: the host is still right, but a redirect now happens (A2's
    /// saved-301 premise erodes). `.warn`, not `.broken` — the code already
    /// falls back safely, this only says the optimization stopped paying off.
    @Test func trackViewUrlNowRedirectsIsWarnNotBroken() throws {
        let probeCase = try nativeMacCase()
        var observation = passingObservation(for: probeCase)
        observation = AppStoreProbeObservation(
            single: observation.single, pageShape: observation.pageShape,
            trackViewCheck: .init(url: observation.trackViewCheck!.url, hostOK: true, zeroRedirects: false,
                                  namesThisTrackId: true, carriesMacMarker: true),
            batchEntry: observation.batchEntry)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .warn)
        #expect(verdict.warnings.contains { $0.hasPrefix("trackViewUrlNowRedirects:") })
    }

    /// A route other than `.nativeMac` never carries a `trackViewCheck` at
    /// all (only `nativeMacVersion` trusts `trackViewUrl` — see
    /// `MacAppStoreSource.iosOnMacVersion`'s comment on why it builds its own
    /// URL instead). `nil` must not be treated as a failure.
    @Test func absentTrackViewCheckIsNotAFailure() throws {
        let probeCase = try iosOnMacCase()
        let verdict = Verify.classifyAppStore(probeCase, passingObservation(for: probeCase))
        #expect(verdict.status == .ok)
    }

    // MARK: - check 5: batch ≡ single

    /// Mutation: the batched lookup answers a DIFFERENT kind/trackId than the
    /// single lookup for the same bundle id — A3's negative-cache premise
    /// breaking. Compared on shape only: this fixture's `single` and
    /// `batchEntry` deliberately carry the SAME made-up trackId so a naive
    /// "compare versions" implementation (which this function must not have)
    /// couldn't accidentally be what's failing the test.
    @Test func batchDisagreeingWithSingleIsBroken() throws {
        let probeCase = try nativeMacCase()
        let single = AppStoreLookupShape(kind: probeCase.expectedKind, trackId: probeCase.trackId)
        let observation = AppStoreProbeObservation(
            single: single, pageShape: .reachable(found: true), trackViewCheck: nil,
            batchEntry: .some(AppStoreLookupShape(kind: "software", trackId: probeCase.trackId)))
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.contains { $0.hasPrefix("batchDisagreesWithSingle:") })
    }

    /// Mutation: the batch ran and legitimately had no entry for this bundle
    /// id (`.some(nil)`) while the single lookup found one — exactly the
    /// "an app the batch silently drops" failure #5 in the design brief
    /// describes, which would poison `AppStoreLookupCache` with a false
    /// "not found".
    @Test func batchMissingEntryWhileSingleFoundIsBroken() throws {
        let probeCase = try nativeMacCase()
        let single = AppStoreLookupShape(kind: probeCase.expectedKind, trackId: probeCase.trackId)
        let observation = AppStoreProbeObservation(
            single: single, pageShape: .reachable(found: true), trackViewCheck: nil,
            batchEntry: .some(nil))
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.contains { $0.hasPrefix("batchDisagreesWithSingle:") })
    }

    /// Outer nil (`batchEntry == nil`) means "the batch never ran this
    /// sweep" (a failed fetch, or a sweep that skipped it) — must be silently
    /// skipped, not treated as a mismatch. This is what makes the whole batch
    /// check additive, matching `prewarm(_:)`'s own contract.
    @Test func batchNeverRunIsNotAFailure() throws {
        let probeCase = try nativeMacCase()
        let single = AppStoreLookupShape(kind: probeCase.expectedKind, trackId: probeCase.trackId)
        let observation = AppStoreProbeObservation(
            single: single, pageShape: .reachable(found: true), trackViewCheck: nil, batchEntry: nil)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .ok)
        #expect(verdict.warnings.isEmpty)
    }

    // MARK: - escalation is order-independent and never downgrades

    /// Mutation this pins: an `escalate` that OVERWRITES instead of only
    /// ever raising the severity. A `.broken` cause (kind mismatch) and a
    /// `.warn` cause (trackViewUrl redirect regression) fire on the same
    /// case; the combined verdict must stay `.broken` however the checks are
    /// ordered inside `classifyAppStore`, and both warnings must still be
    /// reported — losing the second message would make one problem hide the
    /// other in the report. Verified red: temporarily changing
    /// `if order.firstIndex(of: candidate)! > order.firstIndex(of: status)!`
    /// to unconditional assignment (`status = candidate`) in
    /// `classifyAppStore` makes this fail because the LAST check to run
    /// (batch ≡ single, which passes here) would reset status back to `.ok`
    /// — confirmed before writing this comment.
    @Test func aBrokenCauseSurvivesALaterWarnCause() throws {
        let probeCase = try nativeMacCase()
        let observation = AppStoreProbeObservation(
            single: AppStoreLookupShape(kind: "software", trackId: probeCase.trackId),  // .broken cause
            pageShape: .reachable(found: true),
            trackViewCheck: .init(  // .warn cause, checked AFTER kind in classifyAppStore's source order
                // The id and marker conditions must PASS here: they are checked
                // before the redirect one, and this case asserts the redirect
                // warning specifically.
                url: URL(string: "https://apps.apple.com/us/app/x/id\(probeCase.trackId)?mt=12")!,
                hostOK: true, zeroRedirects: false,
                namesThisTrackId: true, carriesMacMarker: true),
            batchEntry: .some(AppStoreLookupShape(kind: "software", trackId: probeCase.trackId)))  // agrees, .ok
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.contains { $0.hasPrefix("kindMismatch:") })
        #expect(verdict.warnings.contains { $0.hasPrefix("trackViewUrlNowRedirects:") })
    }

    /// Check 4 must notice a `trackViewUrl` that stopped naming this listing.
    ///
    /// The guard in `validatedProductPageURL` grew from one condition (host) to
    /// three; this and the case below are the two that were unmonitored when
    /// it did. Without them a `trackViewUrl` that lost its id or its `mt=12`
    /// would leave every check green while production rejected it and paid the
    /// 301 on every single scrape — the optimisation silently switching itself
    /// off, which is the failure this sweep exists to catch.
    ///
    /// Mutation run: deleting the `namesThisTrackId` branch in
    /// `classifyAppStore` turns this red and leaves the rest green.
    @Test func aTrackViewUrlThatStoppedNamingThisIdWarns() throws {
        let probeCase = try nativeMacCase()
        var observation = passingObservation(for: probeCase)
        observation = AppStoreProbeObservation(
            single: observation.single, pageShape: observation.pageShape,
            trackViewCheck: .init(
                url: URL(string: "https://apps.apple.com/us/app/x/id999999?mt=12")!,
                hostOK: true, zeroRedirects: true,
                namesThisTrackId: false, carriesMacMarker: true),
            batchEntry: observation.batchEntry)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .warn)
        #expect(verdict.warnings.contains { $0.hasPrefix("trackViewUrlNoLongerNamesThisId:") })
    }

    /// Check 4 must notice a `trackViewUrl` that lost its Mac platform marker.
    ///
    /// This is the load-bearing half of the guard: one trackId serves both the
    /// iOS and the Mac product page, so the marker — not the id — is what says
    /// which one a URL points at.
    ///
    /// Mutation run: deleting the `carriesMacMarker` branch turns this red and
    /// leaves the rest green.
    @Test func aTrackViewUrlThatLostItsMacMarkerWarns() throws {
        let probeCase = try nativeMacCase()
        var observation = passingObservation(for: probeCase)
        observation = AppStoreProbeObservation(
            single: observation.single, pageShape: observation.pageShape,
            trackViewCheck: .init(
                url: URL(string: "https://apps.apple.com/us/app/x/id\(probeCase.trackId)?uo=4")!,
                hostOK: true, zeroRedirects: true,
                namesThisTrackId: true, carriesMacMarker: false),
            batchEntry: observation.batchEntry)
        let verdict = Verify.classifyAppStore(probeCase, observation)
        #expect(verdict.status == .warn)
        #expect(verdict.warnings.contains { $0.hasPrefix("trackViewUrlLostItsMacMarker:") })
    }
}
