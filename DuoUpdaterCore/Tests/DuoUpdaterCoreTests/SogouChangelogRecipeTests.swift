import Testing
import Foundation
@testable import DuoUpdaterCore

/// Sogou's update log (`pinyin.sogou.com/mac/update_log.php`), served GBK.
@Suite struct SogouChangelogRecipeTests {

    /// Seven entries cut out of the real response bytes (served as
    /// `text/html;charset=gbk`) without re-encoding: the two newest pinyin
    /// entries, the touchbar and wubi decoys that share the page, and 6.0.5 /
    /// 6.0.4 / 6.0.3 — the older shape, where an entry has no closing `</p>`
    /// and items are numbered `1.` instead of `1、`.
    static let page = Data(base64Encoded: """
        PHAgY2xhc3M9InBvc3RfbWVzc2FnZSI+CjxzcGFuIGNsYXNzPSJwb3N0X3R5cGUiPsvRubfK5Mjrt6ggZm9yIE1hYyA2LjI1\
        LjE8L3NwYW4+CjxzcGFuIGNsYXNzPSJwb3N0X3RpbWUiPjIwMjYtMDktMTY8L3NwYW4+CjwvcD4KPHAgY2xhc3M9InR5cGVf\
        bWVzIj4KPHNwYW4+uMTJxjwvc3Bhbj48YnI+CjGhotDeuLSyv7fW0tHWqs7KzOIKPGJyPgo8L3A+CgogICAgICAgICAgICAg\
        ICAgICAgICAgICAgICAgPHAgY2xhc3M9InBvc3RfbWVzc2FnZSI+CjxzcGFuIGNsYXNzPSJwb3N0X3R5cGUiPsvRubfK5Mjr\
        t6ggZm9yIE1hYyA2LjI0LjE8L3NwYW4+CjxzcGFuIGNsYXNzPSJwb3N0X3RpbWUiPjIwMjYtMDctMTc8L3NwYW4+CjwvcD4K\
        PHAgY2xhc3M9InR5cGVfbWVzIj4KPHNwYW4+0MLU9jwvc3Bhbj48YnI+CjGhotDC1PbBy9K70KnX7tDCtcQgZW1vammjrMfD\
        x8OhsLTzzbehsaGwu6K+qKGxobC77MLSobG1yLeiz9awyaGrPGJyPgoyoaLTxbuvZW1vamkgw+aw5aOssqLQwtT2ZW1vamkg\
        t/TJq7bg0aG8sLzH0uS5psTcPGJyPgozoaLQwtT2wcvSu9Cpw+aw5dHVzsTX1go8YnI+CjxzcGFuPrjEycY8L3NwYW4+PGJy\
        PgoxoaLTxbuvMjfPtc2zz8LKudPDzOXR6Qo8YnI+CjwvcD4KCgo8cCBjbGFzcz0icG9zdF9tZXNzYWdlIj4KCQk8c3BhbiBj\
        bGFzcz0icG9zdF90eXBlIj7L0bm3yuTI67eoIGZvciBNYWMgdG91Y2hiYXIzLjA8L3NwYW4+CgkJPHNwYW4gY2xhc3M9InBv\
        c3RfdGltZSI+MjAxNy4wMy4wOTwvc3Bhbj4KCTwvcD4KCTxwIGNsYXNzPSJ0eXBlX21lcyI+CgkJPHNwYW4+0MLU9jwvc3Bh\
        bj48YnI+CgkJ1tDOxNOizsTLq72jus/otaOs06LOxMGqz+vSssC0wLI8YnI+CgkJPHNwYW4+0N7V/Twvc3Bhbj48YnI+CgkJ\
        vMzQ+LjE0rvQqcTj1qq1wLvy1d+yu9aqtcC1xM7KzOI8YnI+PGJyPgoJPC9wPgo8L2Rpdj4KPGRpdiBjbGFzcz0idXBsb2df\
        aGlkZSI+Cgk8cCBjbGFzcz0icG9zdF9tZXNzYWdlIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg\
        IDxzcGFuIGNsYXNzPSJwb3N0X3R5cGUiPsvRubfO5bHKyuTI67eoZm9yIE1hYyAxLjQuMDwvc3Bhbj4KICAgICAgICAgICAg\
        ICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJwb3N0X3RpbWUiPjIwMjItMTItMjg8L3NwYW4+CiAg\
        ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvcD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg\
        ICAgPHAgY2xhc3M9InR5cGVfbWVzIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxzcGFuPrjE\
        ycY8L3NwYW4+PGJyLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDGhosrKxeRNMcnosbijrNPF\
        u69NMcnosbi1xMrkyOvM5dHpPGJyLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDKhotPFu6+w\
        stewwfezzKOsveK+9rK/t9bTw7unzt63qLCy17C1xM7KzOI8YnIvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg\
        ICAgICA8L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICAgICAgICAgICAgICAg\
        ICAgICAgICAgPGRpdiBzdHlsZT0ibWFyZ2luLXRvcDo1MHB4Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg\
        ICAgPHAgY2xhc3M9InBvc3RfbWVzc2FnZSI+Cgk8c3BhbiBjbGFzcz0icG9zdF90eXBlIj7L0bm3yuTI67eoIGZvciBNYWMg\
        Ni4wLjU8L3NwYW4+Cgk8c3BhbiBjbGFzcz0icG9zdF90aW1lIj4yMDIxLTA3LTA1PC9zcGFuPgo8L3A+Cgo8cCBjbGFzcz0i\
        dHlwZV9tZXMiPgo8c3Bhbj7Q3tX9PC9zcGFuPjxicj4KMS7Q3ri0sr+31r+ottmhorHAwKO1yNDUxNzOysziPGJyPgoyLtDe\
        uLRNYWNPUzEysr+31sakt/TP1Mq+0uyzo87KzOI8YnI+CjMuuPzQwrOjvPvOysziwdCx7Txicj4KCgo8cCBjbGFzcz0icG9z\
        dF9tZXNzYWdlIj4KCTxzcGFuIGNsYXNzPSJwb3N0X3R5cGUiPsvRubfK5Mjrt6ggZm9yIE1hYyA2LjAuNDwvc3Bhbj4KCTxz\
        cGFuIGNsYXNzPSJwb3N0X3RpbWUiPjIwMjEtMDYtMDQ8L3NwYW4+CjwvcD4KCjxwIGNsYXNzPSJ0eXBlX21lcyI+CjxzcGFu\
        PtDe1f08L3NwYW4+PGJyPgoxLtDeuLSyv7fWv6i22aGiscDAo7XI0NTE3M7KzOI8YnI+CjIu0N64tOSvwMDG97XY1rfAuNfU\
        tq/Tos7EyqfQp87KzOI8YnI+CjMu0N64tLry0aG/8s671sPP1Mq+0uyzo87KzOI8YnI+CjQu0N64tLfJyunW0M7et6jKudPD\
        trfNvM7KzOI8YnI+CjUu0N64tLry0aG/8s/Uyr7Eo7r9zsrM4jxicj4KNi7Q3ri0w9zC67/yyuTI687et6jJz8bBtcTOyszi\
        PGJyPgo3LtDeuLS/qsb00+/S9NTss8nPtc2zv6jLwLXEzsrM4jxicj4KCjxwIGNsYXNzPSJwb3N0X21lc3NhZ2UiPgoJPHNw\
        YW4gY2xhc3M9InBvc3RfdHlwZSI+y9G5t8rkyOu3qCBmb3IgTWFjIDYuMC4zPC9zcGFuPgoJPHNwYW4gY2xhc3M9InBvc3Rf\
        dGltZSI+MjAyMS0wNC0yOTwvc3Bhbj4KPC9wPgoKPHAgY2xhc3M9InR5cGVfbWVzIj4KPHNwYW4+0N7V/Twvc3Bhbj48YnI+\
        CjEu0N64tLK/t9a/qLbZoaKxwMCjtcjQ1MTczsrM4jxicj4KMi7Q3ri0sr+31rzmyN3Q1M7KzOI8YnI+CjMu0N64tNTaxLPQ\
        qdOm08PW0KOs1tDTos7Ez9TKvte0zKy6zcrkyOvXtMyssru21NOmtcTOysziPGJyPgo0LtDeuLTK1ravyf28tsqnsNy1xM7K\
        zOI8YnI+CjUu0N64tMXk1sPP7s2ssr3Kp7DctcTOysziPGJyPgo2LtDeuLTO3reoyejWw7ry0aG/8tfWzOW089ChtcTOyszi\
        PGJyPgoKPC9wPgo=
        """)!

