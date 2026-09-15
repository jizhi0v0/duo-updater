import Foundation

/// The SDK an executable was linked against, as its own load commands record it.
///
/// Read from the binary and never from `Info.plist`, and that choice is measured
/// rather than stylistic. Xcode writes the SDK in both places, but `DTSDKName` is
/// a *plist* key, and a packager that ships a template plist ships its template's
/// value. The copy of Claude 1.52386.6 this was checked against (2026-09-15) carries
/// `DTSDKName = macosx15.5` beside a main executable recording SDK 26.5, and its
/// `Electron Framework` records 26.5 as well — the plist is the stale one.
///
/// What this value is and is not. It is what the binary *declares* — the linker
/// takes it from `-platform_version`, so a build system that is not Xcode sets it
/// to whatever it passes — and it is the same number dyld reports to the running
/// app as its SDK version (checked by linking a probe with a declared SDK of
/// 14.0, 26.0 and 99.3 and reading `dyld_get_program_sdk_version()` back). It is
/// covered by the code signature: rewriting it with `vtool` invalidates the seal.
/// It is not a claim about which Xcode was installed.
public struct BuildSDK: Sendable, Hashable {

    /// Which SDK family the number belongs to. The numbers are not one sequence:
    /// until the 26 releases, Catalyst and iOS SDKs carried iOS numbering, so one
    /// build of one image can record macOS 13.0 and Mac Catalyst 16.0 (see
    /// `preferred(among:)`). The platform travels with the version rather than
    /// being implied by it.
    public enum Platform: String, Sendable, Hashable, CaseIterable {
        case macOS
        case macCatalyst
        case iOS

        /// The `PLATFORM_*` values from `<mach-o/loader.h>` that can describe
        /// something installed in a Mac's application folders. The rest —
        /// simulators, tvOS, watchOS, DriverKit — are not an app this scan reads.
        init?(code: UInt32) {
            switch code {
            case 1: self = .macOS        // PLATFORM_MACOS
            case 2: self = .iOS          // PLATFORM_IOS
            case 6: self = .macCatalyst  // PLATFORM_MACCATALYST
            default: return nil
            }
        }

        /// Apple's product name for the family. Not localized anywhere it appears.
        public var displayName: String {
            switch self {
            case .macOS: "macOS"
            case .macCatalyst: "Mac Catalyst"
            case .iOS: "iOS"
            }
        }
    }

    public let platform: Platform
    /// `X.Y`, or `X.Y.Z` when the patch component is non-zero — the spelling
    /// `vtool -show-build` prints.
    public let version: String

    public init(platform: Platform, version: String) {
        self.platform = platform
        self.version = version
    }

    /// From a load command's packed `xxxx.yy.zz` nibbles. Nil for a zero, which
    /// is how a linker that was given no SDK records one (`vtool` prints `n/a`):
    /// that is "not recorded", and printing it as "0.0" would be a wrong answer
    /// rather than a missing one.
    init?(platform: Platform, packed: UInt32) {
        guard packed != 0 else { return nil }
        let major = packed >> 16
        let minor = (packed >> 8) & 0xff
        let patch = packed & 0xff
        self.init(platform: platform,
                  version: patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)")
    }

    init?(platformCode: UInt32, packed: UInt32) {
        guard let platform = Platform(code: platformCode) else { return nil }
        self.init(platform: platform, packed: packed)
    }

    /// The one to report when a single image records several.
    ///
    /// A *zippered* image — one that loads both into a Mac process and into a
    /// Catalyst one — carries an `LC_BUILD_VERSION` per platform, and the two
    /// numbers differ in kind, not just in value: the `libswift_Concurrency.dylib`
    /// UTM 5.0.5 embeds records macOS SDK 13.0 *and* Mac Catalyst SDK 16.0. On a Mac
    /// the macOS one describes the app, so it wins whatever order the file lists
    /// them in; then Catalyst, then iOS. Within a platform the first recorded is
    /// kept, so the answer depends on nothing but the file.
    static func preferred(among candidates: [BuildSDK]) -> BuildSDK? {
        for platform in Platform.allCases {
            if let match = candidates.first(where: { $0.platform == platform }) { return match }
        }
        return nil
    }
}
