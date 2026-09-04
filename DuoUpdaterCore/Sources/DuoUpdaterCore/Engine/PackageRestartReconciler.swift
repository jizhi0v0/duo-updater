import Foundation

/// What a staged package needs to say about itself for the reconciler to decide.
///
/// Deliberately not the App's `StagedPackage`, which also carries the download
/// URL and the persistence fields: the decision reads exactly two things, and a
/// narrow input is what lets a test state a case in one line.
public struct StagedPackageFacts: Sendable, Equatable {
    public var versionSide: VersionSide
    public var stagedAt: Date

    public init(versionSide: VersionSide, stagedAt: Date) {
        self.versionSide = versionSide
        self.stagedAt = stagedAt
    }
}

/// The outcome of one reconciliation pass. Every field is a decision; the caller
/// performs the effects (notify, drop the staged entry, persist).
public struct PackageRestartReconciliation: Sendable, Equatable {
    /// Rows that should show a Relaunch affordance and keep the badge lit.
    public var pending: Set<String>
    /// Staged entries that are fully done and should be dropped.
    public var settled: [String]
    /// Rows to announce, once each — already folded into `notified`.
    public var toNotify: [String]
    /// The notify-once guard as it should be after this pass.
    public var notified: Set<String>
}

/// Decide, for every staged package, whether its install has landed, whether a
/// stale copy is still running, and whether this is the first pass that can say
/// so.
///
/// Split out of `AppListModel.reconcilePackageRestarts` because the rules here
/// are one-liners with sharp edges and nothing executed them: a pass that cannot
/// see a bundle must decide NOTHING, a pending row that was already lit must
/// stay lit, and the notify-once guard must survive a row falling out of
/// `pending` for a single pass. Each of those is one line, and each of them is a
/// user-visible defect when it is the wrong line.
public enum PackageRestartReconciler {

    /// - Parameters:
    ///   - staged: staged packages by row id (the install path).
    ///   - onDisk: the apps THIS scan found, by row id. An id missing here is a
    ///     blind pass, not a deletion.
    ///   - launchDates: launch dates of running copies, by resolved bundle path.
    ///   - previouslyPending: the badge state going in.
    ///   - previouslyNotified: the notify-once guard going in.
    public static func reconcile(
        staged: [String: StagedPackageFacts],
        onDisk: [String: InstalledApp],
        launchDates: [String: [Date]],
        previouslyPending: Set<String>,
        previouslyNotified: Set<String>
    ) -> PackageRestartReconciliation {
        // Nothing staged: no badge, and no guard to keep. Both sets are dropped
        // rather than intersected, so a cleared queue cannot leave a row lit.
        guard !staged.isEmpty else {
            return PackageRestartReconciliation(
                pending: [], settled: [], toNotify: [], notified: [])
        }

        var pending: Set<String> = []
        var settled: [String] = []
        var toNotify: [String] = []
        var notified = previouslyNotified

        // Sorted so a pass is reproducible. The ids are independent of each
        // other — every branch below reads and writes only its own id — so the
        // order is free to be deterministic, and a test that asserts on
        // `settled` should not have to sort it first.
        for id in staged.keys.sorted() {
            guard let package = staged[id] else { continue }
            guard let app = onDisk[id] else {
                // The row is missing from THIS scan — a bundle can be briefly
                // unreadable while Installer swaps it. Decide nothing from a
                // blind pass: carry a restart that was already pending so one
                // missed scan cannot drop the badge or let the staged entry be
                // reclaimed. A genuinely deleted app is reclaimed later by the
                // file-existence backstop in the caller's prune.
                if previouslyPending.contains(id) { pending.insert(id) }
                continue
            }
            let key = app.path.resolvingSymlinksInPath().path
            switch PackageRestartState.resolve(
                onDiskVersion: app.versionSide,
                stagedVersion: package.versionSide,
                stagedAt: package.stagedAt,
                runningLaunchDates: launchDates[key] ?? [],
                buildIsDerived: AppScanner.buildVersionIsOverridden(bundleID: app.bundleID)
            ) {
            case .pending:
                // Not landed. Normally there is no badge yet; but if one was
                // already lit (it landed on an earlier pass) and the version
                // momentarily reads old — a partial `package.json` read
                // mid-swap — carry it rather than flickering the badge off and
                // re-announcing on the next good pass.
                if previouslyPending.contains(id) { pending.insert(id) }
            case .readyToRestart:
                pending.insert(id)
                if notified.insert(id).inserted { toNotify.append(id) }
            case .settled:
                // Landed with nothing stale running (never opened, or already
                // relaunched). Done — drop the re-open entry.
                settled.append(id)
            }
        }

        // Release the notify-once guard ONLY when a restart genuinely resolves
        // (settled, or its staged entry is gone) — never merely because an id
        // fell out of `pending` for one pass, which would let the same landing
        // announce itself again.
        notified.formIntersection(Set(staged.keys).subtracting(settled))

        return PackageRestartReconciliation(
            pending: pending, settled: settled, toNotify: toNotify, notified: notified)
    }
}

