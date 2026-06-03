import Foundation

/// The CPU architecture of the host Mac, used to pick the right download when a
/// release ships separate Intel and Apple-silicon artifacts.
///
/// Detected at runtime via `sysctl hw.optional.arm64`, NOT `#if arch(arm64)`:
/// the latter is fixed at *our* compile time, so a DuoUpdater binary translated
/// under Rosetta (or a universal build running x86_64) would misreport the
/// machine. `hw.optional.arm64 == 1` is true for every Apple-silicon Mac
/// regardless of how this process happens to be running, which is exactly the
/// "what build should this Mac get?" question we're answering.
public enum HostArch: Sendable, Equatable {
    case arm64
    case x86_64

    /// The running machine's native architecture, resolved once.
    public static let current: HostArch = detect()

    private static func detect() -> HostArch {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &result, &size, nil, 0) == 0, result == 1 {
            return .arm64
        }
        return .x86_64
    }

    /// Lowercased substrings that mark an asset *filename* as built for this
    /// architecture (e.g. `rustdesk-1.4.6-aarch64.dmg`). Kept conservative — only
    /// tokens that appear as real arch markers in release asset names — so they
    /// don't false-match unrelated words.
    public var assetTokens: [String] {
        switch self {
        case .arm64:  return ["aarch64", "arm64"]
        case .x86_64: return ["x86_64", "x86-64", "amd64", "intel"]
        }
    }

    /// The opposite architecture's tokens — an asset carrying one of these is
    /// explicitly for the *other* machine and must not be picked for this one.
    public var foreignTokens: [String] {
        (self == .arm64 ? HostArch.x86_64 : HostArch.arm64).assetTokens
    }
}
