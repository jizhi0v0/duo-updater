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

    /// Run `extract` off-thread so a regression is a failed expectation rather
    /// than a test run that never returns.
    static func extract(from text: String, within budget: TimeInterval) -> (Changelog?, TimeInterval)? {
        final class Box: @unchecked Sendable { var value: Changelog?? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let started = Date()
        let recipe = Self.recipe
        Thread.detachNewThread {
            box.value = .some(ChangelogExtractor.extract(from: text, using: recipe))
            done.signal()
        }
        guard done.wait(timeout: .now() + budget) == .success else { return nil }
        return (box.value!, Date().timeIntervalSince(started))
    }

    /// The guard against this test quietly becoming decoration: the generated page
    /// has to be big enough to have exercised the old blowup, and the pattern has
    /// to actually parse it. If a future edit breaks either, the timing
    /// expectations below would pass against an input that proves nothing.
    @Test func theGeneratedPageIsBigEnoughAndTheRecipeParsesIt() throws {
        let page = Self.generatedPage()
        #expect(page.utf8.count > 100_000, "smaller than this did not reproduce the blowup")
        let (changelog, _) = try #require(Self.extract(from: page, within: 30))
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
    /// The budget is deliberately loose. The measured worst case is 0.06 s, so a
    /// two-second bar cannot be tripped by a slow machine — only by the shape
    /// coming back.
    @Test(arguments: [
        ("the closing </script> renamed", "</script>", "</tmpl-script>"),
        ("the template wrapper dropped", "<script type='text/template'>", "<div class='post-body'>"),
        ("the publishdate class renamed", "class='publishdate'", "class='published-on'"),
    ])
    func aRestyledPageFailsFastInsteadOfBacktracking(name: String, find: String, replace: String) throws {
        let page = Self.generatedPage().replacingOccurrences(of: find, with: replace)
        // Vacuity guard: the mutation has to have changed something.
        #expect(!page.contains(find), "\(name): nothing was mutated")
        let (changelog, elapsed) = try #require(
            Self.extract(from: page, within: 2), "\(name): did not finish within 2s")
        #expect(changelog == nil, "\(name): a restyled page should not parse")
        #expect(elapsed < 2, "\(name) took \(elapsed)s")
    }

    /// The other half of the old blowup, and the one a healthy page can reach on
    /// its own: posts that list no 4-part build number. This one scales with the
    /// number of posts rather than body size, so it needs a bigger page than the
    /// case above to show itself — measured on the old pattern, three posts is
    /// 0.09 s and ten posts is 7.6 s, against 0.047 s now. (The live 852 KB page,
    /// six posts, took 20.6 s.) Ten posts is what makes this test red rather than
    /// decorative.
    @Test func aPageWithNoBuildNumbersFailsFast() throws {
        let page = Self.generatedPage(posts: 10, bodyKB: 100).replacingOccurrences(
            of: #"\d+\.\d+\.\d+\.\d+"#, with: "X", options: .regularExpression)
        #expect(page.utf8.count > 900_000, "fewer posts than this did not reproduce the blowup")
        #expect(page.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) == nil)
        let (changelog, elapsed) = try #require(Self.extract(from: page, within: 2),
                                                "did not finish within 2s")
        #expect(changelog == nil)
        #expect(elapsed < 2, "took \(elapsed)s")
    }

    /// Why the body gap is a plain lazy tempered dot and not `*+` or `(?>…)`:
    /// a possessive/atomic run silently stops matching past roughly 250 000
    /// characters, and Chrome's second post is a 324 KB body. The failure is not an
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
