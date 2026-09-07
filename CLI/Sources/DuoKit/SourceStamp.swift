import Foundation
import CryptoKit

/// Whether the `duo` binary now running was built from the checkout it is standing in.
///
/// `duo verify` sweeps the recipes, and the recipes are **compiled into the binary**.
/// The binary on PATH (`~/.local/bin/duo` → `~/.local/libexec/duo`) is not the working
/// tree, so a sweep can report a full, normal-looking result — scores, pass/warn/fail,
/// captured response bodies — for rules that were replaced hours ago. Nothing in the
/// output says which rules it used.
///
/// That has cost real time twice, in two different directions, which is why the check
/// here is on content rather than on timestamps:
///
///  - **Binary older than the tree.** 2026-08-26, verifying before 0.3.64: one red and
///    one amber, both false, both already fixed in the tree — and the app the release
///    was *for* had no recipe in that binary at all, so "246 green" had never looked at
///    it. A modification-time check would have caught this one.
///  - **Binary newer than the tree, and from somewhere else.** 2026-08-27: `duo verify
///    --only canva` passed, then the same command answered "nothing to verify — no
///    recipe matches canva" with no source change in between. `~/.local` is global and
///    this repository usually has a dozen worktrees open; a concurrent session's `make
///    cli` had replaced the binary with one built from a tree that had no Canva recipe.
///    A modification-time check calls that binary fresh and lets it through.
///
/// So the stamp is a digest of the sources the binary was built from, written beside it
/// by `scripts/build-cli.sh` and compared against a digest of the checkout `duo verify`
/// is run in. Both digests come from `digest(ofCheckoutAt:)` below — the build script
/// asks the freshly built binary for its own, rather than reimplementing the hash in
/// shell where the two could drift apart.
///
/// Outside a checkout there is nothing to compare against and the check says so and
/// stands down: `duo verify` from an arbitrary directory is a legitimate thing to do.
public enum SourceStamp {

    /// Everything `duo` is compiled from. `App/Sources` is deliberately absent: the CLI
    /// does not link it, so an app-only edit does not make this binary wrong.
    static let sourceRoots = ["DuoUpdaterCore/Sources", "CLI/Sources"]

    /// A floor, in the spirit of `check_prose_claims.py`'s: a digest computed over a
    /// handful of files would be a check that passes because it looked at almost
    /// nothing, and it would agree with itself on both sides while doing it. Set well
    /// under the real count (188 on 2026-09-07) so ordinary growth never trips it —
    /// this is here to catch a moved or renamed source root, not to count files.
    static let minimumFiles = 100

    /// Name chosen to be read, not parsed: it sits next to the binary in
    /// `~/.local/libexec/` and answers the question someone standing there is asking.
    static let stampSuffix = ".built-from"

    public enum Verdict: Sendable, Equatable {
        /// Not run from a checkout, so there is nothing this could be stale against.
        case notApplicable
        case matches
        /// Built from different sources than the ones here — or from none we can name.
        case stale(String)
    }

    // MARK: - Digest

    public enum StampError: Error, CustomStringConvertible {
        case tooFewFiles(Int)
        public var description: String {
            switch self {
            case .tooFewFiles(let n):
                return "only \(n) Swift files under \(SourceStamp.sourceRoots.joined(separator: ", "))"
                     + " — expected at least \(SourceStamp.minimumFiles), so the source roots have moved"
            }
        }
    }

