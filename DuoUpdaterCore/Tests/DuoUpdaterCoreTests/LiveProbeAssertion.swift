import Testing
import Foundation
@testable import DuoUpdaterCore

/// Tolerate the network, not the recipe.
///
/// The live channel tests used to read `if let v = try await source
/// .latestVersion(for: app) { … }` — which passes when the probe returns
/// nothing, and a probe returns nothing for *every* reason including the one
/// these tests exist to catch. A vendor rewriting their download page turned
/// each of these into a no-op assertion that still reported green. Two of the
/// three recipe fixes shipped on 2026-08-08 were in recipes covered here.
///
/// So: a transport error or a 5xx is the vendor's server having a bad minute and
/// is skipped out loud; anything that means "the recipe can no longer read this
/// page" fails, as does a probe that resolves nothing without saying why.
enum LiveProbe {

    /// Probe `app` and run `check` on the version, unless the failure was the
    /// network's fault.
    ///
    /// - Parameter mustHaveRecipe: when true (the default), a source that does
    ///   not apply at all — no recipe for the bundle id, or none for the app's
    ///   channel — fails. Every caller here is asserting a specific recipe's
    ///   behaviour, so "there is no such recipe any more" is a regression, and
    ///   the old form could not see it: not-applicable and broken were the same
    ///   nil.
    static func check(
        _ app: InstalledApp,
        source: VendorProbeSource = VendorProbeSource(),
        mustHaveRecipe: Bool = true,
        _ label: String,
        _ check: (String) -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        guard let outcome = await source.probeDiagnostic(for: app) else {
            if mustHaveRecipe {
                let message = "\(label): no vendor recipe applies to "
                    + "\(app.bundleID ?? "?") on channel \(app.releaseChannel.rawValue)"
                    + " — the recipe or its channel gate is gone"
                Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
            }
            return
        }
        if let failure = outcome.failure {
            switch failure.classification {
            case .infra:
                // The vendor's server, not our pattern. Announced rather than
                // silent so a permanently-unreachable host doesn't read as a
                // healthy run forever.
                print("   ~ \(label): skipped, \(failure.kind) — \(failure.detail)")
                return
            case .notApplicable:
                if mustHaveRecipe {
                    Issue.record(
                        Comment(rawValue: "\(label): probe reports not-applicable — \(failure.detail)"),
                        sourceLocation: sourceLocation)
                }
                return
            case .recipe:
                Issue.record(
                    Comment(rawValue: "\(label): \(failure.kind) — \(failure.detail)"),
                    sourceLocation: sourceLocation)
                return
            }
        }
        guard let version = outcome.remote?.shortVersion else {
            Issue.record(
                Comment(rawValue: "\(label): the probe resolved no version and reported no failure"),
                sourceLocation: sourceLocation)
            return
        }
        check(version)
    }

    /// The whole resolved `RemoteVersion`, for tests that assert on the install
    /// plan (installer kind, headers, download URL) rather than the version
    /// string. Returns nil **only** when the vendor's server was at fault;
    /// anything recipe-level has already been recorded as a failure, so a caller
    /// can `guard … else { return }` without hiding a break.
    ///
    /// This is the opposite fix to `check`: these tests used to record an issue
    /// on any nil, which made them fail on a transport blip too.
    static func remote(
        _ app: InstalledApp,
        source: VendorProbeSource = VendorProbeSource(),
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> RemoteVersion? {
        guard let outcome = await source.probeDiagnostic(for: app) else {
            let message = "\(label): no vendor recipe applies to \(app.bundleID ?? "?")"
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
            return nil
        }
        if let failure = outcome.failure {
            if failure.classification == .infra {
                print("   ~ \(label): skipped, \(failure.kind) — \(failure.detail)")
            } else {
                Issue.record(
                    Comment(rawValue: "\(label): \(failure.kind) — \(failure.detail)"),
                    sourceLocation: sourceLocation)
            }
            return nil
        }
        guard let remote = outcome.remote else {
            Issue.record(
                Comment(rawValue: "\(label): resolved nothing and reported no failure"),
                sourceLocation: sourceLocation)
            return nil
        }
        return remote
    }

    /// The resolved version, or nil when the network was at fault — for the
    /// tests that compare two channels against each other rather than checking
    /// one in isolation.
    static func version(
        _ app: InstalledApp,
        source: VendorProbeSource = VendorProbeSource(),
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> String? {
        var resolved: String?
        await check(app, source: source, label, { resolved = $0 },
                    sourceLocation: sourceLocation)
        return resolved
    }

    /// An installed-app fixture for a recipe under test. The version is a
    /// placeholder: these tests assert what the *vendor* reports, never a
    /// comparison against a local install.
    static func app(
        _ name: String, _ bundleID: String, channel: ReleaseChannel = .stable,
        installedVersion: String = "0.0.0"
    ) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: bundleID,
            shortVersion: installedVersion, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(name).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: channel)
    }
}
