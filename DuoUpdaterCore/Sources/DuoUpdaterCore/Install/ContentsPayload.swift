import Foundation

/// Assembles a `.app` out of a vendor update package that ships a **bare
/// `Contents` directory** rather than a bundle.
///
/// SogouInput is the shape in hand (measured on 6.25.1.11973, 2026-09-20). Its
/// self-update archive is a zip of scripts wrapped around a second zip:
///
///     autosetup6.25.1.11973_V10003_20260914_150515.zip
///     ├── Contents6.25.1.11973.zip   → unpacks to `Contents6.25.1.11973/`
///     ├── pre.sh
///     ├── post.sh
///     └── switch.sh
///
/// There is no `.app` anywhere in it, at either level, so `ArchiveExtractor`
/// alone answers `noAppFound`: what the vendor ships is the *inside* of the
/// bundle, because its own updater rotates `Contents` and never replaces the
/// outer directory. `InPlaceSwap.rotateContents` is the same operation from our
/// side and wants exactly this directory — but every gate between here and there
/// reads a bundle, so the directory is given one to sit in first.
///
/// **The assembled bundle is a real one, and that is the point.** Renaming
/// `Contents6.25.1.11973` to `Contents` inside a directory named after the
/// installed app produces a bundle that `codesign --verify --deep --strict`
/// accepts and `spctl` reports as `Notarized Developer ID`, Team `DFD88F82SU`,
/// id `com.sogou.inputmethod.sogou` — measured on the 6.25 payload before this
/// was written. Nothing here weakens a gate; it gives gates 2–6 something they
/// can read.
///
/// **What is deliberately NOT run: the vendor's three scripts.** Each was read
/// off the real 6.25 package, and `docs/app-audits/com-sogou-inputmethod-sogou.md`
/// has them in full:
///
///   * `pre.sh` only acts when the bundle is NOT writable, where it asks for
///     admin and chowns it back to `root:staff`. `InPlaceSwap.stageRotation`
///     refuses that same case up front, with a sentence instead of a password
///     panel, so on every install this path can reach, `pre.sh` is a no-op.
///   * `post.sh` is wrapped entirely in
///     `if [ $SOGOU_INPUT_VERSION == "3.2.0.68597" ]` — a repair for one 2019
///     build, dead code on anything modern.
///   * `switch.sh` is the one with teeth, and the tooth is argument-gated: called
///     with `1` it runs `rm -rf ~/Library/Application Support/Sogou/InputMethod`
///     — the learned dictionary — before moving an older location over it. It
///     also ends in `killall -KILL SystemUIServer`. Neither is something this app
///     does to anybody, and the migration it performs is a first-install concern.
///
/// What the vendor's own update does NOT do is equally load-bearing, because an
/// earlier reading of this app had it the other way round: the self-update
/// package installs no LaunchAgents, registers no QuickLook generator, and
/// touches nothing outside the bundle except through `switch.sh` above. Those
/// belong to the website *installer*. Rotating `Contents` leaves nothing of the
/// update undone.
///
/// The one thing that does go is the `SGQuDao` channel key: the installed copy's
/// `Info.plist` carries `SGQuDao = 1111` and the payload's does not, and no
/// script in the package puts it back. So the vendor's own update drops it too —
/// this is parity, not damage — and re-injecting it would be actively wrong,
/// since `Info.plist` is sealed by the code directory and writing to it would
/// invalidate a signature that has just been verified.
enum ContentsPayload {

    enum PayloadError: LocalizedError {
        /// The outer archive does not hold exactly one member matching the
        /// pattern. Carries the detail: the fix is a recipe edit, and what was
        /// found instead is the whole diagnosis.
        case innerArchive(String)
        /// The inner archive does not hold exactly one usable `Contents…`
        /// directory.
        case contents(String)
        case assemblyFailed(String)

        var errorDescription: String? {
            switch self {
            case .innerArchive(let detail):
                return "The update package is not shaped the way this app's recipe describes: \(detail)"
            case .contents(let detail):
                return "The update package did not contain a replacement bundle: \(detail)"
            case .assemblyFailed(let detail):
                return "The update package could not be prepared for installation: \(detail)"
            }
        }
    }

