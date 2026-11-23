import Foundation
import Synchronization

enum StandaloneCLIArchive {
    struct InvalidMember: LocalizedError {
        var errorDescription: String? { "The archive could not be read as a standalone executable." }
    }

    /// Only the named member goes to stdout. Tar never writes an archive path
    /// or applies archive permissions. bsdtar handles ZIP as well as tarballs.
    static func executable(named name: String, in archive: URL, limit: Int) async throws -> Data {
        let listing = try await tar(["-tvf", archive.path, "--", name], limit: 4096)
        let lines = String(decoding: listing, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard lines.count == 1, let entry = lines.first, entry.hasPrefix("-"), entry.hasSuffix(" " + name)
        else { throw InvalidMember() }
        return try await tar(["-xOf", archive.path, "--", name], limit: limit)
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
            throw InvalidMember()
        }
        return body
    }
}