    /// A digest of every Swift file under `sourceRoots`, by content.
    ///
    /// Content, not modification time. Timestamps move whenever git rewrites a file —
    /// `git checkout` of a branch with the same sources gives every one of them a new
    /// mtime — so a timestamp check reports stale builds that are in fact correct, and
    /// people who are told that learn to pass the override. It also misses the second
    /// incident above outright, where the wrong binary was the newer one.
    ///
    /// The path is hashed alongside the bytes, and the length alongside both: without
    /// the path a file rename is invisible, and without the length two files could be
    /// re-split at a different boundary for the same digest.
    public static func digest(ofCheckoutAt root: URL) throws -> String {
        var files: [(String, URL)] = []
        for relative in sourceRoots {
            let base = root.appendingPathComponent(relative)
            guard let walk = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.pathExtension == "swift" {
                let path = url.standardizedFileURL.path
                let rootPath = root.standardizedFileURL.path
                files.append((String(path.dropFirst(rootPath.count)), url))
            }
        }
        guard files.count >= minimumFiles else { throw StampError.tooFewFiles(files.count) }

        var hasher = SHA256()
        // Sorted, because `enumerator` makes no ordering promise and a digest that
        // depends on directory order would differ between two identical checkouts.
        for (relative, url) in files.sorted(by: { $0.0 < $1.0 }) {
            let bytes = try Data(contentsOf: url)
            hasher.update(data: Data("\(relative)\n\(bytes.count)\n".utf8))
            hasher.update(data: bytes)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Locating the two sides

    /// The checkout `cwd` sits in, if it sits in one.
    ///
    /// Identified by carrying every source root, not by `.git`: a worktree's `.git` is a
    /// file pointing elsewhere, and a checkout missing a source root is not one this can
    /// compare against anyway.
    public static func checkoutRoot(
        from cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        var directory = cwd.standardizedFileURL
        while true {
            let complete = sourceRoots.allSatisfy {
                var isDirectory: ObjCBool = false
                let path = directory.appendingPathComponent($0).path
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            if complete { return directory }
            // `.standardizedFileURL` is what makes this terminate, and without it the
            // failure is a hang, not a wrong answer.
            //
            // Measured 2026-09-07: whether `deletingLastPathComponent()` stops at `/`
            // depends on how the URL was built. Descend from
            // `URL(fileURLWithPath:)` — what `checkoutRoot` does by default, from
            // `currentDirectoryPath` — and `/` is its own parent, so the plain
            // comparison fires. Descend from `FileManager.default.temporaryDirectory`
            // and it does not: `/` becomes `/..`, then `/../..`, and the loop climbs
            // forever at 99% CPU. So production was safe only by accident of one
            // constructor, and `aPartialTreeIsNotACheckout` — which starts in the
            // temporary directory, as any caller might — hung until this line existed.
            // Standardizing collapses `/..` back to `/`, and the path then strictly
            // shortens every turn.
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    /// The file `build-cli.sh` wrote beside the binary that is running.
    ///
    /// Resolved through the symlink on purpose. `~/.local/bin/duo` is a link to
    /// `~/.local/libexec/duo` and the stamp lives beside the real file; measured
    /// 2026-09-07, `Bundle.main.executableURL` returns the link path and
    /// `resolvingSymlinksInPath()` the target. `CommandLine.arguments[0]` is not usable
    /// for this — invoked through PATH it is the bare word `duo`.
    public static var stampURL: URL? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath()
        else { return nil }
        return executable.deletingLastPathComponent()
            .appendingPathComponent(executable.lastPathComponent + stampSuffix)
    }

    // MARK: - The check

    public static func verdict(
        root: URL? = checkoutRoot(), stamp: URL? = stampURL
    ) -> Verdict {
        guard let root else { return .notApplicable }
        let here: String
        do { here = try digest(ofCheckoutAt: root) } catch {
            return .stale("this checkout cannot be digested: \(error)")
        }
        guard let stamp, let recorded = try? String(contentsOf: stamp, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !recorded.isEmpty
        else {
            return .stale("""
                this `duo` carries no record of what it was built from, so whether its \
                recipes match \(root.path) cannot be established
                """)
        }
        guard recorded == here else {
            return .stale("""
                this `duo` was built from different sources than \(root.path) \
                (built \(recorded.prefix(12))…, here \(here.prefix(12))…)
                """)
        }
        return .matches
    }

    /// Print the digest of the checkout this is run in, for `scripts/build-cli.sh` to
    /// store beside the binary it just installed. The build script asks the new binary
    /// rather than hashing in shell so that there is exactly one definition of the
    /// digest, and the writer and the reader cannot drift apart.
    public static func printDigest() -> Int32 {
        guard let root = checkoutRoot() else {
            FileHandle.standardError.write(Data(
                "not inside a checkout: no DuoUpdaterCore/Sources and CLI/Sources above \(FileManager.default.currentDirectoryPath)\n".utf8))
            return 2
        }
        do { print(try digest(ofCheckoutAt: root)) } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return 2
        }
        return 0
    }

    /// The whole point, phrased for someone who is about to spend three minutes and
    /// ~150 requests on an answer that would be about the wrong rules.
    public static func complaint(_ reason: String) -> String {
        """
        stale `duo`: \(reason).

          The recipes are compiled in, so this sweep would report on the rules in the
          binary, not the ones in your tree — and it would look completely normal doing
          it. Rebuild first:

              make cli

          Pass --allow-stale-binary to sweep anyway, once you know that is what you want.
        """
    }
}
