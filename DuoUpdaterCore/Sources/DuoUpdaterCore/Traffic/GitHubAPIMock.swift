import Foundation

/// A developer's way to put a local stand-in where `api.github.com` is: with
/// `DUO_GITHUB_API_MOCK=http://127.0.0.1:<port>` in the environment, every
/// request to the API goes there instead — the rate-limit gate's states, the
/// rows and banners they drive, all exercised against scripted answers, with
/// no real budget spent and nothing between this Mac and GitHub touched
/// (`scripts/github_api_mock.py` is that stand-in).
///
/// **Not in a release.** Compiled only under `DUO_DEV_HOOKS`, which
/// `scripts/install.sh` and `scripts/build-cli.sh` set and the release build
/// (`scripts/notarize.sh`) does not; `scripts/check-no-dev-hooks.sh` fails a
/// release whose binaries still carry it. In any other build `redirect` hands
/// the request back unchanged.
///
/// **Only this Mac.** The address must be a loopback one, and the redirected
/// request goes without its `Authorization` header — the stand-in learns
/// whether one was sent from `X-Duo-Credential` instead — so no setting of the
/// variable can send a token anywhere.
///
/// Applied where the request is sent (`recordedData`, `countedBytes`,
/// `GitHubAnonymousBudget`), after the gate has admitted it: the gate sees the
/// request as it was, `api.github.com` and its credential.
public enum GitHubAPIMock {
    #if DUO_DEV_HOOKS
    /// The stand-in's base URL, when the environment names a loopback one.
    public static let base: URL? = {
        let base = mockBase(ProcessInfo.processInfo.environment["DUO_GITHUB_API_MOCK"])
        if let base {
            Log.app.notice("GitHub API requests go to the stand-in at \(base.absoluteString, privacy: .public) (DUO_GITHUB_API_MOCK)")
        }
        return base
    }()
    #else
    public static let base: URL? = nil
    #endif

    /// `value` as a stand-in base: http(s) on a loopback host, or nil.
    static func mockBase(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), ["127.0.0.1", "localhost", "::1"].contains(host)
        else { return nil }
        return url
    }

    /// `request`, sent to `base` instead when it is for the API.
    public static func redirect(_ request: URLRequest) -> URLRequest {
        redirect(request, to: base)
    }

    static func redirect(_ request: URLRequest, to base: URL?) -> URLRequest {
        guard let base, let url = request.url, ChangelogService.isGitHubAPI(url),
              var target = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let source = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return request }
        target.percentEncodedPath = source.percentEncodedPath
        target.percentEncodedQuery = source.percentEncodedQuery
        guard let redirected = target.url else { return request }
        var out = request
        out.url = redirected
        let credential = request.value(forHTTPHeaderField: "Authorization") == nil ? "anonymous" : "token"
        out.setValue(nil, forHTTPHeaderField: "Authorization")
        out.setValue(credential, forHTTPHeaderField: "X-Duo-Credential")
        return out
    }
}
