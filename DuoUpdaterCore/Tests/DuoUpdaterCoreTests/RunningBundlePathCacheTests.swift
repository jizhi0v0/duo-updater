import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite("RunningBundlePathCache")
struct RunningBundlePathCacheTests {

    /// Counts resolutions and answers with a recognisable transform so the
    /// returned set can be checked against what the resolver said, not just
    /// against how often it was asked.
    private final class Recorder {
        var calls: [String] = []
        func resolve(_ url: URL) -> String {
            calls.append(url.path)
            return "/resolved" + url.path
        }
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func make() -> (RunningBundlePathCache, Recorder) {
        let recorder = Recorder()
        return (RunningBundlePathCache(resolver: recorder.resolve), recorder)
    }

    @Test func firstSnapshotResolvesEveryDistinctPathOnceAndReturnsTheResolvedForm() {
        var (cache, recorder) = make()
        let paths = cache.update(with: [url("/Applications/A.app"), url("/Applications/B.app"), url("/Applications/C.app")])
        #expect(recorder.calls.sorted() == ["/Applications/A.app", "/Applications/B.app", "/Applications/C.app"])
        #expect(paths == ["/resolved/Applications/A.app", "/resolved/Applications/B.app", "/resolved/Applications/C.app"])
        #expect(cache.count == 3)
    }

    /// The common event: some unrelated helper launched or quit and every
    /// long-lived process is still where it was. Zero filesystem work.
    @Test func unchangedSnapshotResolvesNothing() {
        var (cache, recorder) = make()
        let snapshot = [url("/Applications/A.app"), url("/Applications/B.app")]
        _ = cache.update(with: snapshot)
        recorder.calls = []
        let paths = cache.update(with: snapshot)
        #expect(recorder.calls.isEmpty)
        #expect(paths == ["/resolved/Applications/A.app", "/resolved/Applications/B.app"])
    }

    @Test func oneNewPathResolvesOnlyThatOne() {
        var (cache, recorder) = make()
        _ = cache.update(with: [url("/Applications/A.app"), url("/Applications/B.app")])
        recorder.calls = []
        let paths = cache.update(with: [url("/Applications/A.app"), url("/Applications/B.app"), url("/Applications/New.app")])
        #expect(recorder.calls == ["/Applications/New.app"])
        #expect(paths.count == 3)
        #expect(paths.contains("/resolved/Applications/New.app"))
    }

    /// A quit app leaves the table with the process, so the table cannot grow
    /// past the process count — and if the app comes back, it is resolved
    /// again rather than answered from a possibly stale memory. Deleting the
    /// eviction would leave the reappearance at zero calls and fail here.
    @Test func removedPathIsEvictedAndResolvedAgainWhenItReappears() {
        var (cache, recorder) = make()
        _ = cache.update(with: [url("/Applications/A.app"), url("/Applications/Gone.app")])
        #expect(cache.count == 2)

        recorder.calls = []
        let after = cache.update(with: [url("/Applications/A.app")])
        #expect(recorder.calls.isEmpty)
        #expect(after == ["/resolved/Applications/A.app"])
        #expect(cache.count == 1)

        let back = cache.update(with: [url("/Applications/A.app"), url("/Applications/Gone.app")])
        #expect(recorder.calls == ["/Applications/Gone.app"])
        #expect(back.contains("/resolved/Applications/Gone.app"))
        #expect(cache.count == 2)
    }

    /// An app and its helpers report the same bundle; one resolution serves
    /// all of them, within a snapshot and across snapshots.
    @Test func samePathForSeveralProcessesResolvesOnce() {
        var (cache, recorder) = make()
        let helpers = Array(repeating: url("/Applications/Chrome.app"), count: 6)
        let paths = cache.update(with: helpers + [url("/Applications/Other.app")])
        #expect(recorder.calls == ["/Applications/Chrome.app", "/Applications/Other.app"])
        #expect(paths == ["/resolved/Applications/Chrome.app", "/resolved/Applications/Other.app"])
        #expect(cache.count == 2)

        recorder.calls = []
        _ = cache.update(with: helpers + [url("/Applications/Other.app")])
        #expect(recorder.calls.isEmpty)
    }

    @Test func emptySnapshotClearsEverything() {
        var (cache, recorder) = make()
        _ = cache.update(with: [url("/Applications/A.app")])
        #expect(cache.update(with: []).isEmpty)
        #expect(cache.count == 0)
        recorder.calls = []
        _ = cache.update(with: [url("/Applications/A.app")])
        #expect(recorder.calls == ["/Applications/A.app"], "forgotten, so resolved again")
    }

    /// The reason the resolution cannot simply be dropped: `InstalledApp.path`
    /// is symlink-resolved, and the default resolver has to bring a process
    /// launched through a symlink to the same string. Real filesystem, real
    /// symlink, default resolver.
    @Test func defaultResolverFollowsARealSymlinkToTheInstalledPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunningBundlePathCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real.app")
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        var cache = RunningBundlePathCache()
        let paths = cache.update(with: [link])
        let expected = real.resolvingSymlinksInPath().path
        #expect(paths == [expected])
        #expect(link.path != expected, "the fixture must actually go through a symlink")
        // Second event, same process: the answer is served from memory rather
        // than the filesystem — observable as: it still matches after the
        // symlink itself has been removed.
        try FileManager.default.removeItem(at: link)
        #expect(cache.update(with: [link]) == [expected])
    }
}
