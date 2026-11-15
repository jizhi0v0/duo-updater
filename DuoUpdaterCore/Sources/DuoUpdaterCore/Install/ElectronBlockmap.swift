import Foundation

/// electron-builder's external, gzip-compressed v2 map. This describes bytes of
/// the original archive, not files in the installed application bundle.
struct ElectronBlockmap: Sendable {
    static let compressedLimit = 8 * 1024 * 1024
    static let decodedLimit = 32 * 1024 * 1024
    static let archiveLimit: Int64 = 2 * 1024 * 1024 * 1024

    struct File: Decodable, Sendable {
        let name: String
        let offset: Int64
        let checksums: [String]
        let sizes: [Int64]
    }
    private struct Document: Decodable {
        let version: String
        let files: [File]
    }
    enum Invalid: Error { case unsupported, malformed }

    let file: File
    let size: Int64

    init(compressed: Data, expectedSize: Int64? = nil) throws {
        guard compressed.count <= Self.compressedLimit,
              let json = GzipDecode.decompress(compressed, limit: Self.decodedLimit)
        else { throw Invalid.unsupported } // v3 and unknown formats take the full route.
        try self.init(json: json, expectedSize: expectedSize)
    }

    init(json: Data, expectedSize: Int64? = nil) throws {
        guard json.count <= Self.decodedLimit else { throw Invalid.malformed }
        let document = try JSONDecoder().decode(Document.self, from: json)
        guard document.version == "2" else { throw Invalid.unsupported }
        guard document.files.count == 1, let file = document.files.first,
              file.name == "file", file.offset == 0,
              !file.sizes.isEmpty, file.sizes.count <= 500_000,
              file.sizes.count == file.checksums.count
        else { throw Invalid.malformed }
        var size: Int64 = 0
        for (checksum, length) in zip(file.checksums, file.sizes) {
            guard !checksum.isEmpty, checksum.utf8.count <= 128,
                  length > 0, length <= 1024 * 1024,
                  size <= Self.archiveLimit - length
            else { throw Invalid.malformed }
            size += length
        }
        guard expectedSize.map({ $0 == size }) ?? true else { throw Invalid.malformed }
        self.file = file
        self.size = size
    }

    struct Operation: Sendable, Equatable {
        enum Kind: Sendable { case copy, download }
        let kind: Kind
        let offset: Int64
        var length: Int64
    }

    /// Match both hash and size. Offsets for COPY refer to the old archive;
    /// DOWNLOAD offsets refer to the new one. Operations are in output order.
    func operations(from old: ElectronBlockmap) -> [Operation] {
        var lookup: [String: (offset: Int64, size: Int64)] = [:]
        var offset: Int64 = 0
        for (hash, size) in zip(old.file.checksums, old.file.sizes) {
            if lookup[hash] == nil { lookup[hash] = (offset, size) }
            offset += size
        }
        var result: [Operation] = []
        offset = 0
        for (hash, size) in zip(file.checksums, file.sizes) {
            let match = lookup[hash].flatMap { $0.size == size ? $0 : nil }
            let kind: Operation.Kind = match == nil ? .download : .copy
            let start = match?.offset ?? offset
            if let last = result.last, last.kind == kind, last.offset + last.length == start {
                result[result.count - 1].length += size
            } else {
                result.append(Operation(kind: kind, offset: start, length: size))
            }
            offset += size
        }
        return result
    }
    /// Fetch across short COPY gaps instead of issuing tiny, serial requests.
    /// A fragmented untrusted map must be rejected before any range is sent.
    func downloadPlan(from old: ElectronBlockmap, maxRange: Int64, maxRequests: Int = 512, maxIOIterations: Int = 8192) -> [Operation]? {
        var result: [Operation] = []
        var lastDownload: Int?
        var copyGap: Int64 = 0
        for operation in operations(from: old) {
            if operation.kind == .download {
                if let index = lastDownload, copyGap < 8 * 1024 {
                    result.removeSubrange((index + 1)..<result.count)
                    result[index].length += copyGap + operation.length
                } else {
                    lastDownload = result.count
                    result.append(operation)
                }
                copyGap = 0
            } else {
                copyGap += operation.length
                result.append(operation)
            }
        }
        let downloads = result.filter { $0.kind == .download }
        let bytes = downloads.reduce(Int64(0)) { $0 + $1.length }
        let requests = downloads.reduce(Int64(0)) { $0 + ($1.length + maxRange - 1) / maxRange }
        let ioIterations = result.reduce(Int64(0)) { count, operation in
            let chunk = operation.kind == .copy ? 1024 * 1024 : maxRange
            return count + (operation.length + chunk - 1) / chunk
        }
        guard bytes < size, requests <= maxRequests, ioIterations <= maxIOIterations else { return nil }
        return result
    }

}
