import DuoUpdaterCore
import Testing

struct AutomaticUpdateReasonTextTests {
    @Test func backgroundProcessDeferralIsLocalizedWithoutLosingItsName() {
        let reason = "Background processes are still running (RustDesk service). Automatic updating is paused for this app."
        #expect(AutomaticUpdateReasonText.isKnown(reason))
        #expect(AutomaticUpdateReasonText.display(reason).contains("RustDesk service"))
    }
    /// Every reason a running app waits for is translated when shown. Mutation:
    /// reword a `RunningAppAutoUpdate.Reason` message without its entry → red.
    @Test func everyRunningAppReasonIsTranslated() {
        let reasons: [RunningAppAutoUpdate.Reason] = [
            .gaveUp, .retryLater, .independentHelper,
        ]
        for reason in reasons {
            #expect(AutomaticUpdateReasonText.isKnown(reason.message), "\(reason.message)")
        }
    }

    @Test func earlierActivityDeferralsStillDisplayFromEventHistory() {
        for reason in [
            "The app is running, and its update has been waiting less than 30 minutes.",
            "The app is running, and it was quit for an update less than 15 minutes ago.",
            "The app is running and in front.",
            "The app is running and was used in the last hour.",
            "The app is running, and the Mac is in use.",
            "The app is running and busy (Playing audio).",
            "The app is running a process of its own, such as a shell or a build.",
        ] {
            #expect(AutomaticUpdateReasonText.isKnown(reason))
        }
    }

    @Test func unknownTextIsShownAsStored() {
        let error = "The download's EdDSA signature did not match the app's public key."
        #expect(!AutomaticUpdateReasonText.isKnown(error))
        #expect(AutomaticUpdateReasonText.display(error) == error)
    }
}
