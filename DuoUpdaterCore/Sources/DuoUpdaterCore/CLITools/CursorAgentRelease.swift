import Foundation

/// What the installer would install: the version the script at cursor.com/install
/// names.
///
/// The script is generated per release — the version is written into it twice,
/// `TEMP_EXTRACT_DIR=…/versions/.tmp-<version>-$(date +%s)` and
/// `FINAL_DIR="$HOME/.local/share/cursor-agent/versions/<version>"` — so fetching
/// it is asking the channel, and the click runs the very script the check read
/// (or a newer one, never an older: `CursorAgentUpdater`). On 2026-10-04 it named
/// 2026.10.01-e373342; the Wayback Machine's copy of 2026-05-18 named
/// 2026.05.16-0338208. The CLI's own update asks Cursor's backend instead
/// (`getCliDownloadUrl`), which a GUI app cannot call without the user's session.
public struct CursorAgentRelease: Sendable {

    public static let installerURL = URL(string: "https://cursor.com/install")!

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        /// The answer is not Cursor's installer, or names no version.
        case unreadable

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "cursor.com/install did not answer with the installer"
            }
        }
    }

    typealias Fetch = @Sendable (URL, RequestPurpose) async throws -> (Data, Int)

    let fetch: Fetch

    public init(session: URLSession = .updates) {
        self.init(fetch: { url, purpose in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await session.countedData(for: request, purpose: purpose)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }

    /// The seam tests use, so nothing here reaches the network.
    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The installer as served now, and the version it installs.
    public func installer(purpose: RequestPurpose = .versionCheck) async throws -> (script: Data, version: String) {
        let (data, status) = try await fetch(Self.installerURL, purpose)
        guard status == 200 else { throw Failure.http(status) }
        guard let version = Self.version(inInstaller: data) else { throw Failure.unreadable }
        return (data, version)
    }

    public func latest() async throws -> String {
        try await installer().version
    }

    static let finalDir = #"FINAL_DIR="$HOME/.local/share/cursor-agent/versions/"#

    /// The version the script installs: its one `FINAL_DIR` line, which must also
    /// be the release its download URL names. nil for anything else — an error
    /// page, a script of another shape.
    static func version(inInstaller data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("#!/usr/bin/env bash") || text.hasPrefix("#!/bin/bash") else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let finals = lines.filter { $0.hasPrefix(finalDir) }
        guard finals.count == 1, finals[0].hasSuffix("\"") else { return nil }
        let version = String(finals[0].dropFirst(finalDir.count).dropLast())
        guard isVersion(version),
              lines.contains(where: { $0.hasPrefix("DOWNLOAD_URL=\"https://downloads.cursor.com/lab/\(version)/") })
        else { return nil }
        return version
    }

    /// `2026.10.01-e373342`: a date and a commit, as every release so far.
    static func isVersion(_ s: String) -> Bool {
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count >= 6, parts[1].count <= 40,
              parts[1].allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return false }
        let date = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        return date.count == 3 && date[0].count == 4 && date[1].count == 2 && date[2].count == 2
            && date.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// Ordered by the date; two releases of one day are told apart only as
    /// different, the CLI's own rule for a manual update (`update-core.ts`: same
    /// date, other commit, is an update). Returned as `.orderedAscending` then.
    static func compare(_ installed: String, _ latest: String) -> ComparisonResult {
        let a = installed.prefix(10), b = latest.prefix(10)
        if a != b { return a < b ? .orderedAscending : .orderedDescending }
        return installed == latest ? .orderedSame : .orderedAscending
    }
}
