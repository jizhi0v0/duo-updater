import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct MattermostBuildTests {
    private func bundle(
        plistVersion: String = "6.2.5", version: String,
        bundleID: String = "Mattermost.Desktop", packageName: String = "mattermost-desktop"
    ) throws -> URL {
        let app = TestScratch.directory("mattermost-build").appendingPathComponent("Mattermost.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleName": "Mattermost",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": plistVersion,
            "CFBundleVersion": "410327120331",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let package = try JSONSerialization.data(withJSONObject: ["name": packageName, "version": version])
        try asar(payload: package).write(to: contents.appendingPathComponent("Resources/app.asar"))
        return app
    }

    private func asar(payload: Data, offset: String = "0", padding: Int = 0) throws -> Data {
        var json = try JSONSerialization.data(withJSONObject: [
            "files": ["package.json": ["size": payload.count, "offset": offset]],
        ])
        json.append(Data(repeating: 32, count: padding))
        let padded = (json.count + 3) / 4 * 4
        func word(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        var data = word(4) + word(8 + padded) + word(4 + padded) + word(json.count) + json
        data.append(Data(count: padded - json.count))
        data.append(payload)
        return data
    }

    @Test(arguments: [
        ("6.1.0-rc.4", "6.1.0-rc.4"),
        ("6.2.5", "6.2.5-rc.5"),
        ("6.4.0", "6.4.0"),
        ("6.5.0", "6.5.0-nightly.20261116"),
    ])
    func scanAndDiskReadersAgreeOnTheCompletePackageVersion(plist: String, package: String) throws {
        let app = try bundle(plistVersion: plist, version: package)
        let scanner = AppScanner(testflight: TestFlightInventory(macRows: []), channelBinding: { _, _, _ in nil })
        let scanned = try #require(scanner.readApp(at: app))
        #expect(scanned.shortVersion == package)
        #expect(InstallJournal.versions(at: app).marketing == package)
        #expect(StagedRelaunch.diskVersionSide(app).marketing == package)
        #expect(RelaunchRecheck.read(app)?.side.marketing == package)
    }

    @Test func anUnchangedCoercedRCIsNotAnInstallThatCompleted() async throws {
        let app = try bundle(version: "6.2.5-rc.4")
        let entry = InstallJournal.Entry(
            job: "fixture", appID: app.path, appName: "Mattermost", bundleID: "Mattermost.Desktop",
            appPath: app.path, oldVersion: "6.2.5-rc.4", oldBuild: "410327120331", oldCDHash: nil,
            targetVersion: "6.2.5-rc.5", targetBuild: nil, route: "vendor", backupKey: "fixture",
            startedAt: Date(), owner: .init(pid: 0, started: 0), child: nil, damage: nil)
        #expect(await InstallJournal.classify(entry) == .resolved(.unchanged))
    }

    @Test(arguments: [
        ("com.example.other", "mattermost-desktop", "6.2.5-rc.5"),
        ("Mattermost.Desktop", "another-product", "6.2.5-rc.5"),
        ("Mattermost.Desktop", "mattermost-desktop", "99.0.0-rc.5"),
        ("Mattermost.Desktop", "mattermost-desktop", "6.2.5-custom-edition"),
    ])
    func foreignOrMismatchedMetadataDoesNotRewriteThePlist(id: String, name: String, version: String) throws {
        let app = try bundle(version: version, bundleID: id, packageName: name)
        #expect(MattermostBuild.version(in: app, bundleID: id, plistVersion: "6.2.5") == nil)
        #expect(InstallJournal.versions(at: app).marketing == "6.2.5")
    }

    @Test func aMissingAsarLeavesThePlistUsable() throws {
        let app = try bundle(version: "6.2.5-rc.5")
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Resources/app.asar"))
        #expect(InstallJournal.versions(at: app).marketing == "6.2.5")
    }

    @Test func aCorruptOffsetCannotOverflowDuringScanning() throws {
        let app = try bundle(version: "6.2.5-rc.5")
        let file = app.appendingPathComponent("Contents/Resources/app.asar")
        try asar(payload: Data("{}".utf8), offset: String(UInt64.max)).write(to: file)
        #expect(AsarEntryReader.packedEntry("package.json", inAsarAt: file) == nil)
    }

    @Test func oversizedValidHeadersAreNotAllocatedByTheReader() throws {
        let app = try bundle(version: "6.2.5-rc.5")
        let file = app.appendingPathComponent("Contents/Resources/app.asar")
        try asar(payload: Data("{}".utf8), padding: 17 * 1024 * 1024).write(to: file)
        #expect(AsarEntryReader.packedEntry("package.json", inAsarAt: file) == nil)
    }

    @Test func aReplacementWithEqualSizeAndTimestampInvalidatesTheCachedEntry() throws {
        let app = try bundle(version: "6.2.5-rc.4")
        let file = app.appendingPathComponent("Contents/Resources/app.asar")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(MattermostBuild.version(in: app, bundleID: "Mattermost.Desktop", plistVersion: "6.2.5") == "6.2.5-rc.4")
        let package = try JSONSerialization.data(withJSONObject: ["name": "mattermost-desktop", "version": "6.2.5-rc.5"])
        try asar(payload: package).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: file.path)
        #expect((try FileManager.default.attributesOfItem(atPath: file.path))[.size] as? NSNumber == attributes[.size] as? NSNumber)
        #expect(MattermostBuild.version(in: app, bundleID: "Mattermost.Desktop", plistVersion: "6.2.5") == "6.2.5-rc.5")
    }
}
