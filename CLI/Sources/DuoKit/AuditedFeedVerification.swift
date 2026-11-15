import Foundation
import DuoUpdaterCore

extension InstallVerify {
    /// Enumerated from reviewed public audit documents, never the runner's
    /// installed apps. The interactive source stack continues to use bundles.
    static func auditedTargets(
        entries: [AuditedUpdateFeeds.Entry] = AuditedUpdateFeeds.entries,
        only: [String] = [],
        previous: @Sendable (String) -> Previous? = { _ in nil },
        recordedKeys: [String: String] = [:]
    ) -> [Target] {
        entries.filter { entry in
            only.isEmpty || only.contains { selector in
                entry.recipeID.localizedCaseInsensitiveContains(selector)
                    || entry.bundleID.localizedCaseInsensitiveContains(selector)
            }
        }.map { entry in
            let registry: String
            let host: String
            let key: String?
            switch entry.source {
            case .electron(let config):
                registry = "electron"
                host = config.manifestURL?.host ?? "-"
                key = nil
            case .sparkle(let feed, let publicKey, _):
                registry = "sparkle"
                host = feed.host ?? "-"
                key = recordedKeys[entry.recipeID] ?? publicKey
            }
            return Target(
                recipeID: entry.recipeID, registry: registry, bundleID: entry.bundleID,
                probeHost: host,
                resolve: {
                    switch entry.source {
                    case .electron:
                        return await ElectronManifestSource().probeDiagnostic(for: entry.app)
                    case .sparkle:
                        return await SparkleAppcastSource().probeDiagnostic(for: entry.app)
                    }
                }, previous: previous(entry.recipeID), recordedSparkleKey: key,
                ownsResolutionFinding: true)
        }
    }

    /// Unlike vendor/GitHub targets these feeds have no separate `duo verify`
    /// registry. A missing answer therefore belongs here, rather than silently
    /// becoming an unresolved/skipped installation check.
    static func applyResolutionFailure(_ outcome: ProbeOutcome, target: Target, to item: inout Item) {
        guard target.ownsResolutionFinding else { return }
        if outcome.failure?.classification == .notApplicable {
            item.status = .skipped
            return
        }
        item.status = .failed
        item.stage = .resolve
        item.httpStatus = outcome.httpStatus
        item.resolutionIsInfra = outcome.failure?.classification == .infra
    }

    static func missingInventoryItems(
        identityIDs: Set<String>, baselineIDs: Set<String>, live: Set<String>, only: [String]
    ) -> [Item] {
        let persisted = identityIDs.union(baselineIDs.compactMap { id in
            id.hasPrefix("install:") ? String(id.dropFirst("install:".count)) : nil
        })
        return persisted.subtracting(live).sorted().compactMap { id in
            guard only.isEmpty || only.contains(where: { id.localizedCaseInsensitiveContains($0) })
            else { return nil }
            let parts = id.split(separator: ":").map(String.init)
            var item = Item(
                recipeID: id, registry: parts.first ?? "-",
                bundleID: parts.count > 1 ? parts[1] : id, probeHost: "-", status: .warn)
            item.warnings = ["inventoryEntryMissing: a previously tracked installer is absent from "
                + "the compiled inventory — restore its target or explicitly review and retire "
                + "its identity and issue state; history was preserved"]
            return item
        }
    }
}
