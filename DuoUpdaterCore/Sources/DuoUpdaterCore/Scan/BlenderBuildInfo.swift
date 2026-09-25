import Foundation

/// What a Blender build says about itself, read out of its main executable.
///
/// **Why the executable.** Every Blender build — release, beta, release
/// candidate, the daily alpha — is `org.blenderfoundation.blender`, signed by
/// the same team, with a `CFBundleShortVersionString` that carries no cycle
/// (every 5.3 alpha is "5.3.0", and so will the release be). The only place the
/// difference exists is compiled into the binary, in two spots:
///
/// - **The cycle.** `blender_version_init()` (`source/blender/blenkernel/intern/
///   blender.cc`) picks a suffix by comparing `BLENDER_VERSION_CYCLE` against
///   literals, which the compiler folds, so only the chosen pair of literals
///   survives — and it survives next to the two format strings that function
///   passes to `SNPRINTF`: `" Beta\0 b\0 LTS\0%d.%01d.%d%s%s\0%d.%01d.%d%s"`.
///   A release keeps neither pair. The pair is read ADJACENT to the format
///   strings, never searched for on its own: a bare `" Alpha"` is in every
///   build (5.2.2 release included), for unrelated reasons.
/// - **The build info** (`buildinfo.c`'s globals): date, time (UTC) and commit
///   (12 hex) as consecutive strings, then padding and the commit timestamp as
///   an integer, then the branch and the platform, `"Darwin"`.
///   Alpha builds come from `main`; beta, RC and release all come from
///   `blender-vX.Y-release`, which is why the branch alone cannot tell them apart.
///
/// Both were read from the four builds the audit mounted (5.2.2 release, 5.2.0
/// beta, 5.2.1 RC, 5.3.0 alpha); `BlenderBuildInfoTests` pins the byte shapes.
public struct BlenderBuildInfo: Sendable, Equatable {
    public static let bundleID = "org.blenderfoundation.blender"

    public enum Cycle: String, Sendable {
        case alpha, beta, rc, release
    }

    /// Nil when the version format strings are not where this reader expects
    /// them: then nothing is claimed and the ordinary channel detection stands.
    public let cycle: Cycle?
    public let commit: String?
    public let branch: String?
    /// When the build was made, from the build info's UTC date and time.
    public let builtAt: Date?

    /// The channel this build belongs to, or nil when the cycle could not be read.
    public var channel: ReleaseChannel? {
        switch cycle {
        case .alpha: return .alpha
        case .beta: return .beta
        case .rc: return .rc
        case .release: return .stable
        case nil: return nil
        }
    }

