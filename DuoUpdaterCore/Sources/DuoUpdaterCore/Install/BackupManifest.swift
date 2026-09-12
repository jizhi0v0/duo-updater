import CryptoKit
import Foundation

/// A digest of everything in a backed-up bundle, recorded when the backup is
/// taken and rechecked before it is restored.
///
/// It exists because the previous gate asked the wrong question. It required the
/// **vendor's** code signature to still validate, which is not a property of our
/// storage at all — and several real apps break their own seal by writing state
/// inside their bundle (ToDesk keeps an mmkv database and JSON under
/// `Contents/`; EasyConnect ships a socket). Those apps are already
/// signature-invalid where they sit in `/Applications`, so any faithful copy is
/// too, and the gate refused to restore a backup that was in fact a perfect copy
/// of what the user had been running.
///
/// What a gate on a *backup* should assert is "this is byte-for-byte what we
/// stored", and that is what this does. It does not, and cannot, say the app was
/// trustworthy when we copied it — that is the download-time signature check's
/// job, on the way in.
public struct BackupManifest: Codable, Equatable, Sendable {

    /// SHA-256 over a canonical rendering of the tree: one line per file, sorted
    /// by path, `relative/path\tsize\tsha256`. Sorting is what makes it stable —
    /// directory enumeration order is not guaranteed across filesystems.
    public let digest: String
    /// How many files it covers, so a mismatch can say whether the shape changed
    /// or only the contents.
    public let fileCount: Int

    /// Files a bundle contains that we cannot read, split by whether the code
    /// signature seals them.
    ///
    /// The split is what decides whether a backup is possible at all. An app
    /// that writes runtime state inside its own bundle leaves files the seal
    /// never covered — ToDesk's mmkv database and log caches, root-owned and
    /// unreadable — and omitting those still yields a bundle that runs; the app
    /// recreates them. A file the seal *does* cover is shipped payload
    /// (EasyConnect's setuid helpers), and a copy without it is a broken app, so
    /// there is nothing honest to store.
    ///
    /// "The seal covers it" is not the same as "`CodeResources` lists it": the
    /// bundle's own main executable, its `Info.plist` and the signature directory
    /// are sealed by the CodeDirectory's special slots instead and appear in no
    /// resource list. See ``directlySealedKeys(of:interior:fileManager:)``.
    public struct UnreadableFiles: Sendable {
        /// Relative to the bundle root, e.g. `Contents/mmkv.default`.
        public let sealed: [String]
        public let unsealed: [String]
        public var isEmpty: Bool { sealed.isEmpty && unsealed.isEmpty }
    }

