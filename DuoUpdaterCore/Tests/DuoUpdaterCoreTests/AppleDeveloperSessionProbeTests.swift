import Foundation
import Testing
@testable import DuoUpdaterCore

@Test func sessionProbeRedirectToTheCDNIsSignedIn() {
    #expect(AppleDeveloperSessionProbe.verdict(
        status: 302,
        location: "https://download.developer.apple.com/Developer_Tools/Xcode_16.4/Xcode_16.4.xip")
        == .signedIn)
}

@Test func sessionProbeRedirectToSignInIsExpired() {
    #expect(AppleDeveloperSessionProbe.verdict(
        status: 302,
        location: "https://idmsa.apple.com/IDMSWebAuth/signin?appIdKey=abc&path=%2Fservices-account%2Fdownload")
        == .expired)
}

/// A proxy's block page, an outage, or a host nobody measured must not flip the
/// row to "expired" — the user would be told to sign in when nothing is wrong.
@Test func sessionProbeSaysNothingAboutAnythingElse() {
    let v = AppleDeveloperSessionProbe.verdict
    #expect(v(200, nil) == .inconclusive)
    #expect(v(200, "https://idmsa.apple.com/IDMSWebAuth/signin") == .inconclusive)
    #expect(v(403, nil) == .inconclusive)
    #expect(v(302, nil) == .inconclusive)
    #expect(v(302, "https://developer.apple.com/unauthorized/") == .inconclusive)
    #expect(v(302, "https://idmsa.apple.com.example.net/signin") == .inconclusive)
    #expect(v(302, "https://xidmsa.apple.com/signin") == .inconclusive)
    #expect(v(302, "https://xdownload.developer.apple.com/x.xip") == .inconclusive)
    #expect(v(302, "https://download.developer.apple.com.example.net/x.xip") == .inconclusive)
    #expect(v(302, "/relative/path") == .inconclusive)
}

@Test func sessionProbeURLIsTheAuthorizedEndpoint() {
    let url = AppleDeveloperSessionProbe.probeURL
    #expect(url.host == "developer.apple.com")
    #expect(url.path == "/services-account/download")
    #expect(XcodeReleasesSource.authorizedDownloadURL(
        fromCDN: "https://download.developer.apple.com/Developer_Tools/Xcode_16.4/Xcode_16.4.xip") == url)
}

/// The hidden renewal ends signed in only back on the developer site; the
/// sign-in form it passes through, or stays on, is not an arrival.
@Test func sessionRenewalLandsOnlyOnTheDeveloperSite() {
    let landed = AppleDeveloperSessionRenewal.hasLanded
    #expect(landed("developer.apple.com"))
    #expect(landed("Developer.Apple.com"))
    #expect(!landed("idmsa.apple.com"))
    #expect(!landed(nil))
    #expect(!landed("www.apple.com"))
    #expect(!landed("xdeveloper.apple.com"))
    #expect(!landed("developer.apple.com.example.net"))
}

/// One try per expiry, only on "expired", and never while the user is in the
/// sign-in window (PR #816 review, round 1).
@Test func sessionRenewalIsTriedOnlyOnceOnAnExpiryAndNotDuringSignIn() {
    let t = AppleDeveloperSessionRenewal.shouldTry
    #expect(t(.expired, false, true))
    #expect(!t(.expired, true, true))
    #expect(!t(.expired, false, false))
    #expect(!t(.signedIn, false, true))
    #expect(!t(.inconclusive, false, true))
}
