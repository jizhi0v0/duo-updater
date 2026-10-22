import Foundation
import Testing
@testable import DuoUpdaterCore

/// `OneClickGate`: a recipe family names which installed copies may take the
/// one-click; everything else keeps detection only. Exercised through the
/// gates registered today (MuseScore, Memoh and Readest by installed version, GitKraken
/// by an asar entry) and through both places that enforce them.
struct OneClickGateTests {
    /// A bundle at a fresh path whose `app.asar` packs `files` (path → contents),
    /// in Electron's layout: `[4][header pickle size]`, then
    /// `[payload][json length][json]` padded to 4 bytes, then the file bytes.
    private func bundle(_ files: [String: String]?) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("one-click-gate-\(UUID().uuidString)/App.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        guard let files else { return app }
        var tree: [String: Any] = [:]
        var body = Data()
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let bytes = Data(text.utf8)
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
            insert(&tree, path.split(separator: "/").map(String.init)[...])
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

    private func app(_ bundleID: String, _ version: String?, at path: URL? = nil) -> InstalledApp {
        InstalledApp(
            name: "Fixture", bundleID: bundleID, shortVersion: version, buildVersion: nil,
            path: path ?? URL(fileURLWithPath: "/Applications/ZZFixture-\(UUID().uuidString).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    private func gitKraken(_ edition: String) throws -> InstalledApp {
        app("com.axosoft.gitkraken", "12.5.0", at: try bundle([
            "src/main/static/clientType.js": "// auto-generated\nmodule.exports = '\(edition)';\n",
            "package.json": #"{"name":"gitkraken","version":"12.5.0"}"#,
        ]))
    }

    private func offer(_ app: InstalledApp, source: String = "Vendor") -> UpdateResult {
        UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: "99.0", version: nil,
                downloadURL: URL(string: "https://example.invalid/App.zip"),
                sourceName: source, vendorInstallerKind: .zip),
            status: .updateAvailable(latest: "99.0"))
    }

    @Test func theRegisteredGatesAreTheMeasuredCases() {
        #expect(Set(OneClickGateRegistry.gates.map(\.bundleID))
            == ["org.musescore.MuseScore", "com.axosoft.gitkraken", "ai.memoh.desktop", "co.zeit.hyper",
                "com.bilingify.readest", "io.masscode.app"])
    }

    /// Versions of the real bundles: stable 3.4.1, 3.4.0, 3.0.2 and the canary
    /// 4.0.0-canary.5, all `co.zeit.hyper`, Team JW6Y669B67. Older canary
    /// tags (`3.4.0-canary.1`, `3.0.1-canary.4`) stamp the same shape.
    @Test func hyperOneClickIsForStableCopiesOnly() {
        for version in ["3.4.1", "3.4.0", "3.0.2", "4.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("co.zeit.hyper", version)) == nil, "\(version)")
        }
        for version in ["4.0.0-canary.5", "3.4.0-canary.1", "3.0.1-canary.4"] {
            #expect(OneClickGateRegistry.withholding(app("co.zeit.hyper", version)) != nil, "\(version)")
        }
    }

    /// The versions of the real bundles: GitHub's stable dmgs (0.12.16, 0.12.12,
    /// 0.10.1, 0.7.9) and the nightly `.app.tar.gz` from
    /// download.readest.com/nightly/ (0.12.16-2026102206), all
    /// `com.bilingify.readest`, Team J5W48D69VR.
    @Test func readestOneClickIsForStableBuildsOnly() {
        for version in ["0.12.16", "0.12.12", "0.10.1", "0.7.9", "1.0"] {
            #expect(OneClickGateRegistry.withholding(app("com.bilingify.readest", version)) == nil, "\(version)")
        }
        for version in ["0.12.16-2026102206", "0.11.4-2026061406"] {
            #expect(OneClickGateRegistry.withholding(app("com.bilingify.readest", version)) != nil, "\(version)")
        }
    }

    @Test func museScoreOneClickIsFor4xCopiesOnly() {
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", "3.6.2.548020600")) != nil)
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", nil)) != nil)
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", "4.7.4")) == nil)
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", "4.0")) == nil)
    }

