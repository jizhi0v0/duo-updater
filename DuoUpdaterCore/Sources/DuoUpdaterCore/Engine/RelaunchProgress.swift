import Foundation

/// What has to become true on disk before a quit app is brought back, and
/// whether it has.
///
/// **Why this lives in Core.** It used to be a nested enum inside
/// `AppListModel`, which has no test target — `App/project.yml` declares four
/// targets and none of them are tests — so nothing ever executed it. Both of its
/// version comparisons were wrong in the same way and neither could be caught:
/// `.stagedSwap` compared a marketing string against a marketing string, so for
/// an app that ships many builds under one name (`Amp` shipped ten builds called
/// "1.0" on 2026-08-28) `disk == target` was true *before* the swap, and the
/// relaunch poll's own predicate was never true *after* it. Moving the decision
/// here is the fix; `RelaunchProgressTests` is what keeps it fixed.
public enum RelaunchLanding: Sendable, Equatable {

    /// Nothing to wait for: the new build was swapped in *before* we asked for
    /// the quit (our own in-place install), so the quit was the last step.
    /// Relaunch as soon as the app is actually gone.
    case applied

    /// The app's own updater swaps on quit. Launch only once disk shows this
    /// staged build or newer — never before, or ShipIt aborts with "App Still
    /// Running Error". If it never lands, leave the app quit: the marker's
    /// promise was that specific build.
    case stagedSwap(to: VersionSide)

    /// The app's own updater swaps on its next *launch* (Spotify — see
    /// `StagedApplyTrigger.launch`). The opposite order from `.stagedSwap`:
    /// launch as soon as the app is gone, because nothing lands until we do, then
    /// wait for disk to reach this build. Waiting first is a guaranteed timeout
    /// that leaves the app closed.
    case stagedOnLaunch(to: VersionSide)

    /// App Store swaps once the app is gone (we quit it ourselves on the user's
    /// Relaunch tap). Launch once disk moves past this pre-install version — and
    /// launch anyway if it never does: we closed the user's app for an update, so
    /// it comes back whether or not the store delivered one.
    case appStoreSwap(past: VersionSide)

    /// The landing for a build the app's own updater has staged — the one place
    /// that turns `StagedApplyTrigger` into an order of operations.
    public static func staged(_ staged: StagedSelfUpdate) -> RelaunchLanding {
        switch staged.appliesOn {
        case .quit: return .stagedSwap(to: staged.versionSide)
        case .launch: return .stagedOnLaunch(to: staged.versionSide)
        }
    }

    /// True once what is on disk satisfies this landing.
    ///
    /// Takes the whole `VersionSide` rather than a marketing string, because the
    /// caller reads both fields from one `Info.plist` anyway and throwing the
    /// build away is what broke this. `hasReached` treats "same build" and "a
    /// newer build" alike: an app may have moved past the build we were waiting
    /// for while we waited.
    public func isSatisfied(byDisk disk: VersionSide) -> Bool {
        switch self {
        case .applied:
            return true
        case .stagedSwap(let target), .stagedOnLaunch(let target):
            guard !disk.isEmpty else { return false }
            return VersionComparator.hasReached(target, disk: disk)
        case .appStoreSwap(let baseline):
            guard !disk.isEmpty else { return false }
            // Strictly newer, unlike `.stagedSwap`: the baseline is what was
            // installed BEFORE, so equality means the store delivered nothing.
            return VersionComparator.isNewer(disk, than: baseline)
        }
    }

