import Testing
import Foundation
@testable import DuoUpdaterCore

/// #300: "day precision never reaches `publishedAt`" used to hold only for
/// `SparkleAppcastSource` — the other four sources that read a vendor
/// timestamp (`AlcoveUpdateSource`, `ElectronManifestSource`,
/// `GitHubReleasesSource`, `VendorProbeSource`) called `ReleaseDate.parse`
/// directly, which has no `vendorDay` tier at all to protect. That made the
/// invariant true by convention, not by construction: nothing stopped a sixth
/// caller from doing the same thing.
///
/// After #300 every one of those sources — and any future one — must go
/// through `ReleaseDate.publishedFields(from:)` (or `parseWithPrecision`
/// directly), the one place the day/minute split happens. This test pins that
/// down at the source level rather than trusting it stays true: it scans every
/// `.swift` file under `DuoUpdaterCore/Sources` for a direct call to
/// `ReleaseDate.parse(` — `Releases/ReleaseDate.swift` itself, where `parse` is
/// declared, is the only file allowed to contain that spelling.
///
/// **Why a source scan, not just relying on `parse` being `internal`.** Access
/// control blocks a caller in `CLI`/`App` (separate modules, `parse` isn't
/// `public`), but `DuoUpdaterCore` is one target — nothing in the language
/// stops a new file inside it from calling `parse` directly. `ReleaseDateTests.
/// swift` legitimately calls `parse` dozens of times to pin the formatter
/// internals `parseWithPrecision` shares with it, so this cannot be "no call to
/// `parse` anywhere in the module" — it has to be scoped to *production*
/// sources, which is what the `Sources/` subdirectory (as opposed to `Tests/`)
/// picks out.
///
/// Mutation-tested by hand (see the PR description): temporarily reverting one
/// of the five converted call sites back to `ReleaseDate.parse(...)` turns this
/// red, naming the offending file.
struct ReleaseDateParseScopeTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .deletingLastPathComponent()   // repo root

    /// The one file allowed to spell `ReleaseDate.parse(` — where it's declared.
    private static let allowedFile = "Releases/ReleaseDate.swift"

    @Test func noProductionSourceCallsReleaseDateParseDirectly() throws {
        let sourcesRoot = Self.repoRoot
            .appendingPathComponent("DuoUpdaterCore/Sources/DuoUpdaterCore")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil),
            Comment(rawValue:
                "could not enumerate \(sourcesRoot.path) — repoRoot resolution is probably wrong"))

        var offenders: [String] = []
        var sawAnySwiftFile = false
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            sawAnySwiftFile = true
            let relativePath = url.path.replacingOccurrences(
                of: sourcesRoot.path + "/", with: "")
            guard relativePath != Self.allowedFile else { continue }

            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("ReleaseDate.parse(") {
                offenders.append(relativePath)
            }
        }

        // A guard that silently scanned zero files would pass for the wrong
        // reason — same shape as the empty-fixture traps this repo has hit
        // before (see CLAUDE.md's fixture-distribution warning).
        #expect(sawAnySwiftFile,
            Comment(rawValue: "scanned zero .swift files under \(sourcesRoot.path)"))
        #expect(offenders.isEmpty,
            Comment(rawValue:
                "these production files call ReleaseDate.parse(...) directly instead of "
                    + "publishedFields(from:)/parseWithPrecision(_:), so a day-only vendor "
                    + "date they capture would silently reach publishedAt as a fabricated "
                    + "midnight: \(offenders.sorted().joined(separator: ", "))"))
    }
}
