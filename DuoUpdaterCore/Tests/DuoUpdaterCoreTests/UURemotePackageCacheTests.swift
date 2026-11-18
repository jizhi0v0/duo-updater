import Foundation
import Testing
@testable import DuoUpdaterCore

struct UURemotePackageCacheTests {
    private let key = "downloaded_package_manualUpdate"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let packageURL =
        "https://a56.gdl.netease.com/uuyc_4.48.0_nochannel.pkg?key1=fixture&key2=7fffffff"

    @Test func cacheOnlySuppliesThePublicProbeRelease() throws {
        let snapshot = cache([("downloaded_package_forceUpdate", response(code: 1151)), (key, response())])
        let candidate = try #require(try preferred(snapshot))
        #expect(candidate.url == URL(string: packageURL))
        #expect(candidate.identity == .init(bundleID: "com.netease.uuremote", marketing: "4.48.0", build: "632"))
        #expect(try preferred(snapshot, remote: Self.vendor(version: "4.49.0")) == nil)
        #expect(try preferred(snapshot, remote: Self.vendor(version: "4.47.0")) == nil)
        #expect(try preferred(snapshot, remote: nil) == nil)
        #expect(try preferred() == nil)
    }

    @Test func onlyVendorPackageRouteCanUseTheCache() throws {
        let snapshot = cache([(key, response())])
        #expect(try preferred(snapshot, app: Self.installed(bundleID: "com.example.other")) == nil)
        #expect(try preferred(snapshot, app: Self.installed(isMASApp: true)) == nil)
        #expect(try preferred(snapshot, remote: Self.vendor(source: "Homebrew")) == nil)
        #expect(try preferred(snapshot, remote: Self.vendor(kind: nil)) == nil)
    }

    @Test func anOverwrittenOrDeletedOfferDoesNotSurvive() throws {
        #expect(try preferred(cache([(key, response()), (key, response(code: 1151))])) == nil)
        #expect(try preferred(cache([(key, response()), (key, nil)])) == nil)
        #expect(try preferred(cache([("green_tip", response())])) == nil)
    }

    @Test func refusesInvalidSnapshotsAndExpiredOrDifferentPackages() throws {
        let snapshot = cache([(key, response())])
        #expect(try preferred((snapshot.file, Data(repeating: 0, count: 4))) == nil)
        #expect(try preferred((Data(snapshot.file.dropLast()), snapshot.checksum)) == nil)
        #expect(try preferred(snapshot, now: Date(timeIntervalSince1970: 2_147_483_647)) == nil)
        #expect(try preferred(snapshot, app: Self.installed(build: "632")) == nil)
        #expect(try preferred(cache([(key,
            response(url: packageURL.replacingOccurrences(of: "4.48.0", with: "4.47.0")))])) == nil)
        #expect(try preferred(cache([(key,
            response(url: packageURL.replacingOccurrences(of: "a56.gdl.netease.com", with: "example.com")))])) == nil)
    }

    private static func installed(bundleID: String = "com.netease.uuremote",
                                  build: String = "631", isMASApp: Bool = false) -> InstalledApp {
        InstalledApp(name: "UU Remote", bundleID: bundleID, shortVersion: "4.47.0", buildVersion: build,
                     path: URL(fileURLWithPath: "/Applications/UURemote.app"),
                     isMASApp: isMASApp, sparkleFeedURL: nil)
    }

    private static func vendor(version: String = "4.48.0", source: String = VendorProbeSource.sourceName,
                               kind: VendorInstallerKind? = .pkg) -> RemoteVersion {
        RemoteVersion(shortVersion: version, version: nil,
                      downloadURL: URL(string: "https://api.nrd.nie.163.com/api/v1/release/dl/4?channel=gwqd"),
                      sourceName: source, requiresManualInstaller: true, vendorInstallerKind: kind)
    }

    private func preferred(_ snapshot: (file: Data, checksum: Data)? = nil,
                           app: InstalledApp? = nil, remote: RemoteVersion? = UURemotePackageCacheTests.vendor(),
                           now: Date? = nil) throws -> (url: URL, identity: PackageInstaller.PayloadIdentity)? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("HomeTopUpdatePackage")
        if let snapshot {
            try snapshot.file.write(to: file)
            try snapshot.checksum.write(to: file.appendingPathExtension("crc"))
        }
        return UURemotePackageCache(cache: file).preferredPackage(
            for: app ?? Self.installed(), remote: remote, now: now ?? self.now)
    }

    private func response(code: Int = 0, url: String? = nil) -> Data {
        Data("""
        {"source":"manualUpdate","response":{"code":\(code),"data":{
          "version_name":"4.48.0","version_code":632,"update_type":"UpdateManual","url":"\(url ?? packageURL)"
        }}}
        """.utf8)
    }

    private func cache(_ entries: [(String, Data?)]) -> (file: Data, checksum: Data) {
        var payload = Data([0]) // MMKV's reserved initial varint.
        for (key, value) in entries {
            payload.append(field(Data(key.utf8)))
            payload.append(field(value.map(field) ?? Data()))
        }
        return (littleEndian(UInt32(payload.count)) + payload, littleEndian(RemoteZipEntry.crc32(payload)))
    }

    private func field(_ value: Data) -> Data {
        var length = value.count
        var prefix = Data()
        while length >= 128 {
            prefix.append(UInt8(length & 0x7f) | 0x80)
            length >>= 7
        }
        prefix.append(UInt8(length))
        return prefix + value
    }

    private func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
