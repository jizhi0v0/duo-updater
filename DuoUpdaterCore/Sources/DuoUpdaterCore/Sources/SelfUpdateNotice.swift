import Foundation

/// Whether to tell the user that Duo Updater updated itself, and to what.
///
/// Duo Updater installs its own updates silently and on purpose — it waits for the
/// machine to be idle and swaps itself without a prompt, because a tool that nags
/// you about itself is a tool that interrupts the work it exists to protect. The
/// cost of that design is that the user ends up on a version they never agreed to
/// and never saw the notes for. Every other app in their list gets a "what
/// changed" pane; ours was the one that changed under them in silence.
///
/// This is the smallest honest fix: notice the version moved, say so once, and
/// let them read it if they care.
public enum SelfUpdateNotice {

    /// The version to announce, or nil for "say nothing".
    ///
    /// Silent in three cases, each deliberate:
    ///
    ///   - **No record yet.** A fresh install, or the first launch after this
    ///     feature shipped. Nobody was updated out from under anyone, so
    ///     announcing would be a lie on day one. The caller seeds the record
    ///     instead.
    ///   - **Unchanged.** The common case, every launch.
    ///   - **Moved backwards.** A rollback, or a user running an older build on
    ///     purpose. "Updated to 0.3.40" when you just went back to it reads as a
    ///     failure of the thing that is supposed to be tracking versions
    ///     correctly. The caller reseeds so the next real update is announced.
    public static func announcement(running: String?, lastSeen: String?) -> String? {
        guard let running = running?.trimmingCharacters(in: .whitespaces), !running.isEmpty
        else { return nil }
        guard let lastSeen = lastSeen?.trimmingCharacters(in: .whitespaces), !lastSeen.isEmpty
        else { return nil }
        guard VersionComparator.compare(running, lastSeen) == .orderedDescending
        else { return nil }
        return running
    }

    /// Whether the stored record should be brought in line with the running build
    /// without announcing anything — the two silent cases above that are not simply
    /// "nothing changed".
    ///
    /// Kept separate from `announcement` so the caller cannot accidentally treat
    /// "seed it quietly" as "we already told them": seeding must happen for a fresh
    /// install (or nothing would ever be announced later), while the announced case
    /// must NOT clear the record until the user has actually seen the notes.
    public static func shouldSeedSilently(running: String?, lastSeen: String?) -> Bool {
        guard let running = running?.trimmingCharacters(in: .whitespaces), !running.isEmpty
        else { return false }
        guard let lastSeen = lastSeen?.trimmingCharacters(in: .whitespaces), !lastSeen.isEmpty
        else { return true }                                     // no record yet
        return VersionComparator.compare(running, lastSeen) == .orderedAscending  // rolled back
    }
}
