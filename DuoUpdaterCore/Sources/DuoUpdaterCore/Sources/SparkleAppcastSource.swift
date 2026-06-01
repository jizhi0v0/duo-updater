import Foundation

/// Resolves updates for apps that ship a Sparkle `SUFeedURL`. Fetches the
/// appcast RSS, parses the items, filters to macOS releases the current system
/// can run, and returns the highest-versioned one.
public struct SparkleAppcastSource: UpdateSource {
    public let name = "Sparkle"

    private let session: URLSession
    private let currentSystemVersion: String

    public init(session: URLSession = .shared, currentSystemVersion: String? = nil) {
        self.session = session
        self.currentSystemVersion = currentSystemVersion
            ?? ProcessInfo.processInfo.operatingSystemVersionString
        // operatingSystemVersionString is verbose; prefer the numeric form.
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard let feedURL = app.sparkleFeedURL else { return nil }

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 15
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SparkleError.badStatus(http.statusCode)
        }

        let items = SparkleAppcastParser.parse(data)
        guard !items.isEmpty else { return nil }

        let osVersion = Self.numericSystemVersion()
        let usable = items.filter { item in
            // Skip delta updates — they patch a specific old build.
            guard item.deltaFrom == nil else { return false }
            // Honor minimum system version when declared.
            if let minOS = item.minimumSystemVersion, !minOS.isEmpty {
                return VersionComparator.compare(osVersion, minOS) != .orderedAscending
            }
            return true
        }

        let best = usable.max { lhs, rhs in
            VersionComparator.compare(lhs.comparisonKey, rhs.comparisonKey) == .orderedAscending
        }
        guard let best else { return nil }

        return RemoteVersion(
            shortVersion: best.shortVersionString,
            version: best.version,
            downloadURL: best.enclosureURL,
            edSignature: best.edSignature,
            minimumSystemVersion: best.minimumSystemVersion,
            sourceName: name
        )
    }

    /// e.g. "26.6.0" — used to evaluate `minimumSystemVersion`.
    static func numericSystemVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    enum SparkleError: Error {
        case badStatus(Int)
    }
}

// MARK: - Appcast parsing

struct SparkleAppcastItem {
    var shortVersionString: String?
    var version: String?
    var enclosureURL: URL?
    var edSignature: String?
    var minimumSystemVersion: String?
    var deltaFrom: String?

    /// Prefer the build version (Sparkle's canonical key); fall back to short.
    var comparisonKey: String { version ?? shortVersionString ?? "0" }
}

/// Minimal XMLParser-backed appcast reader. Version metadata in Sparkle feeds
/// may live either on the `<enclosure>` attributes or as child elements of
/// `<item>`; we collect both.
final class SparkleAppcastParser: NSObject, XMLParserDelegate {

    static func parse(_ data: Data) -> [SparkleAppcastItem] {
        let parser = XMLParser(data: data)
        let delegate = SparkleAppcastParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private var items: [SparkleAppcastItem] = []
    private var current: SparkleAppcastItem?
    private var textBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        textBuffer = ""
        switch elementName {
        case "item":
            current = SparkleAppcastItem()
        case "enclosure":
            current?.enclosureURL = attributeDict["url"].flatMap { URL(string: $0) }
            if let v = attributeDict["sparkle:version"] { current?.version = v }
            if let s = attributeDict["sparkle:shortVersionString"] {
                current?.shortVersionString = s
            }
            if let sig = attributeDict["sparkle:edSignature"] {
                current?.edSignature = sig
            }
            if let delta = attributeDict["sparkle:deltaFrom"] {
                current?.deltaFrom = delta
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "sparkle:version":
            if current?.version == nil, !text.isEmpty { current?.version = text }
        case "sparkle:shortVersionString":
            if current?.shortVersionString == nil, !text.isEmpty {
                current?.shortVersionString = text
            }
        case "sparkle:minimumSystemVersion":
            current?.minimumSystemVersion = text
        case "item":
            if let item = current { items.append(item) }
            current = nil
        default:
            break
        }
        textBuffer = ""
    }
}
