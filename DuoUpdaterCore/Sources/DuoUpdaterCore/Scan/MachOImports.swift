import Foundation

/// The shared libraries a Mach-O executable links against, read from its load
/// commands.
///
/// This exists because a bundle's *layout* can only answer half of "what is this
/// app built with". `Contents/Frameworks/Electron Framework.framework` is a fact
/// on disk; "this is an AppKit app" is not — nothing in the directory tree says
/// so. The load commands do, and they are the linker's own record rather than
/// anything we infer.
///
/// Only the header region is read: the Mach-O header names how many bytes of load
/// commands follow (`sizeofcmds`), and that is all we fetch. A `FileHandle` is
/// used rather than `Data(contentsOf:.mappedIfSafe)` on purpose — "ifSafe" is
/// allowed to fall back to reading the whole file, and app executables here run to
/// hundreds of megabytes (Warp is 795 MB, Zed 403 MB). Two bounded reads cost the
/// same for those as for a 200 KB launcher.
///
/// Anything unexpected — a big-endian image, a truncated header, a load-command
/// region larger than `maxLoadCommandBytes` — returns nil rather than a partial
/// answer, so a caller can distinguish "links nothing we recognize" (empty set)
/// from "could not read" (nil) and fail closed.
public enum MachOImports {

    /// Mach-O magics as they read when the first four bytes are loaded in host
    /// (little-endian) order. `fat` and `fat64` look byte-swapped because a fat
    /// header is stored big-endian on disk.
    private enum Magic {
        static let macho64: UInt32 = 0xfeed_facf
        static let macho32: UInt32 = 0xfeed_face
        static let fat: UInt32 = 0xbeba_feca
        static let fat64: UInt32 = 0xbfba_feca
    }

    /// The four load commands that name a linked dylib. `LC_REQ_DYLD` (0x8000_0000)
    /// is set on the weak/reexport/upward variants.
    private enum LoadCommand {
        static let loadDylib: UInt32 = 0x0000_000c
        static let loadWeakDylib: UInt32 = 0x8000_0018
        static let reexportDylib: UInt32 = 0x8000_001f
        static let loadUpwardDylib: UInt32 = 0x8000_0023

        static func namesADylib(_ cmd: UInt32) -> Bool {
            cmd == loadDylib || cmd == loadWeakDylib || cmd == reexportDylib || cmd == loadUpwardDylib
        }
    }

    /// `CPU_TYPE_ARM64` — the slice we prefer inside a universal binary. DuoUpdater
    /// is arm64-only (see `App/project.yml`), so this is also the slice that would
    /// actually run here; the linked-library list is the same in every slice of a
    /// normally-built universal binary, so the preference only decides which one we
    /// pay to parse.
    private static let cpuTypeARM64: UInt32 = 0x0100_000c

    /// Refuse to read a load-command region larger than this. Real ones are a few
    /// kilobytes; a larger value means the header is corrupt or we are not looking
    /// at a Mach-O at all, and the only sane response is "cannot read".
    private static let maxLoadCommandBytes: UInt32 = 2 * 1024 * 1024

    /// The dylib install names the image at `url` links against — e.g.
    /// `/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit`,
    /// `@rpath/Sparkle.framework/Versions/B/Sparkle`.
    ///
    /// Returns nil when the file cannot be read as a Mach-O image at all.
    public static func linkedLibraries(at url: URL) -> Set<String>? {
        loadedDylibs(at: url).map { Set($0.keys) }
    }

    /// The same list with each entry's `current_version` — the version the linker
    /// recorded for the library that was linked against, which is often the only
    /// place a bundled toolkit's version survives. Qt is the case in hand: apps
    /// that ship it as frameworks carry a readable `Info.plist`, apps that ship it
    /// as `libQt6Core.6.dylib` do not, and both record `5.15.2` here.
    public static func loadedDylibs(at url: URL) -> [String: String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = read32(handle, at: 0, bigEndian: false) else { return nil }

        switch magic {
        case Magic.macho64, Magic.macho32:
            return imports(handle, sliceOffset: 0, is64Bit: magic == Magic.macho64)
        case Magic.fat, Magic.fat64:
            guard let offset = preferredSliceOffset(handle, is64BitTable: magic == Magic.fat64),
                  let sliceMagic = read32(handle, at: offset, bigEndian: false),
                  sliceMagic == Magic.macho64 || sliceMagic == Magic.macho32
            else { return nil }
            return imports(handle, sliceOffset: offset, is64Bit: sliceMagic == Magic.macho64)
        default:
            // Big-endian images (PowerPC-era) and anything that is not a Mach-O.
            return nil
        }
    }

