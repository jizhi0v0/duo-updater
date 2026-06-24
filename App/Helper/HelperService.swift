import Foundation
import Security

/// Accepts incoming XPC connections only from the genuine, correctly-signed main
/// app, then vends `MASHelperProtocol`.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        guard HelperService.isValidClient(conn) else {
            NSLog("duo-helper: rejected connection — client failed code-signing check")
            return false
        }
        conn.exportedInterface = NSXPCInterface(with: MASHelperProtocol.self)
        conn.exportedObject = HelperService()
        conn.resume()
        return true
    }
}

/// The root-side worker. Each accepted connection gets its own instance; all
/// installs funnel through one serial queue so two `mas` processes never run as
/// root at the same time (Update All fans out concurrent calls).
final class HelperService: NSObject, MASHelperProtocol {
    static let machServiceName = "com.duoupdater.helper"

    /// The caller (main app) must satisfy this requirement: Apple-anchored, our
    /// bundle id, our Developer ID team OU. This is THE security gate — only the
    /// real DuoUpdater app can drive root through this helper.
    private static let clientRequirement =
        "anchor apple generic and identifier \"com.duoupdater.app\" "
        + "and certificate leaf[subject.OU] = \"RS59HDH7Y3\""

    private static let workQueue = DispatchQueue(label: "com.duoupdater.helper.install")

    // MARK: Peer validation

    static func isValidClient(_ conn: NSXPCConnection) -> Bool {
        guard var token = auditToken(of: conn) else { return false }
        let data = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attrs = [kSecGuestAttributeAudit: data] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let guest = code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(clientRequirement as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }
        return SecCodeCheckValidity(guest, [], req) == errSecSuccess
    }

    /// `auditToken` is SPI on NSXPCConnection (stable since macOS 11) — no public
    /// API exposes it, so read it via KVC, where it bridges as an NSValue wrapping
    /// the `audit_token_t` struct. This is the long-standing pattern for XPC peer
    /// validation. If it ever returns nil we fail closed (reject the connection).
    private static func auditToken(of conn: NSXPCConnection) -> audit_token_t? {
        guard conn.responds(to: NSSelectorFromString("auditToken")),
              let value = conn.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { buf in
            value.getValue(buf.baseAddress!, size: buf.count)
        }
        return token
    }

    // MARK: MASHelperProtocol

    func installMASApp(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void) {
        Self.workQueue.async {
            guard adamID > 0 else { reply(-1, "invalid adamID"); return }
            // logPath: absolute, in the temp area, our prefix — bounds what the root
            // redirect can write.
            guard logPath.hasPrefix("/"),
                  (logPath as NSString).lastPathComponent.hasPrefix("duo-mas-") else {
                reply(-1, "invalid log path"); return
            }
            guard let mas = Self.bundledMASPath() else {
                reply(-1, "bundled mas not found"); return
            }
            // userName is interpolated inside single quotes — strip any quote so it
            // stays a single inert token.
            let safeUser = userName.replacingOccurrences(of: "'", with: "")
            // Identical orchestration to the old MASInstaller osascript command — only
            // the privilege source changed (this process is already root):
            //   launchctl asuser <uid> → user's Aqua session (storedownloadd runs there)
            //   script -q /dev/null     → pseudo-TTY (mas emits live "N% downloaded")
            //   env SUDO_*              → mas seteuid's back to the account owner
            let command =
                "/bin/launchctl asuser \(uid) "
                + "/usr/bin/script -q /dev/null "
                + "/usr/bin/env SUDO_UID=\(uid) SUDO_GID=\(gid) SUDO_USER='\(safeUser)' MAS_NO_AUTO_INDEX=1 "
                + "'\(mas)' install \(adamID) --force > '\(logPath)' 2>&1"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                reply(-1, "launch failed: \(error.localizedDescription)")
                return
            }
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let err = String(data: errData, encoding: .utf8)
            reply(process.terminationStatus, (err?.isEmpty ?? true) ? nil : err)
        }
    }

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0")
    }

    /// Locate `mas` relative to the helper's own embedded location:
    /// `…/Contents/MacOS/<helper>` → `…/Contents/Resources/mas`. Never trusts a
    /// path supplied by the client.
    private static func bundledMASPath() -> String? {
        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            return nil
        }
        let mas = URL(fileURLWithPath: execPath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()   // …/Contents/MacOS
            .deletingLastPathComponent()   // …/Contents
            .appendingPathComponent("Resources/mas")
            .path
        return FileManager.default.isExecutableFile(atPath: mas) ? mas : nil
    }
}
