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
        // doesn't starve the loop.
        let isize = Int(bytes[bytes.count - 4])
            | (Int(bytes[bytes.count - 3]) << 8)
            | (Int(bytes[bytes.count - 2]) << 16)
            | (Int(bytes[bytes.count - 1]) << 24)

        return inflate(Array(deflate), hint: max(isize, 64 * 1024))
    }

    /// Stream raw DEFLATE bytes through `compression_stream` until done.
    private static func inflate(_ deflate: [UInt8], hint: Int) -> Data? {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil)
        guard compression_stream_init(
            &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { return nil }
        defer { compression_stream_destroy(&stream) }

        let chunk = max(hint, 64 * 1024)
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
