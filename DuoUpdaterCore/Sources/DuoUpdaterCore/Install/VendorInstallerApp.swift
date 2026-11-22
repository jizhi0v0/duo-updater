import AppKit
import CryptoKit
import Foundation

/// A release archive containing an interactive vendor installer. The installer
/// owns all changes to the app and its system components.
public struct VendorInstallerApp: Sendable, Hashable, Codable {
    public let bundleIdentifier: String
    let teamIdentifier: String
    let installedPath: String

    public init(bundleIdentifier: String, teamIdentifier: String, installedPath: String) {
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.installedPath = installedPath
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleIdentifier, teamIdentifier, installedPath
    }

    public init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier),
            teamIdentifier: try container.decode(String.self, forKey: .teamIdentifier),
            installedPath: try container.decode(String.self, forKey: .installedPath))
    }

    func matchesDestination(_ app: URL) -> Bool {
        app.standardizedFileURL.path == installedPath
    }

    enum HandoffError: LocalizedError {
        case wrongDestination, unexpectedInstaller, installerChanged

        var errorDescription: String? {
            switch self {
            case .wrongDestination:
                return "The vendor installer does not update this copy’s location."
            case .unexpectedInstaller:
                return "The download does not contain the expected vendor installer."
            case .installerChanged:
                return "The verified vendor installer changed before it could be opened."
            }
        }
    }

    /// Shared by the updater and nightly inspection. The version in the sealed
    /// installer plist has to name the actual release, as well as the feed URL.
    func verify(_ installer: URL, version: String?) throws -> String {
        let values = try installer.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard installer.pathExtension == "app", values.isDirectory == true, values.isSymbolicLink != true,
              let proof = try SignatureVerifier.verifyCodeSignatureCapturingCdhash(appAt: installer),
              CLIToolTrust.signature(of: installer, teamIdentifier: teamIdentifier,
                  signingIdentifier: bundleIdentifier) == .vendor
        else { throw HandoffError.unexpectedInstaller }
        let plist = SignatureVerifier.infoPlist(of: installer)
        guard let version, plist["CFBundleIdentifier"] as? String == bundleIdentifier,
              plist["CFBundleShortVersionString"] as? String == version
        else { throw HandoffError.unexpectedInstaller }
        try SignatureVerifier.verifyRunnableArchitecture(appAt: installer)
        try SignatureVerifier.verifyRunnableSystemVersion(appAt: installer)
        return proof
    }

    func fingerprint(_ installer: URL, remote: RemoteVersion) throws -> Data {
        guard let digest = remote.expectedSHA256 else {
            throw HandoffError.unexpectedInstaller
        }
        let seal = try verify(installer, version: remote.shortVersion)
        return Data(SHA256.hash(data: Data("\(digest.lowercased()):\(seal)".utf8)))
    }

    /// Explicit interactive launch. Re-check on every open, including a staged
    /// retry after cancellation. The vendor gets no host-supplied arguments.
    @MainActor
    public func open(_ installer: URL, result: UpdateResult, expectedProof: Data) async throws {
        let installed = result.app.path
        guard let remote = result.remote, remote.vendorInstallerApp == self else {
            throw HandoffError.unexpectedInstaller
        }
        try await offCooperativePool {
            guard matchesDestination(installed),
                  installed.resolvingSymlinksInPath().path == installedPath,
                  let bundleID = result.app.bundleID,
                  CLIToolTrust.signature(of: installed, teamIdentifier: teamIdentifier,
                      signingIdentifier: bundleID) == .vendor,
                  let current = SignatureVerifier.infoPlist(of: installed)["CFBundleShortVersionString"] as? String,
                  let version = remote.shortVersion,
                  VersionComparator.compare(current, version) == .orderedAscending
            else { throw HandoffError.wrongDestination }
            guard try fingerprint(installer, remote: remote) == expectedProof else {
                throw HandoffError.installerChanged
            }
        }
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.bundleURL?.standardizedFileURL == installer.standardizedFileURL }) {
            existing.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: installer, configuration: configuration)
    }
}
