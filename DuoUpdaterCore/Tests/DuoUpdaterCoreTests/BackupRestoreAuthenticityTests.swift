import Testing
import Foundation
import Security
@testable import DuoUpdaterCore

/// What a restore believes about a backup store it did not write alone: the
/// sidecar and the copy beside it can both be rewritten by whoever can write
/// the store, so neither may decide on its own what lands over the live app,
/// where an archive unpacks, or which files user data is put back over.
///
/// Serialized: the store and home seams are task-locals, but the signed fixture
/// is a copy of a system app and each test makes its own; nothing is shared.
@Suite(.serialized)
struct BackupRestoreAuthenticityTests {

    // MARK: - Fixtures

    /// A fresh directory, removed afterwards.
    private func withScratch(_ body: (URL) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoRestoreAuthenticity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try await body(base)
    }

    private func run(_ tool: String, _ arguments: [String]) async throws -> Bool {
        try await ChildProcess.run(
            tool, arguments, standardOutput: .discard, standardError: .discard,
            onCancel: .runToCompletion).succeeded
    }

    /// A certificate-signed app the test can own: a copy of one Apple ships.
    /// Its designated requirement is `identifier "com.apple.Stickies" and
    /// anchor apple`, with no Team ID — the "no Team" branch. `cp`, not `ditto`
    /// or `FileManager`: those carry the system volume's restricted flags and
    /// are refused writing them (measured 2026-10-25, "Operation not permitted").
    private func signedApp(named name: String, in dir: URL) async throws -> URL {
        let app = dir.appendingPathComponent(name)
        let copied = try await run("/bin/cp", ["-R", "/System/Applications/Stickies.app", app.path])
        try #require(copied, "copying the Apple-signed fixture failed")
        return app
    }

    /// Replace `app`'s signature with an ad-hoc one: what anyone can make
    /// without a certificate.
    private func signAdHoc(_ app: URL) async throws {
        let signed = try await run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", app.path])
        try #require(signed, "ad-hoc signing the fixture failed")
    }

