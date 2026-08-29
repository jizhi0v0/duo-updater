import Foundation

/// Applies a Sparkle binary patch: installed bundle + `.delta` → the new bundle.
///
/// Sparkle's format is its own (version 3 since Sparkle 2.1 — a custom container
/// with lzma, replacing the xar/bzip2 of version 2), so the only correct reader
/// is Sparkle's own `BinaryDelta`. We ship that executable rather than reimplement
/// a format that has already changed once and carries no compatibility promise.
///
/// A patch saves download, not disk. Applying one reads the installed bundle and
/// writes a complete replacement into the scratch directory, so the I/O is
/// comparable to unpacking the full archive — measured at **7.5 s for ChatGPT's
/// 1.4 GB bundle** against a 1.9 MB patch. Still a large net win there (the full
/// archive took 120 s to download alone), but a caller should not read "incremental"
/// as "free", and a nearly-full disk can fail the patch route for space.
///
/// The patch is NOT trusted on the strength of having applied cleanly. What it
/// produces is an app bundle like any other, and it goes through exactly the same
/// gates a downloaded archive does — code signature, Team ID, bundle identifier.
/// That is what makes an unverified patch safe to attempt: a tampered one cannot
/// yield a bundle that still carries the vendor's Apple-issued signature.
/// (Confirmed end to end on Keka 1.6.5 → 1.6.7: the patched bundle came out
/// `accepted / source=Notarized Developer ID`, Team 4FG648TM2A.)
public enum DeltaApplier {

    public enum DeltaError: LocalizedError {
        case toolMissing
        case applyFailed(code: Int32, message: String)
        case producedNothing
        case baselineUnreadable
        case baselineMoved(expected: String, found: String)

        public var errorDescription: String? {
            switch self {
            case .toolMissing:
                return "The delta patch tool is missing from this build."
            case .applyFailed(let code, let message):
                let detail = message.isEmpty ? "" : " — \(message)"
                return "Applying the incremental patch failed (exit \(code))\(detail)."
            case .producedNothing:
                return "The incremental patch produced no application bundle."
            case .baselineUnreadable:
                return "Could not read the installed build to apply an incremental patch."
            case .baselineMoved(let expected, let found):
                return "The installed build changed from \(expected) to \(found) while the "
                    + "incremental patch was downloading."
            }
        }
    }

    /// Where `BinaryDelta` lives, or nil when this build doesn't carry it.
    ///
    /// Two homes because two products use this. The menu-bar app finds it inside
    /// its own bundle; `duo`, which is a bare executable with no bundle of its
    /// own, borrows the installed app's copy — the same tool, and the CLI is not
    /// worth a second 1.4 MB universal binary. A build with neither simply has no
    /// delta route and every install takes the full archive.
    public static func toolURL(bundle: Bundle = .main) -> URL? {
        if let embedded = bundle.url(forAuxiliaryExecutable: "BinaryDelta"),
           FileManager.default.isExecutableFile(atPath: embedded.path) {
            return embedded
        }
        let shared = URL(fileURLWithPath:
            "/Applications/DuoUpdater.app/Contents/MacOS/BinaryDelta")
        if FileManager.default.isExecutableFile(atPath: shared.path) { return shared }
        return nil
    }

    /// Whether this build can apply patches at all — the gate a caller checks
    /// before choosing the delta route over the full archive.
    public static var isAvailable: Bool { toolURL() != nil }

