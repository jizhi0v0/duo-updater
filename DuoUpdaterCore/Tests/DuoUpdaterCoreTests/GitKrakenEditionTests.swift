import Foundation
import Testing
@testable import DuoUpdaterCore

/// GitKraken's On-Premise Serverless edition shares bundle id, Team and versions
/// with the normal one; only `src/main/static/clientType.js` in `app.asar` says
/// which it is. A copy that is not NORMAL keeps detection and loses one-click.
struct GitKrakenEditionTests {
    /// A bundle whose `app.asar` packs `files` (path → contents), in the layout
    /// Electron writes: `[4][header pickle size]`, then `[payload][json length][json]`
    /// padded to 4 bytes, then the file bytes.
    private func bundle(_ files: [String: String], asar: Bool = true) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("gk-edition-\(UUID().uuidString)/GitKraken.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        guard asar else { return app }
        var tree: [String: Any] = [:]
        var body = Data()
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let bytes = Data(text.utf8)
            let parts = path.split(separator: "/").map(String.init)
            func insert(_ node: inout [String: Any], _ rest: ArraySlice<String>) {
                var children = node["files"] as? [String: Any] ?? [:]
                if rest.count == 1 {
                    children[rest.first!] = ["size": bytes.count, "offset": String(body.count)]
                } else {
                    var child = children[rest.first!] as? [String: Any] ?? [:]
                    insert(&child, rest.dropFirst())
                    children[rest.first!] = child
                }
                node["files"] = children
            }
            insert(&tree, parts[...])
            body.append(bytes)
        }
        let json = try JSONSerialization.data(withJSONObject: tree)
        let padded = (json.count + 3) / 4 * 4
        func le(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        var data = le(4) + le(8 + padded) + le(4 + padded) + le(json.count) + json
        data.append(Data(count: padded - json.count))
        data.append(body)
        try data.write(to: resources.appendingPathComponent("app.asar"))
        return app
    }

    private func clientType(_ edition: String) -> [String: String] {
        ["src/main/static/clientType.js": "// auto-generated\nmodule.exports = '\(edition)';\n",
         "package.json": #"{"name":"gitkraken","version":"12.6.0"}"#]
    }

    @Test func readsTheEditionTheAppExports() throws {
        #expect(GitKrakenEdition.clientType(bundleAt: try bundle(clientType("NORMAL"))) == "NORMAL")
        #expect(GitKrakenEdition.clientType(bundleAt: try bundle(clientType("STANDALONE"))) == "STANDALONE")
    }

    @Test func onlyAProvenNormalCopyKeepsOneClick() throws {
        let id = GitKrakenEdition.bundleID
        #expect(!GitKrakenEdition.withholdsOneClick(bundleID: id, bundleURL: try bundle(clientType("NORMAL"))))
        #expect(GitKrakenEdition.withholdsOneClick(bundleID: id, bundleURL: try bundle(clientType("STANDALONE"))))
        // Unreadable or missing: withheld, the safe direction.
        #expect(GitKrakenEdition.withholdsOneClick(bundleID: id, bundleURL: try bundle([:], asar: false)))
        #expect(GitKrakenEdition.withholdsOneClick(
            bundleID: id, bundleURL: try bundle(["package.json": "{}"])))
        #expect(GitKrakenEdition.withholdsOneClick(
            bundleID: id, bundleURL: try bundle(["src/main/static/clientType.js": "module.exports = 1;"])))
        // Any other app is untouched, asar or not.
        #expect(!GitKrakenEdition.withholdsOneClick(
            bundleID: "com.example.other", bundleURL: try bundle(clientType("STANDALONE"))))
    }

    @Test func aStandaloneCopyIsDetectionOnly() throws {
        func result(_ edition: String) throws -> UpdateResult {
            let app = InstalledApp(
                name: "GitKraken", bundleID: GitKrakenEdition.bundleID, shortVersion: "12.5.0",
                buildVersion: nil, path: try bundle(clientType(edition)),
                isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
            return UpdateResult(
                app: app,
                remote: RemoteVersion(
                    shortVersion: "12.6.0", version: nil,
                    downloadURL: URL(string: "https://api.gitkraken.dev/releases/production/darwin/arm64/12.6.0/GitKraken-v12.6.0.zip"),
                    sourceName: "Vendor", vendorInstallerKind: .zip),
                status: .updateAvailable(latest: "12.6.0"))
        }
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)
        let environment = InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        #expect(UpdatePolicy.canAutoInstall(try result("NORMAL"), settings: settings, environment: environment))
        #expect(!UpdatePolicy.canAutoInstall(try result("STANDALONE"), settings: settings, environment: environment))
    }

    @Test func theInstallerRefusesAStandaloneCopy() async throws {
        let app = InstalledApp(
            name: "GitKraken", bundleID: GitKrakenEdition.bundleID, shortVersion: "12.5.0",
            buildVersion: nil, path: try bundle(clientType("STANDALONE")),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
        let result = UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: "12.6.0", version: nil,
                downloadURL: URL(string: "https://example.invalid/GitKraken.zip"),
                sourceName: "Vendor", vendorInstallerKind: .zip),
            status: .updateAvailable(latest: "12.6.0"))
        await #expect {
            _ = try await VendorInstaller().download(result, population: nil) { _ in }
        } throws: { error in
            guard case .otherEdition? = error as? VendorInstaller.InstallError else { return false }
            return true
        }
    }
}
