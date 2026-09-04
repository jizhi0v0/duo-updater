import Testing
import Foundation
@testable import DuoUpdaterCore

/// The query language, and the numbers it makes the strip above the log show.
///
/// Two halves on purpose. The parser is checked as a pure function — that is
/// where a typo in the grammar shows — and everything that ends up as SQL is
/// checked against a real store, because a predicate that is wrong in a way the
/// parser cannot see (a NULL that swallows a row, a boolean SUM that counts
/// cache hits as failures) only shows when SQLite runs it.
@Suite(.serialized)
struct RequestQueryTests {

    // MARK: - Parsing

    @Test("A half-typed token is a normal state of the field, not an error")
    func partialInputParsesToNothing() {
        // Every keystroke of "host:" passes through the parser. If a bare key
        // filtered on the empty string the list would blank out mid-type.
        #expect(RequestQuery.parse("host:").isEmpty)
        #expect(RequestQuery.parse("").isEmpty)
        #expect(RequestQuery.parse("   ").isEmpty)
        #expect(RequestQuery.parse("stat").text == ["stat"])
    }

    @Test("Repeating a key is OR; different keys are AND")
    func repeatedKeysAccumulate() {
        let query = RequestQuery.parse("status:403 status:fail host:github.com")
        #expect(query.statuses == [.code(403), .failed])
        #expect(query.hosts == ["github.com"])
    }

    @Test("Friendly purpose names and the raw enum values both work")
    func purposeAliases() {
        #expect(RequestQuery.purpose("check") == .versionCheck)
        #expect(RequestQuery.purpose("versionCheck") == .versionCheck)
        #expect(RequestQuery.purpose("VERSIONCHECK") == .versionCheck)
        #expect(RequestQuery.purpose("download") == .install)
        #expect(RequestQuery.purpose("notes") == .changelog)
        #expect(RequestQuery.purpose("self") == .selfUpdate)
        // `duo events --purpose <raw>` has always taken these; the window shows
        // the friendly ones. Both front ends compile to the same query.
        #expect(RequestQuery.purpose("nonsense") == nil)
    }

    @Test("Status families, sentinels and codes")
    func statusVocabulary() {
        #expect(RequestQuery.status("4xx") == .family(4))
        #expect(RequestQuery.status("404") == .code(404))
        #expect(RequestQuery.status("fail") == .failed)
        #expect(RequestQuery.status("cache") == .cache)
        #expect(RequestQuery.status("problems") == .problem)
        #expect(RequestQuery.status("99") == nil, "not an HTTP status")
        #expect(RequestQuery.status("xyz") == nil)
    }

    @Test("Sizes are decimal, matching what the window prints")
    func sizeUnits() {
        // The list renders bytes with ByteCountFormatter, which is decimal. If
        // this parsed 1GB as 2^30, `size>1GB` would drop rows the window had
        // just labelled "1.02 GB".
        #expect(RequestQuery.bytes("10MB") == 10_000_000)
        #expect(RequestQuery.bytes("1.5GB") == 1_500_000_000)
        #expect(RequestQuery.bytes("900") == 900)
        #expect(RequestQuery.bytes("nope") == nil)
        #expect(RequestQuery.seconds("5s") == 5)
        #expect(RequestQuery.seconds("500ms") == 0.5)
        #expect(RequestQuery.seconds("2.5") == 2.5)
    }

    @Test("An unrecognised key is reported, never silently dropped")
    func unknownKeysSurface() {
        // The failure this guards is a filter that reads as narrowing while
        // actually widening: `statis:403` matching everything, with no sign.
        let query = RequestQuery.parse("purpose:banana status:teapot")
        #expect(query.purposes.isEmpty)
        #expect(query.statuses.isEmpty)
        #expect(query.ignoredKeys == ["purpose:banana", "status:teapot"])
    }

