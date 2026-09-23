import Foundation

/// Every Xcode release the xcodereleases index can hand a download for, one entry
/// per release, newest first — for Settings → Xcode's "Download Xcode" list.
///
/// A plain download of the `.xip`, nothing more: no expansion, no install, no
/// overwrite. What the user does with the archive is theirs. The URL is the same
/// allow-listed authorized endpoint the update route uses, so it only ever goes
/// to developer.apple.com with the user's Apple Developer session.
public struct XcodeDownloadItem: Sendable, Equatable, Identifiable {
    /// Index items: build plus the index's ordering — an RC and the release it
    /// became share a build (Apple ships the same bits) but are two entries with
    /// two archives. Apple-only items: their archive path.
    public let id: String
    /// Nil for an item only Apple's list has: Apple does not publish builds.
    public let build: String?
    /// The index's `_versionOrder`; nil for an Apple-only item.
    let order: Int?
    /// "27.1 beta 1 (27A9269)", as the Xcode row shows it; "27.1 beta" for an
    /// Apple-only item.
    public let displayVersion: String
    /// Listed by Apple but not (yet) by the index — typically the hour or so
    /// after a release, before xcodereleases.com catches up.
    public let onlyFromApple: Bool
    public let isPrerelease: Bool
    /// For placing an Apple-only item among index items.
    var sortDate: Date? { date.flatMap { Calendar(identifier: .gregorian).date(from: $0) } }
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

    /// Fetch the index and merge in Apple's own list (`AppleDeveloperDownloadList`
    /// JSON the caller fetched with the user's session).
    public static func load(
        mergingAppleList appleData: Data, session: URLSession = .updates
    ) async throws -> [XcodeDownloadItem] {
        let releases = try await XcodeReleasesSource(session: session).fetch()
        return merged(
            index: releases, apple: AppleDeveloperDownloadList.parse(appleData), host: .current)
    }

    /// The index's items plus every Apple release the index has no archive of.
    /// Pure.
    ///
    /// Matched on the archive path, which both publish identically
    /// (`/Developer_Tools/Xcode_27.1_beta/Xcode_27.1_beta.xip`, 2026-09-23). A
    /// release counts as known when ANY of its archives is in the index — the
    /// index may carry the Universal one where this Mac is offered Apple silicon.
    ///
    /// An Apple-only item goes in by date, ahead of the first index item that is
    /// older, so the index's own version order is left as it was.
    static func merged(
        index releases: [XcodeReleasesSource.Release],
        apple: [AppleDeveloperDownloadList.Release],
        host: HostArch
    ) -> [XcodeDownloadItem] {
        var result = items(from: releases, host: host)
        let known = Set(releases.compactMap { $0.authorizedURL.flatMap(archivePath(of:)) })
        let extra = apple
            .filter { release in !release.archives.contains { known.contains($0.path) } }
            .compactMap { appleItem($0, host: host) }
            .sorted { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }
        for item in extra {
            let at = result.firstIndex { ($0.sortDate ?? .distantPast) < (item.sortDate ?? .distantPast) }
                ?? result.endIndex
            result.insert(item, at: at)
        }
        return result
    }

    private static func appleItem(
        _ release: AppleDeveloperDownloadList.Release, host: HostArch
    ) -> XcodeDownloadItem? {
        // Same preference as `chooseDownload`: the Apple silicon build on arm64,
        // else Universal; on Intel only Universal. An archive whose name says
        // neither was the only one for every Mac.
        let archives = release.archives
        let chosen: AppleDeveloperDownloadList.Archive? = {
            switch host {
            case .arm64:
                return archives.first { $0.arch == .appleSilicon }
                    ?? archives.first { $0.arch == .universal }
                    ?? (archives.count == 1 ? archives.first : nil)
            case .x86_64:
                return archives.first { $0.arch == .universal }
                    ?? (archives.count == 1 && archives[0].arch == .unlabelled ? archives.first : nil)
            }
        }()
        guard let chosen,
              let url = XcodeReleasesSource.authorizedDownloadURL(
                fromCDN: "https://download.developer.apple.com" + chosen.path)
        else { return nil }
        var day: DateComponents?
        if let listed = release.listed {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = AppleDeveloperDownloadList.timeZone
            day = calendar.dateComponents([.year, .month, .day], from: listed)
        }
        let fileName = chosen.path.split(separator: "/").last.map(String.init) ?? ""
        return XcodeDownloadItem(
            id: "apple:" + chosen.path, build: nil, order: nil,
            displayVersion: release.displayName, onlyFromApple: true,
            isPrerelease: release.isPrerelease, date: day,
            requiresMacOS: release.requiresMacOS, authorizedURL: url, fileName: fileName)
    }

    /// `/Developer_Tools/<dir>/<file>.xip` from an authorized URL's `path=`.
    static func archivePath(of authorizedURL: URL) -> String? {
        URLComponents(url: authorizedURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "path" }?.value
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
                id: "\(chosen.build)#\(chosen.order)",
                build: chosen.build, order: chosen.order, displayVersion: chosen.displayVersion,
                onlyFromApple: false,
                isPrerelease: chosen.stability != .release, date: chosen.date,
                requiresMacOS: chosen.requires, authorizedURL: url, fileName: fileName)
        }
        .sorted { ($0.order ?? 0) != ($1.order ?? 0)
            ? ($0.order ?? 0) > ($1.order ?? 0) : ($0.build ?? "") > ($1.build ?? "") }
    }
}
