import Foundation
import DuoUpdaterCore

/// What a row says when `InstallCoordinator.backUp` took no copy because an
/// earlier install of the app was cut off or is still running
/// (`BackupOutcome.skippedForEarlierInstall`) — before an update, or before a
/// Relaunch, which goes ahead either way. Worded as `duo restart` words it
/// (`Install.earlierInstallBackupNote`): it names the way back when there is
/// one (`InstallJournal.wayBack`) and says there is none when there is none.
/// Kept out of `AppListModel` so the app's test target can compile it.
enum EarlierInstallBackupNote {

    /// The note, or nil for `.clear`, which skips nothing. `hasWayBack`:
    /// whether `InstallJournal.wayBack(for:)` found a copy to restore from.
    static func text(_ standing: InstallJournal.Standing, hasWayBack: Bool) -> String? {
        switch standing {
        case .clear:
            return nil
        case .stillRunning:
            return stillRunning
        case .interrupted:
            return hasWayBack ? interruptedWithWayBack : interruptedWithoutWayBack
        }
    }

    /// Every text ``text(_:hasWayBack:)`` returns, so a later attempt can take
    /// down the one an earlier attempt left (`restartHoldBackNotes`' rule:
    /// retract exactly these texts and nothing else).
    static var all: [String] { [stillRunning, interruptedWithWayBack, interruptedWithoutWayBack] }

    private static var stillRunning: String {
        String(localized: "No new restore point: an earlier update of this app is still running.")
    }
    private static var interruptedWithWayBack: String {
        String(localized: "No new restore point: an earlier update of this app was interrupted, and the copy on disk may be damaged. The restore point from before that update is kept.")
    }
    private static var interruptedWithoutWayBack: String {
        String(localized: "No new restore point: an earlier update of this app was interrupted, and the copy on disk may be damaged. There is no restore point from before that update.")
    }
}
