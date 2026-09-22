import Foundation

/// Every Xcode release the xcodereleases index can hand a download for, one entry
/// per release, newest first — for Settings → Xcode's "Download Xcode" list.
///
/// A plain download of the `.xip`, nothing more: no expansion, no install, no
/// overwrite. What the user does with the archive is theirs. The URL is the same
/// allow-listed authorized endpoint the update route uses, so it only ever goes
/// to developer.apple.com with the user's Apple Developer session.
public struct XcodeDownloadItem: Sendable, Equatable, Identifiable {
    /// Build plus the index's ordering: an RC and the release it became share a
    /// build (Apple ships the same bits) but are two entries with two archives.
    public var id: String { "\(build)#\(order)" }
    public let build: String
    let order: Int
    /// "27.1 beta 1 (27A9269)", as the Xcode row shows it.
    public let displayVersion: String
    public let isPrerelease: Bool
    public let date: DateComponents?
    /// Minimum macOS, from the index; nil when it does not say.
    public let requiresMacOS: String?
    public let authorizedURL: URL
    /// The archive's file name ("Xcode_27.1_beta_Apple_silicon.xip").
    public let fileName: String
}

public enum XcodeDownloadCatalog {
    /// Fetch the index and build the list for this Mac.
    public static func load(session: URLSession = .updates) async throws -> [XcodeDownloadItem] {
        items(from: try await XcodeReleasesSource(session: session).fetch(), host: .current)
    }

    /// One item per release that has a usable archive for `host`. Pure.
    ///
    /// A release is its `_versionOrder`, not its build: 16.4 RC and 16.4 are both
    /// `16F6`, and grouping by build alone merged their two archives into one
    /// ambiguous group and listed neither (caught on the live index 2026-09-22).
    /// Within a release, the entries are the same bits packaged per architecture.
    ///
    /// The archive is picked by the update route's own rule (`chooseDownload`).
    /// Most older entries list no architectures, which that rule never accepts;
    /// for a download the user asked for by name, a build whose entries list none
    /// at all offers its single archive anyway — those predate the Apple silicon
    /// split and were one file for every Mac.
    static func items(from releases: [XcodeReleasesSource.Release], host: HostArch) -> [XcodeDownloadItem] {
        let byRelease = Dictionary(grouping: releases) { "\($0.build)#\($0.order)" }
        return byRelease.values.compactMap { entries -> XcodeDownloadItem? in
            let usable = entries.filter { $0.authorizedURL != nil }
            let chosen = XcodeReleasesSource.chooseDownload(among: entries, host: host)
                ?? (usable.count == 1 && usable[0].architectures == nil ? usable[0] : nil)
            guard let chosen, let url = chosen.authorizedURL,
                  let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "path" })?.value,
                  let fileName = path.split(separator: "/").last.map(String.init)
            else { return nil }
            return XcodeDownloadItem(
                build: chosen.build, order: chosen.order, displayVersion: chosen.displayVersion,
                isPrerelease: chosen.stability != .release, date: chosen.date,
                requiresMacOS: chosen.requires, authorizedURL: url, fileName: fileName)
        }
        .sorted { $0.order != $1.order ? $0.order > $1.order : $0.build > $1.build }
    }
}