    @Test("A pasted URL is text to search for, not a broken filter")
    func pastedURLIsText() {
        let query = RequestQuery.parse("https://api.github.com/repos/x/y")
        #expect(query.text == ["https://api.github.com/repos/x/y"])
        #expect(query.ignoredKeys.isEmpty)
    }

    @Test("A key nobody defined is reported, not quietly turned into a search word")
    func unknownKeyDoesNotBecomeText() {
        // Left as free text this matches no host and no path, so the list empties
        // and the only explanation on screen is "no such requests" — a filter
        // that never happened, reported as an answer.
        let query = RequestQuery.parse("bogus:x host:apple.com")
        #expect(query.ignoredKeys == ["bogus:x"])
        #expect(query.text.isEmpty)
        #expect(query.hosts == ["apple.com"])
        // A colon inside an ordinary search word is not a key: no scheme, and
        // far too long to be one.
        #expect(RequestQuery.parse("install_info_2.2.3:657").text
                == ["install_info_2.2.3:657"])
    }

    @Test("Quoted values keep their spaces")
    func quotedValues() {
        #expect(RequestQuery.parse("app:\"Visual Studio Code\"").apps == ["Visual Studio Code"])
    }

    @Test("Nothing renders as a dash, never as a unit")
    func zeroIsNotZeroKB() {
        // ByteCountFormatter says "Zero KB", which reads as a broken unit rather
        // than as "none" — and a filter that matched nothing is exactly when the
        // reader is deciding whether the number is broken.
        #expect(ByteFormat.stringOrDash(0) == "—")
        #expect(ByteFormat.stringOrDash(1_000_000) == ByteFormat.string(1_000_000))
        // Decimal, which is what `size>10MB` parses to. If this ever became
        // binary the filter would drop rows the window had just labelled "1 MB".
        #expect(ByteFormat.string(1_000_000).hasPrefix("1 MB"))
    }

    // MARK: - Highlighting

    /// Each span as "text|kind" — tuples are not Equatable, and comparing the
    /// rendered text to the kind is the whole assertion.
    private static func spans(_ input: String) -> [String] {
        let utf16 = Array(input.utf16)
        return RequestQuery.highlights(input).map {
            let text = String(decoding: utf16[$0.location..<($0.location + $0.length)],
                              as: UTF16.self)
            return "\(text)|\($0.kind)"
        }
    }

    @Test("A key and its value are coloured apart; a bare word is neither")
    func highlightSplitsKeysFromValues() {
        #expect(Self.spans("host:github.com zed") == [
            "host:|key", "github.com|value", "zed|text",
        ])
        #expect(Self.spans("size>10MB") == ["size>|key", "10MB|value"])
        // `size` takes `>` or `<`, never a colon. Painting it as a working
        // filter would promise filtering that never happens; leaving it as a
        // search word would empty the list with no explanation. It is neither.
        #expect(Self.spans("size:10MB") == ["size:10MB|unknown"])
    }

    @Test("A token that will not filter is painted as one that will not")
    func highlightMarksIgnoredTokens() {
        // The whole point: `status:teapot` parses to nothing, so a field that
        // drew it like every other filter would be showing a narrowing that is
        // not happening.
        #expect(Self.spans("status:teapot") == ["status:teapot|unknown"])
        #expect(Self.spans("status:404") == ["status:|key", "404|value"])
    }

    @Test("Spans are UTF-16 offsets, so non-ASCII text does not shift the colours")
    func highlightOffsetsSurviveWideCharacters() {
        // NSTextStorage indexes in UTF-16. Counting Characters instead would put
        // every span after an emoji or a CJK path in the wrong place — and the
        // real log is full of them (apps.apple.com/…/huawei-cloud-welink-办公软件).
        let input = "办公软件 host:apple.com"
        let spans = RequestQuery.highlights(input)
        let utf16 = Array(input.utf16)
        for span in spans {
            #expect(span.location + span.length <= utf16.count)
        }
        #expect(Self.spans(input) == [
            "办公软件|text", "host:|key", "apple.com|value",
        ])
    }

    @Test("A quoted value keeps its quotes inside the span")
    func highlightCoversQuotes() {
        #expect(Self.spans("app:\"Visual Studio\"") == [
            "app:|key", "\"Visual Studio\"|value",
        ])
    }

    // MARK: - Execution

    private static func store() -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("query-\(UUID().uuidString).sqlite")
        return (EventStore(fileURL: url, flushEventCount: 1, flushDelay: .milliseconds(10)), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    private static func request(
        host: String = "example.com", path: String = "/feed",
        purpose: RequestPurpose = .versionCheck, client: RequestClient = .app,
        status: Int? = 200, fetchType: RequestEvent.FetchType = .networkLoad,
        received: Int64 = 1000, appID: String? = nil,
        seconds: TimeInterval = 0.1, at: Date = Date()
    ) -> DuoEvent {
        DuoEvent(date: at, client: client, payload: .request(RequestEvent(
            purpose: purpose, method: "GET", scheme: "https", host: host, port: nil,
            path: path, appID: appID, taskID: UUID(), hopIndex: 0, redirectCount: 0,
            status: status, fetchType: fetchType,
            responseBodyBytes: received,
            fetchStart: at, responseEnd: at.addingTimeInterval(seconds))))
    }

    /// Seeds one of everything the strip has to tell apart.
    private static func seed(_ store: EventStore) async {
        await store.append(request(host: "api.github.com", path: "/repos/a/b",
                                   status: 304, received: 0))
        await store.append(request(host: "api.github.com", path: "/repos/c/d", status: 403))
        await store.append(request(host: "api.github.com", path: "/repos/e/f", status: nil))
        await store.append(request(host: "cache.example.com", status: nil,
                                   fetchType: .localCache, received: 0))
        await store.append(request(host: "dl.example.com", path: "/App.dmg",
                                   purpose: .install, received: 50_000_000,
                                   appID: "/Applications/Zed.app", seconds: 9))
        await store.append(request(host: "sweep.example.com", client: .cli, received: 7))
        await store.flush()
    }

    @Test("A cache hit is not a failure, and 403 is not a transport error")
    func statusTermsSeparateThreeDifferentThings() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.seed(store)

        // status IS NULL alone would call the cache hit a failure — the row that
        // cost nothing and worked perfectly.
        #expect(await store.requestLog(.parse("status:fail")).count == 1)
        #expect(await store.requestLog(.parse("status:cache")).count == 1)
        // `problem` is the wider one the failure chip binds to: the 403 belongs
        // here and nowhere else, and it is the most common reason an app stops
        // updating.
        #expect(await store.requestLog(.parse("status:problems")).count == 2)
        #expect(await store.requestLog(.parse("status:4xx")).count == 1)
    }

    @Test("The strip is recomputed for the filter, not for the lifetime")
    func summaryFollowsTheFilter() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.seed(store)

        let all = await store.requestSummary(.parse("client:app"))
        #expect(all.requests == 5)
        #expect(all.notModified == 1)
        #expect(all.cached == 1)
        #expect(all.problems == 2)

        let filtered = await store.requestSummary(.parse("client:app host:api.github.com"))
        #expect(filtered.requests == 3)
        #expect(filtered.problems == 2)
        #expect(filtered.cached == 0)
        #expect(filtered.hostCount == 1)
        #expect(filtered.bytesReceived == 2000, "the 304 carried no body")
    }

    @Test("`duo`'s own sweep stays out of the window's numbers")
    func clientFilter() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.seed(store)
        // A `duo verify` sweep is ~150 diagnostic requests. Folding those in is
        // how the strip starts misreporting what the background updater costs.
        #expect(await store.requestSummary(.parse("client:app")).requests == 5)
        #expect(await store.requestSummary(.parse("client:cli")).requests == 1)
        #expect(await store.requestSummary(.parse("client:all")).requests == 6)
    }

    @Test("Install events never appear in a request filter")
    func installEventsAreNotRequests() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.seed(store)
        await store.append(DuoEvent(date: Date(), client: .app, payload: .install(
            InstallEvent(appID: "/Applications/Zed.app", appName: "Zed", bundleID: nil,
                         fromVersion: "1", toVersion: "2", sourceName: "GitHub",
                         bytes: 50_000_000))))
        await store.flush()
        // The same download is in the log twice at two altitudes: a socket
        // measurement and a ledger entry. Counting both would double it.
        #expect(await store.requestSummary(.parse("client:all")).requests == 6)
        #expect(await store.requestLog(.parse("app:Zed")).count == 1)
    }

    @Test("Size and duration bounds read the payload, not a column")
    func sizeAndDurationBounds() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.seed(store)
        #expect(await store.requestLog(.parse("size>1MB")).count == 1)
        // Scoped to the app: the CLI sweep row is 7 bytes and would count too.
        #expect(await store.requestLog(.parse("size<100 client:app")).count == 2,
                "the 304 and the cache hit, both empty")
        #expect(await store.requestLog(.parse("took>5s")).count == 1)
        #expect(await store.requestLog(.parse("took>30s")).isEmpty)
    }

    @Test("Free text matches host and path together")
    func freeTextSpansHostAndPath() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await Self.seed(store)
        #expect(await store.requestLog(.parse("github")).count == 3)
        // Path-only: the host has nothing to do with the word.
        #expect(await store.requestLog(.parse("App.dmg")).count == 1)
        // Several words narrow.
        #expect(await store.requestLog(.parse("github repos/a")).count == 1)
    }

    @Test("Sorting picks which rows the capped page contains, not just their order")
    func sortingIsPartOfTheQuery() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        // Recent, not a fixed epoch: the store prunes by age, and a 2023
        // timestamp is simply deleted on the way in — which reads as a broken
        // ORDER BY rather than as retention doing its job.
        let start = Date(timeIntervalSinceNow: -300)
        await store.append(Self.request(path: "/small", received: 10,
                                        seconds: 9, at: start))
        await store.append(Self.request(path: "/big", received: 5_000_000,
                                        seconds: 0.1, at: start.addingTimeInterval(60)))
        // Never timed: no fetchStart/responseEnd pair.
        await store.append(DuoEvent(date: start.addingTimeInterval(120), client: .app,
            payload: .request(RequestEvent(
                purpose: .versionCheck, method: "GET", scheme: "https",
                host: "untimed.example.com", port: nil, path: "/x",
                taskID: UUID(), hopIndex: 0, redirectCount: 0,
                status: 200, fetchType: .networkLoad, responseBodyBytes: 1))))
        await store.flush()

        var bySize = RequestQuery.parse("client:app")
        bySize.sort = .size
        #expect(await store.requestLog(bySize).first?.request?.path == "/big")
        bySize.ascending = true
        #expect(await store.requestLog(bySize).map { $0.request?.bytesReceived ?? -1 }
                == [1, 10, 5_000_000], "ascending is the exact reverse")

        var byDuration = RequestQuery.parse("client:app")
        byDuration.sort = .duration
        // The untimed row sorts last in BOTH directions. Ordinary NULL handling
        // would open "fastest first" with a page of hops that were never timed,
        // which reads as "these took no time at all".
        let slowestFirst = await store.requestLog(byDuration)
        #expect(slowestFirst.map { $0.request?.path ?? "?" } == ["/small", "/big", "/x"])
        byDuration.ascending = true
        let fastestFirst = await store.requestLog(byDuration)
        #expect(fastestFirst.map { $0.request?.path ?? "?" } == ["/big", "/small", "/x"])
    }

    @Test("The log reads newest first")
    func newestFirst() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await store.append(Self.request(path: "/old", at: start))
        await store.append(Self.request(path: "/new", at: start.addingTimeInterval(60)))
        await store.flush()
        let log = await store.requestLog(.init())
        #expect(log.first?.request?.path == "/new")
    }
}