    private final class SogouPageProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html;charset=gbk"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: SogouChangelogRecipeTests.page)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    /// Through the fetch, so the bytes reach the recipe the way the app gets
    /// them: decoded by the `charset=gbk` the server declares.
    private func load() async throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.sogou.inputmethod.sogou"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SogouPageProtocol.self]
        return try #require(await ChangelogService.loadUncached(
            recipe, feedPage: nil, session: URLSession(configuration: configuration)))
    }

    @Test func readsOnlyThePinyinEntries() async throws {
        let changelog = try await load()
        #expect(changelog.entries.map(\.version) == ["6.25.1", "6.24.1", "6.0.5", "6.0.4", "6.0.3"])
    }

    @Test func readsTheNewestEntry() async throws {
        let newest = try #require(try await load().entries.first)
        #expect(newest.version == "6.25.1")
        #expect(newest.date == "2026-09-16")
        #expect(newest.items == ["修复部分已知问题"])
        let previous = try #require(try await load().entries.dropFirst().first)
        #expect(previous.items.count == 4)
        #expect(previous.items.first == "新增了一些最新的 emoji，敲敲“大头”“虎鲸”“混乱”等发现吧～")
    }

    /// 6.0.5 has no `</p>`: without the stop at the next entry its body would
    /// run on into 6.0.4, and 6.0.4 would vanish.
    @Test func anEntryWithoutAClosingParagraphDoesNotSwallowTheNext() async throws {
        let entries = try await load().entries
        let v605 = try #require(entries.first { $0.version == "6.0.5" })
        #expect(v605.date == "2021-07-05")
        #expect(v605.items == ["修复部分卡顿、崩溃等性能问题", "修复MacOS12部分皮肤显示异常问题", "更新常见问题列表"])
        let v604 = try #require(entries.first { $0.version == "6.0.4" })
        #expect(v604.items.count == 7)
    }

    /// The accepted mismatch: the page says x.y.z, the build is x.y.z.build.
    @Test func thePageNeverCarriesTheFourPartBuild() async throws {
        let changelog = try await load()
        #expect(!changelog.carries(version: "6.25.1.11973"))
        #expect(changelog.carries(version: "6.25.1"))
    }
}
