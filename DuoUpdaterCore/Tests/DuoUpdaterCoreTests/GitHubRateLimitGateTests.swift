import Testing
import Foundation
@testable import DuoUpdaterCore

/// `GitHubRateLimitGate`: GitHub's documented rules for when the REST API may
/// be asked again, and the per-credential store that applies them. Each case
/// names the mutation it fails under.
struct GitHubRateLimitGateTests {

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func headers(remaining: Int? = nil, reset: TimeInterval? = nil, retryAfter: Int? = nil,
                 resource: String? = "core") -> [String: String] {
        var h: [String: String] = [:]
        if let resource { h["x-ratelimit-resource"] = resource }
        if let remaining { h["X-RateLimit-Remaining"] = String(remaining) }
        if let reset { h["x-ratelimit-reset"] = String(Int(reset)) }
        if let retryAfter { h["Retry-After"] = String(retryAfter) }
        return h
    }

    func closure(_ status: Int, _ headers: [String: String], body: String? = nil, strikes: Int = 0)
        -> GitHubRateLimitGate.Closure?
    {
        GitHubRateLimitGate.closure(status: status, headers: headers, body: body.map { Data($0.utf8) },
                                    strikesBefore: strikes, now: now)
    }

    /// Primary: `remaining: 0` closes until `reset` — on the 403 that says so,
    /// and on the 200 that spent the last request, since the next would be
    /// refused. A reset already past closes nothing.
    ///
    /// Mutations: only on 403/429; ignore `reset` (close for a fixed time);
    /// drop the `reset > now` check.
    @Test func aSpentBudgetClosesUntilReset() {
        let reset = now.timeIntervalSince1970 + 1500
        for status in [200, 304, 403, 429] {
            #expect(closure(status, headers(remaining: 0, reset: reset))
                    == .init(until: Date(timeIntervalSince1970: reset), reason: .exhausted), "\(status)")
        }
        #expect(closure(403, headers(remaining: 0, reset: now.timeIntervalSince1970 - 1)) == nil)
        #expect(closure(200, headers(remaining: 1, reset: reset)) == nil)
    }

    /// Another resource's budget (search, GraphQL) is not `core`'s.
    ///
    /// Mutation: drop the `isCore` check.
    @Test func anotherResourcesBudgetLeavesCoreOpen() {
        let reset = now.timeIntervalSince1970 + 60
        #expect(closure(200, headers(remaining: 0, reset: reset, resource: "search")) == nil)
    }

    /// Secondary: `retry-after` seconds when given; otherwise, on a 429 or a
    /// 403 whose body names a rate limit, a minute doubling with each refusal
    /// in a row, up to an hour. A 403 for anything else closes nothing.
    ///
    /// Mutations: ignore `retry-after`; no doubling; no ceiling; close on any 403.
    @Test func aSecondaryLimitWaitsAsDocumented() {
        #expect(closure(403, headers(retryAfter: 90))?.until == now.addingTimeInterval(90))
        #expect(closure(429, headers())?.until == now.addingTimeInterval(60))
        let body = #"{"message":"You have exceeded a secondary rate limit."}"#
        #expect(closure(403, headers(), body: body) == .init(until: now.addingTimeInterval(60), reason: .secondary(strike: 1)))
        #expect(closure(403, headers(), body: body, strikes: 1)?.until == now.addingTimeInterval(120))
        #expect(closure(403, headers(), body: body, strikes: 2)?.until == now.addingTimeInterval(240))
        #expect(closure(403, headers(), body: body, strikes: 20)?.until == now.addingTimeInterval(3600))
        #expect(closure(403, headers(), body: #"{"message":"Resource not accessible"}"#) == nil)
        #expect(closure(404, headers()) == nil)
    }

    // MARK: the store

    /// A settable clock and a scripted probe that counts its calls and can be
    /// held at a gate.
    final class World: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var probes = 0
        var answer: GitHubRateLimitGate.ProbeAnswer?
        var hold: Hold?
        func probe() async -> GitHubRateLimitGate.ProbeAnswer? {
            probes += 1
            await hold?.wait()
            return answer
        }
    }

    actor Hold {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var arrived = 0
        func wait() async {
            arrived += 1
            if open { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() { open = true; waiters.forEach { $0.resume() }; waiters = [] }
    }

    func store(_ world: World, patience: Duration = .seconds(20)) -> GitHubRateLimitGate.Store {
        GitHubRateLimitGate.Store(now: { world.now }, canaryPatience: patience)
    }

    func admit(_ store: GitHubRateLimitGate.Store, _ world: World, _ credential: GitHubRateLimitGate.Credential = .token,
               generation: Int = 1) async -> GitHubRateLimitGate.Admission {
        await store.admit(credential, generation: generation, probe: { await world.probe() })
    }

    func until(_ condition: () async -> Bool) async {
        for _ in 0..<2000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("condition never became true")
    }

    /// The first request probes once, then goes alone as the canary; the others
    /// wait for its answer and go once it says there is room.
    ///
    /// Mutations: open straight after the probe (no canary); probe per request.
    @Test func aFirstRequestProbesAndGoesAloneAsTheCanary() async {
        let world = World()
        world.answer = .init(remaining: 100, reset: world.now.addingTimeInterval(600))
        let store = store(world)

        #expect(await admit(store, world) == .go(canary: true))
        let others = (0..<5).map { _ in Task { await self.admit(store, world) } }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(world.probes == 1)
        await store.complete(.token, generation: 1, canary: true, status: 200,
                             headers: ["x-ratelimit-remaining": "99", "x-ratelimit-reset": "1800000600"], body: nil)
        for other in others { #expect(await other.value == .go(canary: false)) }
        #expect(world.probes == 1)
    }

    /// A probe that finds the budget spent closes the gate: not one real
    /// request goes, and the requests waiting on the probe are all refused.
    ///
    /// Mutation: ignore the probe's answer (always canary).
    @Test func aProbeThatFindsTheBudgetSpentLetsNothingGo() async {
        let world = World()
        let reset = world.now.addingTimeInterval(900)
        world.answer = .init(remaining: 0, reset: reset)
        world.hold = Hold()
        let store = store(world)

        let requests = (0..<10).map { _ in Task { await self.admit(store, world) } }
        await until { await world.hold!.arrived == 1 }
        await world.hold!.release()
        for request in requests {
            #expect(await request.value == .refused(.init(until: reset, reason: .exhausted)))
        }
        #expect(world.probes == 1)
    }

    /// A canary whose answer says the budget is spent closes the gate; the
    /// requests waiting on it are refused, not sent.
    ///
    /// Mutation: the canary's answer opening the gate whatever it said.
    @Test func aSpentCanaryClosesTheGateForTheRest() async {
        let world = World()
        world.answer = .init(remaining: 50, reset: world.now.addingTimeInterval(600))
        let store = store(world)
        #expect(await admit(store, world) == .go(canary: true))
        let waiting = Task { await self.admit(store, world) }
        try? await Task.sleep(for: .milliseconds(20))
        await store.complete(.token, generation: 1, canary: true, status: 403,
                             headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000700"], body: nil)
        #expect(await waiting.value == .refused(.init(until: Date(timeIntervalSince1970: 1_800_000_700), reason: .exhausted)))
    }

    /// When a closure ends the gate does not just open: it probes again, and a
    /// canary goes first.
    ///
    /// Mutation: a closure that has ended opening the gate directly.
    @Test func anEndedClosureProbesAgain() async {
        let world = World()
        let reset = world.now.addingTimeInterval(300)
        world.answer = .init(remaining: 0, reset: reset)
        let store = store(world)
        #expect(await admit(store, world) == .refused(.init(until: reset, reason: .exhausted)))

        world.now = reset
        world.answer = .init(remaining: 5000, reset: reset.addingTimeInterval(3600))
        #expect(await admit(store, world) == .go(canary: true))
        #expect(world.probes == 2)
    }

    /// Another token is another budget: switching to it probes it; switching
    /// back to the spent one probes again and finds it spent — no real request
    /// meets it. The anonymous budget is untouched by either.
    ///
    /// Mutations: one entry for every generation; anonymous sharing the token's entry.
    @Test func switchingTokensProbesEachOne() async {
        let world = World()
        let reset = world.now.addingTimeInterval(900)
        world.answer = .init(remaining: 0, reset: reset)
        let store = store(world)
        #expect(await admit(store, world, generation: 1) == .refused(.init(until: reset, reason: .exhausted)))

        world.answer = .init(remaining: 4000, reset: reset)
        #expect(await admit(store, world, generation: 2) == .go(canary: true))

        world.answer = .init(remaining: 0, reset: reset)
        #expect(await admit(store, world, generation: 3) == .refused(.init(until: reset, reason: .exhausted)))
        #expect(world.probes == 3)

        world.answer = .init(remaining: 60, reset: reset)
        #expect(await admit(store, world, .anonymous, generation: 0) == .go(canary: true))
    }

    /// A canary that got no answer (offline, cancelled) still releases the
    /// others, and so does one that never reports back, after `canaryPatience`.
    /// A gate must never be what hangs a check.
    ///
    /// Mutations: release only on an answer; no patience timer.
    @Test func anUnansweredCanaryReleasesTheOthers() async {
        let world = World()
        world.answer = .init(remaining: 10, reset: world.now.addingTimeInterval(600))
        let store = store(world, patience: .milliseconds(50))
        #expect(await admit(store, world) == .go(canary: true))
        let waiting = Task { await self.admit(store, world) }
        await store.complete(.token, generation: 1, canary: true, status: nil, headers: [:], body: nil)
        #expect(await waiting.value == .go(canary: false))

        let quiet = self.store(world, patience: .milliseconds(50))
        #expect(await admit(quiet, world) == .go(canary: true))
        let stuck = Task { await self.admit(quiet, world) }
        #expect(await stuck.value == .go(canary: false))
    }

    /// Refusals to requests in flight together are one strike: thirty 403s of
    /// a secondary limit wait one minute, not an hour; a refusal after the wait
    /// is the next strike. A success ends the run.
    ///
    /// Mutations: count every refusal as a strike; strikes never cleared; a
    /// later, shorter answer shortening the wait.
    @Test func aBurstOfRefusalsIsOneStrike() async {
        let world = World()
        world.answer = .init(remaining: 100, reset: world.now.addingTimeInterval(3600))
        let store = store(world)
        _ = await admit(store, world)
        await store.complete(.token, generation: 1, canary: true, status: 200, headers: [:], body: nil)
        let body = Data(#"{"message":"You have exceeded a secondary rate limit."}"#.utf8)
        for _ in 0..<30 {
            await store.complete(.token, generation: 1, canary: false, status: 403, headers: [:], body: body)
        }
        #expect(await store.closure(.token)?.until == world.now.addingTimeInterval(60))

        world.now = world.now.addingTimeInterval(61)
        await store.complete(.token, generation: 1, canary: false, status: 403, headers: [:], body: body)
        #expect(await store.closure(.token)?.until == world.now.addingTimeInterval(120))
        // A shorter answer from a request in flight does not cut the wait short.
        await store.complete(.token, generation: 1, canary: false, status: 403,
                             headers: ["retry-after": "5"], body: nil)
        #expect(await store.closure(.token)?.until == world.now.addingTimeInterval(120))

        world.now = world.now.addingTimeInterval(121)
        await store.complete(.token, generation: 1, canary: false, status: 200, headers: [:], body: nil)
        await store.complete(.token, generation: 1, canary: false, status: 403, headers: [:], body: body)
        #expect(await store.closure(.token)?.until == world.now.addingTimeInterval(60))
    }
}