/// The update session's cache, which is a bandwidth decision rather than a
/// tuning preference.
@Suite
struct UpdateSessionCacheTests {

    @Test("The cache is big enough to actually hold the largest version probe")
    func capacityFitsTheLargestProbe() {
        // `URLCache` silently declines to store a response larger than roughly
        // 5% of its capacity — measured 2026-09-04 against
        // `download.scdn.co/SpotifyInstaller.zip` (1,868,156 bytes): not stored
        // at 32 MB, stored at 40 MB. Apple documents no ratio, so this pins the
        // measurement with room to spare.
        //
        // What it costs to get wrong: with the response uncacheable,
        // `reloadRevalidatingCacheData` has no validator to send and every check
        // re-downloads the whole thing. One machine spent 160 MB on 92 Spotify
        // checks — more than every other app's update checks combined — where a
        // revalidation is 238 bytes. Nothing else fails; the updater just
        // quietly costs a hundred times what it should.
        let capacity = URLSession.updates.configuration.urlCache?.memoryCapacity ?? 0
        #expect(capacity >= URLSession.largestProbeBody * 20,
                "a probe body must stay under the ~5% ceiling, with headroom for it to grow")
    }

    @Test("Nothing cached by the update session may reach disk")
    func nothingReachesDisk() {
        // The other half of the same object, and the reason the capacity above
        // is memory-only: these responses include credential-bearing URLs.
        #expect(URLSession.updates.configuration.urlCache?.diskCapacity == 0)
    }
}

