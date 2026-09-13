import Foundation

/// How much DuoUpdater does about TestFlight betas — the user's choice, not a
/// consequence of whether they happened to grant Full Disk Access.
///
/// Three states rather than a switch, because the two costs of "on" are
/// different things and a `Bool` would weld them together:
///
/// | | reads | needs Full Disk Access | background cost |
/// |---|---|---|---|
/// | ``off`` | nothing | no | none — and no "Data Access Blocked" notices, since nothing is attempted |
/// | ``whenAsked`` | the store, each round | yes | none; TestFlight is asked to sync only by the Refresh button |
/// | ``keepFresh`` | the store and its announcements | yes | a sync when a round earns one (`TestFlightSyncPolicy`) — measured ~0.72 MB each |
///
/// The store is the only thing that can say what build a beta is on, and only
/// TestFlight.app writes it (#478). So ``keepFresh`` is the one that starts an
/// app the user did not start, which is exactly why it is a choice and not the
/// default: #543 shipped that behaviour to everyone with the grant, and this
/// type is what gives it back to them to decide (#547).
public enum TestFlightDetection: String, CaseIterable, Identifiable, Sendable {
    /// Nothing is read and nothing is claimed. A TestFlight row says so — it does
    /// not show the question mark, which means "asked, and could not be told".
    case off
    /// The store is read on every round; the Refresh button is the only thing that
    /// asks TestFlight to bring it up to date. What every build before #543 did
    /// for anyone who had the grant.
    case whenAsked
    /// As ``whenAsked``, and a round may also earn a sync of its own from what it
    /// saw — a row the store provably cannot bound, or nothing having written the
    /// store in `TestFlightSyncPolicy.floorInterval`.
    case keepFresh

    public var id: String { rawValue }

    /// Whether anything may read TestFlight's store at all. The single question
    /// every read site asks, so "off" cannot mean one thing in a round and another
    /// in a per-row recheck.
    public var readsStore: Bool { self != .off }

    /// Whether a round may ask TestFlight to sync without the user having pressed
    /// Refresh. The button itself is not this: it is an explicit request, and
    /// ``whenAsked`` exists precisely to keep it working while nothing else syncs.
    public var syncsUnasked: Bool { self == .keepFresh }

    /// Whether a trigger the user did not aim at DuoUpdater — a timer, or TestFlight
    /// being opened for its own reasons — may read TestFlight's container.
    ///
    /// ⚠️ **This is not `TCCPreflight.admitsOtherAppsData`, and the difference is the
    /// whole point.** That one admits `.unknown`, which is right for a refresh someone
    /// asked for: they are watching, and a prompt is an answer to their request.
    /// Reading with nothing known about the grant is what raises macOS's "access data
    /// from other apps" prompt, and `RefreshIntent` states the rule for anything the
    /// user is not looking at — "a silent check must never surface [it] unprompted".
    ///
    /// So this defers to `.scheduled` rather than restating the test. One rule, and a
    /// new unattended trigger cannot accidentally get a laxer one by reaching for the
    /// preflight directly: `TestFlightDetectionUnattendedTests` fails if `.unknown`
    /// starts admitting a read here.
    public func readsStoreUnattended(fullDiskAccess: TCCAuthStatus) -> Bool {
        readsStore && RefreshIntent.scheduled.readsTestFlight(fullDiskAccess: fullDiskAccess)
    }

    /// The value a Mac that has never had this setting starts with.
    ///
    /// Full Disk Access already granted means TestFlight rows are answering today,
    /// and an update must not silently take that away — so ``whenAsked``, which is
    /// exactly what those users had before #543. Everyone else starts ``off``:
    /// without the grant nothing could be read anyway, and the choice is then made
    /// once, deliberately, instead of falling out of a permission.
    ///
    /// Decided once and written down, never re-derived at each launch. Re-deriving
    /// would silently promote anyone who later grants Full Disk Access for
    /// CotEditor's sake, and silently rewrite the choice of anyone who revokes it.
    ///
    /// `.unknown` — the preflight SPI is gone — reads as granted here for the same
    /// reason `TCCPreflight.admitsOtherAppsData` reads it that way: the SPI
    /// vanishing must not be what switches TestFlight off for someone using it.
    public static func firstRunDefault(fullDiskAccess: TCCAuthStatus) -> Self {
        TCCPreflight.admitsOtherAppsData(fullDiskAccess: fullDiskAccess) ? .whenAsked : .off
    }

    /// Terse on purpose, like `AppStoreUpdateStrategy.label`: these sit in a popup
    /// button in the settings row, which truncates its own current selection
    /// rather than wrapping. The sentence each one deserves is in the card footer.
    public var label: String {
        switch self {
        case .off:       return String(localized: "Off")
        case .whenAsked: return String(localized: "When I refresh")
        case .keepFresh: return String(localized: "Keep it fresh")
        }
    }
}

/// Why a TestFlight row cannot say whether its beta is current — which mark it
/// carries, and what tapping that mark explains.
///
/// In one place because the two surfaces draw the same row and used to be given a
/// bare `fullDiskAccessMissing: Bool`, which could only ever describe two of the
/// three reasons. A third bool would have made a cross product that each surface
/// resolves for itself, which is how the popover and the workbench drifted apart
/// before `RowActionState` existed.
public enum TestFlightUnboundedReason: Sendable, Equatable, CaseIterable {
    /// Detection is off: nothing was read, so there is nothing to be silent about.
    /// Ranked first — when nothing was attempted, a missing permission is not the
    /// reason, and saying so would send the user to grant something unused.
    case checkingOff
    /// The read that could have answered was not allowed.
    case noFullDiskAccess
    /// The store was read and does not bound this copy: no build on file, an
    /// installed build newer than anything on file, or an announcement the store
    /// has not caught up with.
    case storeSilent

    public static func of(
        detection: TestFlightDetection, fullDiskAccessMissing: Bool
    ) -> Self {
        if !detection.readsStore { return .checkingOff }
        return fullDiskAccessMissing ? .noFullDiskAccess : .storeSilent
    }
}
