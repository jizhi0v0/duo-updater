@testable import DuoUpdaterCore
import Foundation
import Testing

@MainActor struct PersonalSourcesTests {
    @Test func unknownFormatSurvivesSavingAndRemovingAnotherCopy() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let future = Data(#"{"schema":42,"future":{"format":"keep verbatim"}}"#.utf8)
        let futurePath = "/tmp/future/Demo.app"
        defaults.set([futurePath: future], forKey: "personalGitHubSources")
        let store = PersonalSources(defaults: defaults)
        #expect(store.record(futurePath) == nil)
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: app) }
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "test.personal-source", "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let anchor = try PersonalSourceZIP.Identity(at: app)
        let repo = try JSONDecoder().decode(PersonalGitHubSource.Repository.self, from: Data(#"{"id":3,"full_name":"org/repo","owner":{"id":4}}"#.utf8))
        let lastCheck = Date(timeIntervalSince1970: 42)
        try store.save(.init(repository: repo, track: .preview, filenameContains: "Lite", includeStable: true,
                             anchor: anchor, lastSuccessfulCheck: lastCheck, confirmedVersion: "1.0"), path: app.path)
        let reopened = PersonalSources(defaults: defaults)
        #expect(reopened.record(app.path)?.filenameContains == "Lite")
        #expect(reopened.record(app.path)?.anchor == anchor)
        #expect(reopened.record(app.path)?.channelFilters == ["Preview": "Lite"])
        try reopened.saveConfiguration(for: app, repository: "https://github.com/ORG/repo",
                                       track: .stable, filters: ["Stable": "Pro", "Preview": "Lite"], includeStable: true)
        let switched = try #require(PersonalSources(defaults: defaults).record(app.path))
        #expect(switched.track == .stable)
        #expect(switched.repository == repo)
        #expect(switched.anchor == anchor)
        #expect(switched.lastSuccessfulCheck == lastCheck)
        #expect(switched.confirmedVersion == "1.0")
        #expect(!switched.includeStable)
        #expect(switched.filenameContains == "Pro")
        #expect(switched.channelFilters == ["Stable": "Pro", "Preview": "Lite"])
        #expect(switched.channelFilters["Nightly"] == nil)
        #expect(throws: PersonalGitHubSource.Failure.self) {
            try reopened.saveConfiguration(for: app, repository: "org/other",
                                           track: .nightly, filters: [:], includeStable: false)
        }
        #expect(PersonalSources(defaults: defaults).record(app.path) == switched)
        #expect(reopened.record(futurePath) == nil)
        let secondPath = "/tmp/another-copy/" + app.lastPathComponent
        #expect(reopened.record(secondPath) == nil)
        reopened.remove(app.path)
        #expect(PersonalSources(defaults: defaults).records == [futurePath: future])
    }

    @Test func newlyScannedBuiltInFeedsHavePriority() {
        func unchecked(_ id: String, feed: MyGoUpdateConfig? = nil) -> UpdateResult {
            let app = InstalledApp(name: "Test", bundleID: id, shortVersion: "1.0", buildVersion: nil,
                                   path: URL(fileURLWithPath: "/Applications/Test.app"), isMASApp: false,
                                   sparkleFeedURL: nil, myGoUpdate: feed)
            return ScanRowAssembly.unchecked(app, proofs: ResolvedChannelStore.Snapshot())
        }
        #expect(PersonalSources.lacksBuiltInSource(unchecked("test.personal-source")))
        #expect(!PersonalSources.lacksBuiltInSource(unchecked("test.personal-source",
                    feed: MyGoUpdateConfig(feed: "https://example.com/feed.json", publicKey: "test"))))
        #expect(!PersonalSources.lacksBuiltInSource(unchecked(XcodeReleasesSource.bundleID)))
    }

    @Test func finderHandoffSurvivesEditorRevalidationAndNewRelease() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let app = root.appendingPathComponent("Test.app")
        let staged = root.appendingPathComponent("checked")
        let candidate = staged.appendingPathComponent("Test.app")
        func makeBundle(at url: URL, version: String) throws {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "test.personal-source", "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeBundle(at: app, version: "1.0")
        try makeBundle(at: candidate, version: "1.1")
        let anchor = try PersonalSourceZIP.Identity(at: app)
        let repo = PersonalGitHubSource.Repository(id: 3, full_name: "org/repo", owner: .init(id: 4))
        let asset = PersonalGitHubSource.Asset(id: 5, name: "Test.zip", size: 80, digest: nil, updated_at: "1")
        let first = PersonalGitHubSource.Release(id: 6, tag_name: "1.1", prerelease: false, draft: false,
                                                 body: nil, assets: [asset])
        let latest = PersonalGitHubSource.Release(id: 7, tag_name: "1.2", prerelease: false, draft: false,
                                                  body: nil, assets: [])
        func snapshot(_ releases: [PersonalGitHubSource.Release]) -> PersonalGitHubSource.Snapshot {
            .init(repository: repo, releases: releases, checked: .now, truncated: false)
        }
        let installed = InstalledApp(name: "Test", bundleID: anchor.bundle, shortVersion: anchor.version,
                                     buildVersion: nil, path: app, isMASApp: false, sparkleFeedURL: nil)
        let row = UpdateResult(app: installed, remote: nil, status: .unknown)
        let store = PersonalSources(defaults: defaults)
        let checked = PersonalSources.Checked(release: first, asset: asset, directory: staged, application: candidate,
                                              identity: try .init(at: candidate), manifest: try #require(BackupManifest.compute(for: candidate)))
        try store.saveConfiguration(for: app, repository: repo.full_name, track: .stable, filters: [:],
                                    includeStable: false, validation: (snapshot([first]), anchor))
        store.checked[app.path] = checked
        try store.recordHandoff(try #require(store.record(app.path)), checked: checked, path: app.path)
        #expect(!store.needsAction(row))
        try store.saveConfiguration(for: app, repository: repo.full_name, track: .stable, filters: ["Nightly": "arm"],
                                    includeStable: false, validation: (snapshot([first]), anchor))
        #expect(PersonalSources(defaults: defaults).record(app.path)?.handoff?.asset == asset)
        #expect(FileManager.default.fileExists(atPath: candidate.path))
        await store.refresh(installed) { _ in snapshot([latest, first]) }
        #expect(store.candidate(row) == latest)
        #expect(store.needsAction(row))
        #expect(store.checked[app.path] == nil)
        #expect(FileManager.default.fileExists(atPath: candidate.path))
        #expect(PersonalSources(defaults: defaults).record(app.path)?.handoff?.asset == asset)
        // The transport maps both 403 and 404 to repositoryAccess. Access
        // failures hide stale release data while leaving the Finder file usable.
        for status in [403, 404] {
            await store.refresh(installed) { _ in
                throw PersonalGitHubSource.Failure("HTTP \(status)", .repositoryAccess)
            }
            #expect(store.snapshots[app.path] == nil)
            #expect(store.needsGitHubSettings.contains(app.path))
            #expect(store.record(app.path)?.handoff?.asset == asset)
            #expect(FileManager.default.fileExists(atPath: candidate.path))
            await store.refresh(installed) { _ in snapshot([first]) }
        }
        let info = app.appendingPathComponent("Contents/Info.plist")
        let parked = root.appendingPathComponent("parked.plist")
        try FileManager.default.moveItem(at: info, to: parked)
        await store.reconcileLocal(installed)
        #expect(store.snapshots[app.path] == nil)
        #expect(store.record(app.path)?.handoff?.asset == asset)
        #expect(FileManager.default.fileExists(atPath: candidate.path))
        try FileManager.default.moveItem(at: parked, to: info)

        let wrongOwner = PersonalGitHubSource.Repository(id: repo.id, full_name: repo.full_name, owner: .init(id: 99))
        await store.refresh(installed) { _ in
            .init(repository: wrongOwner, releases: [latest], checked: .now, truncated: false)
        }
        #expect(store.record(app.path)?.repository == repo)
        #expect(store.snapshots[app.path] == nil)
        #expect(store.paused.contains(app.path))
        #expect(!store.needsAction(row))
        store.remove(app.path)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }
}
