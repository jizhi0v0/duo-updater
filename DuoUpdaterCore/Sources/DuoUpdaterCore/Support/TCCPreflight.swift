#if os(macOS)
import Foundation

/// The current state of a TCC permission, as reported by `TCCAccessPreflight`.
public enum TCCAuthStatus: Sendable, Equatable {
    case granted        // preflight 0 — authorized
    case denied         // preflight 1 — explicitly denied
    case notDetermined  // preflight 2 — never asked / no entry
    case unknown        // SPI unavailable or an unexpected value — treat as "can't tell"
}

/// Reads a TCC permission's current status via the **private** `TCCAccessPreflight` SPI
/// in `TCC.framework`.
///
/// Why this exists: macOS exposes a public status API for *Accessibility*
/// (`AXIsProcessTrusted()`) but **not** for *App Management*
/// (`kTCCServiceSystemPolicyAppBundles`). Short of granting ourselves Full Disk Access
/// to read `TCC.db`, this SPI is the only way to learn an App Management grant's state
/// without side effects — it doesn't prompt, doesn't write, and needs no extra
/// permission. (Verified: it returns 0/1/2 for granted/denied/not-determined.)
///
/// Defensive by construction: the symbol is resolved at runtime with `dlsym`, so if a
/// future macOS renames or removes it (it's undocumented SPI), every call returns
/// `.unknown` and callers fall back to their "can't verify — grant to be safe" path
/// instead of crashing. This makes the whole thing a *progressive enhancement*: real
/// status where the SPI is present, graceful degradation where it isn't.
public enum TCCPreflight {

    /// App Management (`kTCCServiceSystemPolicyAppBundles`) — needed to replace apps
    /// installed outside the App Store (Sparkle, Homebrew, direct downloads).
    public static func appManagementStatus() -> TCCAuthStatus {
        status(for: "kTCCServiceSystemPolicyAppBundles")
    }

    /// Generic preflight for any TCC service constant.
    public static func status(for service: String) -> TCCAuthStatus {
        guard let preflight = Self.preflight else { return .unknown }
        switch preflight(service as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        case 2: return .notDetermined
        default: return .unknown
        }
    }

    /// `int TCCAccessPreflight(CFStringRef service, CFDictionaryRef options)` — a C
    /// function pointer (so Sendable; captures nothing). Resolved once: the on-disk
    /// framework path is a stub on modern macOS, but `dlopen` loads it from the dyld
    /// shared cache. `nil` if the SPI is gone, which collapses every call to `.unknown`.
    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int32
    private static let preflight: PreflightFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFn.self)
    }()
}
#endif