/// The seven defects a review of this change turned up, each pinned so the fix
/// cannot quietly come undone.
@Suite(.serialized)
struct RequestQueryReviewTests {

    @Test("A bound that parses to nothing is reported, not dropped")
    func unparseableBoundIsReported() {
        // `size>banana` is pinned as an ordinary capsule, so left unreported it
        // looks exactly like a filter that works while the list fails to narrow.
        let query = RequestQuery.parse("size>banana")
        #expect(query.minBytes == nil)
        #expect(query.ignoredKeys == ["size>banana"])
        #expect(RequestQuery.parse("took>soon").ignoredKeys == ["took>soon"])
        // And a real one still parses.
        #expect(RequestQuery.parse("size>10MB").minBytes == 10_000_000)
        #expect(RequestQuery.parse("size>10MB").ignoredKeys.isEmpty)
    }

    @Test("Each bound is judged on its own, not on whether any bound landed")
    func boundsAreReportedPerToken() {
        // The first version asked whether all three bounds were nil, so a good
        // one masked a bad one: `size>10MB took>abc` reported nothing while
        // silently applying only half of what the field showed.
        let query = RequestQuery.parse("size>10MB took>abc")
        #expect(query.minBytes == 10_000_000)
        #expect(query.minDuration == nil)
        #expect(query.ignoredKeys == ["took>abc"])
    }

