import Testing
import Foundation
@testable import DuoUpdaterCore

/// `Task.sleep` throws `CancellationError` once its task is cancelled ("If the
/// task is canceled before the time ends, this function throws
/// CancellationError." — Apple, `Task.sleep(for:tolerance:clock:)`), and
/// `try? await Task.sleep(...)` swallows that. Inside a loop a cancelled task
/// then stops sleeping and spins. So every `try? await Task.sleep` under
/// `Install/` and `CLITools/` must be one of:
///
/// - (a) in a loop that checks `Task.isCancelled` on every pass;
/// - (b) inside an `InstallCommit.run` body, which no cancel reaches;
/// - (c) a one-shot pause, not in a loop;
/// - (d) bounded or detached, so a cancelled task cannot spin there.
///
/// The code cannot check which class a site is in. The site instead carries a
/// `// cancel-ok: <reason>` comment on the same line or the line above, stating
/// why it cannot spin. A site that does spin is not changed by this package; it
/// is listed in `pendingSpins` with its reason. Fixing it means deleting its
/// entry, and the stale-entry check fails when an entry no longer matches a live
/// offender.
///
/// A source scan, like `ReleaseDateParseScopeTests`: nothing in the language
/// stops a new `try? await Task.sleep` inside a loop.
struct NoSwallowedCancelSleepsTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .deletingLastPathComponent()   // repo root

    /// Directories under `DuoUpdaterCore/Sources/DuoUpdaterCore` the rule covers.
    private static let scannedDirectories = ["Install", "CLITools"]

    private static let sleepMarker = "try? await Task.sleep"
    private static let cancelOK = "// cancel-ok:"

    /// Known spins this package does not fix. `path` is relative to
    /// `DuoUpdaterCore/Sources/DuoUpdaterCore`; `line` is a substring of the
    /// offending line.
    private static let pendingSpins: [(path: String, line: String, reason: String)] = [
        (path: "CLITools/LorcaUpdater.swift",
         line: "try? await Task.sleep(for: pollInterval)",
         reason: "settle wait (up to 5 min) runs after the command's commit with no cancel check; a cancelled update keeps polling"),
    ]

    @Test func everySwallowedSleepIsCancelSafeOrPending() throws {
        let sourcesRoot = Self.repoRoot
            .appendingPathComponent("DuoUpdaterCore/Sources/DuoUpdaterCore")

        var sawAnySwiftFile = false
        var offenders: [String] = []
        var liveSpins = Set<Int>()   // indexes into pendingSpins that still match an offender

        for directory in Self.scannedDirectories {
            let root = sourcesRoot.appendingPathComponent(directory)
            let enumerator = try #require(
                FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
                Comment(rawValue:
                    "could not enumerate \(root.path) — repoRoot resolution is probably wrong"))

            for case let url as URL in enumerator {
                guard url.pathExtension == "swift" else { continue }
                sawAnySwiftFile = true
                let relativePath = url.path.replacingOccurrences(
                    of: sourcesRoot.path + "/", with: "")
                let lines = try String(contentsOf: url, encoding: .utf8)
                    .components(separatedBy: "\n")

                for (index, line) in lines.enumerated() where line.contains(Self.sleepMarker) {
                    let above = index > 0 ? lines[index - 1] : ""
                    if line.contains(Self.cancelOK) || above.contains(Self.cancelOK) { continue }
                    if let entry = Self.pendingSpins.indices.first(where: {
                        Self.pendingSpins[$0].path == relativePath
                            && line.contains(Self.pendingSpins[$0].line)
                    }) {
                        liveSpins.insert(entry)
                        continue
                    }
                    offenders.append(
                        "\(relativePath):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        let stale = Self.pendingSpins.indices
            .filter { !liveSpins.contains($0) }
            .map { "\(Self.pendingSpins[$0].path): \"\(Self.pendingSpins[$0].line)\"" }

        // A guard that scanned zero files would pass for the wrong reason — the
        // same trap `ReleaseDateParseScopeTests` guards against.
        #expect(sawAnySwiftFile,
            Comment(rawValue: "scanned zero .swift files under \(sourcesRoot.path)"))
        #expect(offenders.isEmpty,
            Comment(rawValue:
                "try? await Task.sleep swallows cancellation: add `// cancel-ok: <reason>` on the "
                    + "same line or the line above if the site cannot spin, or fix it. Offenders: "
                    + offenders.joined(separator: "; ")))
        #expect(stale.isEmpty,
            Comment(rawValue:
                "pendingSpins entries that no longer match a live offender (fixed? then remove "
                    + "them from the list): " + stale.joined(separator: "; ")))
    }
}
