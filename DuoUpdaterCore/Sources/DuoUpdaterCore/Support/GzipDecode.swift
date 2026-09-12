import Foundation
import Compression

/// Minimal, dependency-free gzip (RFC 1952) decompressor built on Apple's
/// `Compression` framework. Apple only exposes raw DEFLATE (`COMPRESSION_ZLIB`,
/// which here means RFC 1951 with no zlib/gzip wrapper), so we parse and strip the
/// gzip header + trailer ourselves and feed the bare DEFLATE block to the stream
/// decoder.
///
/// Used by `StructuredChangelogDecoder` to unpack vendor changelog payloads that
/// ship base64+gzip inside an HTML page (Typeless embeds the whole release-notes
/// JSON as `compressedData` in its Next.js `__NEXT_DATA__`). Pure and
/// side-effect-free, so it stays unit-testable on a fixture string. Totally
/// defensive: a bad magic, an unsupported method, or a truncated stream yields
/// nil, never a throw.
enum GzipDecode {

    /// Ceiling on the scratch buffer `inflate` allocates, whatever a caller or a
    /// gzip trailer asks for. See `inflate` for why capping it is free.
    static let maxChunkBytes = 64 * 1024 * 1024

    /// The scratch-buffer size `inflate` will actually allocate for a hint.
    ///
    /// Split out as a pure function so the ceiling can be asserted without
    /// allocating what it refuses to allocate: the end-to-end test below it can
    /// only show that a hostile ISIZE still decodes correctly, which a missing
    /// ceiling also does — on a machine where a 4 GiB reservation happens to
    /// succeed.
    static func chunkSize(hint: Int) -> Int {
        min(max(hint, 64 * 1024), maxChunkBytes)
    }

    /// Decompress a complete gzip member. Returns nil on any malformation.
    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        // Header is at least 10 bytes; trailer (CRC32 + ISIZE) is 8.
        guard bytes.count >= 18,
              bytes[0] == 0x1f, bytes[1] == 0x8b, // magic
              bytes[2] == 0x08                    // CM = DEFLATE
        else { return nil }

        let flg = bytes[3]
        var idx = 10 // fixed header: magic(2) CM(1) FLG(1) MTIME(4) XFL(1) OS(1)

        // FEXTRA: 2-byte little-endian length, then that many bytes.
        if flg & 0x04 != 0 {
            guard idx + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2 + xlen
        }
        // FNAME / FCOMMENT: NUL-terminated strings.
        if flg & 0x08 != 0 {
            while idx < bytes.count, bytes[idx] != 0 { idx += 1 }
            idx += 1
        }
        if flg & 0x10 != 0 {
            while idx < bytes.count, bytes[idx] != 0 { idx += 1 }
            idx += 1
        }
        // FHCRC: 2-byte header CRC.
        if flg & 0x02 != 0 { idx += 2 }

        // What's left, minus the 8-byte trailer, is the raw DEFLATE block.
        let deflateEnd = bytes.count - 8
        guard idx < deflateEnd else { return nil }
        let deflate = bytes[idx..<deflateEnd]

        // ISIZE (last 4 bytes, little-endian) is the uncompressed size mod 2^32 —
        // a good initial buffer hint. Clamp to a sane floor so a zero/tiny ISIZE
        // doesn't starve the loop, and to a ceiling in `inflate` because nothing
        // here has verified the trailer: it is the tail of a vendor response, and
        // `0xFFFFFFFF` is a four-byte request for a 4 GiB allocation.
        let isize = Int(bytes[bytes.count - 4])
            | (Int(bytes[bytes.count - 3]) << 8)
            | (Int(bytes[bytes.count - 2]) << 16)
            | (Int(bytes[bytes.count - 1]) << 24)

        return inflate(Array(deflate), hint: max(isize, 64 * 1024))
    }

    /// Decompress a zlib stream (RFC 1950) — a 2-byte header, the same raw
    /// DEFLATE body `decompress` ends up at, and a 4-byte adler32 trailer.
    ///
    /// Split out rather than duplicated because the inflate loop below is the
    /// part worth having exactly once: gzip and zlib differ only in what wraps
    /// the DEFLATE, and a second copy of the streaming decode is a second place
    /// for a buffer bug to live.
    ///
    /// Qt's `qCompress` emits this (behind its own 4-byte big-endian length
    /// prefix, which is the caller's business, not ours) — see
    /// `WindscribeChannel`.
    ///
    /// The header check is the real one, not just "is the first byte 0x78":
    /// CMF's low nibble must be 8 (DEFLATE) and `(CMF << 8 | FLG) % 31` must be
    /// 0, which is the checksum RFC 1950 defines those two bytes to carry. A
    /// preset dictionary (FDICT) is refused rather than mis-parsed — nothing
    /// that reaches here uses one, and guessing would hand the inflater a
    /// dictionary id as if it were compressed data.
    static func decompressZlib(_ data: Data, hint: Int) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let cmf = bytes[0], flg = bytes[1]
        guard cmf & 0x0F == 8,
              (Int(cmf) << 8 | Int(flg)) % 31 == 0,
              flg & 0x20 == 0                       // no preset dictionary
        else { return nil }
        // Body runs to the adler32 trailer, which the raw inflater neither needs
        // nor tolerates.
        let end = bytes.count - 4
        guard 2 < end else { return nil }
        return inflate(Array(bytes[2..<end]), hint: max(hint, 64 * 1024))
    }

    /// Stream raw DEFLATE bytes through `compression_stream` until done.
    private static func inflate(_ deflate: [UInt8], hint: Int) -> Data? {
        // Both pointers are placeholders that `compression_stream_init` requires
        // to be non-null and never reads: the real `src_ptr`/`dst_ptr` are set
        // inside the loop below, before the first `_process`. `dst_ptr` used to
        // be an `allocate(capacity: 0)` that nothing ever deallocated — a leak on
        // every call, however small. A dangling non-null address costs nothing
        // and cannot be forgotten, which is what `src_ptr` was already doing.
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil)
        guard compression_stream_init(
            &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { return nil }
        defer { compression_stream_destroy(&stream) }

        // The hint is a *hint*: this is a reusable scratch buffer the loop drains
        // and refills until the stream ends, so a hint smaller than the output
        // costs iterations, never correctness. That makes the ceiling free — and
        // necessary, because `decompress` derives its hint from gzip's ISIZE
        // trailer, four bytes of attacker-supplied data that can ask for 4 GiB.
        // A vendor changelog is not 64 MiB; a page that claims to be gets decoded
        // 64 MiB at a time instead of reserving the claim up front.
        let chunk = chunkSize(hint: hint)
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dstBuffer.deallocate() }

        var output = Data()
        var ok = true
        deflate.withUnsafeBufferPointer { src in
            stream.src_ptr = src.baseAddress!
            stream.src_size = src.count
            repeat {
                stream.dst_ptr = dstBuffer
                stream.dst_size = chunk
                let status = compression_stream_process(
                    &stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(dstBuffer, count: chunk - stream.dst_size)
                    if status == COMPRESSION_STATUS_END { return }
                default:
                    ok = false
                    return
                }
            } while true
        }
        return ok ? output : nil
    }
}
