import Testing
@testable import DuoUpdaterCore

/// The close-to-update sheet has two affirmative buttons the user can reach:
/// ours, and App Store's own Continue in App Store's own window. The installer
/// used to await an answer from ours alone, so answering in the store's window —
/// the obvious thing to do, since the store is what is asking — parked the
/// install on a continuation nothing else could resume.
@Test func anAnswerGivenInAppStoreSettlesTheQuestion() {
    // The app is down and the sheet is gone while we are still asking: the user
    // pressed Continue over there and the swap is running.
    #expect(QuitPrompt.decide(
        answer: .pending, sheetPresent: false, versionChanged: false, appRunning: false)
        == .settledElsewhere)
}

/// Both halves of that reading are required. A sheet that goes away with the app
/// still up is a Cancel we did not press (or a redraw), and a running app with no
/// sheet is not yet a swap — either alone would abandon a question the user still
/// has in front of them.
@Test func neitherHalfAloneAbandonsTheQuestion() {
    #expect(QuitPrompt.decide(
        answer: .pending, sheetPresent: false, versionChanged: false, appRunning: true)
        == .keepWaiting)
    #expect(QuitPrompt.decide(
        answer: .pending, sheetPresent: true, versionChanged: false, appRunning: false)
        == .keepWaiting)
}

/// The bug's sharp end: the prompt outlived the install, and it still meant
/// "quit this app". Pressing it after the update had landed terminated an app
/// that had already been updated and reopened. A moved bundle therefore beats
/// every answer — there is nothing left to quit, whoever consented and wherever.
@Test func aLateTapCannotQuitAnAppThatAlreadyUpdated() {
    #expect(QuitPrompt.decide(
        answer: .proceed, sheetPresent: true, versionChanged: true, appRunning: true)
        == .settledElsewhere)
    // Same for a late decline: the update succeeded, so this is not a cancellation.
    #expect(QuitPrompt.decide(
        answer: .declined, sheetPresent: true, versionChanged: true, appRunning: true)
        == .settledElsewhere)
}

/// The ordinary path, unchanged: the user answers here, we act here.
@Test func answeringHereStillDrivesTheInstall() {
    #expect(QuitPrompt.decide(
        answer: .pending, sheetPresent: true, versionChanged: false, appRunning: true)
        == .keepWaiting)
    #expect(QuitPrompt.decide(
        answer: .proceed, sheetPresent: true, versionChanged: false, appRunning: true)
        == .quitTheApp)
    #expect(QuitPrompt.decide(
        answer: .declined, sheetPresent: true, versionChanged: false, appRunning: true)
        == .cancelled)
}
