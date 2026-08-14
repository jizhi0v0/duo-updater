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
