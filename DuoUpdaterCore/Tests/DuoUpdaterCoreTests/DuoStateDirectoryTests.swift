import Testing
import Foundation
@testable import DuoUpdaterCore

/// `DUO_STATE_DIR` is what keeps the nightly sweep from writing the changelog
/// cache and traffic log the running menu-bar app is reading — the two run as
/// the same user on the same machine. These assert the redirect actually
/// reaches every store that owns our state, because an environment variable
/// nothing reads looks exactly like one that works. (It was in the workflow for
/// a day before anything honoured it.)
@Suite(.serialized)
struct DuoStateDirectoryTests {

    /// Runs `body` with `DUO_STATE_DIR` set, then restores what was there.
    /// `setenv` is process-global, hence the serialized suite.
    private func withStateDir<T>(_ path: String, _ body: () throws -> T) rethrows -> T {
        let previous = ProcessInfo.processInfo.environment["DUO_STATE_DIR"]
        setenv("DUO_STATE_DIR", path, 1)
        defer {
            if let previous { setenv("DUO_STATE_DIR", previous, 1) } else { unsetenv("DUO_STATE_DIR") }
        }
        return try body()
    }

    @Test func unsetFallsBackToApplicationSupport() {
        let previous = ProcessInfo.processInfo.environment["DUO_STATE_DIR"]
        unsetenv("DUO_STATE_DIR")
        defer { if let previous { setenv("DUO_STATE_DIR", previous, 1) } }
        #expect(DuoStateDirectory.base.path.hasSuffix("Application Support"))
    }

    @Test func emptyIsTreatedAsUnset() {
        withStateDir("") {
            #expect(DuoStateDirectory.base.path.hasSuffix("Application Support"),
                    "an empty value is a workflow that forgot to interpolate, not a request to use /")
        }
    }

    @Test func everyStoreThatOwnsOurStateFollowsTheOverride() async {
        let cacheDirectory = withStateDir("/tmp/duo-state-test") {
            #expect(TrafficStore.defaultFileURL().path
                == "/tmp/duo-state-test/com.duoupdater.app/traffic.json")
            #expect(ReleaseTimelineStore.defaultFileURL().path
                == "/tmp/duo-state-test/com.duoupdater.app/releases.json")
            #expect(BackupStore.root.path == "/tmp/duo-state-test/DuoUpdater/Backups")
            #expect(GitHubConditionalCache.defaultFileURL().path
                == "/tmp/duo-state-test/com.duoupdater.app/github-conditional-cache.json")
            // Resolved in the initialiser, so it must be constructed inside the
            // override; reading it back is what needs the await.
            return ChangelogDiskCache()
        }
        #expect(await cacheDirectory.directory.path
            == "/tmp/duo-state-test/com.duoupdater.app/changelogs")
    }
}
