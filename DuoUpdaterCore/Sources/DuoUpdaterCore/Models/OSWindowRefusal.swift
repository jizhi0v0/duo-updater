import Foundation

/// The vendor's own word that its newest release is not for the macOS this Mac
/// runs — below the floor it states, or above the ceiling it caps the release at.
///
/// A source used to swallow this: Sparkle dropped the item and VendorProbe
/// answered `.notApplicable`, both arriving at `UpdateChecker` as a plain nil, so
/// an app with no other source settled on `.unknown` — the "no source covers this
/// app" dash. That is a false statement about an app whose feed was read, and for
/// a ceiling it never corrects itself: a min-filtered release reappears when the
/// user upgrades macOS, a max-filtered one waits on the vendor (#634, part 3).
/// Carrying the refusal lets the row say what actually happened.
public struct OSWindowRefusal: Sendable, Equatable {
    public enum Bound: Sendable, Equatable {
        /// The release needs macOS `minimum` or newer.
        case floor(minimum: String)
        /// The vendor supports the release up to macOS `maximum` and no further.
        case ceiling(maximum: String)
    }

    public let bound: Bound
    /// The refused release, in the spelling the row displays.
    public let version: String
    /// The macOS the verdict was made against, so the explanation names the Mac it
    /// was about rather than asking the host again when it is drawn.
    public let hostOS: String

    public init(bound: Bound, version: String, hostOS: String) {
        self.bound = bound
        self.version = version
        self.hostOS = hostOS
    }

    /// Whether a release declaring `minimum`/`maximum` is refused on a Mac running
    /// `osVersion`, and by which bound. nil when it is not.
    ///
    /// The floor is `SignatureVerifier.canRun(minimumSystemVersion:on:)` — the
    /// predicate every OS floor calls (see `HostOS`). The ceiling follows Sparkle's
    /// `SPUAppcastItemStateResolver -isMaximumOperatingSystemVersionOK:` on
    /// numeric bounds: `compare(max, host) == .orderedAscending` refuses, so a
    /// "26.99" ceiling admits 26.6.0 and refuses 27.0.0.
    ///
    /// A bound with no digit in it (`any`, `latest`, `-`) is absent. `canRun`
    /// already guards the floor that way; the ceiling gets the same guard because
    /// `VersionComparator` ranks a text token below a number, so an unguarded
    /// `"any"` ceiling reads as below every host and refuses every Mac. That guard
    /// is ours — whether Sparkle itself refuses on a text ceiling was not checked —
    /// and it changed the Sparkle path, which had no guard before.
    ///
    /// The floor is checked first: a release outside both bounds is reported by the
    /// one an OS upgrade would at least address.
    public static func evaluate(
        minimum: String?, maximum: String?, osVersion: String, version: String
    ) -> OSWindowRefusal? {
        if !SignatureVerifier.canRun(minimumSystemVersion: minimum, on: osVersion),
           let minimum {
            return OSWindowRefusal(bound: .floor(minimum: minimum), version: version, hostOS: osVersion)
        }
        if let maximum, maximum.rangeOfCharacter(from: .decimalDigits) != nil,
           VersionComparator.compare(maximum, osVersion) == .orderedAscending {
            return OSWindowRefusal(bound: .ceiling(maximum: maximum), version: version, hostOS: osVersion)
        }
        return nil
    }

    /// One line for logs and `duo` output. Not for the UI, which words this itself
    /// and localizes it.
    public var logDescription: String {
        switch bound {
        case .floor(let minimum):
            return "the vendor states \(version) needs macOS \(minimum) or newer; this Mac runs \(hostOS)"
        case .ceiling(let maximum):
            return "the vendor caps \(version) at macOS \(maximum); this Mac runs \(hostOS)"
        }
    }
}

/// Thrown by a source whose newest release the vendor says is not for this Mac.
///
/// Thrown rather than returned because `latestVersion(for:)` has no third answer
/// between "here is a version" and nil ("this source does not cover the app"),
/// and nil is exactly the answer that turned this into a dash. `UpdateChecker`
/// catches it apart from every other error: it is not a failed check and must not
/// become `.error` with a Retry — nothing changes until the vendor moves its bound
/// or the user moves macOS.
///
/// Carries the refused release as the source would have reported it, because a
/// refusal is only news when that release would have been an UPDATE. A copy
/// already on the refused build (the Mac moved to a macOS the vendor has not
/// caught up with), or ahead of it (a lagging or abandoned feed capped at an old
/// macOS), must not be told the vendor "won't offer" it — `UpdateChecker` runs
/// `release` through the same `evaluate(installed:remote:)` an answer goes
/// through, so the version rules exist once.
public struct OSWindowRefused: Error, LocalizedError, Sendable, Equatable {
    public let refusal: OSWindowRefusal
    public let release: RemoteVersion

    public init(_ refusal: OSWindowRefusal, release: RemoteVersion) {
        self.refusal = refusal
        self.release = release
    }

    public var errorDescription: String? { refusal.logDescription }
}
