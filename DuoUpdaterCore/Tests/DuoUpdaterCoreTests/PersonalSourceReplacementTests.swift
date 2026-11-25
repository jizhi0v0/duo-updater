import Foundation
import Testing
@testable import DuoUpdaterCore

struct PersonalSourceReplacementTests {
    private static let signedFixture = Task { await DigestOnlyInstallTests.teamSignedApp() }

    enum Interruption: CaseIterable { case beforeMove, missing, damagedOriginal, foreign, committed, badBackup, externalUpdate, unwritable }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DUO_TEST_PERSONAL_TIGHT_VOLUME"] != nil))
    func insufficientSpacePreservesInstalledCopy() throws {
        let env = ProcessInfo.processInfo.environment
        let volume = try #require(env["DUO_TEST_PERSONAL_TIGHT_VOLUME"])
        let target = URL(fileURLWithPath: volume).appendingPathComponent("DuoShot.app")
        let app = URL(fileURLWithPath: try #require(env["DUO_TEST_PERSONAL_NEW"]))
        let anchor = try PersonalSourceZIP.Identity(at: target)
        let checked = try PersonalSourceZIP.Identity(at: app)
        let manifest = try #require(BackupManifest.compute(for: app))
        let repo = PersonalGitHubSource.Repository(id: 7, full_name: "demo/example", owner: .init(id: 3))
        let asset = PersonalGitHubSource.Asset(id: 9, name: "App.zip", size: 512, digest: nil, updated_at: "")
        let release = PersonalGitHubSource.Release(id: 8, tag_name: checked.version, prerelease: false, draft: false, body: nil, assets: [asset])
        do {
            _ = try PersonalSourceReplacement.prepare(target: target, app: app, anchor: anchor, checked: checked,
                manifest: manifest, authorization: UUID(), repository: repo, track: .stable, release: release, asset: asset)
            Issue.record("Unexpectedly prepared a replacement on the full test volume")
        } catch {
            let error = error as NSError
            #expect(error.code == NSFileWriteOutOfSpaceError || error.code == Int(ENOSPC))
        }
        #expect(try PersonalSourceZIP.Identity(at: target) == anchor)
        #expect(try PersonalSourceReplacement.load(for: target) == nil)
    }

    @Test(arguments: Interruption.allCases)
    func transaction(_ interruption: Interruption) async throws {
        let fm = FileManager.default
        let root = try DigestOnlyInstallTests.scratch("personal-swap")
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("Installed.app")
        let env = ProcessInfo.processInfo.environment
        let original: URL
        let candidate: URL
        if let old = env["DUO_TEST_PERSONAL_OLD"], let new = env["DUO_TEST_PERSONAL_NEW"] {
            original = URL(fileURLWithPath: old)
            candidate = URL(fileURLWithPath: new)
        } else {
            let signed = await Self.signedFixture.value
            original = try #require(signed)
            candidate = original
        }
        try fm.copyItem(at: original, to: target)
        let anchor = try PersonalSourceZIP.Identity(at: target)
        let checked = try PersonalSourceZIP.Identity(at: candidate)
        let manifest = try #require(BackupManifest.compute(for: candidate))
        let repo = PersonalGitHubSource.Repository(id: 7, full_name: "demo/example", owner: .init(id: 3))
        let asset = PersonalGitHubSource.Asset(id: 9, name: "App.zip", size: 512, digest: "sha256:" + String(repeating: "0", count: 64), updated_at: "")
        let release = PersonalGitHubSource.Release(id: 8, tag_name: checked.version, prerelease: false, draft: false, body: nil, assets: [asset])
        let plan = try PersonalSourceReplacement.prepare(target: target, app: candidate, anchor: anchor, checked: checked,
            manifest: manifest, authorization: UUID(), repository: repo, track: .stable, release: release, asset: asset)
        defer { try? fm.removeItem(at: plan.preparationDirectory) }
        if interruption == .badBackup {
            try fm.removeItem(at: plan.preparationDirectory.appendingPathComponent("Backup.app"))
            #expect(throws: (any Error).self) { try plan.verifyBeforeCommit() }
            #expect(try PersonalSourceZIP.Identity(at: target) == anchor)
            #expect(try PersonalSourceReplacement.load(for: target) == nil)
            return
        }
        try plan.verifyBeforeCommit()
        if interruption == .unwritable {
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
            #expect(throws: (any Error).self) { try plan.commit() }
            #expect(try PersonalSourceZIP.Identity(at: target) == anchor)
            #expect(try PersonalSourceReplacement.load(for: target) == nil)
            return
        }
        if interruption == .committed {
            try plan.commit()
        } else if interruption == .externalUpdate {
            try fm.moveItem(at: target, to: root.appendingPathComponent("Moved.app"))
            try fm.copyItem(at: candidate, to: target)
            let foreign = try PersonalSourceZIP.Identity(at: target)
            #expect(throws: (any Error).self) { try plan.commit() }
            #expect(try PersonalSourceZIP.Identity(at: target) == foreign)
            #expect(try PersonalSourceReplacement.load(for: target) == nil)
            return
        } else {
            // Recreate a killed process at a specific durable rename boundary.
            let directory = PersonalSourceReplacement.directory(for: target)
            try fm.moveItem(at: plan.preparationDirectory, to: directory)
            try JSONEncoder().encode(plan).write(to: directory.appendingPathComponent("transaction.json"))
            if interruption != .beforeMove {
                try fm.moveItem(at: target, to: directory.appendingPathComponent("Original.app"))
            }
            if interruption == .damagedOriginal {
                try Data("damaged".utf8).write(to: directory.appendingPathComponent("Original.app/Contents/Info.plist"))
            }
            if interruption == .foreign { try fm.copyItem(at: candidate, to: target) }
        }
        let reopened = try #require(try PersonalSourceReplacement.load(for: target))
        let foreignBefore = try? PersonalSourceZIP.Identity(at: target)
        let outcome = try reopened.reconcile()
        switch interruption {
        case .committed:
            #expect(outcome == .installed)
            #expect(try PersonalSourceZIP.Identity(at: target) == plan.candidate)
        case .damagedOriginal:
            #expect(outcome == .restoredBackup)
            #expect(try PersonalSourceZIP.Identity(at: target) == plan.backupIdentity)
        case .foreign, .externalUpdate:
            #expect(outcome == .needsReview)
            #expect(try PersonalSourceZIP.Identity(at: target) == foreignBefore)
        default:
            #expect(outcome == .original)
            #expect(try PersonalSourceZIP.Identity(at: target) == anchor)
        }
    }
}
