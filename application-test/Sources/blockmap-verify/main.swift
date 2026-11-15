import AppKit
import CryptoKit
import Darwin
import Foundation
import DuoUpdaterCore

// Non-shipping VM harness: runs production archive verification and swap against
// explicitly prepared copies, then starts that exact bundle through LaunchServices.
// Input/output paths and all artifacts are kept for independent inspection.
struct Input: Decodable {
    let name: String
    let appPath: String
    let archivePath: String?
    let downloadURL: URL
    let mapURL: URL?
    let downloadSize: Int64?
    let sha256: String?
    let sha512: String?
    let version: String
    let outputPath: String
    let launch: Bool
    let useCoordinator: Bool?
}

struct Receipt: Codable {
    let name: String
    let date: Date
    let appPath: String
    var scannedVersion: String?
    var installedVersion: String?
    var bytesDownloaded: Int64?
    var archiveSHA256: String?
    var downloadedArchive: String?
    var usedDelta: Bool?
    var ledgerDownloadKind: TrafficDownloadKind?
    var deltaBadge: Bool?
    var launchPID: Int32?
    var launchedBundle: String?
    var stayedRunning: Bool?
    var state = "started"
    var error: String?
}

@main struct Verify {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw NSError(domain: "blockmap-verify: pass one JSON input path", code: 2)
            }
            let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let appURL = URL(fileURLWithPath: input.appPath).standardizedFileURL
            // This harness is for prepared VM copies. Refuse system/host copies.
            let allowed = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/DuoBlockmap").path + "/"
            guard appURL.path.hasPrefix(allowed), appURL.pathExtension == "app" else {
                throw NSError(domain: "blockmap-verify: target must be inside ~/Applications/DuoBlockmap", code: 2)
            }
            var receipt = Receipt(name: input.name, date: Date(), appPath: appURL.path)
            do {
                let scanned = await offCooperativePool { AppScanner().scan(bundlesAt: [appURL]) }
                guard let app = scanned.first, scanned.count == 1 else {
                    throw NSError(domain: "blockmap-verify: scanner did not find the prepared copy", code: 3)
                }
                receipt.scannedVersion = app.shortVersion
                let remote = RemoteVersion(shortVersion: input.version, version: nil,
                    downloadURL: input.downloadURL, downloadSize: input.downloadSize,
                    electronBlockmapURL: input.mapURL, sourceName: "Vendor", vendorInstallerKind: .zip,
                    expectedSHA512: input.sha512, expectedSHA256: input.sha256)
                let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: input.version))
                if input.useCoordinator == true {
                    guard ProcessInfo.processInfo.environment["DUO_STATE_DIR"] != nil else {
                        throw NSError(domain: "blockmap-verify: coordinator ledger requires isolated DUO_STATE_DIR", code: 2)
                    }
                    let unusedStash = URL(fileURLWithPath: input.outputPath)
                        .deletingLastPathComponent().appendingPathComponent("unused-stash")
                    let coordinator = InstallCoordinator(vendor: VendorInstaller(
                        stashCachesDirectory: unusedStash, stashApplicationSupportDirectory: unusedStash))
                    let outcome = try await coordinator.perform(
                        result, route: .vendor, installedPopulation: nil,
                        digestOnlyAllowed: false, progress: { _ in })
                    receipt.bytesDownloaded = outcome.bytesDownloaded
                    receipt.usedDelta = outcome.usedDelta
                    // Same public event/ledger path the App uses after perform.
                    await EventStore.shared.append(DuoEvent(client: .app, payload: .install(InstallEvent(
                        appID: app.id, appName: app.name, bundleID: app.bundleID,
                        fromVersion: app.shortVersion, toVersion: input.version,
                        fromBuild: app.buildVersion, toBuild: remote.version,
                        sourceName: remote.sourceName, bytes: outcome.bytesDownloaded,
                        downloadKind: outcome.usedDelta ? .delta : .full, applied: outcome.applied))))
                    await EventStore.shared.flush()
                    if let stat = await EventStore.shared.appTrafficStats().first(where: { $0.appID == app.id }),
                       let event = stat.events.last {
                        receipt.ledgerDownloadKind = event.downloadKind
                        receipt.deltaBadge = stat.deltaEvidence(for: event) != nil
                    }
                } else {
                    let installer = VendorInstaller()
                    let download: DownloadedUpdate
                    if let path = input.archivePath {
                        let work = FileManager.default.temporaryDirectory.appendingPathComponent("duo-blockmap-verify-\(UUID())")
                        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
                        download = DownloadedUpdate(archiveURL: URL(fileURLWithPath: path), bytesDownloaded: 0, workDir: work)
                    } else {
                        download = try await installer.download(result, useLocalStash: false,
                                                                population: nil, onStage: { _ in })
                    }
                    defer { try? FileManager.default.removeItem(at: download.workDir) }
                    receipt.bytesDownloaded = download.bytesDownloaded
                    receipt.archiveSHA256 = try await offCooperativePool {
                        let handle = try FileHandle(forReadingFrom: download.archiveURL)
                        defer { try? handle.close() }
                        var hash = SHA256()
                        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
                        return hash.finalize().map { String(format: "%02x", $0) }.joined()
                    }
                    receipt.downloadedArchive = download.archiveURL.lastPathComponent
                    try await installer.apply(result, download: download, digestOnlyAllowed: false, onStage: { _ in })
                }
                let after = await offCooperativePool { AppScanner().scan(bundlesAt: [appURL]) }
                receipt.installedVersion = after.first?.shortVersion
                guard receipt.installedVersion == input.version else {
                    throw NSError(domain: "blockmap-verify: installed version differs from requested version", code: 4)
                }
                receipt.state = "installed"
                if input.launch {
                    let config = NSWorkspace.OpenConfiguration()
                    config.createsNewApplicationInstance = true
                    config.activates = false
                    let running = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                    receipt.launchPID = running.processIdentifier
                    receipt.launchedBundle = running.bundleURL?.standardizedFileURL.path
                    guard receipt.launchedBundle == appURL.path else {
                        throw NSError(domain: "blockmap-verify: LaunchServices opened another copy", code: 5)
                    }
                    // A settling interval, not a performance assertion. The PID and
                    // bundle identity are observed before and after it.
                    try await Task.sleep(for: .seconds(5))
                    receipt.stayedRunning = kill(running.processIdentifier, 0) == 0 && !running.isTerminated
                    let alive = receipt.stayedRunning == true
                    _ = running.terminate()
                    try await Task.sleep(for: .milliseconds(500))
                    if !running.isTerminated { _ = running.forceTerminate() }
                    guard alive else { throw NSError(domain: "blockmap-verify: application exited during startup", code: 6) }
                    receipt.state = "installed-and-launched"
                }
            } catch {
                receipt.error = String(describing: error)
                receipt.state = "failed"
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(receipt)
            try data.write(to: URL(fileURLWithPath: input.outputPath))
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(receipt.error == nil ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2)
        }
    }
}
