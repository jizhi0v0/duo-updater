import Foundation

/// Reading the build number of what is actually on disk, and deciding when that
/// reading is the honest answer.
///
/// The traffic log records a version transition, and marketing versions are not
/// always enough to describe one: Surge shipped four separate releases as "6.9.0",
/// so those rows read "6.9.0 → 6.9.0". The build number is what moved. The
/// installed side of it can only be trusted when the new build is genuinely on
/// disk, which is what makes this a decision rather than a lookup.
public enum InstalledBuild {

    /// `CFBundleVersion` read straight out of the bundle's `Info.plist`.
    ///
    /// Deliberately not `Bundle(path:)`: `Bundle` memoises one instance per path
    /// for the life of the process, and this is called immediately after an
    /// in-place swap replaced the bundle at that exact path. A cached `Bundle`
    /// would hand back the version of the build we just overwrote — the one number
    /// this function exists to avoid recording.
    ///
    /// Returns nil when the bundle is unreadable or declares no build, so callers
    /// fall back rather than record a wrong value.
    public static func read(at bundleURL: URL) -> String? {
        let plist = BundleLayout.infoPlistURL(for: bundleURL)
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                  from: data, format: nil),
              let fields = object as? [String: Any],
              let build = fields["CFBundleVersion"] as? String,
              !build.isEmpty
        else { return nil }
        return build
    }

    /// The build to record as the one an install landed on.
    ///
    /// - Parameters:
    ///   - applied: whether the new version is on disk *now* — the install
    ///     coordinator's own `Outcome.applied`, not a proxy for it. False for a
    ///     staged `.pkg`, where macOS's installer still has a window open and the
    ///     bundle on disk is still the old build; reading it there would record the
    ///     version being replaced as the version installed, which is worse than
    ///     recording nothing.
    ///   - onDisk: reads the installed build. Not called at all unless `applied`,
    ///     so a staged install never touches the bundle.
    ///   - declared: what the source said it was shipping. The fallback, and the
    ///     only answer available for a staged install. Nil for sources that publish
    ///     no build number (GitHub releases, Homebrew, the App Store).
    public static func recorded(
        applied: Bool,
        onDisk: () -> String?,
        declared: String?
    ) -> String? {
        guard applied else { return declared }
        return onDisk() ?? declared
    }
}