    public static func unreadableFiles(in bundle: URL) -> UnreadableFiles {
        let fm = FileManager.default
        // nil means there was no seal to consult; then every unreadable file
        // counts as payload, because we cannot tell payload from droppings.
        let sealedPaths = sealedEntries(of: bundle)
        // Where this bundle keeps its interior — `Contents/` normally, but a
        // wrapped iPhone/iPad app has no `Contents/` at all and holds both its
        // plist and its seal under `Wrapper/<Inner>.app/`. Read from the bundle
        // rather than assumed, so the seal keys below line up with the walk.
        let interior = BundleLayout.interiorPrefix(for: bundle, fileManager: fm)
        let directlySealed = directlySealedKeys(of: bundle, interior: interior, fileManager: fm)
        let base = bundle.standardizedFileURL.path
        var sealed: [String] = []
        var unsealed: [String] = []
        guard let walker = fm.enumerator(
            at: bundle, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        else { return UnreadableFiles(sealed: [], unsealed: []) }
        for case let item as URL in walker {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true,
                  !fm.isReadableFile(atPath: item.path) else { continue }
            let relative = String(item.standardizedFileURL.path.dropFirst(base.count + 1))
            // `CodeResources` keys are relative to the bundle's interior, the
            // tree we walk is relative to the bundle root.
            let sealKey = relative.hasPrefix(interior)
                ? String(relative.dropFirst(interior.count)) : relative
            guard let sealedPaths else { sealed.append(relative); continue }
            if sealedPaths.contains(sealKey)
                || directlySealed.contains(sealKey)
                || sealKey.hasPrefix("_CodeSignature/") {
                sealed.append(relative)
            } else {
                unsealed.append(relative)
            }
        }
        return UnreadableFiles(sealed: sealed.sorted(), unsealed: unsealed.sorted())
    }

    /// Paths listed in the bundle's `_CodeSignature/CodeResources`, relative to
    /// `Contents/`, or **nil when there is no seal to read**. The distinction
    /// matters: an empty set would classify every unreadable file as droppings
    /// and quietly store a partial copy of an unsigned app, which is the
    /// opposite of the cautious reading.
    private static func sealedEntries(of bundle: URL) -> Set<String>? {
        let url = BundleLayout.codeResourcesURL(for: bundle)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        var out: Set<String> = []
        for key in ["files", "files2"] {
            if let entries = plist[key] as? [String: Any] { out.formUnion(entries.keys) }
        }
        return out
    }

    /// Paths the code signature seals **directly**, relative to the bundle's
    /// interior, rather than through the resource envelope — so they are sealed
    /// while being listed in no `CodeResources` dictionary.
    ///
    /// `files`/`files2` enumerate *resources*. The bundle's own `Info.plist` and
    /// main executable are hashed into the CodeDirectory (the plist into a special
    /// slot, the executable into the page hashes carrying the signature itself),
    /// and `_CodeSignature/` is the envelope, which cannot list itself. Measured
    /// 2026-09-13 on `/Applications/{Safari,Keka,DuoUpdater}.app`: `Info.plist`,
    /// `MacOS/<CFBundleExecutable>` and `_CodeSignature/CodeResources` are absent
    /// from both dictionaries in all three, and in a scratch `ditto` copy
    /// appending one byte to any of them makes `codesign --verify --deep --strict`
    /// exit 1 ("invalid Info.plist", a main-executable hash mismatch, "invalid
    /// resource directory"). Treating the omission as "unsealed" let `ditto` skip
    /// an unreadable main executable and had the manifest certify — and
    /// `.savedWithoutRuntimeState` report success for — a bundle that cannot run.
    ///
    /// `Contents/PkgInfo` is the counter-example that keeps this list from growing
    /// into "every top-level file": it is in neither place, and on the same two
    /// bundles mutating *and* deleting it left verification passing.
    ///
    /// An unreadable `Info.plist` costs us the executable's name, but it is itself
    /// in this set, so such a bundle is refused on that entry alone.
    private static func directlySealedKeys(
        of bundle: URL, interior: String, fileManager fm: FileManager
    ) -> Set<String> {
        var keys: Set<String> = ["Info.plist"]
        guard let data = try? Data(contentsOf: BundleLayout.infoPlistURL(
                for: bundle, fileManager: fm)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty
        else { return keys }
        // `Contents/MacOS/<exe>` in a normal bundle; a wrapped iPhone/iPad app has
        // a flat layout and keeps its executable at the interior root. Settled by
        // what is on disk rather than by which layout we think this is, the way
        // `BundleLayout` settles the interior itself.
        let interiorURL = bundle.appendingPathComponent(interior, isDirectory: true)
        let nested = "MacOS/" + executable
        keys.insert(
            fm.fileExists(atPath: interiorURL.appendingPathComponent(nested).path)
                ? nested : executable)
        return keys
    }

    /// Files present and readable in `source` but absent from `copy`, ignoring
    /// `expected`. Non-empty means the copy lost something we meant to keep, so
    /// the caller must not store it as a rollback point.
    ///
    /// Needed because `ditto` reports one exit status for the whole run: a copy
    /// that skipped only the runtime droppings and a copy that ran out of disk
    /// look identical from the outside.
    public static func unexpectedOmissions(
        source: URL, copy: URL, expected: [String]
    ) -> [String] {
        let fm = FileManager.default
        let base = source.standardizedFileURL.path
        let allowed = Set(expected)
        var missing: [String] = []
        guard let walker = fm.enumerator(
            at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        else { return ["<could not enumerate \(source.path)>"] }
        for case let item as URL in walker {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let relative = String(item.standardizedFileURL.path.dropFirst(base.count + 1))
            if allowed.contains(relative) { continue }
            // Unreadable and unexpected: we could not have copied it either, and
            // the classification above should have caught it.
            if !fm.isReadableFile(atPath: item.path) { missing.append(relative); continue }
            if !fm.fileExists(atPath: copy.appendingPathComponent(relative).path) {
                missing.append(relative)
            }
        }
        return missing
    }

    /// Compute the manifest for the bundle at `url`.
    ///
    /// Symlinks are recorded by their destination rather than followed: a bundle
    /// is full of them (`Versions/Current`), and following them would both
    /// double-count and, for an absolute link, hash something outside the
    /// bundle. Unreadable files make this return nil — a manifest that silently
    /// skipped them would certify a copy we never fully saw.
    public static func compute(for url: URL) -> BackupManifest? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [])
        else { return nil }

        let base = url.standardizedFileURL.path
        var lines: [String] = []
        for case let item as URL in walker {
            let values = try? item.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            let relative = String(item.standardizedFileURL.path.dropFirst(base.count))

            if values?.isSymbolicLink == true {
                let target = (try? fm.destinationOfSymbolicLink(atPath: item.path)) ?? ""
                lines.append("\(relative)\t->\t\(target)")
                continue
            }
            guard values?.isRegularFile == true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: item) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            // Streamed in chunks: a bundle can hold multi-hundred-megabyte
            // binaries, and reading one whole into memory to hash it is how a
            // backup of a large app turns into a memory spike.
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            lines.append("\(relative)\t\(values?.fileSize ?? 0)\t\(hex)")
        }

        lines.sort()
        var overall = SHA256()
        for line in lines { overall.update(data: Data(line.utf8)) }
        return BackupManifest(
            digest: overall.finalize().map { String(format: "%02x", $0) }.joined(),
            fileCount: lines.count)
    }
}
