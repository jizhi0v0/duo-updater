import Foundation
import Testing
import DuoUpdaterCore

/// The row note for a backup `InstallCoordinator.backUp` skipped over an
/// earlier install of the app (install journal round 4, #2): it says why, and
/// says what the way back is, or that there is none — as `duo restart` does.
struct EarlierInstallBackupNoteTests {

    @Test func anEarlierInstallStillRunningSaysSo() {
        #expect(EarlierInstallBackupNote.text(.stillRunning(pid: 4242), hasWayBack: false)
            == "No new restore point: an earlier update of this app is still running.")
    }

    @Test func anInterruptedOneSaysWhetherAWayBackExists() {
        let kept = EarlierInstallBackupNote.text(.interrupted, hasWayBack: true)
        let none = EarlierInstallBackupNote.text(.interrupted, hasWayBack: false)
        #expect(kept?.hasSuffix("The restore point from before that update is kept.") == true)
        #expect(none?.hasSuffix("There is no restore point from before that update.") == true)
        #expect(none?.contains("is kept") == false)
    }

    @Test func nothingToSayWhenClear() {
        #expect(EarlierInstallBackupNote.text(.clear, hasWayBack: true) == nil)
    }

    /// A later attempt takes down whichever of these an earlier one left.
    @Test func everyTextIsListedForRetraction() {
        let texts = [
            EarlierInstallBackupNote.text(.stillRunning(pid: 1), hasWayBack: false),
            EarlierInstallBackupNote.text(.interrupted, hasWayBack: true),
            EarlierInstallBackupNote.text(.interrupted, hasWayBack: false),
        ].compactMap { $0 }
        #expect(Set(texts) == Set(EarlierInstallBackupNote.all))
        #expect(texts.count == 3)
    }
}
