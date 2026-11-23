import Foundation
import Synchronization

enum MulticaArchive {
    static let maximumExecutableBytes = 128 * 1024 * 1024

    enum Failure: LocalizedError {
        case invalidMember
        case wrongBinary

        var errorDescription: String? {
            switch self {
            case .invalidMember: "The Multica archive must contain a single regular multica executable at its root."
            case .wrongBinary: "The Multica executable does not match the release version and architecture."
            }
        }
    }

    /// Only the named member goes to stdout. Tar never writes a pathname, applies
    /// archive permissions or follows an archive link into the filesystem.
    static func extract(_ archive: URL, version: String, architecture: MulticaBinary.Architecture,
                        into executable: URL) async throws {
        let listing = try await tar(["-tvf", archive.path, "--", "multica"], limit: 4096)
        let lines = String(decoding: listing, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard lines.count == 1, let entry = lines.first, entry.hasPrefix("-"), entry.hasSuffix(" multica")
        else { throw Failure.invalidMember }

        let body = try await tar(["-xOf", archive.path, "--", "multica"], limit: maximumExecutableBytes)
        try await offCooperativePool {
            try body.write(to: executable)
            guard MulticaBinary.read(at: executable) == MulticaBinary(version: version, architecture: architecture)
            else { throw Failure.wrongBinary }
        }
    }

    private static func tar(_ arguments: [String], limit: Int) async throws -> Data {
        let output = Mutex<Data?>(Data())
        let result = try await ChildProcess.run(
            "/usr/bin/tar", arguments, environment: ["PATH": "/usr/bin:/bin", "LC_ALL": "C"],
            standardOutput: .discard, standardError: .discard,
            deadline: .init(terminateAfter: .seconds(30), killAfter: .seconds(32)),
            onCancel: .terminateChild,
            onOutputChunk: { chunk in
                output.withLock { body in
                    guard let size = body?.count else { return }
                    if chunk.count > limit - size { body = nil } else { body?.append(chunk) }
                }
            })
        guard result.succeeded, !result.timedOut, let body = output.withLock({ $0 }) else {
            throw Failure.invalidMember
        }
        return body
    }
}
