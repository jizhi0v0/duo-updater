import Foundation

/// Apple's developer release feed, `developer.apple.com/news/releases/rss/releases.rss`,
/// read only for its Xcode items: "Xcode 27.1 beta (27A9269)".
///
/// Public and unauthenticated, 1.7 KB gzip (18 KB decoded), `max-age=300`, and no
/// `ETag` or `Last-Modified` to revalidate against (measured 2026-09-23). It is an
/// announcement, not a source: an item carries no download, and the feed skips
/// many Xcode releases — between May and September 2026 it had 27, 27.1 beta,
/// 27.2 beta and 26.6, and none of 27 beta 2–6, 27 RC or 26.6 RC 2. So it only
/// ever tells `XcodeReleaseWatch` to keep asking the index a while longer.
public enum AppleDeveloperReleaseFeed {
    public static let url = URL(string: "https://developer.apple.com/news/releases/rss/releases.rss")!

    public struct Announcement: Sendable, Equatable {
        /// "Xcode 27.1 beta (27A9269)", as the feed writes it.
        public let title: String
        /// "27A9269" — what the index calls `version.build`.
        public let build: String
        public let date: Date
    }

    /// The Xcode items, or nil when `data` is not an RSS document at all (a proxy
    /// or error page), so the caller can tell "no Xcode news" from "no feed".
    public static func xcodeAnnouncements(in data: Data) -> [Announcement]? {
        guard let text = String(data: data, encoding: .utf8),
              text.contains("<rss"), text.contains("<channel")
        else { return nil }
        return matches(of: #"<item>(.*?)</item>"#, in: text).compactMap { item in
            guard let title = first(of: #"<title>(.*?)</title>"#, in: item).map(unwrapped),
                  let build = first(of: #"^Xcode [0-9][^()]* \(([0-9]+[A-Z][0-9]+[a-z]?)\)$"#, in: title),
                  let pubDate = first(of: #"<pubDate>(.*?)</pubDate>"#, in: item),
                  let date = date(from: pubDate)
            else { return nil }
            return Announcement(title: title, build: build, date: date)
        }
    }

    static func fetch(session: URLSession = .updates) async throws -> [Announcement] {
        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        let (data, response) = try await session.versionFeedData(for: request, label: "AppleReleaseFeed")
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let items = xcodeAnnouncements(in: data) else { throw URLError(.cannotParseResponse) }
        return items
    }

    /// "Fri, 18 Sep 2026 10:00:00 PDT" — RFC 822, as the feed writes it.
    static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string.trimmingCharacters(in: .whitespaces)) { return date }
        }
        return nil
    }

    private static func unwrapped(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<![CDATA["), t.hasSuffix("]]>") {
            t = String(t.dropFirst("<![CDATA[".count).dropLast("]]>".count))
        }
        return t.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces)
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func first(of pattern: String, in text: String) -> String? {
        matches(of: pattern, in: text).first
    }
}
