import Foundation
import DuoUpdaterCore

// duo-tcc-spike — answers, on this machine and this OS, whether a standalone
// Developer ID-signed executable can hold its own App Management grant.
//
// The question gates how much of `duo install` can exist. Replacing an app in
// /Applications needs `kTCCServiceSystemPolicyAppBundles`, macOS attributes TCC
// to the *responsible* process, and a program started from a terminal is
// normally the terminal's responsibility — so a CLI can end up borrowing the
// terminal's grant rather than holding one, which works until it doesn't.
//
// Four separable questions, printed as JSON:
//
//   Q1  can this binary be added to System Settings and show `granted`?
//   Q2  started from a shell, is it its own responsible process?
//   Q3  started from launchd — no terminal anywhere — same answers?
//   Q4  does a real write into a third-party app bundle actually succeed?
//
// Q4 is the one that counts. Q1 can say `granted` while the write still fails,
// and the write can succeed on a borrowed grant while Q1 says `notDetermined`.
//
// Usage:
//   duo-tcc-spike                      report status only
//   duo-tcc-spike --probe-write <app>  additionally attempt a reversible write
//   duo-tcc-spike --disclaim …         re-exec disclaiming responsibility first

// MARK: - responsibility

/// `responsibility_spawnattrs_setdisclaim` tells the kernel that the process we
/// are about to spawn should be responsible for itself rather than inheriting
/// our responsibility. It is private SPI, so it is resolved at runtime and the
/// whole feature degrades to "couldn't try" if it ever disappears — the same
/// progressive-enhancement shape as `TCCPreflight`.
// Signature is `int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *, int)`
// — a pointer *to* the attribute, not the attribute value. Passing the value
// compiles and returns non-zero, which reads as "the SPI refused" rather than
// "we called it wrong".
typealias SetDisclaimFn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

let setDisclaim: SetDisclaimFn? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
                             "responsibility_spawnattrs_setdisclaim") else { return nil }
    return unsafeBitCast(symbol, to: SetDisclaimFn.self)
}()

/// Re-exec ourselves as our own responsible process. Returns only on failure;
/// on success the child replaces us from the caller's point of view.
func reExecDisclaimed(_ arguments: [String]) -> String? {
    guard let setDisclaim else { return "SPI responsibility_spawnattrs_setdisclaim not found" }
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    guard attributes != nil else { return "posix_spawnattr_init failed" }
    let disclaimResult = setDisclaim(&attributes, 1)
    guard disclaimResult == 0 else {
        return "setdisclaim returned \(disclaimResult)"
    }

    let path = CommandLine.arguments[0]
    let argStrings: [String] = [path] + arguments
    let envStrings: [String] = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        + ["DUO_SPIKE_DISCLAIMED=1"]
    var argv: [UnsafeMutablePointer<CChar>?] = argStrings.map { strdup($0) } + [nil]
    defer { for pointer in argv where pointer != nil { free(pointer) } }
    var environment: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) } + [nil]
    defer { for pointer in environment where pointer != nil { free(pointer) } }

    var pid: pid_t = 0
    let status = posix_spawn(&pid, path, nil, &attributes, &argv, &environment)
    guard status == 0 else { return "posix_spawn failed with \(status)" }
    var exitStatus: Int32 = 0
    waitpid(pid, &exitStatus, 0)
    exit(exitStatus >> 8)
}

// MARK: - the probe write

/// Create and immediately remove a file inside a bundle's `Contents`. Gated by
/// exactly `kTCCServiceSystemPolicyAppBundles`, and reversible.
///
/// The target must be a **third-party notarized app**. A bundle we made
/// ourselves isn't a managed bundle in TCC's eyes and writes fine regardless,
/// and anything signed by our own team is exempt — either would report a pass
/// that means nothing.
func probeWrite(into app: String) -> [String: Any] {
    let target = URL(fileURLWithPath: app).appendingPathComponent("Contents/.duo-tcc-probe")
    var result: [String: Any] = ["target": app]

    let team = teamIdentifier(of: app)
    result["targetTeam"] = team ?? "unknown"
    result["targetIsOurOwnTeam"] = (team == "RS59HDH7Y3")

    do {
        try Data("probe".utf8).write(to: target)
        try? FileManager.default.removeItem(at: target)
        result["ok"] = true
    } catch {
        let code = (error as NSError).code
        result["ok"] = false
        result["errno"] = code
        result["error"] = error.localizedDescription
        // EPERM is the App Management denial; EACCES is ordinary permissions.
        result["looksLikeAppManagementDenial"] = (code == NSFileWriteNoPermissionError)
    }
    return result
}

func teamIdentifier(of path: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["-dv", path]
    let pipe = Pipe()
    process.standardError = pipe
    process.standardOutput = FileHandle.nullDevice
    try? process.run()
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard let range = text.range(of: #"TeamIdentifier=[A-Z0-9]+"#, options: .regularExpression)
    else { return nil }
    return String(text[range]).replacingOccurrences(of: "TeamIdentifier=", with: "")
}

// MARK: - report

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--disclaim" {
    arguments.removeFirst()
    if ProcessInfo.processInfo.environment["DUO_SPIKE_DISCLAIMED"] == nil {
        if let failure = reExecDisclaimed(arguments) {
            FileHandle.standardError.write(Data("disclaim failed: \(failure)\n".utf8))
        }
    }
}

var report: [String: Any] = [
    "argv0": CommandLine.arguments[0],
    "pid": ProcessInfo.processInfo.processIdentifier,
    "ppid": getppid(),
    "uid": getuid(),
    "euid": geteuid(),
    "disclaimed": ProcessInfo.processInfo.environment["DUO_SPIKE_DISCLAIMED"] != nil,
    "disclaimSPIAvailable": setDisclaim != nil,
    "appManagement": String(describing: TCCPreflight.appManagementStatus()),
    "fullDiskAccess": String(describing: TCCPreflight.status(for: "kTCCServiceSystemPolicyAllFiles")),
    "hasControllingTerminal": isatty(STDIN_FILENO) == 1 || isatty(STDOUT_FILENO) == 1,
]

if let index = arguments.firstIndex(of: "--probe-write"), index + 1 < arguments.count {
    report["probeWrite"] = probeWrite(into: arguments[index + 1])
}

let json = try! JSONSerialization.data(
    withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