    /// `BinaryDelta apply <old> <new> <patch>`.
    ///
    /// - Parameters:
    ///   - installedApp: the bundle on disk the patch was cut against. Read only.
    ///   - patch: the downloaded `.delta`.
    ///   - destination: where to write the patched bundle. Must not exist; the
    ///     caller owns it and the scratch directory around it.
    ///
    /// Throws on a non-zero exit or a missing result. Never touches `installedApp`
    /// — a failed patch leaves the running app exactly as it was, which is what
    /// lets the caller fall back to the full download without cleanup.
    public static func apply(
        installedApp: URL,
        patch: URL,
        destination: URL,
        bundle: Bundle = .main
    ) throws {
        guard let tool = toolURL(bundle: bundle) else { throw DeltaError.toolMissing }

        let process = Process()
        process.executableURL = tool
        process.arguments = ["apply", installedApp.path, destination.path, patch.path]
        let errPipe = Pipe()
        let outPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = outPipe

        try process.run()
        // Drained before `waitUntilExit` so a verbose failure can't fill the pipe
        // buffer and deadlock the tool against a reader that never runs.
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        _ = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").last.map(String.init) ?? ""
            throw DeltaError.applyFailed(code: process.terminationStatus, message: message)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw DeltaError.producedNothing
        }
    }

    /// Verify a downloaded patch and rebuild the app from it — the whole patch
    /// route in one place, so the two installers cannot drift apart. They had
    /// already started to: one borrowed the archive's signature for an unsigned
    /// patch, the other did not.
    ///
    /// Order matters. The baseline is checked first because it is free and it is
    /// the failure that actually happens: the patch is selected during `download`
    /// and applied after an unbounded wait for the apply permit, during which the
    /// app's own updater may have replaced the bundle (ChatGPT does exactly this).
    /// `BinaryDelta` would catch it anyway — it refuses a mismatched source with
    /// exit 1 and writes nothing, verified here — but only after reading a
    /// multi-gigabyte bundle, so catching it up front costs nothing and saves that.
    ///
    /// Then the signature, and only then the patch tool. A file that failed
    /// verification must never reach `apply`.
    ///
    /// - Parameter edPublicKey: the app's `SUPublicEDKey`. When present, a patch
    ///   MUST carry its own signature — never the archive's, which signs different
    ///   bytes and can only fail. When absent the patch is unverified until it
    ///   becomes a bundle, and the caller's code-signature and Team-ID gates carry
    ///   the trust, exactly as they do for any unsigned vendor archive: a tampered
    ///   patch cannot produce a bundle still bearing the vendor's Apple signature.
    static func reconstruct(
        installedApp: URL,
        patch: DeltaPatch,
        patchFile: URL,
        workDir: URL,
        edPublicKey: String?,
        onStage: (InstallStage) -> Void
    ) throws -> URL {
        guard let onDisk = InstalledBuild.read(at: installedApp) else {
            throw DeltaError.baselineUnreadable
        }
        guard onDisk == patch.fromBuild else {
            throw DeltaError.baselineMoved(expected: patch.fromBuild, found: onDisk)
        }

        if let key = edPublicKey, !key.isEmpty {
            onStage(.verifyingSignature)
            let bytes = try Data(contentsOf: patchFile, options: .mappedIfSafe)
            try SignatureVerifier.verifyEdSignature(
                fileData: bytes,
                signatureBase64: patch.edSignature,
                publicKeyBase64: key)
        }

        onStage(.extracting)
        let destination = workDir
            .appendingPathComponent("patched-\(installedApp.lastPathComponent)")
        try? FileManager.default.removeItem(at: destination)
        try apply(installedApp: installedApp, patch: patchFile, destination: destination)
        return destination
    }

    /// The patch that upgrades `app` as it stands right now, or nil when none of
    /// the published patches match.
    ///
    /// Matched on `CFBundleVersion`, because that is the number Sparkle cuts
    /// patches against (`sparkle:deltaFrom` carries `sparkle:version`). Apps whose
    /// marketing and build numbers differ — Keka 1.6.5 is build 5715, ChatGPT
    /// 26.818.41705 is build 6971 — would match nothing, or worse the wrong thing,
    /// on the marketing string.
    ///
    /// A miss is ordinary, not an error: vendors publish a handful of patches per
    /// release (5, 8, 13 on the feeds measured here), so anyone who skipped a few
    /// versions simply takes the full archive.
    public static func patch(for app: InstalledApp, in remote: RemoteVersion) -> DeltaPatch? {
        guard !remote.deltas.isEmpty, let installedBuild = app.buildVersion else { return nil }
        return remote.deltas.first { $0.fromBuild == installedBuild }
    }
}

/// Marks a failure that happened on the incremental-patch route and is therefore
/// recoverable by retrying with the full archive.
///
/// A distinct type rather than a flag because it decides whether an install gets a
/// second attempt: only failures wrapped in this are retried, so a genuine gate
/// failure on the full route still stops the install instead of looping.
/// Whether a failure on the patch route is worth retrying with the full archive.
///
/// The delta route's premise is that anything that goes wrong applying a patch
/// is recoverable by taking the full download instead — true for the TRUST gates
/// (a bad patch really can produce a bundle whose signature is broken while the
/// full archive's is fine) and false for the LIVENESS gates. An OS floor or a
/// missing architecture slice is a property of the VERSION, not of how its bytes
/// arrived: the full archive carries the same bundle and is refused for the same
/// reason. Retrying buys the user a second, full-size download — hundreds of
/// megabytes for a large app — and the identical refusal.
///
/// Lives here rather than inline in the two installers so both classify the same
/// way and the rule can be tested without running an install.
public func deltaRouteFailureIsWorthRetrying(_ error: Error) -> Bool {
    guard let verify = error as? SignatureVerifier.VerifyError else { return true }
    switch verify {
    case .unsupportedSystemVersion, .unrunnableArchitecture:
        return false
    case .edSignatureMissing, .edSignatureInvalid, .codeSignatureInvalid,
         .noTeamIdentifier, .teamIdentifierMismatch,
         .noBundleIdentifier, .bundleIdentifierMismatch:
        return true
    }
}

public struct DeltaRouteFailure: LocalizedError {
    public let underlying: Error
    /// Bytes the abandoned patch attempt already pulled over the network.
    ///
    /// Carried so the retry can add them to its own total. Without this the ledger
    /// records only the fallback's download and silently under-counts exactly the
    /// failed-delta case — biasing the one dataset used to judge whether the patch
    /// route is worth keeping.
    public let bytesSpent: Int64

    public init(underlying: Error, bytesSpent: Int64 = 0) {
        self.underlying = underlying
        self.bytesSpent = bytesSpent
    }

    /// Reads as the underlying problem: if the fallback also fails, the user should
    /// see what actually went wrong, not that a patch was tried first.
    public var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription
            ?? underlying.localizedDescription
    }
}
