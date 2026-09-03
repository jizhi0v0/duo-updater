import Foundation
import DuoUpdaterCore

/// What earlier passes proved about a copy's release channel.
///
/// A protocol rather than `ResolvedChannelStore.Snapshot` itself so the assembly
/// below can be exercised without a `resolved-channels.json` on disk: `Snapshot`
/// decodes a file and drops every entry whose path is not actually there
/// (`ResolvedChannelStore.load`), so a fixture would have to mint real bundles.
protocol ChannelProofSource {
    func provenChannel(for app: InstalledApp) -> ReleaseChannel?
}

extension ResolvedChannelStore.Snapshot: ChannelProofSource {
    func provenChannel(for app: InstalledApp) -> ReleaseChannel? {
        ResolvedChannelStore.provenChannelSnapshot(for: app, in: self)
    }
}

/// Builds the rows a disk scan produces: the ones nothing has checked yet, and
/// the merge of a fresh scan onto the rows already on screen.
///
/// Lives outside `AppListModel` because this is the code that has been got wrong
/// most often — four of the defects found reviewing the channel-store change were
/// here, each one compiling and each one passing `make test`, because
/// `App/project.yml` had no test target over it. It is a plain enum of static
/// functions with no UI, no `Preferences` and no `AppListModel` so that the test
/// target can compile this one file instead of the whole app.
///
/// Keep it that way: if this file ever needs SwiftUI or `AppListModel`, the test
/// target stops building — which is the intended failure, not an obstacle to
/// route around.
enum ScanRowAssembly {
    /// A row for a copy nothing has checked in this process.
    ///
    /// Not `UpdateResult(app:remote:status:)`: `provenChannel` has a default, so
    /// omitting it compiles, and for an app whose bundle cannot name its own
    /// channel (UTM) that field is the only thing holding the row's channel
    /// before — or after a failure, instead of — a check. A bare row repaints a
    /// Beta row as Stable and files its notes under the wrong cache key. Every
    /// site that needs an unchecked row goes through here so the omission has
    /// nowhere left to happen.
    static func unchecked(_ app: InstalledApp, proofs: some ChannelProofSource) -> UpdateResult {
        UpdateResult(
            app: app, remote: nil, status: .unknown,
            provenChannel: proofs.provenChannel(for: app))
    }

    static func unchecked(_ apps: [InstalledApp], proofs: some ChannelProofSource) -> [UpdateResult] {
        apps.map { unchecked($0, proofs: proofs) }
    }

    /// Merge a fresh disk scan onto the rows already on screen, carrying each
    /// app's prior status/remote forward (re-evaluated against the new on-disk
    /// version) so a rescan doesn't blank out what we already knew. Shared by
    /// `refreshLocal` (the network-free rescan) and the in-flight `performRefresh`
    /// (so the sidebar holds the menu bar's data instead of flashing `.unknown`
    /// rows during a re-check). Apps new since the last scan come in unchecked.
    static func merged(
        _ found: [InstalledApp], prior: [UpdateResult], proofs: some ChannelProofSource
    ) -> [UpdateResult] {
        let byID = Dictionary(prior.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return found.map { app -> UpdateResult in
            guard let was = byID[app.id] else { return unchecked(app, proofs: proofs) }
            // A rescan re-derives the row's VERDICT. It must not re-derive the
            // row's IDENTITY. `carriedForward` is in Core and has tests; a version
            // gate written at the call site covered `provenChannel` and missed
            // that the same claim also rides on the carried `remote`, so the rule
            // does not live here.
            func carrying(_ remote: RemoteVersion?, _ status: UpdateStatus) -> UpdateResult {
                was.carriedForward(
                    onto: app, remote: remote, status: status,
                    proven: proofs.provenChannel(for: app))
            }
            // Re-derive status from the cached remote against the fresh on-disk
            // version. With no remote (App Store / Toolbox / unknown) keep what we
            // had, just refreshed to the new bundle info.
            guard let remote = was.remote else {
                return carrying(nil, was.status)
            }
            // A Toolbox row can't be re-run through `evaluate` (its verdict is a
            // Toolbox build compare, not a compare against `shortVersion`), but it
            // must still settle when Toolbox installs the update itself between our
            // checks — otherwise the cached "update available" stands beside the
            // freshly-rescanned version, reading "262.132.21 → 262.132.21".
            if remote.sourceName == "Toolbox" {
                return carrying(remote, UpdateChecker.evaluateToolbox(
                    cached: was.status, installed: app, remote: remote))
            }
            // TestFlight owns its betas' status (its own cache, not a version
            // compare) — keep it; don't re-evaluate.
            guard remote.sourceName != "TestFlight" else {
                return carrying(remote, was.status)
            }
            return carrying(remote, UpdateChecker.evaluate(installed: app, remote: remote))
        }
    }
}
