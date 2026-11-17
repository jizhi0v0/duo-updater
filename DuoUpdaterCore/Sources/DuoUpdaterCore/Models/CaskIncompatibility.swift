import Foundation

/// The installed cask still owns this copy, but its selected release cannot be
/// installed on this host. Keeping this separate from matching preserves the
/// owning cask instead of adopting another channel or another same-named copy.
public enum CaskIncompatibility: Error, LocalizedError, Sendable, Hashable {
    case architecture(required: [HostArch], host: HostArch)
    case macOS(required: CaskMacOSRequirement, host: String)

    static func check(
        macOS: CaskMacOSRequirement?, architectures: [HostArch]?,
        osVersion: String = HostOS.numericVersion(), hostArchitecture: HostArch = .current
    ) -> CaskIncompatibility? {
        if let architectures, !architectures.contains(hostArchitecture) {
            return .architecture(required: architectures, host: hostArchitecture)
        }
        if let macOS, !macOS.admits(osVersion) {
            return .macOS(required: macOS, host: osVersion)
        }
        return nil
    }

    public var logDescription: String {
        switch self {
        case .architecture(let required, let host):
            let names = required.map(Self.architectureName).joined(separator: ", ")
            return "This Homebrew release requires \(names); this Mac uses \(Self.architectureName(host))."
        case .macOS(let required, let host):
            return "This Homebrew release requires macOS \(required.comparison.rawValue) \(required.versions.joined(separator: ", ")); this Mac runs macOS \(host)."
        }
    }

    public var errorDescription: String? { logDescription }

    public static func architectureName(_ architecture: HostArch) -> String {
        architecture == .arm64 ? "Apple Silicon (arm64)" : "Intel (x86_64)"
    }
}
