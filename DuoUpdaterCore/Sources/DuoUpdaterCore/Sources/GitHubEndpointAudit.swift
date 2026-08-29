import Foundation

/// What the GitHub endpoint actually answered, as opposed to what we asked it.
///
/// Exists because of a failure that every other check in this codebase is blind
/// to. When a repo is renamed, `api.github.com/repos/<old>/…` answers 301 to
/// `/repositories/<id>/…`, URLSession follows it, and the release data comes back
/// correct — so detection works, `duo verify` reports ✓, and
/// `GitHubReleaseRuleTests.batchRuleSlugsArePinned` stays green because it
/// compares our slug against our own pinned copy of it. Three rules
/// (`block/goose`, `containers/podman-desktop`, `headlamp-k8s/headlamp`) drifted
/// that way with nothing noticing.
///
/// The cost is not cosmetic: **URLSession drops `Authorization` while following
/// that redirect.** Measured 2026-08-29 on the same session, same request, the
/// only difference being whether a redirect was involved:
///
///     …/repos/aaif-goose/goose/releases/latest   → x-ratelimit-limit: 5000
///     …/repos/block/goose/releases/latest        → x-ratelimit-limit: 60
///
/// 60 is the anonymous ceiling. Those rules were checking on the shared
/// per-IP budget no matter what token the user had configured, and nothing said
/// so. See issue #135.
///
/// Nothing in the app sets this — the task-local is nil there, so the shipping
/// check path pays one optional read per request and records nothing. It is the
/// verification sweep that opts in.
public enum GitHubEndpointAudit {

    /// One request's worth of "what came back", recorded where the
    /// `HTTPURLResponse` is still in hand.
    public struct Observation: Sendable, Equatable {
        /// The `owner/repo` the rule asked for.
        public let requestedSlug: String
        /// The repo's real `owner/repo`, when the answer let us name it — read
        /// out of the release's own `html_url`, which GitHub writes with the
        /// canonical name. Nil whenever no release came back to name it, which
        /// includes every non-2xx response; `redirected` and
        /// ``redirectedButUnnamed`` are what still speak in that case.
        public let canonicalSlug: String?
        /// True when the response's final URL is not the one we requested.
        public let redirected: Bool
        /// `x-ratelimit-limit` off the response that actually carried the data.
        /// 60 is GitHub's anonymous ceiling, 5000 the authenticated one.
        public let rateLimitCeiling: Int?
        /// Whether this request went out carrying an `Authorization` header.
        /// Without it, a ceiling of 60 is simply the truth rather than a fault.
        public let sentToken: Bool

        /// Public so the sweep's own tests can state a shape without going
        /// through a live response; nothing in production builds one by hand.
        public init(
            requestedSlug: String, canonicalSlug: String?, redirected: Bool,
            rateLimitCeiling: Int?, sentToken: Bool
        ) {
            self.requestedSlug = requestedSlug
            self.canonicalSlug = canonicalSlug
            self.redirected = redirected
            self.rateLimitCeiling = rateLimitCeiling
            self.sentToken = sentToken
        }

        /// The slug drifted and we can name what it should be.
        public var staleSlug: String? {
            guard let canonicalSlug, canonicalSlug.lowercased() != requestedSlug.lowercased()
            else { return nil }
            return canonicalSlug
        }

        /// GitHub sent us somewhere else and we could not name where. Worth
        /// reporting on its own: with no release in the answer there is nothing
        /// to read `html_url` from, and on a 403 there is no body at all — but
        /// the redirect still happened and still cost the request its token.
        /// Without this, the case with the least information available would be
        /// the case the sweep says nothing about.
        public var redirectedButUnnamed: Bool {
            redirected && staleSlug == nil
        }

        /// We authenticated and were answered on the anonymous budget anyway.
        /// Deliberately requires `sentToken`: for a user with no token every
        /// response says 60, and warning about that would be noise on all 69
        /// rules rather than a signal on the broken ones.
        public var authSilentlyDropped: Bool {
            sentToken && rateLimitCeiling == 60
        }
    }

    /// A sweep unit's observations. A class so they survive the `withValue`
    /// scope; locked because one rule can issue two requests (`/releases/latest`
    /// then the list fallback).
    public final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Observation] = []

        public init() {}

        public var observations: [Observation] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }

        func record(_ observation: Observation) {
            lock.lock(); storage.append(observation); lock.unlock()
        }
    }

    /// Set by a caller that wants the observations; nil everywhere else, which is
    /// why the app pays nothing for this.
    @TaskLocal public static var ledger: Ledger?

    /// `https://github.com/aaif-goose/goose/releases/tag/v1.48.0` -> `aaif-goose/goose`.
    /// Nil for anything that isn't a github.com URL with at least two path
    /// components, so a vendor-hosted `html_url` can never be mistaken for a slug.
    ///
    /// The host test is an exact match or a real subdomain, deliberately NOT
    /// `hasSuffix("github.com")`: that also accepts `mygithub.com` and
    /// `evil-github.com`, and GitHub Enterprise instances on custom domains are
    /// routinely named that way. A false slug here is worse than none — it makes
    /// the sweep tell a maintainer to repoint a rule at a repo that does not exist.
    static func slug(fromHTMLURL url: URL?) -> String? {
        guard let url, let host = url.host,
              host == "github.com" || host.hasSuffix(".github.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    /// Record one response. No-op when no ledger is installed.
    static func record(
        requestedSlug: String, requestedURL: URL, response: HTTPURLResponse,
        firstReleaseHTMLURL: URL?, sentToken: Bool
    ) {
        guard let ledger else { return }
        let ceiling = (response.value(forHTTPHeaderField: "x-ratelimit-limit"))
            .flatMap(Int.init)
        ledger.record(Observation(
            requestedSlug: requestedSlug,
            canonicalSlug: slug(fromHTMLURL: firstReleaseHTMLURL),
            // Compare the final URL to the one we asked for. A rename lands on
            // `/repositories/<id>/…`, which never equals the `/repos/<slug>/…` we
            // built, so this is true exactly when GitHub redirected us.
            redirected: response.url.map { $0 != requestedURL } ?? false,
            rateLimitCeiling: ceiling,
            sentToken: sentToken))
    }
}