    /// Unpack `outerArchive`, find the inner archive matching `innerArchivePattern`,
    /// unpack that, and return a `<bundleName>.app` whose `Contents` is the
    /// directory it held.
    ///
    /// - Parameter bundleName: the INSTALLED bundle's name without `.app`. Taken
    ///   from the installed copy rather than from anything in the archive: the
    ///   name is what `rotateContents` is about to write inside, and an archive
    ///   does not get to choose it. (It has no effect on the gates, which read
    ///   the bundle id and the signature, but a wrong name here would make the
    ///   log lines name an app that does not exist.)
    static func assemble(
        outerArchive: URL, innerArchivePattern: String, bundleName: String, workDir: URL
    ) async throws -> URL {
        let fm = FileManager.default
        let root = workDir.appendingPathComponent("contents-payload", isDirectory: true)
        // Its own scratch directory under the caller's, for the reason
        // `unwrapNestedPayload` takes one: two extractions that share a directory
        // have to choose between each other's output.
        try? fm.removeItem(at: root)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let outer = root.appendingPathComponent("outer", isDirectory: true)
        try fm.createDirectory(at: outer, withIntermediateDirectories: true)
        try await ArchiveExtractor.unpack(outerArchive, into: outer)

        // The outer archive legitimately holds the vendor's scripts beside the
        // payload, so only the MATCH has to be unique here — see `exclusive`.
        let innerArchive = try soleMember(
            in: outer, matching: innerArchivePattern, directory: false, exclusive: false,
            describe: PayloadError.innerArchive)

        let inner = root.appendingPathComponent("inner", isDirectory: true)
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try await ArchiveExtractor.unpack(innerArchive, into: inner)

        // `Contents` optionally followed by the version, which is how the vendor
        // names it (`Contents6.25.1.11973`). Anchored, and digits-and-dots only:
        // the directory about to become a bundle's interior must not be chosen by
        // a prefix match that `Contents.evil` would also satisfy.
        let contents = try soleMember(
            in: inner, matching: #"^Contents[0-9.]*$"#, directory: true, exclusive: true,
            describe: PayloadError.contents)

        let assembled = root.appendingPathComponent("\(bundleName).app", isDirectory: true)
        do {
            try fm.createDirectory(at: assembled, withIntermediateDirectories: true)
            try fm.moveItem(at: contents, to: assembled.appendingPathComponent("Contents"))
        } catch {
            throw PayloadError.assemblyFailed(error.localizedDescription)
        }
        return assembled
    }

    /// The one top-level entry of `dir` whose name matches `pattern` — refusing
    /// both "none" and "more than one", and refusing anything that is not a plain
    /// file (or directory) living inside `dir`.
    ///
    /// Strictness is the whole job. Everything downstream treats what comes back
    /// as "the update", and the archive it came out of is unsigned at both levels
    /// — unlike the installer stub `nestedArchivePath` unwraps, there is no
    /// vendor signature over these bytes to check BEFORE opening them. The trust
    /// still comes from gates 2–6 running on the assembled bundle, exactly as it
    /// ultimately does for the stub; what this adds is that an archive carrying
    /// two candidates, or a symlink named like one, is refused rather than
    /// silently resolved by picking one.
    ///
    /// `__MACOSX` and dot-files are ignored before counting: a zip built on a Mac
    /// can carry the former beside the real member, and refusing over it would be
    /// a refusal about nothing.
    ///
    /// - Parameter exclusive: also require the match to be the archive's ONLY
    ///   entry. True for the inner archive, which carries the replacement
    ///   bundle's interior and must carry nothing else; false for the outer one,
    ///   where the vendor's `pre.sh`/`post.sh`/`switch.sh` are expected company.
    private static func soleMember(
        in dir: URL, matching pattern: String, directory: Bool, exclusive: Bool,
        describe: (String) -> PayloadError
    ) throws -> URL {
        let fm = FileManager.default
        let base = dir.resolvingSymlinksInPath().standardizedFileURL.path
        let entries = ((try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.lastPathComponent != "__MACOSX" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let regex = try NSRegularExpression(pattern: pattern)
        let matches = entries.filter { entry in
            let name = entry.lastPathComponent
            return regex.firstMatch(
                in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
        guard matches.count == 1, let member = matches.first else {
            let found = entries.isEmpty
                ? "it is empty"
                : "it holds \(entries.map(\.lastPathComponent).joined(separator: ", "))"
            throw describe(
                matches.isEmpty
                    ? "nothing in it matches \(pattern) — \(found)."
                    : "\(matches.count) entries match \(pattern): "
                        + "\(matches.map(\.lastPathComponent).joined(separator: ", ")).")
        }
        let values = try? member.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true else {
            throw describe("“\(member.lastPathComponent)” is a symbolic link.")
        }
        guard values?.isDirectory == directory else {
            throw describe(
                "“\(member.lastPathComponent)” is \(directory ? "not a directory" : "a directory").")
        }
        // A backstop, and knowingly kept as one: the only way an entry can resolve
        // outside the directory it was extracted into is by being a link, and the
        // guard above has already refused those — no mutation of this line makes
        // a test fail. It stays because the alternative is trusting that
        // `ditto -x -k` never writes a member outside its destination, which is a
        // statement about another program two steps upstream of a swap into
        // `/Library/Input Methods`.
        let resolved = member.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(base + "/") else {
            throw describe("“\(member.lastPathComponent)” resolves outside the archive.")
        }
        // Counted after the filters, so `__MACOSX` is not what trips it.
        guard !exclusive || entries.count == 1 else {
            throw describe(
                "it holds \(entries.count) entries and should hold one: "
                + entries.map(\.lastPathComponent).joined(separator: ", ") + ".")
        }
        return member
    }
}
