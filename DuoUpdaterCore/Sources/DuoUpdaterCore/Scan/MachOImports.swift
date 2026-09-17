import Foundation

/// The shared libraries a Mach-O executable links against, read from its load
/// commands — and, from the same pass, the SDK it was linked against (`BuildSDK`).
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

        /// `build_version_command`: platform, minos, sdk, ntools.
        static let buildVersion: UInt32 = 0x0000_0032
        /// `version_min_command`: version, sdk. The older form, which a binary
        /// linked before `LC_BUILD_VERSION` existed carries instead — WeLink 7.53.9's
        /// main executable, checked 2026-09-15, is one.
        static let versionMinMacOSX: UInt32 = 0x0000_0024
        static let versionMinIPhoneOS: UInt32 = 0x0000_0025
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
        loadCommands(at: url)?.dylibs
    }

    /// The SDK the image at `url` was linked against. Nil when the file cannot be
    /// read as a Mach-O image, and also when it can but records no SDK — see
    /// `BuildSDK` for the one shape that does that.
    public static func buildSDK(at url: URL) -> BuildSDK? {
        loadCommands(at: url)?.buildSDK
    }

    /// Everything this reader takes out of one image's load commands, from one
    /// pass over them. The scan asks for both halves of every app, and the two
    /// accessors above each pay for the open and the two bounded reads.
    public struct LoadCommands: Sendable, Equatable {
        /// Install name → packed `current_version`, as `loadedDylibs(at:)`.
        public let dylibs: [String: String]
        public let buildSDK: BuildSDK?
    }

    public static func loadCommands(at url: URL) -> LoadCommands? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = read32(handle, at: 0, bigEndian: false) else { return nil }

        switch magic {
        case Magic.macho64, Magic.macho32:
            return commands(handle, sliceOffset: 0, is64Bit: magic == Magic.macho64)
        case Magic.fat, Magic.fat64:
            guard let offset = preferredSliceOffset(handle, is64BitTable: magic == Magic.fat64),
                  let sliceMagic = read32(handle, at: offset, bigEndian: false),
                  sliceMagic == Magic.macho64 || sliceMagic == Magic.macho32
            else { return nil }
            return commands(handle, sliceOffset: offset, is64Bit: sliceMagic == Magic.macho64)
        default:
            // Big-endian images (PowerPC-era) and anything that is not a Mach-O.
            return nil
        }
    }

    /// Every slice's architecture, in the order the image stores them — e.g.
    /// `["x86_64", "arm64"]` for a universal binary. `Bundle.executableArchitectures`
    /// answers this for a bundle's main executable only; `duo diff` asks it of every
    /// Mach-O file in a release, helpers and dylibs included.
    ///
    /// Header reads only, like the rest of this type. Nil when the file is not a
    /// little-endian Mach-O image or a fat file of them.
    public static func architectures(at url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = read32(handle, at: 0, bigEndian: false) else { return nil }

        func sliceName(at offset: UInt64) -> String? {
            guard let sliceMagic = read32(handle, at: offset, bigEndian: false),
                  sliceMagic == Magic.macho64 || sliceMagic == Magic.macho32,
                  let cpuType = read32(handle, at: offset + 4, bigEndian: false),
                  let subtype = read32(handle, at: offset + 8, bigEndian: false)
            else { return nil }
            return architectureName(cpuType: cpuType, subtype: subtype & 0x00ff_ffff)
        }

        switch magic {
        case Magic.macho64, Magic.macho32:
            return sliceName(at: 0).map { [$0] }
        case Magic.fat, Magic.fat64:
            // Java class files share the fat magic; the word after it is then a
            // class file version (45 and up), which the bound below refuses.
            guard let count = read32(handle, at: 4, bigEndian: true), count > 0, count < 64 else { return nil }
            let entrySize: UInt64 = magic == Magic.fat64 ? 32 : 20
            var names: [String] = []
            for index in 0..<UInt64(count) {
                let base = 8 + index * entrySize
                let offset = magic == Magic.fat64
                    ? read64(handle, at: base + 8, bigEndian: true)
                    : read32(handle, at: base + 8, bigEndian: true).map(UInt64.init)
                guard let offset, let name = sliceName(at: offset) else { return nil }
                names.append(name)
            }
            return names
        default:
            return nil
        }
    }

    static func architectureName(cpuType: UInt32, subtype: UInt32) -> String {
        switch cpuType {
        case cpuTypeARM64: return subtype == 2 ? "arm64e" : "arm64"
        case 0x0100_0007: return "x86_64"
        case 0x0200_000c: return "arm64_32"
        case 7: return "i386"
        default: return String(format: "cputype 0x%x", cpuType)
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

    private static func commands(_ handle: FileHandle, sliceOffset: UInt64, is64Bit: Bool) -> LoadCommands? {
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
        var sdks: [BuildSDK] = []
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
            } else if cmd == LoadCommand.buildVersion, size >= 24,
                      let platform = region.u32(at: cursor + 8),
                      let sdk = region.u32(at: cursor + 16) {
                if let found = BuildSDK(platformCode: platform, packed: sdk) { sdks.append(found) }
            } else if cmd == LoadCommand.versionMinMacOSX || cmd == LoadCommand.versionMinIPhoneOS,
                      size >= 16, let sdk = region.u32(at: cursor + 12) {
                let platform = cmd == LoadCommand.versionMinMacOSX
                    ? BuildSDK.Platform.macOS : BuildSDK.Platform.iOS
                if let found = BuildSDK(platform: platform, packed: sdk) { sdks.append(found) }
            }
            cursor += Int(size)
        }
        return LoadCommands(dylibs: names, buildSDK: BuildSDK.preferred(among: sdks))
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