    private func certificateCount(_ app: URL) -> Int {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code
        else { return 0 }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return ((info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [Any])?.count ?? 0
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    /// Recompute the stored copy's manifest and write it into its sidecar —
    /// everything an attacker with write access to the store can do.
    private func rewriteSidecar(forKey key: String, root: URL, bundle: URL) throws {
        let sidecarURL = root.appendingPathComponent(key).appendingPathComponent("backup.json")
        var sidecar = try readJSON(sidecarURL)
        let manifest = try #require(BackupManifest.compute(for: bundle))
        sidecar["manifest"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(manifest))
        try writeJSON(sidecar, to: sidecarURL)
    }

    // MARK: - Report item 3: authenticity

    /// The attack measured in the review: replace the stored copy, recompute
    /// the manifest, write it into the sidecar. The integrity gate passes —
    /// both halves agree — so only the installed copy's signature can refuse it.
    ///
    /// Mutation: drop the `verifyRestoreAuthenticity` call in `restore` → the
    /// ad-hoc copy is swapped in and the installed app loses its certificate.
    @Test func aRewrittenSidecarDoesNotRestoreOverASignedApp() async throws {
        try await withScratch { base in
            let root = base.appendingPathComponent("store", isDirectory: true)
            let apps = base.appendingPathComponent("apps", isDirectory: true)
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let installed = try await signedApp(named: "Stickies.app", in: apps)
            try #require(certificateCount(installed) > 0)

            try await BackupStore.$rootOverride.withValue(root) {
                let key = BackupStore.key(bundleID: "com.apple.Stickies", path: installed)
                let saved = try await BackupStore.save(
                    appPath: installed, key: key, version: "1.0", bundleID: "com.apple.Stickies")
                try await signAdHoc(saved.bundlePath)
                try rewriteSidecar(forKey: key, root: root, bundle: saved.bundlePath)

                do {
                    _ = try await BackupStore.restore(forKey: key, over: installed)
                    Issue.record("an ad-hoc copy was restored over an Apple-signed app")
                } catch BackupStore.BackupError.signerMismatch {
                    // Refused by the signer gate, not by anything earlier.
                }
            }
            #expect(certificateCount(installed) > 0, "the installed copy must still be Apple-signed")
        }
    }

    /// The gate must not cost a legitimate rollback: an untouched copy of a
    /// certificate-signed app still goes back.
    @Test func aFaithfulBackupStillRestoresOverASignedApp() async throws {
        try await withScratch { base in
            let root = base.appendingPathComponent("store", isDirectory: true)
            let apps = base.appendingPathComponent("apps", isDirectory: true)
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let installed = try await signedApp(named: "Stickies.app", in: apps)

            try await BackupStore.$rootOverride.withValue(root) {
                let key = BackupStore.key(bundleID: "com.apple.Stickies", path: installed)
                try await BackupStore.save(
                    appPath: installed, key: key, version: "1.0", bundleID: "com.apple.Stickies")
                let version = try await BackupStore.restore(forKey: key, over: installed)
                #expect(version == "1.0")
            }
            #expect(certificateCount(installed) > 0)
        }
    }

    /// Directly: what the gate refuses and what it lets through.
    @Test func theSignerGateOnlyAppliesOverACertificateSignedCopy() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("DuoRestoreSigner-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let signed = try await signedApp(named: "Signed.app", in: base)
        let otherSigned = try await signedApp(named: "OtherSigned.app", in: base)
        let adHoc = try await signedApp(named: "AdHoc.app", in: base)
        try await signAdHoc(adHoc)
        let unsigned = base.appendingPathComponent("Unsigned.app/Contents", isDirectory: true)
        try fm.createDirectory(at: unsigned, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>com.apple.Stickies</string>
        </dict></plist>
        """.utf8).write(to: unsigned.appendingPathComponent("Info.plist"))
        let unsignedApp = unsigned.deletingLastPathComponent()

        // Over a certificate-signed copy: same signer passes, anything else is refused.
        try BackupStore.verifyRestoreAuthenticity(staged: otherSigned, over: signed)
        #expect(throws: BackupStore.BackupError.self) {
            try BackupStore.verifyRestoreAuthenticity(staged: adHoc, over: signed)
        }
        #expect(throws: BackupStore.BackupError.self) {
            try BackupStore.verifyRestoreAuthenticity(staged: unsignedApp, over: signed)
        }
        // Over an ad-hoc or unsigned copy, or nothing at all: no reference
        // signature, so the gate stands aside — as it did before.
        try BackupStore.verifyRestoreAuthenticity(staged: signed, over: adHoc)
        try BackupStore.verifyRestoreAuthenticity(staged: adHoc, over: unsignedApp)
        try BackupStore.verifyRestoreAuthenticity(
            staged: adHoc, over: base.appendingPathComponent("Missing.app"))
    }

    /// A Team ID is spliced into requirement text, so only a real one is.
    @Test func onlyAWellFormedTeamIDBecomesARequirement() {
        #expect(BackupStore.teamRequirement("RS59HDH7Y3") != nil)
        #expect(BackupStore.teamRequirement("RS59HDH7Y3\" or anchor apple or \"") == nil)
        #expect(BackupStore.teamRequirement("") == nil)
        #expect(BackupStore.teamRequirement("SHORT") == nil)
    }

    /// AndroMeld's designated requirement as `codesign -dr -` printed it
    /// (2026-10-25): the App Store branch first, the Developer ID branch second,
    /// the Team only on the second.
    static let appStoreDR = """
        (anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ \
        or anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ \
        and certificate leaf[subject.OU] = "5F8W8RDSU8") and identifier "com.catchingnow.andfiles"
        """

    /// The restore is held to the installed copy's own requirement — not to a
    /// Team pinned on the leaf, which an App Store app never satisfies. The
    /// conditional `anAppStoreAppRestoresOverItself` checks the same thing
    /// against a real App Store signature where the machine has one.
    @Test func theRestoreRequirementIsTheInstalledCopysOwn() throws {
        let same = BackupStore.restoreRequirementText(
            installedDR: Self.appStoreDR, installedIdentifier: "com.catchingnow.andfiles",
            backupIdentifier: "com.catchingnow.andfiles")
        #expect(same == Self.appStoreDR)
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(try #require(same) as CFString, [], &requirement)
            == errSecSuccess)

        // A migration rollback: only the identifier clause changes.
        let reaimed = try #require(BackupStore.restoreRequirementText(
            installedDR: Self.appStoreDR, installedIdentifier: "com.catchingnow.andfiles",
            backupIdentifier: "com.catchingnow.oldfiles"))
        #expect(reaimed == Self.appStoreDR.replacingOccurrences(
            of: "identifier \"com.catchingnow.andfiles\"", with: "identifier \"com.catchingnow.oldfiles\""))
        #expect(reaimed.contains("leaf[field.1.2.840.113635.100.6.1.9]"))
        #expect(reaimed.contains("leaf[subject.OU] = \"5F8W8RDSU8\""))

        // Unquoted, as a plain identifier may be printed.
        #expect(BackupStore.restoreRequirementText(
            installedDR: "anchor apple and identifier com.apple.Stickies",
            installedIdentifier: "com.apple.Stickies", backupIdentifier: "com.apple.Notes")
            == "anchor apple and identifier \"com.apple.Notes\"")
        // A longer identifier sharing the prefix is not the clause.
        #expect(BackupStore.restoreRequirementText(
            installedDR: "anchor apple and identifier com.apple.Stickies2",
            installedIdentifier: "com.apple.Stickies", backupIdentifier: "com.apple.Notes") == nil)
        // Nothing to re-aim, or nothing safe to splice in: refuse.
        #expect(BackupStore.restoreRequirementText(
            installedDR: "anchor apple generic", installedIdentifier: "a.b",
            backupIdentifier: "c.d") == nil)
        #expect(BackupStore.restoreRequirementText(
            installedDR: Self.appStoreDR, installedIdentifier: "com.catchingnow.andfiles",
            backupIdentifier: "x\" or anchor apple or identifier \"y") == nil)
    }

    /// The first App Store app in `/Applications` small enough to copy, or nil.
    /// Its leaf certificate is Apple's, not the developer's, so a Team pinned on
    /// the leaf's OU never matches it (measured 2026-10-25 on AndroMeld, Developer,
    /// Microsoft Word). A hosted runner has none, which is why this is conditional.
    static let appStoreApp: URL? = {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        let cap: Int64 = 64 << 20
        func fits(_ app: URL) -> Bool {
            guard let walker = fm.enumerator(
                at: app, includingPropertiesForKeys: [.fileSizeKey], options: []) else { return false }
            var total: Int64 = 0
            for case let item as URL in walker {
                total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if total > cap { return false }
            }
            return true
        }
        return apps
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first {
                fm.fileExists(atPath: $0.appendingPathComponent("Contents/_MASReceipt").path) && fits($0)
            }
    }()

    /// An App Store app's own copy goes back over it, and its Team is read as
    /// valid — the rollback a `leaf[subject.OU]` requirement refused.
    @Test(.enabled(if: appStoreApp != nil, "no App Store app in /Applications to copy"))
    func anAppStoreAppRestoresOverItself() async throws {
        let original = try #require(Self.appStoreApp)
        try await withScratch { base in
            let installed = base.appendingPathComponent("Installed.app")
            let staged = base.appendingPathComponent("Staged.app")
            for copy in [installed, staged] {
                let copied = try await run("/bin/cp", ["-R", original.path, copy.path])
                try #require(copied, "copying \(original.lastPathComponent) failed")
            }
            // Blocking Security calls, so in one hop off the cooperative pool.
            let (certificates, team, refusal, validated) = await offCooperativePool {
                () -> (Int, String?, String?, String?) in
                var refusal: String?
                do {
                    try BackupStore.verifyRestoreAuthenticity(staged: staged, over: installed)
                } catch {
                    refusal = "\(error)"
                }
                return (certificateCount(installed),
                        try? SignatureVerifier.teamIdentifier(at: installed),
                        refusal, BackupStore.validatedTeamIdentifier(at: staged))
            }
            try #require(certificates > 0)
            try #require(team != nil, "\(original.lastPathComponent) has no Team ID")
            #expect(refusal == nil, "\(original.lastPathComponent)")
            #expect(validated == team, "\(original.lastPathComponent)")
        }
    }

    // MARK: - Report item 4: bundleName is a name

    private func makeApp(named name: String, in dir: URL) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>App</string>
          <key>CFBundleIdentifier</key><string>com.example.other</string>
          <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("payload".utf8).write(to: contents.appendingPathComponent("marker.txt"))
        return app
    }

    /// A sidecar on a backup disk naming its bundle `../<dir>/Other.app`
    /// unpacked the archive outside the restore's scratch — before any gate
    /// could refuse it, and left there when one did.
    ///
    /// Mutation: drop the `isSingleBundleName` guard in `readMeta` → the
    /// backup is found and the archive lands outside the scratch.
    @Test func aDestinationSidecarWithAPathInItsBundleNameIsNotABackup() async throws {
        try await withScratch { base in
            let fm = FileManager.default
            let outbox = base.appendingPathComponent("outbox", isDirectory: true)
            let disk = base.appendingPathComponent("disk", isDirectory: true)
            let apps = base.appendingPathComponent("apps", isDirectory: true)
            for dir in [outbox, disk, apps] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let identity = UUID().uuidString
            try BackupVolumeMarker(identity: identity, volumeName: "TestDisk").write(to: disk)
            let destination = BackupDestination(
                kind: .external, path: disk.path, identity: identity, volumeName: "TestDisk")

            let source = try makeApp(named: "Other.app", in: apps)
            let keyDir = disk.appendingPathComponent("k", isDirectory: true)
            try fm.createDirectory(at: keyDir, withIntermediateDirectories: true)
            let archive = keyDir.appendingPathComponent("Other.aar")
            try await BundleArchive.archive(bundle: source, to: archive)
            let escape = "DuoEscape-\(UUID().uuidString)"
            let landing = fm.temporaryDirectory.appendingPathComponent(escape, isDirectory: true)
            defer { try? fm.removeItem(at: landing) }
            try writeJSON([
                "version": "1.0", "bundleID": "com.example.other",
                "originalPath": "/Applications/Other.app",
                "bundleName": "../\(escape)/Other.app", "savedAt": 0,
                "archiveName": "Other.aar",
                "archiveSHA256": try BundleArchive.sha256(of: archive),
            ] as [String: Any], to: keyDir.appendingPathComponent("backup.json"))
            let installed = try makeApp(named: "Installed.app", in: apps)

            try await BackupStore.$rootOverride.withValue(outbox) {
                try await BackupStore.$destinationOverride.withValue(destination) {
                    #expect(BackupStore.backup(forKey: "k") == nil)
                    await #expect(throws: BackupStore.BackupError.self) {
                        try await BackupStore.restore(forKey: "k", over: installed)
                    }
                    _ = await BackupStore.verify(deep: true)
                }
            }
            #expect(!fm.fileExists(atPath: landing.path),
                    "nothing may be unpacked outside the restore's scratch")
        }
    }

    /// The outbox reads its payload by the same name, so a path there names a
    /// bundle outside the key's directory — read as no backup at all.
    @Test func anOutboxSidecarWithAPathInItsBundleNameIsNotABackup() async throws {
        try await withScratch { base in
            let root = base.appendingPathComponent("outbox", isDirectory: true)
            let keyDir = root.appendingPathComponent("k", isDirectory: true)
            try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true)
            // Something real where the path points, so only the name can refuse it.
            try makeApp(named: "Other.app", in: root.appendingPathComponent("x", isDirectory: true))
            try writeJSON([
                "version": "1.0", "originalPath": "/Applications/Other.app",
                "bundleName": "../x/Other.app", "savedAt": 0,
            ] as [String: Any], to: keyDir.appendingPathComponent("backup.json"))

            try await BackupStore.$rootOverride.withValue(root) {
                #expect(BackupStore.backup(forKey: "k") == nil)
            }
        }
    }

    /// A payload that is a symlink is not something `save` writes.
    @Test func anOutboxPayloadThatIsASymlinkIsNotABackup() async throws {
        try await withScratch { base in
            let root = base.appendingPathComponent("outbox", isDirectory: true)
            let keyDir = root.appendingPathComponent("k", isDirectory: true)
            try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true)
            let elsewhere = try makeApp(named: "Other.app", in: base)
            try FileManager.default.createSymbolicLink(
                at: keyDir.appendingPathComponent("Other.app"), withDestinationURL: elsewhere)
            try writeJSON([
                "version": "1.0", "originalPath": "/Applications/Other.app",
                "bundleName": "Other.app", "savedAt": 0,
            ] as [String: Any], to: keyDir.appendingPathComponent("backup.json"))

            try await BackupStore.$rootOverride.withValue(root) {
                #expect(BackupStore.backup(forKey: "k") == nil)
            }
        }
    }

    @Test func onlyASingleAppNameIsABundleName() {
        #expect(BackupStore.isSingleBundleName("Slack.app"))
        #expect(BackupStore.isSingleBundleName("WeType.app"))
        for bad in ["", ".", "..", ".app", "../Other.app", "x/Other.app", "Other", "Ot\0her.app"] {
            #expect(!BackupStore.isSingleBundleName(bad), "\(bad.debugDescription)")
        }
    }

    // MARK: - Report item 5: user-data targets

    private struct IMEFixture {
        let home: URL
        let store: URL
        static let name = "Fixture"
        static let bundleID = "com.example.ime"
        var key: String { "ime" }
        var library: URL { home.appendingPathComponent("Library", isDirectory: true) }
        var snapshot: URL { InputMethodDataBackup.snapshotDirectory(forKey: key, in: store) }
    }

    private func withIMEFixture(_ body: (IMEFixture) async throws -> Void) async throws {
        try await withScratch { base in
            let fm = FileManager.default
            let fixture = IMEFixture(
                home: base.appendingPathComponent("home", isDirectory: true),
                store: base.appendingPathComponent("store", isDirectory: true))
            let support = fixture.library
                .appendingPathComponent("Application Support/\(IMEFixture.name)", isDirectory: true)
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            try fm.createDirectory(
                at: fixture.library.appendingPathComponent("Preferences"),
                withIntermediateDirectories: true)
            try Data("learned".utf8).write(to: support.appendingPathComponent("words.db"))
            try fm.createDirectory(
                at: fixture.store.appendingPathComponent(fixture.key), withIntermediateDirectories: true)
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                try await InputMethodDataBackup.$homeOverride.withValue(fixture.home) {
                    let saved = await InputMethodDataBackup.save(
                        bundleName: IMEFixture.name, bundleID: IMEFixture.bundleID,
                        key: fixture.key, in: fixture.store)
                    try #require(saved.count == 1, "the fixture's own snapshot must have been taken")
                    try await body(fixture)
                }
            }
        }
    }

    /// Add an entry to the snapshot's manifest, with its stored copy.
    private func plant(
        originalPath: String, storedName: String, content: String = "planted", in fixture: IMEFixture
    ) throws {
        let manifestURL = fixture.snapshot.appendingPathComponent("userdata.json")
        var manifest = try readJSON(manifestURL)
        var entries = try #require(manifest["entries"] as? [[String: Any]])
        entries.append(["originalPath": originalPath, "storedName": storedName])
        manifest["entries"] = entries
        try writeJSON(manifest, to: manifestURL)
        let stored = fixture.snapshot.appendingPathComponent(storedName)
        try FileManager.default.createDirectory(
            at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: stored)
    }

    /// A manifest entry naming a file outside the three library directories
    /// user data is captured from is not restored there — by either overload.
    ///
    /// Mutation: have `allowedTarget` return the target unchecked → the
    /// planted file is written into the home directory.
    @Test func aManifestEntryOutsideTheInputMethodsLocationsIsNotRestored() async throws {
        try await withIMEFixture { fixture in
            let outside = fixture.home.appendingPathComponent("Documents/evil.txt")
            try plant(originalPath: outside.path, storedName: "Documents-evil.txt", in: fixture)

            let structural = try await InputMethodDataBackup.restore(forKey: fixture.key)
            #expect(!FileManager.default.fileExists(atPath: outside.path))
            #expect(structural.count == 1, "the fixture's own location still restores")

            let owned = try await InputMethodDataBackup.restore(
                forKey: fixture.key, from: fixture.snapshot,
                bundleName: IMEFixture.name, bundleID: IMEFixture.bundleID)
            #expect(!FileManager.default.fileExists(atPath: outside.path))
            #expect(owned.map(\.original.lastPathComponent) == [IMEFixture.name])
        }
    }

    /// A stored name with `..` in it reads from outside the snapshot; one that
    /// is not what `save` derives from the target is not one of ours.
    @Test func aStoredNameThatIsNotTheDerivedOneIsNotRestored() async throws {
        try await withIMEFixture { fixture in
            let target = fixture.library.appendingPathComponent("Preferences/\(IMEFixture.bundleID).plist")
            // Read from beside the snapshot directory, not inside it.
            try plant(
                originalPath: target.path, storedName: "../sibling.plist", in: fixture)

            let restored = try await InputMethodDataBackup.restore(
                forKey: fixture.key, from: fixture.snapshot,
                bundleName: IMEFixture.name, bundleID: IMEFixture.bundleID)
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(restored.count == 1)
        }
    }

    /// Inside an allowed directory but belonging to another app: the owner
    /// check is what refuses it.
    @Test func anotherAppsDataIsNotRestoredForThisOne() async throws {
        try await withIMEFixture { fixture in
            let fm = FileManager.default
            let other = fixture.library.appendingPathComponent("Application Support/OtherApp")
            let otherPrefs = fixture.library.appendingPathComponent("Preferences/com.other.app.plist")
            let otherContainer = fixture.library.appendingPathComponent("Containers/com.other.app")
            try plant(originalPath: other.path, storedName: "Application_Support-OtherApp", in: fixture)
            try plant(originalPath: otherPrefs.path, storedName: "Preferences-com.other.app.plist", in: fixture)
            try plant(originalPath: otherContainer.path, storedName: "Containers-com.other.app", in: fixture)
            let dotted = fixture.library.appendingPathComponent("Preferences").path
                + "/../../Documents/x.plist"
            try plant(originalPath: dotted, storedName: "Preferences-x.plist", in: fixture)

            let restored = try await InputMethodDataBackup.restore(
                forKey: fixture.key, from: fixture.snapshot,
                bundleName: IMEFixture.name, bundleID: IMEFixture.bundleID)
            #expect(!fm.fileExists(atPath: other.path))
            #expect(!fm.fileExists(atPath: otherPrefs.path))
            #expect(!fm.fileExists(atPath: otherContainer.path))
            #expect(!fm.fileExists(atPath: fixture.home.appendingPathComponent("Documents/x.plist").path))
            #expect(restored.map(\.original.lastPathComponent) == [IMEFixture.name])
        }
    }

    /// The legitimate locations still restore under the owner check: the
    /// support directory by name, a preferences file by bundle id prefix and
    /// by name, the container by bundle id.
    @Test func everyLocationSaveCapturesStillRestores() async throws {
        try await withIMEFixture { fixture in
            let fm = FileManager.default
            let prefs = fixture.library.appendingPathComponent("Preferences")
            let byID = prefs.appendingPathComponent("\(IMEFixture.bundleID).settings.plist")
            let byName = prefs.appendingPathComponent("com.vendor.FixtureSettings.plist")
            let container = fixture.library.appendingPathComponent("Containers/\(IMEFixture.bundleID)")
            try plant(originalPath: byID.path,
                      storedName: "Preferences-\(IMEFixture.bundleID).settings.plist", in: fixture)
            try plant(originalPath: byName.path,
                      storedName: "Preferences-com.vendor.FixtureSettings.plist", in: fixture)
            try plant(originalPath: container.path,
                      storedName: "Containers-\(IMEFixture.bundleID)", in: fixture)
            try fm.removeItem(at: fixture.library.appendingPathComponent("Application Support"))

            let restored = try await InputMethodDataBackup.restore(
                forKey: fixture.key, from: fixture.snapshot,
                bundleName: IMEFixture.name, bundleID: IMEFixture.bundleID)
            #expect(restored.count == 4)
            for url in [byID, byName, container] { #expect(fm.fileExists(atPath: url.path)) }
            #expect(fm.fileExists(atPath: fixture.library
                .appendingPathComponent("Application Support/\(IMEFixture.name)/words.db").path))
        }
    }
}
