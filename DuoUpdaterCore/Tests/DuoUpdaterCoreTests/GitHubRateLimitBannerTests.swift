import Testing
import Foundation
@testable import DuoUpdaterCore

/// `GitHubRateLimitBanner`: which budget the popover's rate-limit banner names,
/// how long it says the wait is, and that it still offers a token when none is
/// configured. Each case names the mutation it fails under.
struct GitHubRateLimitBannerTests {

    let tokenUntil = Date(timeIntervalSince1970: 1_800_000_000)
    let anonymousUntil = Date(timeIntervalSince1970: 1_800_000_600)

    func detail(
        _ spent: GitHubRateLimitBanner.Spent, until: Date? = nil,
        cause: GitHubRateLimitBanner.Cause = .exhausted,
        hasToken: Bool = true, count: Int = 60
    ) -> String {
        GitHubRateLimitBanner.detail(
            count: count, spent: spent, until: until, cause: cause, hasToken: hasToken,
            time: { _ in "11:31" })
    }

    /// A secondary limit refuses with the budget still having room. Said as a
    /// spent budget it would contradict the budget card and send the reader
    /// looking for quota that is not gone.
    ///
    /// Mutation: word every closure as a spent budget.
    @Test func aSecondaryThrottleIsNotASpentBudget() {
        for spent in [GitHubRateLimitBanner.Spent.token, .anonymous, .both] {
            let line = detail(spent, until: tokenUntil, cause: .throttled)
            #expect(line.contains("throttling requests"), "\(spent)")
            #expect(!line.contains("budget is spent"), "\(spent)")
        }
        #expect(detail(.anonymous, until: anonymousUntil, cause: .throttled, hasToken: false)
            .contains("throttling"))
    }

    /// The two budgets are said apart. Measured 2026-11-04: the banner said
    /// "when GitHub takes requests again" when the anonymous budget was the
    /// spent one and the token had 4,853 left.
    ///
    /// Mutations: one sentence for every spent budget; the anonymous case
    /// falling back to the token's.
    @Test func theSpentBudgetIsNamed() {
        #expect(detail(.token, until: tokenUntil).contains("your token’s budget is spent"))
        #expect(detail(.anonymous, until: anonymousUntil).contains("anonymous budget is spent"))
        #expect(detail(.both, until: anonymousUntil).contains("both GitHub budgets are spent"))
        #expect(!detail(.anonymous, until: anonymousUntil).contains("token’s budget"))
    }

    /// Both: the wait is the later of the two windows, since that is when
    /// everything answers again.
    ///
    /// Mutation: the first window, or the token's alone.
    @Test func theWaitIsTheLaterWindow() {
        #expect(GitHubRateLimitBanner.until(token: tokenUntil, anonymous: anonymousUntil) == anonymousUntil)
        #expect(GitHubRateLimitBanner.until(token: anonymousUntil, anonymous: tokenUntil) == anonymousUntil)
        #expect(GitHubRateLimitBanner.until(token: nil, anonymous: anonymousUntil) == anonymousUntil)
        #expect(GitHubRateLimitBanner.until(token: nil, anonymous: nil) == nil)
    }

    @Test func theSpentBudgetsAreCounted() {
        #expect(GitHubRateLimitBanner.spent(token: nil, anonymous: nil) == .none)
        #expect(GitHubRateLimitBanner.spent(token: tokenUntil, anonymous: nil) == .token)
        #expect(GitHubRateLimitBanner.spent(token: nil, anonymous: anonymousUntil) == .anonymous)
        #expect(GitHubRateLimitBanner.spent(token: tokenUntil, anonymous: anonymousUntil) == .both)
    }

    /// No token: the anonymous budget is the one in play, so "or add a token"
    /// stays — that is the fix for the rows it stopped.
    ///
    /// Mutation: the token-less case not offering a token.
    @Test func noTokenStillOffersOne() {
        let line = detail(.anonymous, until: anonymousUntil, hasToken: false)
        #expect(line.contains("wait until 11:31"))
        #expect(line.contains("or add a token"))
    }

    /// No closure at all (a burst of 403s that closed nothing): the nudge to add
    /// a token, as before — nothing says "wait until" about a time nobody knows.
    ///
    /// Mutation: inventing a wait for a `.none` state.
    @Test func noClosureOffersAToken() {
        let line = detail(.none, hasToken: false)
        #expect(line.contains("couldn’t be checked"))
        #expect(line.contains("add a token"))
        #expect(!line.contains("wait until"))
    }
}