/// The "from" side of a restart line, as the user should read it.
///
/// `lsappinfo` only exposes the running process's *build* (e.g. "3965"), so a
/// bare restart line reads as a mystery number with its marketing version lost.
/// The marketing half is recovered from one of two records, in this order:
///
///   1. the rollback backup written right before we swapped (our own installs),
///   2. the build→marketing history captured when we scanned that build before
///      it was swapped out (apps that updated through their own updater).
///
/// Both survive our relaunches. The marketing half is left nil when it adds
/// nothing — nothing recovered it, or it is the build over again — which is
/// exactly the case where the target's build has to stay for the two sides to be
/// comparable at all.
public enum RestartLine {
    public static func fromSide(
        runningBuild: String?,
        backupMarketing: String?,
        recoveredMarketing: String?
    ) -> VersionSide? {
        guard let runningBuild else { return nil }
        let build = UpdateResult.strippingBuildPrefix(runningBuild)
        let marketing = backupMarketing ?? recoveredMarketing
        return VersionSide(marketing: marketing == build ? nil : marketing, build: build)
    }
}

/// Which staged package entries are still worth keeping.
///
/// A staged entry outlives its download: the file can be swept by the system
/// while the entry still has a job to do (keeping the Restart badge lit until
/// the user relaunches). So this is not "is the file there" — it is four rules,
/// and three of them keep an entry whose file is gone.
///
/// Split out of `AppListModel.pruneStagedPackages` for the reason its own
/// comment gave away: it decided "has this landed" with its own copy of the
/// expression in `PackageRestartState`, kept in step by a comment saying so.
/// Both now call `PackageRestartState.hasLanded`, and a test asserts the two
/// agree — including for the derived-build apps where the copies were most
/// likely to diverge.
public enum StagedPackagePrune {

    /// - Parameters:
    ///   - staged: staged packages by row id.
    ///   - onDisk: the apps THIS scan found. An id missing here is a blind pass.
    ///   - offered: the version each row's source currently offers, by row id.
    ///     Absent when the source said nothing, or said nothing usable.
    ///   - pending: rows whose landed package is waiting on a relaunch.
    ///   - downloadExists: whether the staged download is still on disk, by row
    ///     id. A closure rather than a precomputed set so the `pending`
    ///     short-circuit below keeps costing no syscall — the entries that are
    ///     certain to be kept never ask.
    /// - Returns: the ids to keep.
    public static func keep(
        staged: [String: StagedPackageFacts],
        onDisk: [String: InstalledApp],
        offered: [String: VersionSide],
        pending: Set<String>,
        downloadExists: (String) -> Bool
    ) -> Set<String> {
        var kept: Set<String> = []
        for id in staged.keys.sorted() {
            guard let package = staged[id] else { continue }

            // A landed package that left a stale copy running is no longer "on
            // offer" (the app is now current) and its download may have been
            // swept, yet its entry must survive to keep the Restart badge lit
            // until the app is relaunched. The reconciler retires it once it
            // settles. Checked first, so this costs no filesystem call.
            if pending.contains(id) {
                kept.insert(id)
                continue
            }

            guard let app = onDisk[id] else {
                // Row missing from THIS scan (bundle mid-swap): don't reclaim on
                // a blind pass — a genuinely deleted app is still bounded by the
                // file backstop once its download is swept.
                if downloadExists(id) { kept.insert(id) }
                continue
            }

            // Landed: keep, so restart tracking survives a one-scan flicker of
            // the launch-time signal even if the download was swept.
            if PackageRestartState.hasLanded(
                onDiskVersion: app.versionSide, stagedVersion: package.versionSide,
                buildIsDerived: AppScanner.buildVersionIsOverridden(bundleID: app.bundleID)
            ) {
                kept.insert(id)
                continue
            }

            // Otherwise it is only usable while still on offer AND re-openable.
            // Both halves matter: an entry for a version no longer offered would
            // install something the source has moved past, and one whose download
            // is gone has nothing to install at all.
            let stillOffered = offered[id].map {
                VersionComparator.isSame($0, as: package.versionSide)
            } == true
            if stillOffered && downloadExists(id) { kept.insert(id) }
        }
        return kept
    }
}
