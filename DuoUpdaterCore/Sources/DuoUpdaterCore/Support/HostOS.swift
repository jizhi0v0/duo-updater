import Foundation

/// The macOS version this Mac is running, in the one spelling every OS gate
/// compares against.
///
/// This exists as a shared definition rather than a local helper because the OS
/// floor is now checked in two places that must not be allowed to disagree:
/// `SparkleAppcastSource.usableItems` drops feed items whose declared
/// `sparkle:minimumSystemVersion`/`maximumSystemVersion` exclude this Mac, and
/// `SignatureVerifier` gate 6 refuses a downloaded bundle whose own
/// `LSMinimumSystemVersion` does. A gate that hid an update and a gate that
/// refused to install one, disagreeing by so much as a patch component, would
/// produce the worst outcome available: an update that is offered forever and
/// fails at the last step every time.
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
