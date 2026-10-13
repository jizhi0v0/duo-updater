import Foundation

/// Where a MyGo app (`github.com/egoist/mygo`) looks for its updates, and the
/// key they must be signed with — read out of the app's own executable.
///
/// The MyGo counterpart of `ElectronUpdateConfig`, with one difference that
/// shapes everything here: MyGo writes neither value to a file. `mygo build`
/// links both into the binary with `-ldflags -X`
/// (`cmd/mygo/updates.go`, `updateFlags`):
///
///     -X github.com/egoist/mygo.packageUpdateFeed=<manifest URL of this target>
///     -X github.com/egoist/mygo.packageUpdateKey=<base64 Ed25519 public key>
///
/// and the app's updater (`updater.go`, `checkUpdate`) reads exactly those two.
/// Info.plist carries neither, and the Go build info does not record the flags
/// of a `-trimpath` build, which every `mygo build` is.
///
/// What makes them findable is how Go's linker stores a `-X` string: as a
/// symbol of its own, `<name>.str`, in read-only data, written with a trailing
/// NUL (`cmd/link/internal/ld/data.go` `addstrdata` → `Addstring`, which appends
/// the 0). Ordinary Go string literals carry no terminator. So the two values
/// are NUL-terminated strings in `__TEXT,__rodata`, and that is the only place
/// read: one section the load commands locate, 0.5–1.6 MB in the binaries
/// measured, rather than a 12–33 MB executable.
///
/// The rules, and why a value is refused rather than guessed:
/// - the feed is a NUL-terminated `https://…/update-darwin-<target>.json`.
///   The target is the build's own (`darwin-arm64`, `darwin-amd64`,
///   `darwin-universal`): the binary names the manifest it reads, so nothing
///   here chooses an architecture. A GitHub feed with a tag prefix keeps its
///   `{version}` placeholder, resolved at check time (`MyGoUpdateSource`);
/// - the key is a NUL-terminated 44-character base64 string, preceded by a
///   byte outside the base64 alphabet, decoding to 32 bytes. A binary carries
///   other strings of that shape (Pulse 0.1.12: 8, among them the `h1:` hash
///   of the MyGo module; Moshi Go 0.5.16: 31) but none of them NUL-terminated;
/// - each must be unique. Two candidates mean the binary holds something this
///   reading does not understand, and the app is left uncovered.
///
/// Measured 2026-10-13 on six binaries of five apps (Pulse 0.1.11 and 0.1.12,
/// Moshi Go 0.5.16, Leafmark 0.9.2, Gotify Desktop 0.2.3 universal, 香篆 0.7.2
/// amd64): exactly one feed and one key each, every key the `publicKey` of the
/// app's published `mygo.json` and verifying its manifest's signature. The key
/// is a fact about the binary the user runs, so trusting it is trusting what the
/// app's own updater trusts; the signature check at install time is what holds
/// a wrong reading to "no install" rather than a wrong one.
public struct MyGoUpdateConfig: Sendable, Hashable {
    /// The feed exactly as linked: the manifest's URL, or for GitHub releases
    /// with a tag prefix, the manifest in the release `<prefix>{version}`.
    public let feed: String
    /// The vendor's MyGo update key, base64.
    public let publicKey: String

    public init(feed: String, publicKey: String) {
        self.feed = feed
        self.publicKey = publicKey
    }

    /// MyGo's `update.VersionPlaceholder`.
    public static let versionPlaceholder = "{version}"

    /// Whether the feed names a release by tag prefix, resolved through the
    /// GitHub API (`update.ResolveFeed`), rather than a manifest outright.
    public var isTagged: Bool { feed.contains(Self.versionPlaceholder) }

    /// The manifest's address, for a feed that names one outright.
    public var manifestURL: URL? {
        isTagged ? nil : URL(string: feed)
    }

    /// Far above any real `__rodata` (1.6 MB in a 33 MB universal binary). A
    /// larger size is a header that is not what it says.
    static let maxSectionBytes: UInt64 = 64 * 1024 * 1024