    /// Whether `libraries` contains a link against the framework named `name`.
    /// Matches on the `<name>.framework/` path component, which is stable across
    /// the `@rpath` / absolute / versioned spellings an install name can take.
    public static func links(_ libraries: Set<String>, framework name: String) -> Bool {
        libraries.contains { $0.contains("/\(name).framework/") }
    }

    // MARK: - Fat header

    /// Byte offset of the slice to parse: arm64 when present, otherwise the first.
    private static func preferredSliceOffset(_ handle: FileHandle, is64BitTable: Bool) -> UInt64? {
        guard let count = read32(handle, at: 4, bigEndian: true), count > 0, count < 64 else { return nil }
        let entrySize: UInt64 = is64BitTable ? 32 : 20
        var first: UInt64?
        for index in 0..<UInt64(count) {
            let base = 8 + index * entrySize
            guard let cpuType = read32(handle, at: base, bigEndian: true) else { return nil }
            let offset: UInt64?
            if is64BitTable {
                offset = read64(handle, at: base + 8, bigEndian: true)
            } else {
                offset = read32(handle, at: base + 8, bigEndian: true).map(UInt64.init)
            }
            guard let offset else { return nil }
            if first == nil { first = offset }
            if cpuType == cpuTypeARM64 { return offset }
        }
        return first
    }

    // MARK: - Load commands

    private static func imports(_ handle: FileHandle, sliceOffset: UInt64, is64Bit: Bool) -> [String: String]? {
        // mach_header: magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds,
        // flags — plus a `reserved` word in the 64-bit variant, which is why the
        // commands start 4 bytes later there.
        let headerSize: UInt64 = is64Bit ? 32 : 28
        guard let commandCount = read32(handle, at: sliceOffset + 16, bigEndian: false),
              let commandBytes = read32(handle, at: sliceOffset + 20, bigEndian: false),
              commandBytes > 0, commandBytes <= maxLoadCommandBytes
        else { return nil }

        guard let region = read(handle, at: sliceOffset + headerSize, count: Int(commandBytes)),
              region.count == Int(commandBytes)
        else { return nil }

        var names: [String: String] = [:]
        var cursor = 0
        for _ in 0..<commandCount {
            guard cursor + 8 <= region.count,
                  let cmd = region.u32(at: cursor),
                  let size = region.u32(at: cursor + 4)
            else { return nil }
            // A zero or unaligned size would loop forever or walk off the end; a
            // header claiming either is not one we can trust the rest of.
            guard size >= 8, size % 4 == 0, cursor + Int(size) <= region.count else { return nil }

            if LoadCommand.namesADylib(cmd), let nameOffset = region.u32(at: cursor + 8) {
                // `dylib.name` is a `lc_str` union: an offset from the start of the
                // command to a NUL-terminated string that runs to the command's end.
                let start = cursor + Int(nameOffset)
                let end = cursor + Int(size)
                if nameOffset >= 8, start < end, let name = region.cString(from: start, upTo: end) {
                    // dylib_command: cmd, cmdsize, name.offset, timestamp,
                    // current_version, compatibility_version — the version is a
                    // packed X.Y.Z, one byte each for Y and Z.
                    let packed = region.u32(at: cursor + 16) ?? 0
                    names[name] = "\(packed >> 16).\((packed >> 8) & 0xff).\(packed & 0xff)"
                }
            }
            cursor += Int(size)
        }
        return names
    }

    // MARK: - Bounded reads

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    private static func read32(_ handle: FileHandle, at offset: UInt64, bigEndian: Bool) -> UInt32? {
        guard let data = read(handle, at: offset, count: 4), data.count == 4 else { return nil }
        let value = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return bigEndian ? value.bigEndian : value.littleEndian
    }

    private static func read64(_ handle: FileHandle, at offset: UInt64, bigEndian: Bool) -> UInt64? {
        guard let data = read(handle, at: offset, count: 8), data.count == 8 else { return nil }
        let value = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return bigEndian ? value.bigEndian : value.littleEndian
    }
}

private extension Data {
    /// Little-endian word at a byte offset, bounds-checked. `Data` read from a
    /// `FileHandle` is always zero-indexed, but the subscript arithmetic is written
    /// against `startIndex` anyway so a sliced value could not silently misread.
    func u32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let start = index(startIndex, offsetBy: offset)
        return self[start..<index(start, offsetBy: 4)].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    /// NUL-terminated string starting at `offset`, never reading past `limit`.
    /// An unterminated run to `limit` is still a valid `lc_str` — the pad bytes at
    /// the end of the command are the terminator.
    func cString(from offset: Int, upTo limit: Int) -> String? {
        guard offset >= 0, offset < limit, limit <= count else { return nil }
        let start = index(startIndex, offsetBy: offset)
        let end = index(startIndex, offsetBy: limit)
        let bytes = self[start..<end].prefix { $0 != 0 }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}