    /// The commit to compare against the builder's newest build of this track, or
    /// nil when this build is not on the branch that track is built from.
    ///
    /// The builder's alpha track is `main` and its beta/RC tracks are the
    /// `blender-vX.Y-release` branches; a build of the same cycle from anywhere
    /// else (an experimental branch, a pull-request build, a local build) is not a
    /// member of the track, and comparing it against the track's head would offer
    /// to "update" it into a different line of development. Without a commit the
    /// engine answers "cannot tell" for it (`UpdateChecker.evaluate`).
    public var trackCommit: String? {
        guard let commit, let branch, let cycle else { return nil }
        switch cycle {
        case .alpha:
            return branch == "main" ? commit : nil
        case .beta, .rc, .release:
            return branch.range(of: #"^blender-v[0-9]+\.[0-9]+-release$"#, options: .regularExpression)
                != nil ? commit : nil
        }
    }

    // MARK: - Reading

    /// Read the executable of the Blender bundle at `bundleURL`. Nil when there
    /// is no readable executable. Remembered per executable identity (size and
    /// mtime), since the read walks a ~300 MB file.
    public static func read(bundleAt bundleURL: URL) -> BlenderBuildInfo? {
        let plist = NSDictionary(
            contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard let executable = AppRuntimeDetector.executableURL(
            bundleAt: bundleURL, infoPlist: plist ?? [:], fm: FileManager.default)
        else { return nil }
        let key = RuntimeVersion.executableIdentity(of: executable).map { "\(executable.path)|\($0)" }
        if let key, let remembered = cached(key) { return remembered }
        guard let data = try? Data(contentsOf: executable, options: .alwaysMapped) else { return nil }
        let info = parse(data)
        if let key { remember(info, for: key) }
        return info
    }

    private nonisolated(unsafe) static var cache: [String: BlenderBuildInfo] = [:]
    private static let cacheLock = NSLock()

    private static func cached(_ key: String) -> BlenderBuildInfo? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func remember(_ info: BlenderBuildInfo, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[key] = info
    }

    /// Pure: the two readings over an executable's bytes.
    static func parse(_ data: Data) -> BlenderBuildInfo {
        let build = buildInfo(in: data)
        return BlenderBuildInfo(
            cycle: cycle(in: data), commit: build?.commit, branch: build?.branch,
            builtAt: build?.builtAt)
    }

    /// The two format strings `blender_version_init()` formats with, in the order
    /// the compiler lays them out.
    private static let versionFormats = Data("\0%d.%01d.%d%s%s\0%d.%01d.%d%s\0".utf8)

    static func cycle(in data: Data) -> Cycle? {
        guard let anchor = data.range(of: versionFormats) else { return nil }
        // The strings ending at the anchor, nearest first. An LTS build stores
        // its " LTS" suffix between the cycle pair and the formats.
        var preceding = strings(endingAt: anchor.lowerBound, in: data, count: 3)
        if preceding.first == " LTS" { preceding.removeFirst() }
        guard preceding.count >= 2 else { return .release }
        switch (preceding[1], preceding[0]) {
        case (" Alpha", " a"): return .alpha
        case (" Beta", " b"): return .beta
        case (" Release Candidate", " RC"): return .rc
        default: return .release
        }
    }

    private static let platformMarker = Data("\0Darwin\0".utf8)

    /// `date\0time\0commit\0`, the first three of `buildinfo.c`'s globals.
    private static let stampedCommit = try! NSRegularExpression(
        pattern: #"([0-9]{4}-[0-9]{2}-[0-9]{2})\x00([0-9]{2}:[0-9]{2}:[0-9]{2})\x00([0-9a-f]{12})\x00"#)

    static func buildInfo(in data: Data) -> (commit: String, branch: String, builtAt: Date)? {
        var searchFrom = data.startIndex
        while let marker = data.range(of: platformMarker, in: searchFrom..<data.endIndex) {
            searchFrom = marker.upperBound - 1
            // `buildinfo.c` is globals, not adjacent literals: between the commit
            // and the branch sit alignment padding and the 8-byte
            // `build_commit_timestamp` (measured on all four builds). So the
            // branch is read as the string before the platform, and the stamped
            // commit is looked for in a short window before the branch.
            guard let branch = strings(endingAt: marker.lowerBound, in: data, count: 1).first,
                  !branch.isEmpty
            else { continue }
            let branchStart = marker.lowerBound - branch.utf8.count
            let windowStart = max(data.startIndex, branchStart - 96)
            guard let window = String(data: data[windowStart..<branchStart], encoding: .isoLatin1)
            else { continue }
            let ns = window as NSString
            guard let match = stampedCommit.matches(
                    in: window, range: NSRange(location: 0, length: ns.length)).last,
                  let builtAt = utcStamp.date(
                    from: ns.substring(with: match.range(at: 1)) + " " + ns.substring(with: match.range(at: 2)))
            else { continue }
            return (ns.substring(with: match.range(at: 3)), branch, builtAt)
        }
        return nil
    }

    private static let utcStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Up to `count` NUL-terminated strings whose terminators precede `end`
    /// (`end` is the index of the NUL that terminates the nearest one), nearest
    /// first. Stops at an empty or non-printable string: those are not C string
    /// literals, and reading across one would pair unrelated neighbours.
    private static func strings(endingAt end: Data.Index, in data: Data, count: Int) -> [String] {
        var result: [String] = []
        var terminator = end
        while result.count < count, terminator > data.startIndex {
            var start = terminator
            while start > data.startIndex, data[start - 1] != 0 { start -= 1 }
            guard start < terminator, terminator - start <= 256,
                  data[start..<terminator].allSatisfy({ $0 >= 0x20 && $0 < 0x7f }),
                  let text = String(data: data[start..<terminator], encoding: .ascii)
            else { break }
            result.append(text)
            terminator = start - 1
        }
        return result
    }
}
