import Foundation
import DuoUpdaterCore

/// Fetch every recipe's `changelogURL` and say which ones are dead.
///
/// The gap this closes (issue #107): a `changelogURL` is not parsed by anything,
/// so no other check in this sweep touches it. `ChangelogURLPolicyTests` asserts
/// its *shape* — https, no credentials, no IP literal — and a shape stays valid
/// forever after the page behind it is retired. A vendor moves their docs, the
/// release-notes button starts opening a 404, and every test stays green. Three
/// Microsoft Edge channels sat that way until someone fetched all 87 by hand.
///
/// **Advisory by construction.** Only 404 and 410 — the two codes that mean the
/// server is asserting the page is gone — become a warning. Everything else is a
/// machine note: a 403 is far more often a bot wall than a dead page, a 429 or a
/// 5xx is the vendor having a bad minute, and a dropped connection is this
/// machine's network. Filing issues for those would train the reader to ignore
/// the ones that matter.
///
/// **This runs on URLSession, and that is the point.** Issue #107 measured the
/// registry with `curl` and reported AnyDesk's changelog as a 403; through
/// `URLSession` the same URL answers 200 (HEAD and GET alike, verified
/// 2026-08-28), because the bot wall is reading the client, not the URL. The app
/// opens these pages in a WebView on Apple's networking stack, so a check that
/// asks the way the app asks measures the thing the user will actually see — and
/// a whole class of phantom "dead page" findings never exists.
///
/// **What it cannot see:** a soft 404 — a 200 page whose body says "not found".
/// Detecting that means reading and judging the body of every changelog page in
/// the registry, which is a different (and much noisier) check than this one.
enum ChangelogLinkSweep {

    /// What the vendor's server said about one changelog page.
    enum Verdict: Sendable, Equatable {
        /// 2xx — the page answers.
        case alive
        /// 404/410. The server is stating the page does not exist.
        case gone(Int)
        /// Any other status, or no response at all. Says nothing about the page.
        case inconclusive(String)
    }