    /// What an armed marker becomes when the staging area has moved on, or nil
    /// when it should be dropped.
    ///
    /// A `.stagedSwap` marker is armed when the app refused to quit (a save
    /// prompt) and lives for `quitHandoffMaxAge` — ten minutes — waiting for the
    /// user to answer. The sweep used to drop it whenever the staged build was no
    /// longer the exact one it was armed against, which conflates two cases:
    ///
    ///   * **staging is gone** — nothing left to land, so the marker is dead. Drop.
    ///   * **staging moved** — the vendor shipped another build inside that ten
    ///     minutes. The app still has a pending swap and the user still asked for
    ///     a relaunch, so abandoning it strands the app closed after the swap,
    ///     which is the exact failure the marker exists to prevent. Amp published
    ///     ten builds in one day; a ten-minute window catching one of them is not
    ///     a corner case.
    ///
    /// Dropping was not even conservative: `hasReached` accepts a build newer than
    /// the target, so a marker left pointing at the old build would have relayed
    /// correctly anyway. Re-targeting just keeps the landing test exact.
    public func retargeted(nowStaged: VersionSide?) -> RelaunchLanding? {
        switch self {
        case .stagedSwap, .stagedOnLaunch:
            guard let nowStaged, !nowStaged.isEmpty else { return nil }
            if case .stagedOnLaunch = self { return .stagedOnLaunch(to: nowStaged) }
            return .stagedSwap(to: nowStaged)
        case .applied, .appStoreSwap:
            return self
        }
    }

    /// Whether this landing has to poll disk *before* the app is launched.
    public var waitsForDisk: Bool {
        switch self {
        case .applied, .stagedOnLaunch: return false
        case .stagedSwap, .appStoreSwap: return true
        }
    }

    /// Whether the landing only happens once we have launched the app, so the
    /// disk poll comes after the launch instead of before it.
    public var landsAfterLaunch: Bool {
        if case .stagedOnLaunch = self { return true }
        return false
    }

    /// Whether the app is reopened even if the landing never happens. Only the
    /// App Store case: we closed the user's app ourselves, so it comes back
    /// regardless of what the store did.
    public var launchesWithoutLanding: Bool {
        if case .appStoreSwap = self { return true }
        return false
    }
}

/// Whether an app's own updater has finished swapping the bundle we are waiting
/// on.
public enum RelaunchProgress {

    /// True once the bundle on disk has moved past what was installed when we
    /// asked the app to quit.
    ///
    /// The predicate behind the Relaunch spinner. It compared
    /// `shortVersion ?? buildVersion` on both sides, which for a frozen-marketing
    /// app is `isNewer("1.0", than: "1.0")` — false forever. Measured on Amp
    /// 2026-08-28: the spinner ran its full 900 ticks (189 s observed) and then
    /// logged `applied=false` for a swap that had already succeeded, leaving the
    /// row apparently stuck while the app had in fact relaunched on the new build.
    ///
    /// Fails closed on an unreadable bundle: an empty side is not proof of
    /// anything, and reporting a landing that did not happen would reopen the app
    /// mid-swap.
    /// - Parameters:
    ///   - old: what was installed when the quit was asked for.
    ///   - disk: what is there now.
    ///   - buildIsDerived: whether `old`'s build came from `AppScanner`'s
    ///     override rather than the bundle's own `CFBundleVersion`. When it did,
    ///     the two sides are not in one namespace and the build is dropped from
    ///     the comparison — DoubaoIme's real `CFBundleVersion` is a flat "1" on
    ///     every build while the scanner stores the vendor's own number, so
    ///     comparing the stored value against a raw plist read would answer "not
    ///     landed" forever, which is the failure this function exists to end.
    ///     Latent today (neither overridden app has an updater
    ///     `SelfUpdaterStaging` recognises) and stated rather than left to be
    ///     rediscovered.
    public static func hasLanded(
        old: VersionSide, disk: VersionSide, buildIsDerived: Bool = false
    ) -> Bool {
        let old = buildIsDerived ? VersionSide(marketing: old.marketing) : old
        guard !disk.isEmpty, !old.isEmpty else { return false }
        return VersionComparator.isNewer(disk, than: old)
    }
}