    /// The config of the executable at `url`, from its `__TEXT,__rodata`
    /// section; nil when the section cannot be read or holds no single feed and
    /// key.
    public static func read(binaryAt url: URL, rodata: MachOImports.FileRange) -> MyGoUpdateConfig? {
        guard rodata.size > 0, rodata.size <= maxSectionBytes,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: rodata.offset)) != nil,
              let bytes = try? handle.read(upToCount: Int(rodata.size)),
              bytes.count == Int(rodata.size)
        else { return nil }
        return find(in: bytes)
    }

    /// The config of the bundle's main executable, when Go linked MyGo into it —
    /// for authoring tools (`FeedDiscovery`), which have no scan to ask. The scan
    /// itself reads the binary its runtime detector settled on.
    public static func read(bundleAt bundleURL: URL) -> MyGoUpdateConfig? {
        let plist = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist"))
        guard let name = plist?["CFBundleExecutable"] as? String else { return nil }
        let executable = bundleURL.appendingPathComponent("Contents/MacOS/\(name)")
        guard let commands = MachOImports.loadCommands(at: executable),
              let info = commands.goBuildInfo.flatMap({ GoBuildInfo.read(at: executable, section: $0) }),
              info.module(AppRuntimeDetector.myGoModule) != nil,
              let rodata = commands.section("__TEXT", "__rodata")
        else { return nil }
        return read(binaryAt: executable, rodata: rodata.range)
    }

    /// The section's bytes → config. Split out so the rules can be tested
    /// without a MyGo binary on disk.
    static func find(in data: Data) -> MyGoUpdateConfig? {
        let bytes = [UInt8](data)
        var feeds: Set<String> = []
        var keys: Set<String> = []
        for end in bytes.indices where bytes[end] == 0 {
            if let key = key(endingAt: end, in: bytes) { keys.insert(key) }
            if let feed = feed(endingAt: end, in: bytes) { feeds.insert(feed) }
        }
        guard feeds.count == 1, keys.count == 1,
              let feed = feeds.first, let key = keys.first
        else { return nil }
        return MyGoUpdateConfig(feed: feed, publicKey: key)
    }

    /// A key ending right before the NUL at `end`.
    private static func key(endingAt end: Int, in bytes: [UInt8]) -> String? {
        let length = 44
        let start = end - length
        guard start >= 0, bytes[end - 1] == UInt8(ascii: "=") else { return nil }
        if start > 0, isBase64(bytes[start - 1]) || bytes[start - 1] == UInt8(ascii: "=") {
            return nil
        }
        for b in bytes[start..<(end - 1)] where !isBase64(b) { return nil }
        let text = String(decoding: bytes[start..<end], as: UTF8.self)
        guard Data(base64Encoded: text)?.count == 32 else { return nil }
        return text
    }

    /// A feed ending right before the NUL at `end`: the printable run before
    /// it, from its last `https://`, shaped like a MyGo manifest of a darwin
    /// target.
    private static func feed(endingAt end: Int, in bytes: [UInt8]) -> String? {
        // `update-darwin-x.json` is the shortest tail worth looking at.
        guard end >= 30, bytes[end - 1] == UInt8(ascii: "n") else { return nil }
        var start = end
        while start > 0, (0x21...0x7e).contains(bytes[start - 1]), end - start < 2048 {
            start -= 1
        }
        let run = String(decoding: bytes[start..<end], as: UTF8.self)
        guard let scheme = run.range(of: "https://", options: .backwards) else { return nil }
        let candidate = String(run[scheme.lowerBound...])
        guard candidate.wholeMatch(of: feedShape) != nil else { return nil }
        return candidate
    }

    /// `https://<host>/<path>/update-darwin-<arch>.json`; the path may carry
    /// MyGo's `{version}` placeholder.
    nonisolated(unsafe) private static let feedShape =
        #/https://[A-Za-z0-9.\-]+(?::[0-9]+)?/[\x21-\x7e]*/update-darwin-[a-z0-9]+\.json/#

    private static func isBase64(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"):
            return true
        default:
            return false
        }
    }
}