    /// This check's own session, deliberately NOT the shared `URLSession.updates`.
    ///
    /// This is the only place in the codebase that issues a HEAD and a GET for the
    /// same URL, and `sweepChangelog` later GETs some of those URLs for real. A
    /// zero-length HEAD response sitting in a shared `URLCache` is exactly the
    /// kind of thing that turns into an empty body and a "recipe broken" issue for
    /// a page that is fine — and `URLRequest.versionFeedCachePolicy`'s own
    /// documentation is about how invisible that class of failure is. Nothing here
    /// benefits from a cache (every request ignores it on the way out anyway), so
    /// the safe move is to have no store to poison.
    private static let linkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    /// Browser-ish, matching `VendorProbeSource`: several docs hosts serve a
    /// different (or no) response to an unrecognised agent, and a 403 we provoked
    /// ourselves would be noise in a check whose whole job is to be quiet.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Distinct changelog pages across `recipes`, in a stable order, minus any
    /// page another part of the sweep is already fetching.
    ///
    /// Deduplicated because several recipes legitimately share one page — Chrome's
    /// four channels, Firefox's trains — and asking the same host the same
    /// question four times is four times the rate-limit exposure for no extra
    /// signal.
    ///
    /// `alreadyFetched` is the stronger version of the same argument. 17 of the 87
    /// pages are ALSO a `ChangelogRecipe.source`, which `sweepChangelog` fetches
    /// with a GET and parses in the same run. Asking again would be a wasted
    /// request, and worse, a second opinion that can disagree with the first: one
    /// report saying a recipe parsed 2 entries from a page and, two lines down,
    /// that the same page is gone. A GET that came back with a parseable document
    /// is the better evidence, so a page that has one is not asked twice.
    static func pages(
        of recipes: [VendorProbeRecipe], alreadyFetched: Set<String> = []
    ) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for recipe in recipes {
            guard let url = recipe.changelogURL else { continue }
            guard !alreadyFetched.contains(url.absoluteString) else { continue }
            if seen.insert(url.absoluteString).inserted { out.append(url) }
        }
        return out
    }

    /// HEAD every page, grouped by host with the sweep's usual per-host pacing.
    static func statuses(
        of recipes: [VendorProbeRecipe], alreadyFetched: Set<String> = [],
        options: VerifyOptions
    ) async -> [String: Verdict] {
        let urls = pages(of: recipes, alreadyFetched: alreadyFetched)
        guard !urls.isEmpty else { return [:] }

        let groups = Dictionary(grouping: urls, by: { $0.host ?? "-" })
            .values.sorted { ($0[0].host ?? "-") < ($1[0].host ?? "-") }
        let delay = options.perHostDelay

        var out: [String: Verdict] = [:]
        var next = 0
        await withTaskGroup(of: [(String, Verdict)].self) { group in
            func addNext() {
                guard next < groups.count else { return }
                let batch = groups[next]
                next += 1
                group.addTask {
                    var produced: [(String, Verdict)] = []
                    for (index, url) in batch.enumerated() {
                        if index > 0 {
                            try? await Task.sleep(
                                for: delay + .milliseconds(Int.random(in: 0...100)))
                        }
                        produced.append((url.absoluteString, await verdict(for: url)))
                    }
                    return produced
                }
            }
            for _ in 0..<min(options.hostConcurrency, groups.count) { addNext() }
            for await produced in group {
                for (key, value) in produced { out[key] = value }
                addNext()
            }
        }
        return out
    }

    /// One page: HEAD to ask cheaply, and **GET before believing any bad news.**
    ///
    /// A HEAD is a request for the headers of a GET, and plenty of hosts do not
    /// implement it that way. The first full live run of this check flagged both
    /// WorkBuddy changelog pages as gone: `www.workbuddy.ai` and
    /// `www.codebuddy.cn` answer HEAD with **404** and GET with **200** and 31 KB
    /// of the page (measured 2026-08-28) — a static-site host that only generates
    /// routes for GET. Two working recipes, accused by name, on a check whose
    /// whole justification is that it stays quiet.
    ///
    /// So a HEAD may only ever confirm a page ALIVE. Anything else is re-asked
    /// the way a browser would ask, and the GET's answer is the one that counts.
    /// The first draft retried on 403/405/400 only — chosen from the codes that
    /// obviously mean "not that method", which quietly assumed a 404 could be
    /// trusted from a request no browser makes. It cannot. The cost is one extra
    /// request per unhealthy page, on a path that is rare by construction.
    static func verdict(for url: URL, session: URLSession = linkSession) async -> Verdict {
        if case .alive = await status(of: url, method: "HEAD", session: session) {
            return .alive
        }
        return await status(of: url, method: "GET", session: session)
    }

    private static func status(
        of url: URL, method: String, session: URLSession
    ) async -> Verdict {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        // A cached 200 from an earlier sweep would hide the day the page died,
        // which is the only day this check exists for.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let response: URLResponse
        do { (_, response) = try await session.countedData(for: request, purpose: .changelog) }
        catch {
            // A host that does not resolve is worth saying out loud rather than
            // filing under "the network was unhappy". Retiring a docs subdomain
            // outright is one of the ways a vendor kills a changelog page, and it
            // is the one shape of this check's blind spot that a reader can act
            // on — so it stays non-accusing (DNS fails for local reasons too) but
            // stops reading as ordinary transport noise.
            // Both codes mean the name did not resolve; which one Foundation
            // surfaces depends on the resolver, so matching only one would leave
            // half of this branch's own case reading as ordinary network noise.
            if let code = (error as? URLError)?.code,
               code == .cannotFindHost || code == .dnsLookupFailed {
                return .inconclusive("does not resolve — the host itself may be retired")
            }
            return .inconclusive("could not be reached")
        }
        guard let http = response as? HTTPURLResponse else {
            return .inconclusive("answered with a non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return .alive
        case 404, 410:  return .gone(http.statusCode)
        default:        return .inconclusive("answered HTTP \(http.statusCode)")
        }
    }

    /// How a verdict should read in the report, or nil when there is nothing to
    /// say. A machine note never promotes a finding to `.warn` — see
    /// `Finding.machineNotePrefix`.
    static func complaint(for verdict: Verdict, url: URL) -> String? {
        switch verdict {
        case .alive:
            return nil
        case .gone(let code):
            return "its release-notes page is gone: \(url.absoluteString) returns HTTP "
                + "\(code) — the button in the app opens a dead page"
        case .inconclusive(let detail):
            return Finding.machineNotePrefix
                + "changelogURLUnverified: \(url.absoluteString) \(detail), which is as "
                + "consistent with a bot wall as with a dead page — needs a human with a browser"
        }
    }
}
