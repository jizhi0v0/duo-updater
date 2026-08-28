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

    /// App Store swaps once the app is gone (we quit it ourselves on the user's
    /// Relaunch tap). Launch once disk moves past this pre-install version — and
    /// launch anyway if it never does: we closed the user's app for an update, so
    /// it comes back whether or not the store delivered one.
    case appStoreSwap(past: VersionSide)

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
        case .stagedSwap(let target):
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
        guard case .stagedSwap = self else { return self }
        guard let nowStaged, !nowStaged.isEmpty else { return nil }
        return .stagedSwap(to: nowStaged)
    }

    /// Whether this landing has to poll disk at all.
    public var waitsForDisk: Bool {
        if case .applied = self { return false }
        return true
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
