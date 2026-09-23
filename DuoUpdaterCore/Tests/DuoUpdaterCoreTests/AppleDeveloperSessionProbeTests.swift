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

/// One try per expiry, only on "expired", never while the user is in the
/// sign-in window (PR #816 review, round 1), and never once the user turned
/// background renewal off.
@Test func sessionRenewalIsTriedOnlyOnceOnAnExpiryAndNotDuringSignIn() {
    let t = AppleDeveloperSessionRenewal.shouldTry
    #expect(t(.expired, false, true, true))
    #expect(!t(.expired, true, true, true))
    #expect(!t(.expired, false, false, true))
    #expect(!t(.expired, false, true, false))
    #expect(!t(.signedIn, false, true, true))
    #expect(!t(.inconclusive, false, true, true))
}

/// On until the user turns it off: a Mac that never saw the switch renews.
@Test func sessionRenewalIsOnUntilTurnedOff() throws {
    let suite = "AppleDeveloperSessionRenewalTests"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.removeObject(forKey: AppleDeveloperSessionRenewal.enabledKey)
    #expect(AppleDeveloperSessionRenewal.isEnabled(in: defaults))
    defaults.set(false, forKey: AppleDeveloperSessionRenewal.enabledKey)
    #expect(!AppleDeveloperSessionRenewal.isEnabled(in: defaults))
    defaults.set(true, forKey: AppleDeveloperSessionRenewal.enabledKey)
    #expect(AppleDeveloperSessionRenewal.isEnabled(in: defaults))
}

/// Names only, and a deletion is told apart from a new cookie — the log line
/// that says whether a check refreshes the session must never carry a value.
@Test func sessionProbeLogsTheNamesOfTheCookiesAResponseSets() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let names = AppleDeveloperSessionProbe.setCookieNames(headerFields: [
        "Set-Cookie": "myacinfo=SECRETVALUE; Domain=.apple.com; Path=/; Secure; HttpOnly, "
            + "DSESSIONID=OTHERSECRET; Domain=.developer.apple.com; Path=/, "
            + "ADCDownloadAuth=gone; Domain=.apple.com; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT, "
            + "aa=; Domain=.idmsa.apple.com; Path=/",
        "Location": "https://download.developer.apple.com/Developer_Tools/Xcode_16.4/Xcode_16.4.xip",
    ], now: now)
    #expect(names == ["-ADCDownloadAuth", "-aa", "DSESSIONID", "myacinfo"])
    #expect(!names.joined().contains("SECRET"))
    #expect(AppleDeveloperSessionProbe.setCookieNames(headerFields: ["Location": "x"], now: now).isEmpty)
}

/// `Max-Age=0` parses to the parsing moment floored to the second. With `now`
/// read 0.9 s before the call, only the second of grace marks it: without it,
/// each call passes only when the sub-second part is ≥ 0.9 (PR #828 review,
/// rounds 1–2). A cookie meant to stay is still not marked.
@Test func sessionProbeMarksAMaxAgeZeroDeletion() {
    for _ in 0..<20 {
        let before = Date().addingTimeInterval(-0.9)
        #expect(AppleDeveloperSessionProbe.setCookieNames(headerFields: [
            "Set-Cookie": "myacinfo=x; Max-Age=0; Domain=.apple.com; Path=/",
        ], now: before) == ["-myacinfo"])
    }
    #expect(AppleDeveloperSessionProbe.setCookieNames(headerFields: [
        "Set-Cookie": "myacinfo=x; Max-Age=3600; Domain=.apple.com; Path=/",
    ]) == ["myacinfo"])
}
