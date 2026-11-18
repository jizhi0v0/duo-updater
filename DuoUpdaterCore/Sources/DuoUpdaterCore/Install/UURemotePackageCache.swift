import Darwin
import Foundation

/// An alternate package URL for the release already selected by the public probe.
struct UURemotePackageCache {
    private let cache: URL
    private static let maximumCacheBytes = 1_048_576
    private static let manualOfferKey = Data("downloaded_package_manualUpdate".utf8)

    init(cache: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.netease.uuremote/MMKVRootDir/HomeTopUpdatePackage")
    ) {
        self.cache = cache
    }

    func preferredPackage(
        for app: InstalledApp, remote: RemoteVersion?, now: Date = Date()
    ) -> (url: URL, identity: PackageInstaller.PayloadIdentity)? {
        guard let bundleID = app.bundleID, bundleID == "com.netease.uuremote", !app.isMASApp,
              let remote, remote.sourceName == VendorProbeSource.sourceName,
              remote.vendorInstallerKind == .pkg, remote.downloadURL != nil,
              let version = remote.shortVersion,
              let installedBuild = app.buildVersion.flatMap(Int.init), installedBuild > 0,
              let bytes = Self.read(cache, limit: Self.maximumCacheBytes),
              let checksum = Self.read(cache.appendingPathExtension("crc"), limit: 4)
        else { return nil }

        guard let record = Self.manualOffer(in: bytes, checksum: checksum),
              let cached = try? JSONDecoder().decode(CachedOffer.self, from: record),
              cached.source == "manualUpdate", cached.response.code == 0,
              let offer = cached.response.data, offer.updateType == "UpdateManual",
              offer.versionName == version, offer.versionCode > installedBuild,
              let url = offer.packageURL(now: now)
        else { return nil }
        return (url, .init(bundleID: bundleID, marketing: version, build: String(offer.versionCode)))
    }

    private static func read(_ url: URL, limit: Int) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return try? file.read(upToCount: limit)
    }

    private struct CachedOffer: Decodable {
        struct Response: Decodable {
            let code: Int
            let data: Offer?
        }
        let source: String
        let response: Response
    }

    private struct Offer: Decodable {
        let versionName: String
        let versionCode: Int
        let updateType: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case url
            case versionName = "version_name"
            case versionCode = "version_code"
            case updateType = "update_type"
        }

        func packageURL(now: Date) -> URL? {
            guard let parts = URLComponents(string: url), parts.scheme == "https",
                  parts.host == "a56.gdl.netease.com", parts.user == nil, parts.password == nil,
                  parts.port == nil, parts.fragment == nil,
                  parts.percentEncodedPath == "/uuyc_\(versionName)_nochannel.pkg"
            else { return nil }

            // In observed UU responses, key2 is the hex epoch 12 h after the
            // check. Drop expired links locally without a CDN request per refresh.
            let keys = (parts.queryItems ?? []).filter { $0.name == "key1" }
            let expiries = (parts.queryItems ?? []).filter { $0.name == "key2" }
            guard keys.count == 1, keys[0].value?.isEmpty == false,
                  expiries.count == 1, let hex = expiries[0].value, hex.utf8.count == 8,
                  let expiry = UInt32(hex, radix: 16), Double(expiry) > now.timeIntervalSince1970
            else { return nil }
            return parts.url
        }
    }

    /// A fixed little-endian length prefixes the MMKV map. The first varint is
    /// reserved, then key/value pairs are length-prefixed and appended. A later
    /// value supersedes its old entry, and an empty value deletes the key.
    private static func manualOffer(in file: Data, checksum: Data) -> Data? {
        guard file.count >= 4, checksum.count == 4,
              let length = Int(exactly: file.withUnsafeBytes({ $0.loadUnaligned(as: UInt32.self).littleEndian })),
              length <= file.count - 4
        else { return nil }
        let payload = file.subdata(in: 4..<(4 + length))
        let expectedCRC = checksum.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard RemoteZipEntry.crc32(payload) == expectedCRC else { return nil }

        var cursor = Cursor(bytes: payload)
        guard cursor.readLength() != nil else { return nil }
        var latest: Data?
        while !cursor.isAtEnd {
            guard let key = cursor.readField(), let value = cursor.readField() else { return nil }
            if key == manualOfferKey { latest = value.isEmpty ? nil : value }
        }
        guard let latest else { return nil }

        // MMKV's stored Data value has its own length prefix around the JSON.
        var value = Cursor(bytes: latest)
        guard let body = value.readField(), value.isAtEnd else { return nil }
        return body
    }

    private struct Cursor {
        let bytes: Data
        var offset = 0
        var isAtEnd: Bool { offset == bytes.count }

        mutating func readLength() -> Int? {
            var result = 0
            for shift in stride(from: 0, to: 35, by: 7) {
                guard !isAtEnd else { return nil }
                let byte = bytes[offset]
                offset += 1
                if shift == 28 && byte > 15 { return nil }
                result |= Int(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return result }
            }
            return nil
        }

        mutating func readField() -> Data? {
            guard let length = readLength(), length <= bytes.count - offset else { return nil }
            let end = offset + length
            defer { offset = end }
            return bytes.subdata(in: offset..<end)
        }
    }
}
