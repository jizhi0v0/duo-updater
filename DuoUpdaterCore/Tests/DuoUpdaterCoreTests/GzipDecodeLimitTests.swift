import Testing
import Foundation
@testable import DuoUpdaterCore

/// `GzipDecode` inflates bytes a vendor (or whoever answers for one) sent, and
/// DEFLATE turns a few hundred kilobytes of zeros into hundreds of megabytes. The
/// caller states how much it can expect; anything past that is refused.
///
/// The bombs are built here, small input and large output: 32 MiB of zeros
/// deflates to roughly 32 KB, which is the same ratio as the 261 KB -> 256 MiB
/// measured in the review.
@Suite struct GzipDecodeLimitTests {

    private static let MiB = 1024 * 1024

    /// Raw DEFLATE of `count` zero bytes. `COMPRESSION_ZLIB` is RFC 1951 data
    /// with no wrapper, which is what `.zlib` produces here.
    private static func deflateZeros(_ count: Int) throws -> Data {
        try (Data(count: count) as NSData).compressed(using: .zlib) as Data
    }

    private static func gzip(_ payload: Data) throws -> Data {
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(try (payload as NSData).compressed(using: .zlib) as Data)
        out.append(contentsOf: [0, 0, 0, 0])                                  // CRC32, unchecked
        out.append(contentsOf: withUnsafeBytes(
            of: UInt32(truncatingIfNeeded: payload.count).littleEndian, Array.init))
        return out
    }

    private static func gzip(zeros count: Int) throws -> Data { try gzip(Data(count: count)) }

    private static func zlib(zeros count: Int) throws -> Data {
        var out = Data([0x78, 0x9C])
        out.append(try deflateZeros(count))
        out.append(contentsOf: [0, 0, 0, 0])                                  // adler32, unchecked
        return out
    }

    // MARK: - gzip

    @Test func aGzipBombIsRefusedAtTheLimit() throws {
        let bomb = try Self.gzip(zeros: 32 * Self.MiB)
        #expect(bomb.count < 200 * 1024, "the fixture must stay a small input: \(bomb.count) bytes")
        #expect(GzipDecode.decompress(bomb, limit: 1 * Self.MiB) == nil)
    }

    @Test func aGzipWithinTheLimitIsUnchanged() throws {
        let member = try Self.gzip(zeros: 512 * 1024)
        let out = try #require(GzipDecode.decompress(member, limit: 1 * Self.MiB))
        #expect(out == Data(count: 512 * 1024))
    }

    /// The limit is on the output: exactly `limit` bytes pass and one more does not.
    @Test func theLimitIsInclusive() throws {
        let limit = 256 * 1024
        #expect(GzipDecode.decompress(try Self.gzip(zeros: limit), limit: limit)?.count == limit)
        #expect(GzipDecode.decompress(try Self.gzip(zeros: limit + 1), limit: limit) == nil)
    }

    /// The trailer's ISIZE is the sender's claim and must not be what decides: a
    /// bomb that declares a tiny size is refused all the same.
    @Test func aBombThatUnderstatesItsSizeIsRefused() throws {
        var bomb = try Self.gzip(zeros: 32 * Self.MiB)
        bomb.replaceSubrange(bomb.count - 4..<bomb.count, with: [1, 0, 0, 0])
        #expect(GzipDecode.decompress(bomb, limit: 1 * Self.MiB) == nil)
    }

    // MARK: - zlib

    @Test func aZlibBombIsRefusedAtTheLimit() throws {
        let bomb = try Self.zlib(zeros: 32 * Self.MiB)
        #expect(bomb.count < 200 * 1024)
        #expect(GzipDecode.decompressZlib(bomb, hint: 0, limit: 1 * Self.MiB) == nil)
    }

    @Test func aZlibWithinTheLimitIsUnchanged() throws {
        let out = try #require(GzipDecode.decompressZlib(
            try Self.zlib(zeros: 512 * 1024), hint: 600, limit: 1 * Self.MiB))
        #expect(out == Data(count: 512 * 1024))
    }

    // MARK: - through the two callers

    /// Windscribe: a CRC-correct `qCompress` blob that inflates past its 1 MiB
    /// ceiling. The real payload is 537 bytes (measured), so nothing legitimate
    /// is near it.
    @Test func windscribeRefusesACompressedBlobPastItsCeiling() throws {
        func blob(zeros: Int) throws -> Data {
            var payload = Data()
            payload.append(contentsOf: [UInt8(zeros >> 24 & 0xFF), UInt8(zeros >> 16 & 0xFF),
                                        UInt8(zeros >> 8 & 0xFF), UInt8(zeros & 0xFF)])
            payload.append(try Self.zlib(zeros: zeros))
            let checksum = WindscribeChannel.qChecksum(payload)
            var body = Data([UInt8(checksum >> 8), UInt8(checksum & 0xFF)])
            body.append(payload)
            var chained = [UInt8]([0xE7] + body)
            var last: UInt8 = 0
            for i in chained.indices {
                chained[i] = chained[i] ^ WindscribeChannel.keyParts[i % 8] ^ last
                last = chained[i]
            }
            return Data([3, 0x03] + chained)       // v3, compression + checksum
        }

        let small = try #require(WindscribeChannel.simpleCryptDecrypt(try blob(zeros: 600)))
        #expect(small == Data(count: 600), "control: a payload the size of the real one decodes")
        #expect(WindscribeChannel.simpleCryptDecrypt(try blob(zeros: 32 * Self.MiB)) == nil)
    }

    /// Typeless: `compressedData` in `__NEXT_DATA__`. The payload is a valid
    /// release-notes array followed by whitespace, which JSON allows, so without a
    /// ceiling it decodes to a real changelog however much padding it carries; the
    /// 16 MiB ceiling is what turns the 32 MiB one into no changelog. The real
    /// payload is 22 KB inflated (measured 2026-10-25).
    @Test func typelessRefusesACompressedPayloadPastItsCeiling() throws {
        let notes = Data(#"[{"version":"1.0.0","date":"2026-01-01","features":[{"title":"T","content":"Fixed a thing."}]}]"#.utf8)
        func page(padding: Int) throws -> String {
            let b64 = try Self.gzip(notes + Data(repeating: 0x20, count: padding)).base64EncodedString()
            return """
            <script id="__NEXT_DATA__" type="application/json">\
            {"props":{"pageProps":{"compressedData":"\(b64)"}}}</script>
            """
        }
        func decode(_ html: String) -> Changelog? {
            StructuredChangelogDecoder.decode(
                html, format: .typelessReleaseNotes, channel: nil, maxEntries: 12)
        }
        #expect(decode(try page(padding: 1024))?.entries.map(\.version) == ["1.0.0"],
                "control: a payload of ordinary size decodes")
        #expect(decode(try page(padding: 32 * Self.MiB)) == nil)
    }
}
