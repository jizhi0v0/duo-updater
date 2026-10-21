import Foundation

/// A copy's offer as its update's turn reads it: what the command-line tools'
/// runs decide on when the turn comes, not when the click was made
/// (`CLIRunReducer`, event `offerRead`).
///
/// The turn can come minutes after the click, behind Homebrew or another
/// click, and a check meanwhile may have moved the offer, taken it away, held
/// it back for the GitHub pause, or changed whether it asks for an
/// administrator password. Both reads are pure functions of the verdicts the
/// app holds at the turn, so a sequence test can replay one (#1520, #1522)
/// without a check landing at the right moment.
public enum CLIRunOffer: Equatable, Sendable {
    /// Run it, as it stands now.
    case run(CLIToolStatus)
    /// Its offer is gone, and not for the GitHub pause: ask its own tool once
    /// more before the click is given up (a click's turn only).
    case askTool
    /// Not run; `CLIRunNotRun` says what its row says.
    case notRun(CLIRunNotRun)

    /// Offered at the turn, on the click's route or not: what brings back the
    /// Cancel an ask at the turn took away (`CLIRunReducer`).
    public var offered: Bool {
        switch self {
        case .run, .notRun(.routeChanged): return true
        case .askTool, .notRun: return false
        }
    }
}

/// Why a copy was not run at its turn, as its row will word it.
public enum CLIRunNotRun: Equatable, Sendable {
    /// Its update now asks for an administrator password where the click
    /// queued it as one that did not, or the reverse: the click decided its
    /// route, and a panel raised at the turn would come minutes after it.
    case routeChanged(nowNeedsAdministrator: Bool)
    /// No longer offered: its check now withholds it, or leaves it
    /// unanswered. `reason` is the withheld reason's wording, nil for none.
    case notOffered(reason: String?)
    /// Offered by its check, but held back at the turn: the GitHub pause
    /// (an Update All lane's read only).
    case heldBack(reason: String?)
    /// Updated from a terminal meanwhile, or gone: the row says that by
    /// itself, and nothing is said.
    case silent
}

extension CLIRunOffer {
    /// A click's own turn (`CLIToolsModel.offerAtTurn`).
    ///
    /// - `offered`: the copy's offer on screen now, every gate passed;
    ///   `published`: its verdict on screen now, offered or not.
    /// - `heldByPause`: its check offers it and only the GitHub pause holds
    ///   it back. Then it is not asked again: that check would be refused by
    ///   the same closed budget, and its answer — no verdict — would replace
    ///   the "update available" the pause holds back, so the Update would not
    ///   come back when the pause lifts (review, 2026-10-20, round 2).
    /// - `asked`: its tool has been asked at this turn already (or there is
    ///   no tool to ask). Checks are not held off while an update runs, and
    ///   one then can read the run ahead of it — "npm is busy" — or leave the
    ///   copy unanswered; asked once more, the click no longer goes away with
    ///   nothing run and nothing said (review, 2026-10-20).
    /// - `needsAdministrator`: the route the click decided on.
    public static func atTurn(
        offered: CLIToolStatus?, published: CLIToolStatus?, heldByPause: Bool, asked: Bool,
        needsAdministrator: Bool
    ) -> CLIRunOffer {
        guard let offered else {
            if !asked, !heldByPause { return .askTool }
            return notOffered(published)
        }
        guard offered.needsAdministrator == needsAdministrator else {
            return .notRun(.routeChanged(nowNeedsAdministrator: offered.needsAdministrator))
        }
        return .run(offered)
    }

    /// What an Update All lane reads at its turn: `atTurn`'s answer, and
    /// whether it fell back on the offer clicked (`onClickedOffer`), which the
    /// log says.
    public struct Lane: Equatable, Sendable {
        public var offer: CLIRunOffer
        public var onClickedOffer: Bool
    }

