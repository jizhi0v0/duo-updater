import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ChangelogService` reads a page in the charset its `Content-Type` declares,
/// and in exactly the old lossy UTF-8 otherwise.
@Suite struct ChangelogCharsetTests {

    /// The first two entries of `pinyin.sogou.com/mac/update_log.php`, cut out of
    /// the real response bytes (served as `text/html;charset=gbk`) without
    /// re-encoding. 611 bytes, 186 of them non-ASCII, and not valid UTF-8.
    static let sogouGBK = Data(base64Encoded: """
        PHAgY2xhc3M9InBvc3RfbWVzc2FnZSI+CjxzcGFuIGNsYXNzPSJwb3N0X3R5cGUiPsvRubfK5Mjrt6ggZm9yIE1hYyA2LjI1\
        LjE8L3NwYW4+CjxzcGFuIGNsYXNzPSJwb3N0X3RpbWUiPjIwMjYtMDktMTY8L3NwYW4+CjwvcD4KPHAgY2xhc3M9InR5cGVf\
        bWVzIj4KPHNwYW4+uMTJxjwvc3Bhbj48YnI+CjGhotDeuLSyv7fW0tHWqs7KzOIKPGJyPgo8L3A+CgogICAgICAgICAgICAg\
        ICAgICAgICAgICAgICAgPHAgY2xhc3M9InBvc3RfbWVzc2FnZSI+CjxzcGFuIGNsYXNzPSJwb3N0X3R5cGUiPsvRubfK5Mjr\
        t6ggZm9yIE1hYyA2LjI0LjE8L3NwYW4+CjxzcGFuIGNsYXNzPSJwb3N0X3RpbWUiPjIwMjYtMDctMTc8L3NwYW4+CjwvcD4K\
        PHAgY2xhc3M9InR5cGVfbWVzIj4KPHNwYW4+0MLU9jwvc3Bhbj48YnI+CjGhotDC1PbBy9K70KnX7tDCtcQgZW1vammjrMfD\
        x8OhsLTzzbehsaGwu6K+qKGxobC77MLSobG1yLeiz9awyaGrPGJyPgoyoaLTxbuvZW1vamkgw+aw5aOssqLQwtT2ZW1vamkg\
        t/TJq7bg0aG8sLzH0uS5psTcPGJyPgozoaLQwtT2wcvSu9Cpw+aw5dHVzsTX1go8YnI+CjxzcGFuPrjEycY8L3NwYW4+PGJy\
        PgoxoaLTxbuvMjfPtc2zz8LKudPDzOXR6Qo8YnI+CjwvcD4=
        """)!

    @Test func aDeclaredGBKBodyDecodesAsChinese() {
        let text = ChangelogService.decodeBody(Self.sogouGBK, declaredCharset: "gbk")
        #expect(text.contains(#"<span class="post_type">搜狗输入法 for Mac 6.25.1</span>"#))
        #expect(text.contains("1、修复部分已知问题"))
        #expect(text.contains("敲敲“大头”“虎鲸”“混乱”等发现吧～"))
        #expect(!text.contains("\u{FFFD}"))
    }

    /// GB18030 is a superset of GBK and GB2312, so it is what every GB label
    /// reads as. `喆` (0x86 0xB4) is GBK but not GB2312: a page that says
    /// `gb2312` and uses it still decodes.
    @Test func everyGBLabelReadsAsGB18030() {
        let zhe = Data([0x86, 0xB4])
        for label in ["gbk", "GBK", "gb2312", "GB2312", "gb18030", "GB18030"] {
            #expect(ChangelogService.decodeBody(zhe, declaredCharset: label) == "喆", "\(label)")
        }
    }

    /// Undeclared: the lossy UTF-8 decode, unchanged — a GBK page with no
    /// charset is not sniffed.
    @Test func anUndeclaredBodyIsTheOldUTF8Decode() {
        for body in [Self.sogouGBK, Data("Café — ✓".utf8)] {
            let old = String(decoding: body, as: UTF8.self)
            #expect(ChangelogService.decodeBody(body, declaredCharset: nil) == old)
            #expect(ChangelogService.decodeBody(body, declaredCharset: "") == old)
        }
    }

    /// Declared UTF-8, in any spelling, is the old decode too — including its
    /// lossy handling of a stray invalid byte, which `String(data:encoding:)`
    /// would turn into nil instead.
    @Test func aDeclaredUTF8BodyIsTheOldUTF8Decode() {
        var body = Data("<li>Café — ✓</li>".utf8)
        body.append(0xFF)
        let old = String(decoding: body, as: UTF8.self)
        for label in ["utf-8", "UTF-8", "utf8"] {
            #expect(ChangelogService.decodeBody(body, declaredCharset: label) == old, "\(label)")
        }
    }

    /// A charset Foundation can't name falls back to UTF-8 rather than to nil.
    @Test func anUnknownCharsetFallsBackToUTF8() {
        let body = Data("<li>ok ✓</li>".utf8)
        #expect(ChangelogService.decodeBody(body, declaredCharset: "x-no-such-charset")
            == String(decoding: body, as: UTF8.self))
    }

    // MARK: through the fetch

    private final class GBKPageProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html;charset=gbk"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: ChangelogCharsetTests.sogouGBK)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    /// The header reaches the decode: a pattern anchored on Chinese text only
    /// matches when the fetch honoured `charset=gbk`.
    @Test func theFetchHonoursTheContentTypeCharset() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GBKPageProtocol.self]
        let recipe = ChangelogRecipe(
            bundleID: "test.changelog-charset.gbk",
            source: URL(string: "https://charset.invalid/update_log.php")!,
            entryPattern: #"<span class="post_type">搜狗输入法 for Mac (?<version>\d+(?:\.\d+)+)</span>\s*"#
                + #"<span class="post_time">(?<date>[^<]*)</span>.*?<p class="type_mes">(?<body>.*?)</p>"#,
            itemPatterns: [#"\d+、(?<item>[^<\n]+)"#])
        let changelog = try #require(await ChangelogService.loadUncached(
            recipe, feedPage: nil, session: URLSession(configuration: configuration)))
        #expect(changelog.entries.map(\.version) == ["6.25.1", "6.24.1"])
        #expect(changelog.entries.first?.date == "2026-09-16")
        #expect(changelog.entries.first?.items == ["修复部分已知问题"])
        #expect(changelog.entries.last?.items.last == "优化27系统下使用体验")
    }
}
