import Foundation

/// The module list the Go toolchain writes into every binary it links — what
/// `go version -m` prints.
///
/// Exists for `AppRuntime.mygo`, which has nothing else to be recognized by. A
/// MyGo app is one statically linked Go binary in an otherwise empty bundle: no
/// framework, no payload directory, nothing in `Info.plist` that Xcode would not
/// also write, and — the part that rules out the load commands — it reaches AppKit
/// and WebKit through `dlopen` at run time rather than by linking them, so the
/// binary links CoreFoundation, Security and libSystem and nothing that says
/// "interface". What the toolchain does record, in every build, is which module
/// versions went into it, and MyGo is one of them.
///
/// It is the toolchain's own record, the same kind of evidence as a load command,
/// and it is cheap to reach: the section is located by `MachOImports` in the pass
/// over the load commands it already makes, and holds a few hundred bytes to a few
/// kilobytes. Nothing here searches a binary.
///
/// Only the inline layout Go has written since 1.18 is read — a 32-byte header
/// whose flags byte says so, then two length-prefixed strings. The older layout
/// stores pointers into the data segment instead, and following those is a
/// different reader for binaries no MyGo app can be: MyGo requires Go 1.27. Any
/// other shape, and any section that does not start with the magic, reads as nil.
/// The format is `debug/buildinfo` and `runtime/debug.ParseBuildInfo` in the Go
/// source; this was checked against Go 1.27.1's copies of both.
public struct GoBuildInfo: Sendable, Equatable {

    /// One `mod` or `dep` line, with the `=>` line that may follow it.
    public struct Module: Sendable, Equatable {
        public let path: String
        /// `v0.2.14`, a pseudo-version, or `(devel)` for a main module built from
        /// a checkout.
        public let version: String
        /// Where `go.mod` pointed the module instead. A local directory has the
        /// version `(devel)`; another module has a real one.
        public let replacement: Replacement?

        public struct Replacement: Sendable, Equatable {
            public let path: String
            public let version: String
        }

        /// The version of the code that was actually compiled in, without the
        /// leading `v` — or nil where there is no version to name, which is
        /// `(devel)`: a main module built in its own checkout, or a dependency
        /// replaced by a local directory. The replacement's version wins over the
        /// one required, since that is the code that was built.
        public var builtVersion: String? {
            let version = replacement?.version ?? version
            guard !version.isEmpty, version != "(devel)" else { return nil }
            return version.hasPrefix("v") ? String(version.dropFirst()) : version
        }
    }

    /// The Go release that linked the binary — `go1.27.1`.
    public let goVersion: String
    /// The module the `main` package belongs to — the app's own. Nil where the
    /// binary was built outside module mode.
    public let main: Module?
    public let dependencies: [Module]

    /// The main module or the dependency with this module path.
    public func module(_ path: String) -> Module? {
        if let main, main.path == path { return main }
        return dependencies.first { $0.path == path }
    }

    // MARK: - Reading

    /// Larger than any real section by orders of magnitude — the module list of a
    /// binary with a thousand dependencies is under 200 KB. A bigger size means a
    /// header that is not what it says, and is refused rather than read.
    static let maxSectionBytes: UInt64 = 1024 * 1024

    /// The build info of the Mach-O image at `url`, or nil when it was not linked
    /// by Go, or was and cannot be read.
    public static func read(at url: URL) -> GoBuildInfo? {
        guard let section = MachOImports.loadCommands(at: url)?.goBuildInfo else { return nil }
        return read(at: url, section: section)
    }

    /// The same, for a caller that already has the load commands — the scan does,
    /// and re-parsing them would be the one avoidable cost here.
    public static func read(at url: URL, section: MachOImports.FileRange) -> GoBuildInfo? {
        guard section.size >= 32, section.size <= maxSectionBytes,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: section.offset)) != nil,
              let bytes = try? handle.read(upToCount: Int(section.size)),
              bytes.count == Int(section.size)
        else { return nil }
        return parse(section: bytes)
    }

    /// The section's bytes → build info. Split out so the format can be tested
    /// without a Go binary on disk.
    static func parse(section: Data) -> GoBuildInfo? {
        let bytes = [UInt8](section)
        // `"\xff Go buildinf:"` in Go, where `\xff` is one raw byte; a Swift
        // string literal would encode it as two.
        let magic: [UInt8] = [0xff] + Array(" Go buildinf:".utf8)
        guard bytes.count >= 32, Array(bytes[0..<14]) == magic,
              bytes[15] & 0x2 == 0x2 // flagsVersionInl
        else { return nil }

        var cursor = 32
        guard let version = string(in: bytes, at: &cursor),
              var modinfo = string(in: bytes, at: &cursor)
        else { return nil }

        // `cmd/go` frames the module list between two 16-byte sentinels; the
        // closing one starts right after a newline. Stripped as bytes, before
        // anything is decoded: the sentinels are not valid UTF-8, and decoding
        // first would widen each bad byte into a three-byte U+FFFD, moving the
        // newline this test looks for.
        // (A slice keeps its parent's indices, hence `endIndex` rather than `count`.)
        if modinfo.count >= 33, modinfo[modinfo.endIndex - 17] == UInt8(ascii: "\n") {
            modinfo = modinfo[(modinfo.startIndex + 16)..<(modinfo.endIndex - 16)]
        }
        return parse(goVersion: String(decoding: version, as: UTF8.self),
                     modinfo: String(decoding: modinfo, as: UTF8.self))
    }

    /// The module lines, as `runtime/debug.ParseBuildInfo` reads them: one record
    /// per newline-*terminated* line, tab-separated, an `=>` line replacing the
    /// module on the line before it. `path` and `build` lines carry nothing asked
    /// of this type and are skipped, as is anything malformed — one bad line does
    /// not cost the rest.
    static func parse(goVersion: String, modinfo: String) -> GoBuildInfo {
        var main: Module?
        var dependencies: [Module] = []
        // Which module an `=>` line applies to, so it can be rebuilt with it.
        enum Last { case main, dependency, none }
        var last = Last.none

        var lines = modinfo.components(separatedBy: "\n")
        lines.removeLast() // whatever follows the final newline is not a line
        for line in lines {
            let fields = line.components(separatedBy: "\t")
            switch fields.first {
            case "mod" where fields.count == 3 || fields.count == 4:
                main = Module(path: fields[1], version: fields[2], replacement: nil)
                last = .main
            case "dep" where fields.count == 3 || fields.count == 4:
                dependencies.append(Module(path: fields[1], version: fields[2], replacement: nil))
                last = .dependency
            case "=>" where fields.count == 4:
                let replacement = Module.Replacement(path: fields[1], version: fields[2])
                switch last {
                case .main:
                    main = main.map { Module(path: $0.path, version: $0.version, replacement: replacement) }
                case .dependency:
                    let replaced = dependencies.removeLast()
                    dependencies.append(Module(path: replaced.path, version: replaced.version,
                                               replacement: replacement))
                case .none:
                    break
                }
                last = .none
            default:
                last = .none
            }
        }
        return GoBuildInfo(goVersion: goVersion, main: main, dependencies: dependencies)
    }

    /// A uvarint length and that many bytes, as `debug/buildinfo.decodeString`.
    private static func string(in bytes: [UInt8], at cursor: inout Int) -> ArraySlice<UInt8>? {
        var length: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard cursor < bytes.count, shift < 64 else { return nil }
            let byte = bytes[cursor]
            cursor += 1
            length |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        guard length <= UInt64(bytes.count - cursor) else { return nil }
        let end = cursor + Int(length)
        defer { cursor = end }
        return bytes[cursor..<end]
    }
}
