import DuoUpdaterCore
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
}
