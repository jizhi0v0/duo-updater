import CryptoKit
import Foundation

/// Applies a MyGo delta update: installed bundle + `.delta` → the new bundle.
///
/// MyGo (`github.com/egoist/mygo`, MIT) is a Go desktop framework with its own
/// updater; Moshi Go ships through it. Its patches are not Sparkle's, so
/// `BinaryDelta` cannot read them. The format is small and specified in the
/// framework's source, `internal/update/delta.go` and `bsdiff.go`, and this is a
/// port of its `ApplyDelta` and `Patch`, including every check they make:
///
///     "mygo delta 1\n", the length of the index (uvarint), the index (JSON,
///     raw DEFLATE), then the data of the files in the order of the index.
///
/// The index lists the new bundle's tree, relative to the bundle: directories,
/// links, and files with their mode, size and SHA-256. A file is a copy of a file
/// of the installed bundle (`from`, no data), a bsdiff-style patch of one (`from`
/// and data), or new (data, the file compressed with DEFLATE).
///
/// Trust is the same as for an unsigned Sparkle patch (`DeltaApplier.reconstruct`).
/// The index is not signed by anything we check, so its hashes only prove the
/// patch applied to the bundle it was cut from; the bundle that comes out goes
/// through the installer's code-signature and Team-ID gates like any download.
/// The manifest's `signature` is MyGo's Ed25519 over the file's SHA-256, made with
/// a key that lives in the app's own binary, not in its Info.plist; it is not
/// checked here.
enum MyGoDelta {

    enum Failure: LocalizedError, Equatable {
        case notADelta
        case damaged
        case wrongVersions(patchFrom: String, patchTo: String, from: String, to: String)
        case linkOutsideApp(String)
        case madeWrong(String)

        var errorDescription: String? {
            switch self {
            case .notADelta:
                return "The incremental patch is not a MyGo delta update."
            case .damaged:
                return "The incremental patch is damaged."
            case let .wrongVersions(patchFrom, patchTo, from, to):
                return "The incremental patch updates \(patchFrom) to \(patchTo), "
                    + "not \(from) to \(to)."
            case .linkOutsideApp(let path):
                return "The incremental patch links \(path) outside the app."
            case .madeWrong(let path):
                return "The incremental patch made \(path) wrong."
            }
        }
    }

    static let magic = Array("mygo delta 1\n".utf8)
    /// MyGo's own limit on the inflated index (`maxDeltaIndex`).
    static let maxIndex = 16 << 20
    /// Files are made in memory, so a size the index claims is capped before
    /// anything is allocated for it. MyGo itself only patches files up to 256 MiB
    /// (`maxDiff`) and includes larger ones whole; 2 GiB is far past any bundle file.
    static let maxFileSize: Int64 = 1 << 31

    struct Index: Decodable {
        let from: String
        let version: String
        let entries: [Entry]
    }

    /// One directory, link or file of the new bundle. MyGo writes the index with
    /// `omitzero`, so every field but `path` may be absent.
    struct Entry: Decodable {
        let path: String
        let dir: Bool
        let link: String
        let mode: UInt32
        let size: Int64
        let sha256: String
        let from: String
        let data: Int64

        var isFile: Bool { !dir && link.isEmpty }

