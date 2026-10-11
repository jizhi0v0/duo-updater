import Testing
import Foundation
@testable import DuoUpdaterCore

/// Chrome's changelog pattern must fail *fast*, not just succeed.
///
/// The shape it had — four unbounded lazy gaps in a row — parsed the live page in
/// 25 ms and, the moment the page stopped matching, searched combinatorially:
/// renaming the closing `</script>` on the real 852 KB page ran past 150 s, and a
/// page with no 4-part build numbers took 20.6 s, both on the thread
/// `ChangelogService.parse` is called from. A vendor restyle is precisely the
/// input that stops matching, so the recipe's *failure* path is the one that has
/// to be bounded.
///
/// The real page is too big to commit, so this generates one with the same shape.
/// The generated page reproduces the blowup faithfully: three posts with 40 KB
/// bodies (124 KB total) took **35.9 s** under the old pattern and **0.012 s**
/// under the current one.
@Suite("Chrome changelog pattern")
struct ChromeChangelogPatternTests {

    /// A stand-in for the Blogger search-label page: posts carrying the title
    /// anchor, a publishdate span, and a template-script block whose body is large
    /// and sprinkled with version-shaped numbers — the three things the pattern
    /// walks and the fourth thing (many candidate versions) that made it backtrack.
    static func generatedPage(posts: Int = 3, bodyKB: Int = 40) -> String {
        var page = "<html><body>"
        for i in 0..<posts {
            page += "<h3 class='post-title'><a href='/2026/09/update-\(i).html'"
                + " title='Stable Channel Update for Desktop'>Stable Channel Update for Desktop</a></h3>"
            page += "<span class='publishdate' itemprop='datePublished'> Tuesday, September \(i + 1), 2026 </span>"
            page += "<script type='text/template'>"
            var body = "<p>The Stable channel has been updated to 152.0.79\(77 - i).\(64 + i) for Mac.</p>"
            while body.utf8.count < bodyKB * 1024 {
                body += "<p>CVE-2026-\(1000 + body.count % 900): Use after free in Something.</p>"
                    + "<p>See 1.2.3.\(body.count % 97) for details.</p>"
            }
            page += body + "</script>"
        }
        return page + "</body></html>"
    }

    static var recipe: ChangelogRecipe {
        ChangelogRecipeRegistry.recipe(forBundleID: "com.google.Chrome")!
    }

    /// Run `extract` on its own thread and charge it by the CPU time that thread
    /// has used, not by the clock. Returns `nil` as soon as that passes `budget`, so
    /// a regression is a failed expectation rather than a run that never returns;
    /// otherwise the result and the CPU seconds it cost.
    ///
    /// Not wall time: this suite runs in parallel, and a 2 s wall bound failed on
    /// 2026-10-11 in a run from a LaunchAgent on the Mac mini, which it shares
    /// with two Actions runners; the mini's sweep agent, which runs `make test`,
    /// is `ProcessType` Background. The no-build-numbers page, measured on a
    /// 14-core M-series Mac (thread CPU / wall):
    ///
    ///                                   current pattern    old pattern
    ///     idle                          0.047 / 0.047 s    7.68 / 7.70 s
    ///     42 busy `yes`                 0.051 / 0.056 s    7.98 / 27.6 s
    ///     `taskpolicy -b` (E-cores)     0.156 / 0.67 s     21.2 / 54.8 s
    ///     `taskpolicy -b`, 14 bg `yes`  0.134 / 1.45 s     —
    ///
    /// Wall time stretches with load, for both patterns. CPU time barely moves
    /// with load; what moves it is the core class the thread lands on, about 3×
    /// slower on an efficiency core — for both patterns alike, so the gap between
    /// them holds wherever the test runs.
    static func extract(from text: String, cpuBudget budget: TimeInterval) -> (Changelog?, TimeInterval)? {
        final class Box: @unchecked Sendable {
            var value: Changelog??
            var cpu: TimeInterval = 0
            var port: thread_act_t = 0
        }
        let box = Box()
        let started = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let recipe = Self.recipe
        Thread.detachNewThread {
            box.port = pthread_mach_thread_np(pthread_self())
            started.signal()
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            box.value = .some(ChangelogExtractor.extract(from: text, using: recipe))
            box.cpu = TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
            done.signal()
        }
        started.wait()
        // Waits as long as the thread needs; only the CPU it has burned can fail it.
        while done.wait(timeout: .now() + .milliseconds(10)) == .timedOut {
            if let used = Self.cpuSeconds(of: box.port), used > budget { return nil }
        }
        return (box.value!, box.cpu)
    }

    /// User + system CPU time of a running thread; `nil` once it has exited.
    static func cpuSeconds(of thread: thread_act_t) -> TimeInterval? {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        func seconds(_ t: time_value_t) -> TimeInterval { TimeInterval(t.seconds) + TimeInterval(t.microseconds) / 1e6 }
        return seconds(info.user_time) + seconds(info.system_time)
    }

