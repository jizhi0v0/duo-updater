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

    /// Full Disk Access (`kTCCServiceSystemPolicyAllFiles`) — what lets a read of
    /// another app's container through, TestFlight's store among them.
    ///
    /// Asked by opening files only it opens (`FullDiskAccessProbe`), which follow
    /// the switch while DuoUpdater runs; preflight only when those opens cannot
    /// say, since preflight keeps the answer it had at launch. Preflight measured
    /// 2026-09-10 on macOS 27: 1 for an app that was never given it (Full Disk
    /// Access has no prompt, so it never reads "not determined"), 0 once granted.
    public static func fullDiskAccessStatus() -> TCCAuthStatus {
        switch FullDiskAccessProbe.verdict(FullDiskAccessProbe.openResults()) {
        case .granted: .granted
        case .denied: .denied
        case .inconclusive: status(for: "kTCCServiceSystemPolicyAllFiles")
        }
    }

    /// Whether DuoUpdater may read another app's container at all. Without Full
    /// Disk Access that read cannot succeed and is not quiet about failing: on
    /// macOS 27 each attempt is blocked with a "Data Access Blocked" notice
    /// (measured 2026-09-10), and earlier systems raise the "access data from other
    /// apps" prompt instead. So a read that cannot succeed is not attempted.
    ///
    /// Only Full Disk Access counts. The narrower "data from other apps" grant is
    /// reported to be per container and to lapse with the session (third-party
    /// reports, not measured here), so a preflight that names no container is not
    /// evidence about TestFlight's.
    ///
    /// `.unknown` — the SPI is gone — reads as yes: that is what every build did
    /// before this check existed, and the SPI vanishing must not quietly switch
    /// TestFlight off for the users who did grant it.
    public static func admitsOtherAppsData(fullDiskAccess: TCCAuthStatus) -> Bool {
        switch fullDiskAccess {
        case .granted, .unknown: true
        case .denied, .notDetermined: false
        }
    }

    /// Whether the status above describes *this* binary, or one it inherited.
    ///
    /// macOS attributes a TCC decision to the **responsible** process, and a
    /// program started from a terminal is normally the terminal's
    /// responsibility. So a CLI can preflight `granted` while holding no grant
    /// of its own, and then fail the moment the same binary runs from launchd or
    /// a cron job. The 2026-08-09 spike measured exactly this: `granted` from a
    /// shell, `notDetermined` and EPERM from launchd, same binary.
    ///
    /// Returns nil when the SPI is unavailable — "can't tell", never a guess.
    public static func isResponsibleForItself() -> Bool? {
        guard let responsible = Self.responsibleForPID else { return nil }
        let me = getpid()
        let owner = responsible(me)
        // A negative result means the SPI could not answer (a race with an
        // exiting ancestor, typically); that is not evidence of either case.
        guard owner > 0 else { return nil }
        return owner == me
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

    /// `pid_t responsibility_get_pid_responsible_for_pid(pid_t)` — libsystem SPI,
    /// resolved from the global namespace (it is not in a framework of its own).
    /// Same progressive-enhancement contract as `preflight`: absent means nil,
    /// never a fabricated answer.
    private typealias ResponsibleForPIDFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleForPID: ResponsibleForPIDFn? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),  // RTLD_DEFAULT
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleForPIDFn.self)
    }()
}
#endif