    /// The versions of the real bundles: the vendor's CDN builds, and the OSS
    /// repo's GitHub builds (Memoh 0.16.0, Memoh Local 0.13.0, Memoh-Desktop
    /// 0.9.0, the 0.7.0 one) — all `ai.memoh.desktop`, Team P9R669C27U.
    @Test func memohOneClickIsForTheVendorsDatedBuildsOnly() {
        for version in ["2026.10.19-1", "2026.9.16-1", "2027.1.2-3"] {
            #expect(OneClickGateRegistry.withholding(app("ai.memoh.desktop", version)) == nil, "\(version)")
        }
        for version in ["0.16.0", "0.13.0", "0.9.0", "0.7.0", "1.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("ai.memoh.desktop", version)) != nil, "\(version)")
        }
        #expect(OneClickGateRegistry.withholding(app("ai.memoh.desktop", nil)) != nil)
    }

    /// The versions of real bundles (5.12.0, 6.0.0, 6.2.1, 6.3.1, 2.0.0-beta.6,
    /// all `io.masscode.app`). v6 reads only a Markdown Vault, which v5
    /// introduced; a 4.x or older library is unreadable by it.
    @Test func massCodeOneClickIsFor5xAnd6xCopiesOnly() {
        for version in ["6.3.1", "6.2.1", "6.0.0", "5.12.0", "5.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("io.masscode.app", version)) == nil, "\(version)")
        }
        for version in ["4.7.1", "3.12.1", "2.0.0-beta.6", "7.0.0", "60.0"] {
            #expect(OneClickGateRegistry.withholding(app("io.masscode.app", version)) != nil, "\(version)")
        }
        #expect(OneClickGateRegistry.withholding(app("io.masscode.app", nil)) != nil)
    }

    @Test func gitKrakenOneClickIsForAProvenNormalEditionOnly() throws {
        #expect(OneClickGateRegistry.withholding(try gitKraken("NORMAL")) == nil)
        #expect(OneClickGateRegistry.withholding(try gitKraken("STANDALONE")) != nil)
        // No asar, no entry, or an entry naming no edition: withheld.
        let id = "com.axosoft.gitkraken"
        #expect(OneClickGateRegistry.withholding(app(id, "12.5.0", at: try bundle(nil))) != nil)
        #expect(OneClickGateRegistry.withholding(app(id, "12.5.0", at: try bundle(["package.json": "{}"]))) != nil)
        #expect(OneClickGateRegistry.withholding(app(id, "12.5.0", at: try bundle(
            ["src/main/static/clientType.js": "module.exports = 1;"]))) != nil)
    }

    @Test func anAppWithNoGateIsUntouched() throws {
        let other = app("com.example.other", "1.0", at: try bundle(
            ["src/main/static/clientType.js": "module.exports = 'STANDALONE';"]))
        #expect(OneClickGateRegistry.withholding(other) == nil)
    }

    /// The offer: detection stays, the one-click goes, whatever the source.
    @Test func aWithheldCopyIsDetectionOnly() throws {
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)
        let environment = InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        func can(_ result: UpdateResult) -> Bool {
            UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment)
        }
        #expect(can(offer(try gitKraken("NORMAL"))))
        #expect(!can(offer(try gitKraken("STANDALONE"))))
        #expect(can(offer(app("org.musescore.MuseScore", "4.7.4"), source: "GitHub")))
        #expect(!can(offer(app("org.musescore.MuseScore", "3.6.2.548020600"), source: "GitHub")))
    }

    /// The gate: refused before anything is touched, on every route.
    @Test func theCoordinatorRefusesAWithheldCopy() async throws {
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        for (result, route) in [
            (offer(app("org.musescore.MuseScore", "3.6.2.548020600"), source: "GitHub"), InstallCoordinator.Route.vendor),
            (offer(try gitKraken("STANDALONE")), .vendor),
            (offer(try gitKraken("STANDALONE")), .homebrew),
        ] {
            await #expect(throws: OneClickGateRegistry.Withheld.self) {
                _ = try await coordinator.perform(
                    result, route: route, installedPopulation: [result.app],
                    digestOnlyAllowed: false, progress: { _ in })
            }
        }
    }
}
