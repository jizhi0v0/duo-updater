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
///  1. `SparkleAppcastSource.usableItems` — drops feed items whose declared
///     `sparkle:minimumSystemVersion` excludes this Mac (the `maximumSystemVersion`
///     half is Sparkle's own predicate, stated beside it).
///  2. `SignatureVerifier` gate 6 (`verifyRunnableSystemVersion`) — refuses a
///     DOWNLOADED bundle whose own `LSMinimumSystemVersion` excludes this Mac.
///     The install-time backstop the detection-time gates are matched against.
///  3. `AppStoreGate.resolve` — turns a listing's `latestMinimumMacOS` into
///     `.needsNewerMacOS`, the one state that RENDERS this condition (#546).
///  4. `VendorHostRequirement.isSatisfied` — a probe recipe's declared floor.
///  5. `XcodeReleasesSource.offer` — bounds the candidate builds by the index's
///     `requires`, so a Mac too old for the newest build is offered the newest
///     one it can run (#640).
///  6. `AlcoveUpdateSource.remote(from:token:osVersion:)` — the licensed API's
///     `minimum_system_version` (#640).
///
/// ⚠️ `UpdateChecker.evaluate` is deliberately NOT on this list and must not
/// join it: a host-dependent branch there makes every one of its comparison
/// tests measure the machine it runs on, and the refusal it could express
/// (`.upToDate`) is a plain checkmark — a second answer for the condition (3)
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
