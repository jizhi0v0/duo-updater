import Foundation

// Design and failure boundaries: docs/engine-notes/electron-blockmap.md
enum ElectronZIPDownload {
    static let mapFileName = ".electron-blockmap"
    static let requestLimit: Int64 = 4 * 1024 * 1024

    struct Attempt: Sendable {
        let archive: URL?
        let bytes: Int64
        let finalHost: String?
    }

    static func sidecar(for url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.path += ".blockmap"
        return parts.url
    }

    static func prepare(
        app: InstalledApp, remote: RemoteVersion, workDir: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Attempt? {
        let cacheLocation = ElectronArchiveCache.Location.current
        guard cacheLocation.root != nil,
              remote.vendorInstallerKind == .zip, remote.nestedArchivePath == nil,
              remote.expectedSHA512 != nil || remote.expectedSHA256 != nil,
              remote.electronBlockmapURL != nil || app.electronUpdate != nil,
              let url = remote.downloadURL,
              let mapURL = remote.electronBlockmapURL ?? sidecar(for: url)
        else { return nil }
        let accounting = ElectronBlockmapHTTP.Accounting()
        var finalHost: String?
        let output = workDir.appendingPathComponent("electron-update.zip")
        do {
            try Task.checkCancellation()
            // An explicitly named map can be on another origin; artifact headers
            // belong only to the artifact's origin, not that unrelated server.
            let mapHeaders = CrossHostCredentialStripper.sameOrigin(url, mapURL) ? remote.downloadHeaders : [:]
            let (data, _) = try await ElectronBlockmapHTTP(
                limit: ElectronBlockmap.compressedLimit, range: nil, total: nil,
                accounting: accounting, appID: app.id).get(mapURL, headers: mapHeaders)
            let map = try await offCooperativePool {
                try ElectronBlockmap(compressed: data, expectedSize: remote.downloadSize)
            }
            // A successful full download can seed the next update as well.
            try await offCooperativePool { try data.write(to: workDir.appendingPathComponent(mapFileName)) }
            let availableBaseline = await offCooperativePool {
                ElectronArchiveCache.open(for: app, at: cacheLocation) ?? ElectronArchiveCache.openVendorBaseline(for: app)
            }
            try Task.checkCancellation()
            guard let baseline = availableBaseline else {
                return Attempt(archive: nil, bytes: accounting.bytes, finalHost: nil)
            }
            guard let operations = map.downloadPlan(from: baseline.map, maxRange: requestLimit) else {
                return Attempt(archive: nil, bytes: accounting.bytes, finalHost: nil)
            }
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
                throw ElectronBlockmap.Invalid.malformed
            }
            let destination = try FileHandle(forWritingTo: output)
            defer { try? destination.close() }
            var written: Int64 = 0
            for operation in operations {
                try Task.checkCancellation()
                var consumed: Int64 = 0
                while consumed < operation.length {
                    try Task.checkCancellation()
                    let length = min(operation.length - consumed,
                                     operation.kind == .copy ? 1024 * 1024 : requestLimit)
                    let start = operation.offset + consumed
                    let bytes: Data
                    if operation.kind == .copy {
                        bytes = try await offCooperativePool {
                            try baseline.archive.seek(toOffset: UInt64(start))
                            guard let data = try baseline.archive.read(upToCount: Int(length)), data.count == length else {
                                throw ElectronBlockmap.Invalid.malformed
                            }
                            return data
                        }
                    } else {
                        let response = try await ElectronBlockmapHTTP(
                            limit: Int(length), range: start..<(start + length), total: map.size,
                            accounting: accounting, appID: app.id).get(url, headers: remote.downloadHeaders)
                        bytes = response.0
                        finalHost = response.1
                    }
                    try await offCooperativePool { try destination.write(contentsOf: bytes) }
                    consumed += length
                    written += length
                    onProgress(Double(written) / Double(map.size))
                }
            }
            try await offCooperativePool {
                try destination.synchronize()
                if let expected = remote.expectedSHA512 { try VendorInstaller.verifyChecksum(output, expectedBase64: expected) }
                if let expected = remote.expectedSHA256 { try VendorInstaller.verifySHA256(output, expectedHex: expected) }
            }
            try Task.checkCancellation()
            Log.install.notice("electron blockmap: reconstructed \(map.size, privacy: .public) bytes, fetched \(accounting.bytes, privacy: .public) bytes")
            return Attempt(archive: output, bytes: accounting.bytes, finalHost: finalHost)
        } catch {
            try? FileManager.default.removeItem(at: output)
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            // Unreadable maps, stale bases, unsupported ranges and a failed target
            // digest all keep the ordinary full-archive path. Their bytes count.
            Log.install.notice("electron blockmap: taking the full archive after an unavailable differential route")
            return Attempt(archive: nil, bytes: accounting.bytes, finalHost: nil)
        }
    }
}
