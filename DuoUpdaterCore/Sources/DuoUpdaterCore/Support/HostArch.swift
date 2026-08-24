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

    /// Lowercased markers that identify an asset *filename* as built for this
    /// architecture (e.g. `rustdesk-1.4.6-aarch64.dmg`). Kept conservative — only
    /// tokens that appear as real arch markers in release asset names — so they
    /// don't false-match unrelated words.
    /// `x64`/`x86` are here because they are the most common Intel marker in the
    /// registry's real asset names (`bruno_…_x64_mac.dmg`, `draw.io-x64-….dmg`,
    /// `VSCodium.x64.….dmg`, `openmtp-…-mac-x64.dmg`). Leaving them out did not
    /// merely lose a preference — it made those artifacts read as arch-NEUTRAL,
    /// i.e. as safe for either Mac, which is the one classification an Intel-only
    /// build must never get. `apple-silicon` is the mirror case on the arm side
    /// (`MarkEdit-…-apple-silicon.dmg`); the hyphenated form is deliberate, so it
    /// cannot fire on the unrelated `…-apple-darwin.tar.gz` CLI tarballs.
    public var assetTokens: [String] {
        switch self {
        case .arm64:  return ["aarch64", "arm64", "apple-silicon"]
        case .x86_64: return ["x86_64", "x86-64", "x64", "x86", "amd64", "intel"]
        }
    }

    /// The opposite architecture's tokens — an asset carrying one of these is
    /// explicitly for the *other* machine and must not be picked for this one.
    public var foreignTokens: [String] {
        (self == .arm64 ? HostArch.x86_64 : HostArch.arm64).assetTokens
    }

    /// Whether `name` carries one of this architecture's standalone filename
    /// markers. Requiring a non-alphanumeric boundary keeps product names such
    /// as `IntelliJ` from accidentally matching the Intel marker while retaining
    /// the separators used by real assets (`App-arm64.zip`, `App_x64_mac.dmg`).
    func isMarked(inAssetName name: String) -> Bool {
        let lower = name.lowercased()
        for token in assetTokens {
            var searchStart = lower.startIndex
            while searchStart < lower.endIndex,
                  let range = lower.range(
                    of: token, range: searchStart..<lower.endIndex) {
                let startsAtBoundary = range.lowerBound == lower.startIndex
                    || {
                        let preceding = lower[lower.index(before: range.lowerBound)]
                        return !preceding.isLetter && !preceding.isNumber
                    }()
                let endsAtBoundary = range.upperBound == lower.endIndex
                    || {
                        let following = lower[range.upperBound]
                        return !following.isLetter && !following.isNumber
                    }()
                if startsAtBoundary && endsAtBoundary { return true }
                searchStart = lower.index(after: range.lowerBound)
            }
        }
        return false
    }

    /// Whether an Intel build can still be *run* on this Mac — the one case where
    /// offering a foreign-architecture download is better than offering nothing.
    ///
    /// Three conditions, all required:
    ///  - the machine is Apple silicon (translation only ever went x86 → arm; an
    ///    arm64 build has never run on an Intel Mac, so that direction is never
    ///    offered regardless of anything below),
    ///  - macOS is 27 or earlier. Apple documents Rosetta as available "through
    ///    the forthcoming macOS 27" and, from macOS 28, only for certain older
    ///    unmaintained games that depend on Intel frameworks — so from 28 an Intel
    ///    app is one that will not launch, not one that runs slowly.
    ///    https://support.apple.com/en-us/102527
    ///  - the Rosetta runtime is actually installed. It is an optional install, so
    ///    its absence means the same thing as its removal: the download would not
    ///    run. The path is not API and may change; that is deliberate here, because
    ///    a path that stops resolving makes us offer LESS, never more.
    public static var canRunIntelBuilds: Bool { translationAvailable }

    private static let translationAvailable: Bool = {
        guard current == .arm64 else { return false }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion <= 27 else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }()
}