    @Test("A row an older build wrote is still counted correctly")
    func cacheFlagFallsBackToThePayload() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("downgrade-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix))
            }
        }
        let store = EventStore(fileURL: url, flushEventCount: 1,
                               flushDelay: .milliseconds(10))
        await store.append(DuoEvent(date: Date(timeIntervalSinceNow: -60), client: .app,
            payload: .request(RequestEvent(
                purpose: .versionCheck, method: "GET", scheme: "https",
                host: "example.com", port: nil, path: "/feed",
                taskID: UUID(), hopIndex: 0, redirectCount: 0,
                status: nil, fetchType: .localCache))))
        await store.flush()
        // Blanking the column *without* clearing the marker is what a downgrade
        // leaves behind: a build that never heard of the column writes rows the
        // migration will not revisit, because as far as this store is concerned
        // it already ran. The payload still says what happened.
        #expect(await store.blankFromCacheForTesting(keepingMarker: true) == 1)
        #expect(await store.requestSummary(RequestQuery.window("")).cached == 1)
        #expect(await store.requestLog(.parse("status:cache")).count == 1)
    }

    @Test("An ignored token is reported exactly as it was typed")
    func ignoredTokensKeepTheirCase() {
        // The capsule matches on the token, so a reconstructed lowercase copy
        // never matched and the one token filtering nothing was drawn as though
        // it were working.
        #expect(RequestQuery.parse("Purpose:banana").ignoredKeys == ["Purpose:banana"])
        #expect(RequestQuery.parse("STATUS:teapot").ignoredKeys == ["STATUS:teapot"])
    }

    @Test("`client:` inside ordinary text does not widen the window")
    func clientScopingReadsTokensNotSubstrings() {
        // A path with a colon in it is free text. Deciding the scoping by
        // searching the raw string for "client:" folded `duo`'s sweep — ~150
        // diagnostic requests — into every figure in the strip.
        #expect(RequestQuery.window("some/client:x/path").clients == [.app])
        #expect(RequestQuery.window("").clients == [.app])
        // An actual token still hands the decision back.
        #expect(RequestQuery.window("client:cli").clients == [.cli])
        #expect(RequestQuery.window("client:all").clients.isEmpty)
    }

    @Test("The cache flag is a column, and history is backfilled into it")
    func cacheFlagIsDenormalised() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fromcache-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix))
            }
        }
        let now = Date(timeIntervalSinceNow: -60)
        func event(_ fetchType: RequestEvent.FetchType, _ offset: TimeInterval) -> DuoEvent {
            DuoEvent(date: now.addingTimeInterval(offset), client: .app,
                payload: .request(RequestEvent(
                    purpose: .versionCheck, method: "GET", scheme: "https",
                    host: "example.com", port: nil, path: "/feed",
                    taskID: UUID(), hopIndex: 0, redirectCount: 0,
                    status: fetchType == .localCache ? nil : 200,
                    fetchType: fetchType, responseBodyBytes: 10)))
        }
        do {
            let store = EventStore(fileURL: url, flushEventCount: 1,
                                   flushDelay: .milliseconds(10))
            await store.append(event(.localCache, 0))
            await store.append(event(.networkLoad, 1))
            await store.flush()
            // Stands in for a store written before the column existed.
            #expect(await store.blankFromCacheForTesting() == 2)
        }
        // Reopening runs the migration. A row left NULL would be counted as
        // "not from cache", so the figures would disagree with the log they sit
        // above — which is why the backfill is mandatory rather than best-effort.
        let reopened = EventStore(fileURL: url, flushEventCount: 1,
                                  flushDelay: .milliseconds(10))
        let summary = await reopened.requestSummary(RequestQuery.window(""))
        #expect(summary.requests == 2)
        #expect(summary.cached == 1)
        #expect(await reopened.requestLog(.parse("status:cache")).count == 1)
    }

    @Test("The change token carries both fields rather than packing them")
    func changeTokenCannotCollide() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + suffix))
            }
        }
        let store = EventStore(fileURL: url, flushEventCount: 1,
                               flushDelay: .milliseconds(10))
        let before = await store.changeToken()
        await store.append(DuoEvent(date: Date(), client: .app, payload: .request(
            RequestEvent(purpose: .versionCheck, method: "GET", scheme: "https",
                         host: "example.com", port: nil, path: "/feed",
                         taskID: UUID(), hopIndex: 0, redirectCount: 0,
                         status: 200, fetchType: .networkLoad))))
        await store.flush()
        // Our own writes move it — `PRAGMA data_version` deliberately ignores
        // them, so a viewer watching only that would never see this app's own
        // requests arrive.
        #expect(await store.changeToken() != before)
    }
}
