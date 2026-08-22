import Testing
import Foundation
@testable import DuoUpdaterCore

/// `URLCache` keys entries on the full request URL, so any feed carrying a secret
/// in its query would otherwise leave that secret in plaintext in `Cache.db`.
/// `CredentialBearingURL` is the predicate that keeps those responses out of the
/// cache; these tests pin both directions, because a predicate that over-matches
/// silently disables caching for ordinary feeds.
@Suite struct CredentialCachingTests {

    /// The real shape this exists for: CleanShot's personalised appcast puts the
    /// activation key in the query of an otherwise ordinary Sparkle feed URL.
    @Test func cleanShotLicensedFeedIsNotCacheable() {
        let url = URL(string:
            "https://legit.maketheweb.io/api/v1/appcast?key=ABCD-1234-EFGH-5678")!
        #expect(CredentialBearingURL.inQuery(url))
    }

    @Test(arguments: [
        "https://example.com/f?token=abc",
        "https://example.com/f?access_token=abc",
        "https://example.com/f?api_key=abc",
        "https://example.com/f?API_KEY=abc",          // name match is case-insensitive
        "https://example.com/f?license=abc",
        "https://example.com/f?licence=abc",
        "https://example.com/f?sig=abc",
        "https://example.com/f?access-token=abc",
        "https://example.com/f?v=1&key=abc",          // not only the first item
        // Variants a review flagged as missed by the first cut: no separator at all,
        // camelCase, and words that only appear as a compound.
        "https://example.com/f?apikey=abc",
        "https://example.com/f?apiKey=abc",
        "https://example.com/f?accessToken=abc",
        "https://example.com/f?clientSecret=abc",
        "https://example.com/f?credential=abc",
        "https://example.com/f?pwd=abc",
        "https://example.com/f?sessionId=abc",
        "https://example.com/f?activation_key=abc",
        "https://example.com/f?x-api-key=abc",
    ])
    func credentialNamesAreCaught(_ raw: String) {
        #expect(CredentialBearingURL.inQuery(URL(string: raw)!))
    }

    /// The other half: these are the version feeds the disk cache exists to serve.
    /// Matching a bare substring would break every one of them.
    @Test(arguments: [
        "https://formulae.brew.sh/api/cask.json",
        "https://api.github.com/repos/o/r/releases/latest",
        "https://example.com/appcast.xml?channel=beta",
        "https://example.com/f?monkey=1",             // contains "key"
        "https://example.com/f?design=1",             // contains "sig"
        "https://example.com/f?keyboard=1",
        "https://example.com/f?turnkey=1",
        "https://example.com/f?signal=1",
        "https://example.com/f?authority=1",
    ])
    func ordinaryFeedsStayCacheable(_ raw: String) {
        #expect(!CredentialBearingURL.inQuery(URL(string: raw)!))
    }

    @Test func noQueryAndNilAreCacheable() {
        #expect(!CredentialBearingURL.inQuery(URL(string: "https://example.com/f")!))
        #expect(!CredentialBearingURL.inQuery(nil))
    }
}

/// The query check above was, for a long time, the *whole* test — on the reading
/// that a header credential never enters the cache *key* and so never reaches disk.
/// The key, no; the archived request, yes: CFNetwork writes the whole `URLRequest`
/// into `cfurl_cache_blob_data`, headers and body included, and 85 blobs across the
/// app's and the CLI's caches were found holding a live GitHub PAT in plaintext.
/// These pin the two hiding places that discovery added.
@Suite struct CredentialCachingRequestTests {

    private func request(
        _ url: String = "https://api.github.com/repos/o/r/releases/latest"
    ) -> URLRequest {
        URLRequest(url: URL(string: url)!)
    }

    /// The exact shape that leaked: `GitHubReleasesSource` setting a PAT as Bearer.
    @Test func bearerTokenIsNotCacheable() {
        var r = request()
        r.setValue("Bearer ghp_notARealToken", forHTTPHeaderField: "Authorization")
        #expect(CredentialBearingRequest.isCredentialed(r))
    }

    @Test(arguments: ["Authorization", "Proxy-Authorization"])
    func credentialHeadersAreNotCacheable(_ field: String) {
        var r = request()
        r.setValue("Basic dXNlcjpwYXNz", forHTTPHeaderField: field)
        #expect(CredentialBearingRequest.isCredentialed(r))
    }

    /// Header lookup is case-insensitive in `URLRequest`, so a source spelling the
    /// field differently is still caught — worth pinning, since the check names one
    /// exact spelling.
    @Test func headerMatchIsCaseInsensitive() {
        var r = request()
        r.setValue("Bearer x", forHTTPHeaderField: "authorization")
        #expect(CredentialBearingRequest.isCredentialed(r))
    }

    /// `AlcoveUpdateSource.issueToken` POSTs the licence key as JSON; that blob was
    /// in the cache too, and no header or query check would have seen it.
    @Test func requestBodyIsNotCacheable() {
        var r = request("https://api.tryalcove.com/issue-token")
        r.httpMethod = "POST"
        r.httpBody = Data(#"{"license_key":"X","instance_id":"Y"}"#.utf8)
        #expect(CredentialBearingRequest.isCredentialed(r))
    }

    /// The other half, as above: an ordinary unauthenticated feed must stay
    /// cacheable, or the disk cache quietly stops doing its job.
    @Test func plainFeedStaysCacheable() {
        var r = request("https://formulae.brew.sh/api/cask.json")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        #expect(!CredentialBearingRequest.isCredentialed(r))
    }

    /// A cross-host redirect makes `willPerformHTTPRedirection` strip the header, so
    /// by the time the response arrives the *current* request looks innocent while
    /// the original was credentialed. Either one being dirty must veto the cache.
    @Test func credentialOnEitherRequestVetoesCaching() {
        var original = request()
        original.setValue("Bearer ghp_notARealToken", forHTTPHeaderField: "Authorization")
        let stripped = request("https://objects.githubusercontent.com/x")

        #expect(CredentialBearingRequest.isCredentialed(original: original, current: stripped))
        #expect(CredentialBearingRequest.isCredentialed(original: stripped, current: original))
        #expect(!CredentialBearingRequest.isCredentialed(original: stripped, current: stripped))
        #expect(!CredentialBearingRequest.isCredentialed(original: nil, current: nil))
    }
}
