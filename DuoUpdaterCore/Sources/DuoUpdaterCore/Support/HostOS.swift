import Foundation

/// The macOS version this Mac is running, in the one spelling every OS gate
/// compares against.
///
/// This exists as a shared definition rather than a local helper because the OS
/// floor is checked in several places that must not be allowed to disagree. A
/// gate that hid an update and a gate that refused to install one, disagreeing
/// by so much as a patch component, would produce the worst outcome available:
/// an update that is offered forever and fails at the last step every time.
///
/// **Every one of these calls `SignatureVerifier.canRun(minimumSystemVersion:on:)`.**
/// That is the invariant; the list is here so a new site is added knowingly, and
/// it was wrong for as long as it named only the first two (#640 review):
///
///  1. `OSWindowRefusal.evaluate` — a vendor's per-release window, for both
///     `SparkleAppcastSource.usableItems` (`sparkle:minimumSystemVersion`) and a
///     probe recipe's `minimumSystemVersionPattern`. The ceiling half is
///     Sparkle's own predicate, stated beside it.
///  2. `SignatureVerifier` gate 6 (`verifyRunnableSystemVersion`) — refuses a
///     DOWNLOADED bundle whose own `LSMinimumSystemVersion` excludes this Mac.
///     The install-time backstop the detection-time gates are matched against.
///  3. `PackageInstaller.verifyPayloadSystemVersion` — the same for the pkg
///     route, reading the floor out of the package's payload; best-effort, and
///     fails open on a payload it cannot read.
///  4. `AppStoreGate.resolve` — turns a listing's `latestMinimumMacOS` into
///     `.needsNewerMacOS`, the state that renders this condition for a store
///     listing (#546). (1) is the only other site whose refusal reaches a row
///     state (`.notForThisMacOS`, #634); a floor at (5), (7) or (8) still leaves
///     that source with nothing to say.
///  5. `VendorHostRequirement.isSatisfied` — a probe recipe's declared floor.
///  6. `XcodeReleasesSource.offer` — bounds the candidate builds by the index's
///     `requires`, so a Mac too old for the newest build is offered the newest
///     one it can run (#640).
///  7. `AlcoveUpdateSource.remote(from:token:osVersion:)` — the licensed API's
///     `minimum_system_version` (#640).
///  8. `CaskMacOSRequirement.admits` — a cask's `depends_on.macos`. Only its `>=`
///     branch is a floor and only that branch calls `canRun`; `==` (membership
///     in a list of majors with gaps) and `<=` (a ceiling) are not floors, and a
///     minimum cannot express them. Its fail-open guards run before any branch.
///
/// ⚠️ `UpdateChecker.evaluate` is deliberately NOT on this list and must not
/// join it: a host-dependent branch there makes every one of its comparison
/// tests measure the machine it runs on, and the refusal it could express
/// (`.upToDate`) is a plain checkmark — a second answer for the condition (4)
/// already renders. See its doc comment.
public enum HostOS {

    /// e.g. "27.0.0". Always three numeric components, because that is what
    /// `VersionComparator` compares cleanly against the two-component values
    /// (`"13.1"`, `"10.15"`) that vendors overwhelmingly declare — its tokenizer
    /// pads the shorter side with zeros, so "27.0.0" vs "13.1" needs no special
    /// case.
    public static func numericVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
