import Foundation

/// The App Store install pre-flight: whether driving the store can be skipped
/// because the bundle on disk already carries the offered version.
///
/// Both App Store routes re-read the bundle right before they drive the store,
/// because the offer can go stale while the row waits at the single-slot store
/// gate — App Store's own background updater may land the update first. On the
/// product page (mas or AX) a stale drive is a doomed `mas install --force` / AX
/// redrive. On the **Updates list** — the region-locked route, which matches the
/// app's row by name and presses its button — it is worse: the settled row has
/// moved to "Updated Recently" and its button reads **Open**, so the press
/// launches the app instead of updating it (#328), and `driveToCompletion` then
/// spends its ~24s idle budget before reporting a failure.
///
/// This type is only the on-disk half; the caller pairs it with a `mas outdated`
/// veto that can still force the drive (see `AppListModel.performInstall`).
public enum AppStoreInstallPreflight {

    /// True when `onDisk` is already at, or past, `target`.
    ///
    /// `!isNewer(target, than: onDisk)` rather than
    /// ``VersionComparator/hasReached(_:disk:)``, deliberately: this is the
    /// predicate the product-page pre-flight has always used, and it fails
    /// toward "already current". `hasReached` needs positive evidence that the
    /// disk got there, so it answers "not yet" for a pair that is non-empty but
    /// shares no comparable field (a target carrying only a build, a disk
    /// carrying only a marketing string). This predicate skips there, and the
    /// caller's `mas outdated` veto is the second opinion for the product route.
    ///
    /// An *empty* side is different and never skips: with nothing to compare at
    /// all (`VersionSide()` or no remote), the answer is false and the caller
    /// drives the store as it always did.
    public static func bundleAlreadyAt(target: VersionSide?, onDisk: VersionSide) -> Bool {
        guard let target, !target.isEmpty, !onDisk.isEmpty else { return false }
        return !VersionComparator.isNewer(target, than: onDisk)
    }
}