/// How a Relaunch of a self-updater-staged build ended, once
/// `relaunchStagedUpdate` stops waiting — and so what the row has to say.
///
/// Before this existed the three endings looked identical on screen: the
/// spinner dropped, the row was re-read, and only `applied=false` in the log
/// told a swap that never landed apart from one that did. DuoUpdater's own
/// install path puts a red line under the row when it fails; a relaunch whose
/// updater never swapped the bundle is the same kind of failure from where the
/// user sits (they clicked, their app closed, nothing got newer).
public enum StagedRelaunchOutcome: Sendable, Equatable {
    /// Disk moved past the version installed when we asked for the quit.
    case applied
    /// The app never went down (a save prompt, a sign-in sheet). Not a failure
    /// of the updater: the swap could not start, and a quit hand-off is armed
    /// to finish the job if the user answers that window.
    case wontQuit
    /// The app quit (or, for a swap-on-launch updater, was launched to apply it)
    /// and the bundle still had not moved when the wait ran out.
    case swapDidNotLand

    /// - Parameters:
    ///   - landed: whether the on-disk version advanced during the wait.
    ///   - everQuit: whether every instance was observed gone at some tick.
    ///
    /// `landed` is asked first on purpose. Each tick of the poll reads disk
    /// before it looks at the process list and stops on a landing, so the
    /// function can end with `landed` true and `everQuit` false whenever the quit
    /// and the swap both fall between two polls. (Not measured how often that
    /// happens; the code allows it, and a bundle that moved is a success
    /// however quickly it moved.)
    public static func classify(landed: Bool, everQuit: Bool) -> StagedRelaunchOutcome {
        if landed { return .applied }
        return everQuit ? .swapDidNotLand : .wontQuit
    }
}

/// The red "didn't apply" line a failed staged relaunch left under a row, and
/// the version it was measured against.
///
/// Kept beside the text in `installErrors` for two reasons. `installErrors` has
/// other writers (every install clears or replaces it), so retraction must only
/// take down this exact text. And the thing that makes the line untrue is
/// precise — the bundle moving past `old` — whereas the generic settle rule
/// (`UpdatePolicy.settledRowIDs`, `.upToDate` only) is both too early and too
/// late here: `UpdatePolicy.actionableStaged` admits a staged build newer than
/// both the installed copy and the remote, so a Relaunch row can have status
/// `.upToDate` — the settle rule would erase the line on the very refresh that
/// follows writing it — and a row whose status is `.unknown` or `.error` after
/// a late landing would keep it until some other action on the row.
public struct StagedRelaunchFailure: Sendable, Equatable {
    public let message: String
    public let old: VersionSide
    /// The same flag the relaunch wait passed to `RelaunchProgress.hasLanded`
    /// (`AppScanner.buildVersionIsOverridden`), so the retraction counts a landing
    /// by exactly the rule the wait used when it gave up.
    public let buildIsDerived: Bool

    public init(message: String, old: VersionSide, buildIsDerived: Bool) {
        self.message = message
        self.old = old
        self.buildIsDerived = buildIsDerived
    }

    /// The ids whose failure line should come down now: still showing our text,
    /// and either the row is gone or its installed version has moved past `old`
    /// — the update landed after we stopped waiting.
    ///
    /// - Parameters:
    ///   - failures: what `relaunchStagedUpdate` recorded, by row id.
    ///   - errors: `installErrors` as it stands.
    ///   - installed: every current row's installed version, by row id. Empty
    ///     is the pre-first-scan state, not "every app vanished", and retracts
    ///     nothing.
    public static func retractable(
        _ failures: [String: StagedRelaunchFailure],
        errors: [String: String],
        installed: [String: VersionSide]
    ) -> Set<String> {
        guard !installed.isEmpty else { return [] }
        var ids: Set<String> = []
        for (id, failure) in failures where errors[id] == failure.message {
            guard let disk = installed[id] else {
                ids.insert(id)   // the app is gone from disk
                continue
            }
            // Both sides come from the scanner here, so the build would compare
            // either way; the flag is passed anyway so this agrees with the wait
            // (which read disk raw and had to drop a derived build).
            if RelaunchProgress.hasLanded(
                old: failure.old, disk: disk, buildIsDerived: failure.buildIsDerived) {
                ids.insert(id)
            }
        }
        return ids
    }
}
