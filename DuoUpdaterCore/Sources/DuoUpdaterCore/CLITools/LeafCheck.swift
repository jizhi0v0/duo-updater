import Foundation

public struct LeafCheck: Sendable {
    let release: LeafRelease
    let verifier: LeafVerifier

    public init() { self.init(release: LeafRelease(), verifier: LeafVerifier()) }
    init(release: LeafRelease, verifier: LeafVerifier) {
        self.release = release
        self.verifier = verifier
    }

    func published() async -> Result<String, any Error> {
        do { return .success(try await release.latest()) } catch { return .failure(error) }
    }

    func status(of install: LeafInstall, busy: Bool, published: Result<String, any Error>) async -> CLIToolStatus {
        let command = install.binary.map { Self.command($0) }
        let hasUpgrade = install.version.map {
            LeafRelease.isVersion($0) && VersionComparator.compare($0, "0.12.0") != .orderedAscending
        } ?? false
        func verdict(_ state: CLIToolState, latest: String? = nil, withheld: CLIToolWithheld? = nil,
                     note: String? = nil, offer: Bool = false) -> CLIToolStatus {
            CLIToolStatus(kind: .leaf, path: install.path, installedVersion: install.version, latestVersion: latest,
                          channel: nil, state: state, oneClick: offer ? command : nil, withheld: withheld, note: note,
                          manualCommand: hasUpgrade && (withheld == .unverified || withheld == .unsupportedInstaller) ? command : nil,
                          detail: .leaf(install))
        }
        guard let binary = install.binary else { return verdict(.unknown, withheld: .broken) }
        guard let installed = install.version else { return verdict(.unknown, withheld: .versionUnreadable) }
        guard LeafRelease.isVersion(installed) else {
            return verdict(.unknown, withheld: .channelUnreadable,
                           note: "leaf upgrade leaves prerelease builds on their own track")
        }
        let newest: String
        switch published {
        case .success(let version): newest = version
        case .failure(let error):
            return verdict(.unknown, withheld: .channelUnreadable, note: "Could not read Leaf's release: \(error)")
        }
        let comparison = VersionComparator.compare(installed, newest)
        if comparison == .orderedSame { return verdict(.upToDate, latest: newest) }
        if comparison == .orderedDescending { return verdict(.ahead, latest: newest) }
        guard let target = install.target, LeafRelease.targets.contains(target), !install.quarantined else {
            return verdict(.updateAvailable, latest: newest, withheld: .unverified,
                           note: "The binary must be a non-quarantined macOS Leaf build")
        }
        guard VersionComparator.compare(installed, "0.12.0") != .orderedAscending, install.writable else {
            return verdict(.updateAvailable, latest: newest, withheld: .unsupportedInstaller,
                           note: "leaf upgrade requires Leaf 0.12.0 or later and a writable install directory")
        }
        let verifier = self.verifier
        if await offCooperativePool({ verifier.knownVerdict(binary: binary, version: installed, target: target) }) == false {
            return verdict(.updateAvailable, latest: newest, withheld: .unverified,
                           note: "This file differs from the published Leaf build")
        }
        if busy { return verdict(.updateAvailable, latest: newest, withheld: .busy) }
        return verdict(.updateAvailable, latest: newest, offer: true)
    }

    static func command(_ binary: String) -> CLIToolCommand {
        CLIToolCommand(executable: binary, arguments: ["upgrade"], pathPrefix: nil,
                       shellLine: NvmCheck.shellQuoted(binary) + " upgrade")
    }
}