    /// An Update All lane copy's turn (`CLIToolsModel.laneOfferAtTurn`).
    /// Read, not asked: one check per copy would be a network round per copy,
    /// and in lanes running side by side a check can read another lane's copy
    /// of the same tool halfway through its install.
    ///
    /// So a verdict that may clear by itself (`mayClearByItself`) falls back
    /// on the click's offer — "an update is already running" (`.busy`), which
    /// a check landing mid-batch gives every other copy in an npm prefix while
    /// the lane's own previous copy runs its npm there (real Mac,
    /// 2026-10-20). So does any verdict short of an offer from a check that
    /// started once this lane had run something (`readsTheLane`): the copy
    /// before can be the next one's updater, so "not verified" read
    /// mid-install is about the batch, not the copy (review, 2026-10-21).
    ///
    /// - `clicked`: the copy as Update All's click read it.
    /// - `published`: its verdict on screen now; `checked`: the same as its
    ///   check returned it, before the GitHub pause.
    /// - `clickedNow`: `clicked` with the pause as it stands now — the
    ///   fallback still honours it.
    public static func laneAtTurn(
        clicked: CLIToolStatus, published: CLIToolStatus?, checked: CLIToolStatus?, readsTheLane: Bool,
        clickedNow: () -> CLIToolStatus
    ) -> Lane {
        // Offered as checked: what the row shows, held back by the GitHub
        // pause or not (as `atTurn`'s `heldByPause` reads it).
        let checkedOffered = checked.map { $0.state == .updateAvailable && $0.oneClick != nil } ?? false
        let saysNothing = checked.map {
            ($0.state == .updateAvailable || $0.state == .unknown) && (readsTheLane || mayClearByItself($0))
        } ?? false
        let turn: CLIToolStatus
        var fellBack = false
        if checkedOffered, let published {
            turn = published
        } else if saysNothing {
            turn = clickedNow()
            fellBack = true
        } else {
            // Updated meanwhile, gone, or held back by a gate of its own.
            return Lane(offer: notOffered(published), onClickedOffer: false)
        }
        guard turn.oneClick != nil else {
            return Lane(offer: .notRun(.heldBack(reason: turn.withheld.map { CLIToolWording.reason($0, of: turn) })),
                        onClickedOffer: fellBack)
        }
        // The lanes never raise a panel: one whose route changed is not run,
        // and its row says to try again, which at the click asks for it.
        guard turn.needsAdministrator == clicked.needsAdministrator else {
            return Lane(offer: .notRun(.routeChanged(nowNeedsAdministrator: turn.needsAdministrator)),
                        onClickedOffer: fellBack)
        }
        return Lane(offer: .run(turn), onClickedOffer: fellBack)
    }

    /// Not offered: why, when the copy is still behind or unanswered.
    private static func notOffered(_ published: CLIToolStatus?) -> CLIRunOffer {
        guard let now = published, now.state == .updateAvailable || now.state == .unknown else {
            return .notRun(.silent)
        }
        return .notRun(.notOffered(reason: now.withheld.map { CLIToolWording.reason($0, of: now) }))
    }

    /// Whether an unchecked install's reason can go away without anything on disk
    /// changing — the network came back, the other update finished — and so is
    /// worth a re-check on the next open. The others (a dev-channel fx, a copy not
    /// signed by its vendor, an editable bub, a broken venv) stay until the scan
    /// sees the disk change — a new version, or a new `CLIToolSighting.state`
    /// for one repaired in place — which `moved` already catches; re-checking them on
    /// every open re-ran every tool's network check for nothing (found in
    /// review, 2026-10-01).
    ///
    /// The three later reasons are disk changes too. `.staged` ends when Junie
    /// applies its update at a launch — a new build and no `pending-update.json`,
    /// both in its sighting. `.unverified` ends with another file or a lifted
    /// quarantine flag: uv's hash verdict, rustup's sha256, an npm prefix's node
    /// signature and quarantine are all in theirs. `.runtimeTooOld` ends with
    /// another node in the prefix (its sighting) or a new release, which the
    /// report's age covers as for any verdict — and it comes with a verdict,
    /// `.updateAvailable`, so it is never among `unchecked` anyway.
    ///
    /// Here, not in the app's model, since the lane's read at its turn
    /// (`laneAtTurn`) rests on it too.
    public static func mayClearByItself(_ status: CLIToolStatus) -> Bool {
        switch status.withheld {
        // A rate limit ends when GitHub's hour does, as `channelUnreadable` did
        // for it before it had a case of its own.
        case nil, .channelUnreadable, .rateLimited, .busy, .versionUnreadable: return true
        case .staged, .unverified, .runtimeTooOld: return false
        default: return false
        }
    }
}
