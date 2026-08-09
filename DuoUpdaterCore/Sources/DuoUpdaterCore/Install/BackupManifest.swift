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
