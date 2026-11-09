import DuoUpdaterCore
import Testing

struct AutomaticUpdateReasonTextTests {
    /// Every reason a running app waits for is translated when shown. Mutation:
    /// reword a `RunningAppAutoUpdate.Reason` message without its entry → red.
    @Test func everyRunningAppReasonIsTranslated() {
        let reasons: [RunningAppAutoUpdate.Reason] = [
            .gaveUp, .retryLater, .delay(30), .recentlyQuit(15), .frontmost, .recentlyUsed,
            .personPresent, .busy("Playing audio"), .childProcess, .independentHelper,
        ]
        for reason in reasons {
            #expect(AutomaticUpdateReasonText.isKnown(reason.message), "\(reason.message)")
        }
    }

    @Test func unknownTextIsShownAsStored() {
        let error = "The download's EdDSA signature did not match the app's public key."
        #expect(!AutomaticUpdateReasonText.isKnown(error))
        #expect(AutomaticUpdateReasonText.display(error) == error)
    }
}
