import Foundation

/// The user's answer to "this app must quit to finish updating".
///
/// A tri-state, and `pending` is the point of it. The installer used to *await*
/// the answer, which meant it stopped looking at the world while it waited — and
/// the world is where the answer often arrives.
public enum QuitPromptAnswer: String, Sendable, Equatable {
    case pending
    case proceed
    case declined
}

/// What to do about App Store's "close this app to update" sheet on this poll.
public enum QuitPromptOutcome: Sendable, Equatable {
    /// Nobody has answered and nothing has moved. Keep polling — and keep the
    /// prompt up, without spending the install's timeout budget on the user.
    case keepWaiting
    /// The user agreed here: quit the app so the store can swap it.
    case quitTheApp
    /// The user declined here: press Cancel and abandon the install.
    case cancelled
    /// The question no longer has an answer to give — someone else already
    /// settled it. Withdraw the prompt and go back to watching the swap.
    case settledElsewhere
}

/// Whether to act on the quit prompt, given the answer and what the screen and
/// the disk now show.
///
/// This exists because the sheet has *two* buttons the user can reach: ours, and
/// App Store's own Continue in its window. Only the first used to resume the
/// installer. Answering in App Store — the obvious thing to do when App Store is
/// the thing asking — left the install suspended on a continuation with no
/// timeout and no other resumer, so:
///
///   • the update landed and the row never noticed. Measured 2026-08-29: the
///     bundle was swapped and the install task stayed parked for minutes, until
///     our own button was pressed, at which point it settled in 0.7s
///     (`resumedInstaller=true` in the log says it had been waiting all along).
///   • the stale button was still live. Pressing it then ran the quit it had
///     always meant, terminating an app that had finished updating and been
///     reopened — a button that kills the app you are using, to finish work that
///     finished minutes ago.
///
/// So `versionChanged` is consulted first and beats every answer: once the
/// bundle has moved there is nothing left to quit, whoever consented and
/// wherever. That single ordering is what makes a late tap harmless.
public enum QuitPrompt {

    public static func decide(
        answer: QuitPromptAnswer,
        sheetPresent: Bool,
        versionChanged: Bool,
        appRunning: Bool
    ) -> QuitPromptOutcome {
        // Ground truth. The swap happened, so the consent happened — ours to
        // observe, not to ask about again.
        if versionChanged { return .settledElsewhere }
        switch answer {
        case .proceed:  return .quitTheApp
        case .declined: return .cancelled
        case .pending:
            // The sheet is gone and the app is down while we were still asking:
            // the user answered in App Store's own window and the store is
            // mid-swap. Stop asking and watch for the bundle to land.
            //
            // Both halves are required. A sheet that vanishes with the app still
            // up is a Cancel we did not press (or a redraw), and a running app
            // with no sheet is not yet a swap; either alone would abandon the
            // prompt on a question the user still has to answer.
            if !sheetPresent && !appRunning { return .settledElsewhere }
            return .keepWaiting
        }
    }
}
