import Foundation

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
        let body: Data
        do {
            body = try await StandaloneCLIArchive.executable(
                named: "multica", in: archive, limit: maximumExecutableBytes)
        } catch is StandaloneCLIArchive.InvalidMember {
            throw Failure.invalidMember
        }
        try await offCooperativePool {
            try body.write(to: executable)
            guard MulticaBinary.read(at: executable) == MulticaBinary(version: version, architecture: architecture)
            else { throw Failure.wrongBinary }
        }
    }
}
