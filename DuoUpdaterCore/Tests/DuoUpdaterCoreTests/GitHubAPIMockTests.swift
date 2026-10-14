import Foundation
import Testing
@testable import DuoUpdaterCore

/// `GitHubAPIMock`'s rules, which hold in every build: only a loopback stand-in,
/// only API requests, and never the token. (Whether the environment is read
/// at all is the `DUO_DEV_HOOKS` build's question; `check-no-dev-hooks.sh`
/// answers it for a release.) Each case names the mutation it fails under.
struct GitHubAPIMockTests {

    /// Only a loopback address over http(s) is a stand-in.
    ///
    /// Mutation: drop the host check.
    @Test func onlyALoopbackStandIn() {
        #expect(GitHubAPIMock.mockBase("http://127.0.0.1:18765") != nil)
        #expect(GitHubAPIMock.mockBase("http://localhost:18765") != nil)
        #expect(GitHubAPIMock.mockBase("https://example.com") == nil)
        #expect(GitHubAPIMock.mockBase("http://192.168.1.2:8765") == nil)
        #expect(GitHubAPIMock.mockBase("ftp://127.0.0.1") == nil)
        #expect(GitHubAPIMock.mockBase(nil) == nil)
    }

    /// An API request goes to the stand-in with its path and query, without
    /// its token, and says which credential it carried.
    ///
    /// Mutations: keep `Authorization`; drop the query; mark every request anonymous.
    @Test func anAPIRequestGoesToTheStandInWithoutItsToken() {
        let base = URL(string: "http://127.0.0.1:18765")!
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/o/r/releases?per_page=2")!)
        request.setValue("Bearer placeholder", forHTTPHeaderField: "Authorization")
        let out = GitHubAPIMock.redirect(request, to: base)
        #expect(out.url?.absoluteString == "http://127.0.0.1:18765/repos/o/r/releases?per_page=2")
        #expect(out.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(out.value(forHTTPHeaderField: "X-Duo-Credential") == "token")

        let anonymous = GitHubAPIMock.redirect(
            URLRequest(url: URL(string: "https://api.github.com/rate_limit")!), to: base)
        #expect(anonymous.value(forHTTPHeaderField: "X-Duo-Credential") == "anonymous")
    }

    /// Anything not for the API, and anything at all with no stand-in, is
    /// left as it was.
    ///
    /// Mutation: redirect every host.
    @Test func everythingElseIsLeftAlone() {
        let base = URL(string: "http://127.0.0.1:18765")!
        let raw = URLRequest(url: URL(string: "https://raw.githubusercontent.com/o/r/main/x")!)
        #expect(GitHubAPIMock.redirect(raw, to: base) == raw)
        let api = URLRequest(url: URL(string: "https://api.github.com/rate_limit")!)
        #expect(GitHubAPIMock.redirect(api, to: nil) == api)
    }
}
