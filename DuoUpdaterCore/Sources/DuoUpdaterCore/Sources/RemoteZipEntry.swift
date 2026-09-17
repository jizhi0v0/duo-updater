import Foundation

/// One file out of a zip that lives on a server, read with HTTP `Range` requests
/// instead of downloading the archive — the runtime behind
/// `VendorProbeRecipe.Mode.redirectArchiveInfoPlist`.
///
/// A zip is addressable from its tail: the end-of-central-directory record says
/// where the central directory starts, each central-directory record says where
/// its entry's local header is, and the entry's bytes follow that header. So one
/// entry of an archive of any size costs three small reads: the tail, the
/// directory up to the entry's record, and the entry itself. The directory is
/// read in growing chunks from its start and the scan stops at the first match,
/// so the cost tracks how early the entry is listed, not how big the archive is.
///
/// The parsing is pure and the fetching is injected (`Fetch`), so both halves run
/// offline in the tests. What this cannot read it refuses rather than guesses:
/// ZIP64 archives, encrypted entries, compression other than stored/deflate, and
/// an entry whose inflated bytes do not match the directory's size and CRC-32.
enum RemoteZipEntry {

    /// The bytes one request asks for: the archive's last `n` bytes, or the
    /// inclusive span `start...end`.
    enum ByteRange: Equatable, Sendable {
        case suffix(Int)
        case span(Int, Int)
    }

    /// What one read returned: the bytes, the archive's total length (from the
    /// response's `Content-Range`) and whatever the host names this copy of the
    /// archive by (its `ETag`, else `Last-Modified`; nil when it sends neither).
    /// May answer fewer bytes than asked for only at the end of the archive.
    struct Chunk: Sendable {
        let data: Data
        let totalLength: Int
        let identity: String?
    }

    typealias Fetch = @Sendable (ByteRange) async throws -> Chunk

    /// The archive, or the entry, is not something this reader can read.
    struct Unreadable: Error, Equatable {
        let detail: String
    }

    /// A later read described a different archive than the first one — the vendor
    /// replaced the file under the same URL between reads (iStat Menus re-publishes
    /// in place). Nothing is wrong with the recipe; the next check reads one copy.
    struct ArchiveChanged: Error, Equatable {
        let detail: String
    }

    /// First tail read. The end-of-central-directory record is the last 22 bytes
    /// of a zip with no archive comment, which is every vendor zip seen so far.
    static let initialTail = 1_024
    /// The record plus the longest comment a zip can carry.
    static let maxTail = 22 + 0xFFFF
    /// First directory read, doubled on each further read up to `maxDirectoryChunk`.
    static let initialDirectoryChunk = 4_096
    static let maxDirectoryChunk = 1 << 20
    /// Directory bytes scanned before giving up on finding the entry.
    static let maxDirectoryBytes = 32 << 20
    /// An entry larger than this (compressed or not) is refused: this reads an
    /// `Info.plist`, not a payload.
    static let maxEntryBytes = 1 << 20

    private static let endOfDirectorySignature: UInt32 = 0x0605_4B50
    private static let directoryRecordSignature: UInt32 = 0x0201_4B50
    private static let localHeaderSignature: UInt32 = 0x0403_4B50