        enum CodingKeys: String, CodingKey { case path, dir, link, mode, size, sha256, from, data }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            dir = try c.decodeIfPresent(Bool.self, forKey: .dir) ?? false
            link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
            mode = try c.decodeIfPresent(UInt32.self, forKey: .mode) ?? 0
            size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
            sha256 = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
            from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
            data = try c.decodeIfPresent(Int64.self, forKey: .data) ?? 0
        }
    }

    /// Build in `destination`, which must not exist, the bundle that the patch
    /// makes of `installedApp`. The patch must update version `from` to `to`
    /// (`to` nil: whatever it says), and every file it makes must have the size
    /// and SHA-256 its index gives. Never writes to `installedApp`.
    static func apply(
        patchFile: URL, from: String, to: String?,
        installedApp: URL, destination: URL
    ) throws {
        let file = try Data(contentsOf: patchFile, options: .alwaysMapped)
        let size = Int64(file.count)
        guard file.starts(with: magic) else { throw Failure.notADelta }
        var cursor = file.startIndex + magic.count
        guard let indexLen = readUvarint(file, &cursor),
              indexLen <= UInt64(size - Int64(cursor - file.startIndex))
        else { throw Failure.damaged }
        let indexEnd = cursor + Int(indexLen)
        guard let js = GzipDecode.inflateRaw(file[cursor..<indexEnd], limit: maxIndex),
              let index = try? JSONDecoder().decode(Index.self, from: js)
        else { throw Failure.damaged }
        guard index.from == from, to == nil || index.version == to else {
            throw Failure.wrongVersions(
                patchFrom: index.from, patchTo: index.version, from: from, to: to ?? index.version)
        }

        // Check the whole index before making anything.
        let dataStart = Int64(indexEnd - file.startIndex)
        var offset = dataStart
        var seen = Set<String>()
        for e in index.entries {
            if !isValidPath(e.path) || e.path == "." || seen.contains(e.path)
                || e.size < 0 || e.data < 0 || e.data > size - offset
                || e.dir && !e.link.isEmpty
                || !e.isFile && (e.size != 0 || e.data != 0 || !e.from.isEmpty)
                || !e.from.isEmpty && !isValidPath(e.from)
                || e.isFile && e.from.isEmpty && e.data == 0 {
                throw Failure.damaged
            }
            if !e.link.isEmpty {
                let target = cleanJoin(parent(of: e.path), e.link)
                if e.link.hasPrefix("/") || !isValidPath(target) {
                    throw Failure.linkOutsideApp(e.path)
                }
            }
            seen.insert(e.path)
            offset += e.data
        }
        guard offset == size else { throw Failure.damaged }

        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        let oldRoot = installedApp.resolvingSymlinksInPath()
        offset = dataStart
        for e in index.entries {
            let url = destination.appendingPathComponent(e.path)
            let dir = parent(of: e.path)
            if dir != "." {
                try fm.createDirectory(
                    at: destination.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
            if e.dir {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } else if !e.link.isEmpty {
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: e.link)
            } else {
                let start = file.startIndex + Int(offset)
                try writeFile(e, data: file[start..<start + Int(e.data)], oldRoot: oldRoot, to: url)
                offset += e.data
            }
        }
    }

    /// Make the file of `e` from its data in the patch, and check it.
    private static func writeFile(_ e: Entry, data: Data, oldRoot: URL, to url: URL) throws {
        guard e.size <= maxFileSize else { throw Failure.madeWrong(e.path) }
        let bytes: Data
        if e.from.isEmpty {
            // One byte over the size inflates to nil, which reads as "made wrong",
            // the same as MyGo's `limitWriter` refusing it.
            guard let inflated = GzipDecode.inflateRaw(data, limit: Int(e.size)) else {
                throw Failure.madeWrong(e.path)
            }
            bytes = inflated
        } else {
            let old = try readOld(e.from, root: oldRoot)
            if data.isEmpty {
                bytes = old
            } else {
                do {
                    bytes = try patch(old: old, size: e.size, patch: data)
                } catch Failure.damaged {
                    // Most likely the installed app is not the one the patch was cut from.
                    throw Failure.madeWrong(e.path)
                }
            }
        }
        let sum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard Int64(bytes.count) == e.size, sum == e.sha256 else { throw Failure.madeWrong(e.path) }

        let mode = mode_t(e.mode & 0o777) | 0o200
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: bytes)
        // `open`'s mode passes through the umask; set the index's bits exactly.
        guard fchmod(fd, mode) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try handle.close()
    }

    /// A file of the installed bundle. Links are followed, as MyGo's `os.Root`
    /// does, but never out of the bundle.
    private static func readOld(_ path: String, root: URL) throws -> Data {
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"),
              let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType,
              type == .typeRegular
        else { throw Failure.madeWrong(path) }
        return try Data(contentsOf: url)
    }

    /// The file of `size` bytes that `patch` makes of `old` — MyGo's `Patch`.
    ///
    /// Colin Percival's bsdiff blocks: each adds difference bytes to bytes of the
    /// old file (bytes outside it count as zeros, as in bspatch), then appends
    /// extra bytes, then moves the old position. The patch is the number of
    /// blocks and the lengths of the first two streams (uvarints), then three
    /// raw-DEFLATE streams: control (per block: difference length, extra length
    /// as uvarints, the move as a varint), difference bytes, extra bytes.
    static func patch(old: Data, size: Int64, patch: Data) throws -> Data {
        var cursor = patch.startIndex
        guard let blocks = readUvarint(patch, &cursor),
              let ctrlLen = readUvarint(patch, &cursor),
              let diffLen = readUvarint(patch, &cursor),
              size >= 0, size <= maxFileSize, blocks <= UInt64(size) + 1
        else { throw Failure.damaged }
        let rest = UInt64(patch.endIndex - cursor)
        guard ctrlLen <= rest, diffLen <= rest - ctrlLen else { throw Failure.damaged }
        let ctrlEnd = cursor + Int(ctrlLen), diffEnd = ctrlEnd + Int(diffLen)
        // Three varints per block, at most ten bytes each.
        guard let ctrl = GzipDecode.inflateRaw(patch[cursor..<ctrlEnd], limit: Int(blocks) * 30),
              let diff = GzipDecode.inflateRaw(patch[ctrlEnd..<diffEnd], limit: Int(size)),
              let extra = GzipDecode.inflateRaw(patch[diffEnd..<patch.endIndex], limit: Int(size))
        else { throw Failure.damaged }

        var out = [UInt8]()
        out.reserveCapacity(Int(min(size, 64 << 20)))
        var c = ctrl.startIndex
        var d = diff.startIndex, x = extra.startIndex
        var oldPos: Int64 = 0, left = size
        let oldSize = Int64(old.count)
        try old.withUnsafeBytes { (oldBytes: UnsafeRawBufferPointer) in
            try diff.withUnsafeBytes { (diffBytes: UnsafeRawBufferPointer) in
                for _ in 0..<blocks {
                    guard let dLen = readUvarint(ctrl, &c), let eLen = readUvarint(ctrl, &c),
                          let seek = readVarint(ctrl, &c),
                          dLen <= UInt64(left), eLen <= UInt64(left) - dLen
                    else { throw Failure.damaged }
                    left -= Int64(dLen + eLen)
                    let dEnd = d + Int(dLen)
                    guard dEnd <= diff.endIndex else { throw Failure.damaged }
                    let base = d - diff.startIndex
                    for i in 0..<Int(dLen) {
                        let at = oldPos + Int64(i)
                        let o: UInt8 = at >= 0 && at < oldSize ? oldBytes[Int(at)] : 0
                        out.append(diffBytes[base + i] &+ o)
                    }
                    d = dEnd
                    oldPos += Int64(dLen)
                    let xEnd = x + Int(eLen)
                    guard xEnd <= extra.endIndex else { throw Failure.damaged }
                    out.append(contentsOf: extra[x..<xEnd])
                    x = xEnd
                    oldPos += seek
                    guard oldPos >= -(1 << 40), oldPos <= 1 << 40 else { throw Failure.damaged }
                }
            }
        }
        guard left == 0 else { throw Failure.damaged }
        return Data(out)
    }

    // MARK: - Go's encoding/binary and io/fs, as MyGo uses them

    /// `binary.Uvarint`: nil on a truncated or overflowing value.
    static func readUvarint(_ data: Data, _ cursor: inout Data.Index) -> UInt64? {
        var x: UInt64 = 0, shift: UInt64 = 0
        for i in 0..<10 {
            guard cursor < data.endIndex else { return nil }
            let b = data[cursor]
            cursor += 1
            if b < 0x80 {
                if i == 9 && b > 1 { return nil }
                return x | UInt64(b) << shift
            }
            x |= UInt64(b & 0x7f) << shift
            shift += 7
        }
        return nil
    }

    /// `binary.Varint`: zig-zag over `Uvarint`.
    static func readVarint(_ data: Data, _ cursor: inout Data.Index) -> Int64? {
        guard let ux = readUvarint(data, &cursor) else { return nil }
        let x = Int64(bitPattern: ux >> 1)
        return ux & 1 != 0 ? ~x : x
    }

    /// `fs.ValidPath`: unrooted, slash-separated, no empty, `.` or `..` element;
    /// `.` alone names the root.
    static func isValidPath(_ name: String) -> Bool {
        if name == "." { return true }
        return name.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// `path.Dir` for the relative paths of an index.
    static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        let dir = String(path[..<slash])
        return dir.isEmpty ? "." : dir
    }

    /// `path.Join(dir, rel)` of two relative paths: cleaned, so a `..` that
    /// climbs out of the bundle stays at the front, where `isValidPath` refuses it.
    static func cleanJoin(_ dir: String, _ rel: String) -> String {
        var parts: [Substring] = []
        for part in (dir + "/" + rel).split(separator: "/") where part != "." {
            if part == "..", let last = parts.last, last != ".." {
                parts.removeLast()
            } else {
                parts.append(part)
            }
        }
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}
