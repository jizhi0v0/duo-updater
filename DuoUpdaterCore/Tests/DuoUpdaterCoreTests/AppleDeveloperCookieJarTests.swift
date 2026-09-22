import Foundation
import Testing
@testable import DuoUpdaterCore

@Test func cookieJarRoundTripsSessionOnlyCookie() throws {
    let cookie = try #require(HTTPCookie(properties: [
        .domain: ".apple.com",
        .path: "/",
        .name: "myacinfo",
        .value: "abc123",
        .secure: "TRUE",
    ]))
    #expect(cookie.isSessionOnly)

    let data = AppleDeveloperCookieJar.encode([cookie])
    let decoded = AppleDeveloperCookieJar.decode(data)

    #expect(decoded.count == 1)
    #expect(decoded.first?.name == "myacinfo")
    #expect(decoded.first?.value == "abc123")
    #expect(decoded.first?.isSessionOnly == true)
}

@Test func cookieJarRoundTripsPersistentCookie() throws {
    let future = Date().addingTimeInterval(30 * 24 * 3600)
    let cookie = try #require(HTTPCookie(properties: [
        .domain: ".idmsa.apple.com",
        .path: "/",
        .name: "DESsomehash",
        .value: "trustme",
        .expires: future,
    ]))
    #expect(!cookie.isSessionOnly)

    let decoded = AppleDeveloperCookieJar.decode(AppleDeveloperCookieJar.encode([cookie]))

    #expect(decoded.count == 1)
    #expect(decoded.first?.isSessionOnly == false)
    // Expiry survives the round trip to within a second (plist date precision).
    let restoredExpiry = try #require(decoded.first?.expiresDate)
    #expect(abs(restoredExpiry.timeIntervalSince(future)) < 1)
}

@Test func cookieJarDropsForeignDomains() throws {
    let appleCookie = try #require(HTTPCookie(properties: [
        .domain: ".apple.com", .path: "/", .name: "myacinfo", .value: "1",
    ]))
    let otherCookie = try #require(HTTPCookie(properties: [
        .domain: ".example.com", .path: "/", .name: "session", .value: "2",
    ]))

    let decoded = AppleDeveloperCookieJar.decode(
        AppleDeveloperCookieJar.encode([appleCookie, otherCookie]))

    #expect(decoded.count == 1)
    #expect(decoded.first?.domain == ".apple.com")
}

@Test func cookieJarDecodeIsEmptyForCorruptData() {
    let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02])
    #expect(AppleDeveloperCookieJar.decode(garbage).isEmpty)
    #expect(AppleDeveloperCookieJar.decode(Data()).isEmpty)
}
