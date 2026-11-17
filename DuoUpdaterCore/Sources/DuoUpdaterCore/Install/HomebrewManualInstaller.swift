import AppKit
import Foundation

/// Prepares an `installer manual` with Brew, then hands the declared installer
/// to the user. `unpack` uses Brew's authenticated definition and downloader;
/// it does not uninstall the old app, run cask hooks or advance its receipt.
public actor HomebrewManualInstaller {
    public init() {}

    public enum ManualError: LocalizedError {
        case changedDefinition
        case unsafeArtifact
        case couldNotOpen

        public var errorDescription: String? {
            switch self {
            case .changedDefinition:
                return "Homebrew’s installer definition changed. Check for updates again before opening it."
            case .unsafeArtifact:
                return "Homebrew’s declared manual installer could not be verified. Nothing was opened."
            case .couldNotOpen:
                return "The installer could not be opened. Try again."
            }
        }
    }

    struct Plan: Equatable, Sendable {
        let token: String
        let version: String
        let path: String
    }

    static let supportedExtensions: Set<String> = ["app", "pkg", "mpkg"]

    static func isRelativeArtifactPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Use the definition read by the owning Brew, not the plain catalog that
    /// supplied the reminder. A definition change requires a new check/approval.
    static func plan(from data: Data, token: String, version: String?, path: String) throws -> Plan {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]], casks.count == 1,
              let cask = casks.first,
              let canonical = cask["token"] as? String,
              canonical == token.split(separator: "/").last.map(String.init)
                || ((cask["old_tokens"] as? [String]) ?? []).contains(token.split(separator: "/").last.map(String.init) ?? ""),
              let resolvedVersion = cask["version"] as? String,
              resolvedVersion == version,
              isRelativeArtifactPath(canonical), !canonical.contains("/"),
              isRelativeArtifactPath(resolvedVersion), !resolvedVersion.contains("/"),
              case .manualInstaller(let declaredPath) = HomebrewCaskCatalog.installKind(
                artifacts: cask["artifacts"], dependsOn: cask["depends_on"],
                conflictsWith: cask["conflicts_with"], disabled: (cask["disabled"] as? Bool) == true),
              declaredPath == path,
              supportedExtensions.contains((path as NSString).pathExtension.lowercased())
        else { throw ManualError.changedDefinition }
        if let incompatibility = CaskIncompatibility.check(
            macOS: CaskMacOSRequirement.parse(dependsOn: cask["depends_on"]),
            architectures: HomebrewCaskCatalog.architectures(dependsOn: cask["depends_on"])) {
            throw incompatibility
        }
        return Plan(token: canonical, version: resolvedVersion, path: declaredPath)
    }

    /// A declared relative path still must resolve inside the extracted tree.
    /// A symlink to a different app (even one with a trusted signature) is not
    /// the installer Brew just downloaded.
    static func artifact(in directory: URL, path: String) throws -> URL {
        guard isRelativeArtifactPath(path) else { throw ManualError.unsafeArtifact }
        let lexical = directory.standardizedFileURL
        let base = lexical.resolvingSymlinksInPath()
        let expected = lexical.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(lexical.lastPathComponent).standardizedFileURL
        guard base == expected else { throw ManualError.unsafeArtifact }
        let file = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: file.path)
        else { throw ManualError.unsafeArtifact }
        return file
    }

    public func prepareAndOpen(
        caskToken: String, app: URL, version: String?, path: String,
        onOutput: @Sendable @escaping (String) -> Void,
        beforeOpen: @Sendable () async -> Void = {}
    ) async throws -> URL {
        guard let brew = HomebrewInstaller.brewPathOverride ?? HomebrewInstaller.brewPath() else {
            throw HomebrewInstaller.BrewError.brewNotFound
        }
        try await HomebrewInstaller.validateAppOwner(app)
        var environment = await LoginShellEnvironment.commandEnvironment()
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["NONINTERACTIVE"] = "1"
        // `unpack` is a developer command; keep its mode local to this child.
        environment["HOMEBREW_DEVELOPER"] = "1"
        let info = try await ChildProcess.run(
            brew, ["info", "--json=v2", "--cask", "--", caskToken],
            environment: environment, standardError: .mergeIntoOutput, onCancel: .terminateChild)
        guard info.succeeded else {
            throw HomebrewInstaller.BrewError.failed(
                code: info.terminationStatus, output: String(decoding: info.standardOutput, as: UTF8.self))
        }
        let plan = try Self.plan(from: info.standardOutput, token: caskToken, version: version, path: path)
        let work = PackageInstaller.workDirectory(forInstalledApp: app)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        InstallJournal.noteWorkDirectory(work)
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: work) } }
        let (outcome, output) = try await StreamedLines.run(
            brew, ["unpack", "--cask", "--destdir=\(work.path)", "--", caskToken],
            environment: environment, onCancel: .interruptChild, onOutput: onOutput)
        guard outcome.succeeded else {
            throw HomebrewInstaller.BrewError.failed(code: outcome.terminationStatus, output: output)
        }
        try Task.checkCancellation()
        let extracted = work.appendingPathComponent("\(plan.token)-\(plan.version)", isDirectory: true)
        let declared = try Self.artifact(in: extracted, path: plan.path)
        let staged = work.appendingPathComponent(declared.lastPathComponent)
        let copied = try await ChildProcess.run(
            "/usr/bin/ditto", [declared.path, staged.path], onCancel: .terminateChild)
        guard copied.succeeded else { throw ManualError.unsafeArtifact }
        if ["pkg", "mpkg"].contains(staged.pathExtension.lowercased()) {
            // These are deliberately interactive even when the helper is ready:
            // the cask explicitly requires its installer to be run by a person.
            _ = try await PackageInstaller().reopen(package: staged, installedApp: app, beforeOpen: beforeOpen)
        } else {
            let proof = try await Self.verifyInstallerApp(staged, installedApp: app)
            await beforeOpen()
            try await InstallCommit.run("Homebrew installer hand-off") {
                guard try await Self.verifyInstallerApp(staged, installedApp: app) == proof else {
                    throw ManualError.unsafeArtifact
                }
                try await Self.openInstallerApp(staged)
            }
        }
        keep = true
        return staged
    }

    @MainActor
    private static func openInstallerApp(_ installer: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        // An older installer with the same bundle ID may still be open. Launch
        // this verified copy rather than merely activating that other process.
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: installer, configuration: configuration)
        } catch {
            throw ManualError.couldNotOpen
        }
    }

    private static func verifyInstallerApp(_ installer: URL, installedApp: URL) async throws -> String {
        try await offCooperativePool {
            guard installer.pathExtension.lowercased() == "app",
                  let proof = try SignatureVerifier.verifyCodeSignatureCapturingCdhash(appAt: installer)
            else { throw ManualError.unsafeArtifact }
            try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: installedApp, downloadedApp: installer)
            try SignatureVerifier.verifyRunnableArchitecture(appAt: installer)
            try SignatureVerifier.verifyRunnableSystemVersion(appAt: installer)
            return proof
        }
    }
}