    /// The guard against this test quietly becoming decoration: the generated page
    /// has to be big enough to have exercised the old blowup, and the pattern has
    /// to actually parse it. If a future edit breaks either, the timing
    /// expectations below would pass against an input that proves nothing.
    @Test func theGeneratedPageIsBigEnoughAndTheRecipeParsesIt() throws {
        let page = Self.generatedPage()
        #expect(page.utf8.count > 100_000, "smaller than this did not reproduce the blowup")
        let (changelog, _) = try #require(Self.extract(from: page, cpuBudget: 30))
        let entries = try #require(changelog?.entries)
        #expect(entries.count == 3)
        #expect(entries.map(\.version) == ["152.0.7977.64", "152.0.7976.65", "152.0.7975.66"])
        #expect(entries.allSatisfy { $0.date?.hasPrefix("Tuesday, September") == true })
        #expect(entries.allSatisfy { !$0.items.isEmpty })
    }

    /// The mutation that actually blew up, and the two next to it.
    ///
    /// Only the first of these three is red against the old pattern — 36 s on this
    /// very page, against 0.012 s now. The other two were already fast (0.35 s and
    /// 0.04 s on the live page) and are here as pins: they are the other two ways
    /// this page can stop matching, and the next edit to the pattern should not be
    /// able to turn one of them into the first one without a test saying so.
    ///
    /// The budget is one second of CPU on the extracting thread. The first case
    /// measured at most 0.034 s of CPU (efficiency core, under load) against 49 s
    /// under the old pattern, and all three together take under 0.1 s on an idle
    /// machine, page generation included — so neither a busy machine nor a slow
    /// core can trip it, only the shape coming back.
    @Test(arguments: [
        ("the closing </script> renamed", "</script>", "</tmpl-script>"),
        ("the template wrapper dropped", "<script type='text/template'>", "<div class='post-body'>"),
        ("the publishdate class renamed", "class='publishdate'", "class='published-on'"),
    ])
    func aRestyledPageFailsFastInsteadOfBacktracking(name: String, find: String, replace: String) throws {
        let page = Self.generatedPage().replacingOccurrences(of: find, with: replace)
        // Vacuity guard: the mutation has to have changed something.
        #expect(!page.contains(find), "\(name): nothing was mutated")
        let (changelog, cpu) = try #require(
            Self.extract(from: page, cpuBudget: 1), "\(name): used more than 1s of CPU")
        #expect(changelog == nil, "\(name): a restyled page should not parse")
        #expect(cpu < 1, "\(name) took \(cpu)s of CPU")
    }

    /// The other half of the old blowup, and the one a healthy page can reach on
    /// its own: posts that list no 4-part build number. This one scales with the
    /// number of posts rather than body size, so it needs a bigger page than the
    /// case above to show itself — measured on the old pattern, three posts is
    /// 0.09 s and ten posts is 7.6 s, against 0.047 s now. (The live 852 KB page,
    /// six posts, took 20.6 s.) Ten posts is what makes this test red rather than
    /// decorative.
    ///
    /// The bound is one second of the extracting thread's CPU, not of the clock:
    /// the current pattern's worst is 0.156 s and the old pattern's best 7.68 s
    /// (table on `extract`), so one second sits about 6× clear of each.
    @Test func aPageWithNoBuildNumbersFailsFast() throws {
        let page = Self.generatedPage(posts: 10, bodyKB: 100).replacingOccurrences(
            of: #"\d+\.\d+\.\d+\.\d+"#, with: "X", options: .regularExpression)
        #expect(page.utf8.count > 900_000, "fewer posts than this did not reproduce the blowup")
        #expect(page.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) == nil)
        let (changelog, cpu) = try #require(Self.extract(from: page, cpuBudget: 1),
                                            "used more than 1s of CPU")
        #expect(changelog == nil)
        #expect(cpu < 1, "took \(cpu)s of CPU")
    }

    /// Why the body gap is a plain lazy tempered dot and not `*+` or `(?>…)`:
    /// a possessive/atomic run silently stops matching past roughly 250 000
    /// characters, and Chrome's post bodies run to hundreds of KB (one was 324 KB
    /// when this was written, 2026-09-02). The failure is not an
    /// error — it is a quiet "no match", i.e. an entry vanishing from the pane. If
    /// this ever stops being true, the comment on the recipe should change with it.
    @Test func aPossessiveRunSilentlyStopsMatchingOnALongBody() throws {
        let pattern = #"<s>(?<body>(?:(?!</s>).)*?(?<v>\d+\.\d+\.\d+\.\d+)(?:(?!</s>).)*+)</s>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        func matches(tail: Int) -> Bool {
            let doc = "<s>a 1.2.3.4 " + String(repeating: "b", count: tail) + "</s>"
            return regex.firstMatch(in: doc, range: NSRange(location: 0, length: (doc as NSString).length)) != nil
        }
        #expect(matches(tail: 100_000), "a short possessive run is fine")
        #expect(!matches(tail: 300_000), "a long one silently fails — this is why the body gap is lazy")
    }
}