    /// The bytes of the entry named exactly `name` (a path inside the archive).
    static func read(
        _ name: String, fetch: Fetch, directoryChunk: Int = initialDirectoryChunk
    ) async throws -> Data {
        // Every read after the first must describe the same archive: offsets taken
        // from one copy are meaningless in another.
        let first = try await fetch(.suffix(initialTail))
        let total = first.totalLength
        func get(_ range: ByteRange) async throws -> Data {
            let chunk = try await fetch(range)
            guard chunk.totalLength == total, chunk.identity == first.identity else {
                throw ArchiveChanged(detail: "the archive changed between range reads ("
                    + "\(total) B \(first.identity ?? "-") → "
                    + "\(chunk.totalLength) B \(chunk.identity ?? "-"))")
            }
            // A fresh buffer, so every offset below is relative to 0 even if a
            // fetcher hands back a slice.
            return Data(chunk.data)
        }

        // 1. The tail, for the end-of-central-directory record.
        var tail = Data(first.data)
        var end = endOfDirectory(in: tail)
        if end == nil, tail.count < min(maxTail, total) {
            tail = try await get(.suffix(maxTail))
            end = endOfDirectory(in: tail)
        }
        let tailStart = total - tail.count
        guard let end else {
            throw Unreadable(detail: "no zip end-of-central-directory record in the last \(tail.count) bytes")
        }
        guard !end.isZip64 else {
            throw Unreadable(detail: "ZIP64 archive — not supported")
        }
        let directoryEnd = end.directoryOffset + end.directorySize
        guard end.directoryOffset >= 0, directoryEnd <= tailStart + end.position else {
            throw Unreadable(detail: "central directory (\(end.directoryOffset)+\(end.directorySize)) overlaps its own end record")
        }

        // 2. The directory, from its start, until the entry's record.
        let wanted = Data(name.utf8)
        var directory = Data()
        var chunk = max(directoryChunk, 46)
        var cursor = 0
        var record: DirectoryRecord?
        scan: while cursor < end.directorySize {
            switch directoryRecord(in: directory, at: cursor) {
            case .complete(let parsed, let length):
                if parsed.name == wanted { record = parsed; break scan }
                cursor += length
            case .truncated:
                let have = directory.count
                guard have < end.directorySize else {
                    throw Unreadable(detail: "central directory record \(cursor) runs past the directory's end")
                }
                guard have < maxDirectoryBytes else {
                    throw Unreadable(detail: "'\(name)' is not in the first \(maxDirectoryBytes) bytes of the central directory")
                }
                let upTo = min(end.directorySize, have + chunk, maxDirectoryBytes)
                let more = try await get(.span(
                    end.directoryOffset + have, end.directoryOffset + upTo - 1))
                guard !more.isEmpty else {
                    throw Unreadable(detail: "the host returned no bytes for the central directory at \(have)")
                }
                directory.append(more)
                chunk = min(chunk * 2, maxDirectoryChunk)
            case .malformed(let detail):
                throw Unreadable(detail: detail)
            }
        }
        guard let record else {
            throw Unreadable(detail: "'\(name)' is not in the archive's central directory")
        }
        guard record.flags & 0x1 == 0 else {
            throw Unreadable(detail: "'\(name)' is encrypted")
        }
        guard record.method == 0 || record.method == 8 else {
            throw Unreadable(detail: "'\(name)' uses compression method \(record.method) — only stored and deflate are read")
        }
        guard !record.isZip64 else {
            throw Unreadable(detail: "'\(name)' has ZIP64 sizes — not supported")
        }
        guard record.compressedSize <= maxEntryBytes, record.size <= maxEntryBytes else {
            throw Unreadable(detail: "'\(name)' is \(record.size) bytes — larger than this reader takes")
        }

        // 3. The local header and the entry's bytes. The local header's extra field
        // may differ in length from the directory's, so ask for some slack and
        // fetch the rest only if that was not enough.
        let guess = 30 + record.name.count + 1_024 + record.compressedSize
        var local = try await get(.span(
            record.localHeaderOffset, min(total, record.localHeaderOffset + guess) - 1))
        guard local.count >= 30, u32(local, 0) == localHeaderSignature else {
            throw Unreadable(detail: "'\(name)' has no local header at offset \(record.localHeaderOffset)")
        }
        let dataStart = 30 + u16(local, 26) + u16(local, 28)
        let dataEnd = dataStart + record.compressedSize
        if local.count < dataEnd {
            local.append(try await get(.span(
                record.localHeaderOffset + local.count, record.localHeaderOffset + dataEnd - 1)))
        }
        guard local.count >= dataEnd else {
            throw Unreadable(detail: "'\(name)' ends past the archive")
        }
        let stored = local.subdata(in: dataStart..<dataEnd)

        let bytes: Data
        if record.method == 8 {
            // `.zlib` is raw DEFLATE (RFC 1951), which is what a zip entry holds —
            // see `Inflate.zlib` in `PackageArchitectureProbe` for the naming trap.
            guard let inflated = try? (stored as NSData).decompressed(using: .zlib) as Data else {
                throw Unreadable(detail: "'\(name)' does not inflate")
            }
            bytes = inflated
        } else {
            bytes = stored
        }
        guard bytes.count == record.size, crc32(bytes) == record.crc32 else {
            throw Unreadable(detail: "'\(name)' does not match its directory record's size and CRC-32")
        }
        return bytes
    }

    // MARK: - Records

    struct EndOfDirectory: Equatable {
        /// Offset of the record inside the tail it was found in.
        let position: Int
        let directorySize: Int
        let directoryOffset: Int
        let isZip64: Bool
    }

    /// The last end-of-central-directory record in `tail` whose comment length
    /// accounts exactly for the bytes after it — the signature alone can occur
    /// inside a comment.
    static func endOfDirectory(in tail: Data) -> EndOfDirectory? {
        guard tail.count >= 22 else { return nil }
        var position = tail.count - 22
        while position >= 0 {
            if u32(tail, position) == endOfDirectorySignature,
               position + 22 + u16(tail, position + 20) == tail.count {
                let entries = u16(tail, position + 10)
                let size = u32(tail, position + 12)
                let offset = u32(tail, position + 16)
                return EndOfDirectory(
                    position: position, directorySize: Int(size), directoryOffset: Int(offset),
                    isZip64: entries == 0xFFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF)
            }
            position -= 1
        }
        return nil
    }

    struct DirectoryRecord: Equatable {
        let name: Data
        let flags: Int
        let method: Int
        let crc32: UInt32
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
        let isZip64: Bool
    }

    enum RecordParse: Equatable {
        case complete(DirectoryRecord, length: Int)
        /// `directory` ends before this record does.
        case truncated
        case malformed(String)
    }

    static func directoryRecord(in directory: Data, at offset: Int) -> RecordParse {
        guard directory.count >= offset + 46 else { return .truncated }
        guard u32(directory, offset) == directoryRecordSignature else {
            return .malformed("central directory record \(offset) has no signature")
        }
        let nameLength = u16(directory, offset + 28)
        let length = 46 + nameLength + u16(directory, offset + 30) + u16(directory, offset + 32)
        guard directory.count >= offset + length else { return .truncated }
        let compressed = u32(directory, offset + 20)
        let size = u32(directory, offset + 24)
        let local = u32(directory, offset + 42)
        return .complete(DirectoryRecord(
            name: directory.subdata(in: offset + 46 ..< offset + 46 + nameLength),
            flags: u16(directory, offset + 8),
            method: u16(directory, offset + 10),
            crc32: u32(directory, offset + 16),
            compressedSize: Int(compressed), size: Int(size), localHeaderOffset: Int(local),
            isZip64: compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF || local == 0xFFFF_FFFF),
            length: length)
    }

    // MARK: - Bytes

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        let base = data.startIndex + offset
        return Int(data[base]) | Int(data[base + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base]) | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
