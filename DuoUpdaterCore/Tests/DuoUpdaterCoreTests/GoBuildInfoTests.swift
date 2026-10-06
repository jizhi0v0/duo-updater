import Testing
import Foundation
@testable import DuoUpdaterCore

/// Go's build info, from the bytes up: the section format, where `MachOImports`
/// finds the section, and the `.mygo` verdict and version built on it.
///
/// Every image here is written by the test, so nothing depends on a Go toolchain
/// or on what is installed. The shapes are the ones a real MyGo app has, checked
/// against `go version -m` on demo apps built with mygo v0.2.14 and Go 1.27.1:
/// one `__go_buildinfo` section in `__DATA`, the inline (1.18+) layout, and the
/// module list framed by `cmd/go`'s two sentinels — which are not valid UTF-8.

/// `cmd/go/internal/modload.infoStart` and `infoEnd`, byte for byte.
private let infoStart: [UInt8] = hex("3077af0c9274080241e1c107e6d618e6")
private let infoEnd: [UInt8] = hex("f932433186182072008242104116d8f2")

private func hex(_ string: String) -> [UInt8] {
    var bytes: [UInt8] = []
    var index = string.startIndex
    while index < string.endIndex {
        let next = string.index(index, offsetBy: 2)
        bytes.append(UInt8(string[index..<next], radix: 16)!)
        index = next
    }
    return bytes
}

/// The modinfo of the web template's demo app, as `go version -m` printed it.
private let demoModinfo = """
    path\tweb-demo
    mod\tweb-demo\t(devel)\t
    dep\tgithub.com/ebitengine/purego\tv0.11.1\th1:2zpWRSQNVKN4eKsKO9eM1ILDgWfYMY9GwqRmK6XeQ/0=
    dep\tgithub.com/egoist/mygo\tv0.2.14\th1:9ZMOatDNWkyZpdXV+sStLE+SKM4u4ugn8oRNToYm1BI=
    build\t-buildmode=exe
    build\tCGO_ENABLED=0
    build\tGOOS=darwin

    """

/// A `__go_buildinfo` section: the 32-byte header, then the Go version and the
/// framed module list as uvarint-length-prefixed strings.
private func section(
    goVersion: String = "go1.27.1", modinfo: String = demoModinfo,
    flags: UInt8 = 0x2, framed: Bool = true
) -> Data {
    var bytes: [UInt8] = [0xff] + Array(" Go buildinf:".utf8) + [8, flags]
    bytes += [UInt8](repeating: 0, count: 16)
    func append(_ payload: [UInt8]) {
        var length = UInt64(payload.count)
        repeat {
            var byte = UInt8(length & 0x7f)
            length >>= 7
            if length != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while length != 0
        bytes += payload
    }
    append(Array(goVersion.utf8))
    append(framed ? infoStart + Array(modinfo.utf8) + infoEnd : Array(modinfo.utf8))
    return Data(bytes)
}

/// A thin 64-bit Mach-O whose single `__DATA` segment holds `__data` and, when
/// given, `__go_buildinfo` — the section's bytes laid down after the load
/// commands, where its `offset` points.
private func image(buildInfo: Data?) -> Data {
    let sections = buildInfo == nil ? 1 : 2
    let commandSize = 72 + 80 * sections
    let headerSize = 32
    let dataOffset = UInt32(headerSize + commandSize)

    var file = Data()
    file.le32(0xfeed_facf, 0x0100_000c, 0, 2, 1, UInt32(commandSize), 0, 0)
    file.le32(0x19, UInt32(commandSize))
    file.name("__DATA")
    file.le64(0, 0, UInt64(dataOffset), UInt64(buildInfo?.count ?? 0))
    file.le32(3, 3, UInt32(sections), 0)
    func sectionHeader(_ name: String, offset: UInt32, size: Int) {
        file.name(name)
        file.name("__DATA")
        file.le64(0, UInt64(size))
        file.le32(offset, 3, 0, 0, 0, 0, 0, 0)
    }
    // A decoy first, so the reader has to pick the section by name.
    sectionHeader("__data", offset: dataOffset, size: 0)
    if let buildInfo {
        sectionHeader("__go_buildinfo", offset: dataOffset, size: buildInfo.count)
        file.append(buildInfo)
    }
    return file
}

/// A universal file with the image as its arm64 slice, behind an x86_64 slice
/// that carries no build info — so a reader that ignored the slice offset, or
/// parsed the first slice, finds nothing.
private func fat(_ arm64: Data) -> Data {
    let alignment = 0x4000
    let intel = image(buildInfo: nil)
    var file = Data()
    func be(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { file.append(contentsOf: $0) } }
    be(0xcafe_babe); be(2)
    be(0x0100_0007); be(0); be(UInt32(alignment)); be(UInt32(intel.count)); be(14)
    be(0x0100_000c); be(0); be(UInt32(2 * alignment)); be(UInt32(arm64.count)); be(14)
    file.append(Data(count: alignment - file.count)); file.append(intel)
    file.append(Data(count: 2 * alignment - file.count)); file.append(arm64)
    return file
}

private extension Data {
    mutating func le32(_ words: UInt32...) {
        for word in words { Swift.withUnsafeBytes(of: word.littleEndian) { append(contentsOf: $0) } }
    }
    mutating func le64(_ words: UInt64...) {
        for word in words { Swift.withUnsafeBytes(of: word.littleEndian) { append(contentsOf: $0) } }
    }
    /// A 16-byte, NUL-padded Mach-O name field.
    mutating func name(_ value: String) {
        append(contentsOf: Array(value.utf8) + [UInt8](repeating: 0, count: 16 - value.utf8.count))
    }
}

private struct Scratch {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-gobuildinfo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func write(_ data: Data, to relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    /// A bundle with nothing in it but this executable and a plist naming it —
    /// which is all a MyGo app ships, give or take an icon.
    func app(_ executable: Data) throws -> URL {
        let bundle = root.appendingPathComponent("Demo-\(UUID().uuidString).app")
        _ = try write(executable, to: "\(bundle.lastPathComponent)/Contents/MacOS/demo")
        _ = try write(
            PropertyListSerialization.data(
                fromPropertyList: ["CFBundleExecutable": "demo", "CFBundleIdentifier": "com.example.demo",
                                   "CFBundleShortVersionString": "0.1.0"],
                format: .xml, options: 0),
            to: "\(bundle.lastPathComponent)/Contents/Info.plist")
        return bundle
    }
}

// MARK: - The section format

@Test func readsTheModuleListOfARealMyGoApp() throws {
    let info = try #require(GoBuildInfo.parse(section: section()))
    #expect(info.goVersion == "go1.27.1")
    #expect(info.main == .init(path: "web-demo", version: "(devel)", replacement: nil))
    #expect(info.dependencies.map(\.path) == ["github.com/ebitengine/purego", "github.com/egoist/mygo"])
    let mygo = try #require(info.module(AppRuntimeDetector.myGoModule))
    #expect(mygo.version == "v0.2.14")
    #expect(mygo.builtVersion == "0.2.14")
}

/// The sentinels are what a decode-then-strip reader trips on: each of their
/// invalid bytes becomes a three-byte U+FFFD, the newline the framing check
/// looks for moves, and the first line comes out glued to garbage.
///
/// In a real app that first line is `path`, which nothing here reads — so the
/// demo's modinfo cannot tell a working strip from a missing one (a mutation
/// removing it passed). A list that opens with the module line itself can, and
/// is one `runtime/debug.ParseBuildInfo` accepts.
@Test func stripsTheFramingBeforeDecodingIt() throws {
    let opensWithMyGo = """
        dep\tgithub.com/egoist/mygo\tv0.2.14\th1:x=
        build\tGOOS=darwin

        """
    let info = try #require(GoBuildInfo.parse(section: section(modinfo: opensWithMyGo)))
    #expect(info.module(AppRuntimeDetector.myGoModule)?.builtVersion == "0.2.14")
    // Unframed modinfo (no sentinels) is read as it stands.
    #expect(GoBuildInfo.parse(section: section(framed: false))?.module(AppRuntimeDetector.myGoModule) != nil)
}

@Test func theCompiledVersionIsTheReplacementsWhenThereIsOne() throws {
    let local = GoBuildInfo.parse(goVersion: "go1.27.1", modinfo: """
        dep\tgithub.com/egoist/mygo\tv0.2.14\th1:x=
        =>\t../mygo\t(devel)\t

        """)
    let localMyGo = try #require(local.module(AppRuntimeDetector.myGoModule))
    #expect(localMyGo.replacement == .init(path: "../mygo", version: "(devel)"))
    #expect(localMyGo.builtVersion == nil)

    let fork = GoBuildInfo.parse(goVersion: "go1.27.1", modinfo: """
        dep\tgithub.com/egoist/mygo\tv0.2.14\th1:x=
        =>\tgithub.com/someone/mygo\tv0.3.0\th1:y=
        dep\tgolang.org/x/image\tv0.46.0\th1:z=

        """)
    #expect(fork.module(AppRuntimeDetector.myGoModule)?.builtVersion == "0.3.0")
    // The replacement attaches to the line before it and nothing after.
    #expect(fork.module("golang.org/x/image")?.replacement == nil)
}

/// An example built inside MyGo's own repository has MyGo as its main module.
@Test func mygoAsTheMainModuleCounts() throws {
    let info = GoBuildInfo.parse(goVersion: "go1.27.1", modinfo: """
        path\tgithub.com/egoist/mygo/examples/hello
        mod\tgithub.com/egoist/mygo\t(devel)\t

        """)
    let mygo = try #require(info.module(AppRuntimeDetector.myGoModule))
    #expect(mygo.builtVersion == nil)
}

/// `runtime/debug.ParseBuildInfo` reads only newline-terminated lines.
@Test func anUnterminatedLastLineIsNotAModule() {
    let info = GoBuildInfo.parse(goVersion: "go1.27.1", modinfo: "dep\tgithub.com/egoist/mygo\tv0.2.14\th1:x=")
    #expect(info.module(AppRuntimeDetector.myGoModule) == nil)
}

@Test func refusesWhatIsNotTheInlineLayout() {
    var badMagic = section()
    badMagic[3] = UInt8(ascii: "X")
    #expect(GoBuildInfo.parse(section: badMagic) == nil)
    // Pre-1.18: pointers into the data segment instead of inline strings.
    #expect(GoBuildInfo.parse(section: section(flags: 0)) == nil)
    // A length that runs past the end of the section.
    #expect(GoBuildInfo.parse(section: section().prefix(40)) == nil)
    #expect(GoBuildInfo.parse(section: Data(count: 31)) == nil)
}

// MARK: - Finding the section

@Test func findsTheSectionInAThinImage() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let url = try scratch.write(image(buildInfo: section()), to: "thin")
    let range = try #require(MachOImports.loadCommands(at: url)?.goBuildInfo)
    #expect(range.size == UInt64(section().count))
    #expect(GoBuildInfo.read(at: url)?.module(AppRuntimeDetector.myGoModule)?.builtVersion == "0.2.14")
}

/// `darwin/universal` is one of `mygo build`'s targets. Section offsets count
/// from the slice, so the slice's own offset has to be added.
@Test func findsTheSectionInTheArm64SliceOfAUniversalImage() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let url = try scratch.write(fat(image(buildInfo: section())), to: "fat")
    let range = try #require(MachOImports.loadCommands(at: url)?.goBuildInfo)
    #expect(range.offset > 0x8000)
    #expect(GoBuildInfo.read(at: url)?.module(AppRuntimeDetector.myGoModule)?.builtVersion == "0.2.14")
}

@Test func anImageGoDidNotLinkHasNoSection() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let url = try scratch.write(image(buildInfo: nil), to: "plain")
    #expect(try #require(MachOImports.loadCommands(at: url)).goBuildInfo == nil)
    #expect(GoBuildInfo.read(at: url) == nil)
}

// MARK: - The verdict

private let appKit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
private let coreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"

private func detect(
    _ bundle: URL, libraries: Set<String>?, goBuildInfo: GoBuildInfo?
) -> AppRuntime? {
    AppRuntimeDetector.detect(
        bundleAt: bundle, isiOSAppOnMac: false, infoPlist: ["CFBundleExecutable": "demo"],
        linkedLibraries: { _ in libraries }, carriesTauriCrate: { _ in false },
        goBuildInfo: { _ in goBuildInfo })
}

private let myGoApp = GoBuildInfo.parse(goVersion: "go1.27.1", modinfo: demoModinfo)
/// A Go app that is not MyGo — Ollama's shape: Go, cgo, links AppKit.
private let otherGoApp = GoBuildInfo.parse(goVersion: "go1.26.0", modinfo: """
    mod\tgithub.com/ollama/ollama\t(devel)\t

    """)

/// What a MyGo app links — and why no link rule could have named it.
@Test func aMyGoBinaryReadsAsMyGo() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try scratch.app(Data())
    #expect(detect(bundle, libraries: [coreFoundation], goBuildInfo: myGoApp) == .mygo)
    // Without the module list the same bundle is unlabelled, as it was before.
    #expect(detect(bundle, libraries: [coreFoundation], goBuildInfo: otherGoApp) == nil)
    #expect(detect(bundle, libraries: [coreFoundation], goBuildInfo: nil) == nil)
}

/// Ahead of the link rules, so a MyGo app that does link AppKit — cgo through
/// some dependency — is still MyGo, while another Go app linking AppKit stays
/// native.
@Test func theModuleListOutranksTheLinkRules() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try scratch.app(Data())
    #expect(detect(bundle, libraries: [appKit], goBuildInfo: myGoApp) == .mygo)
    #expect(detect(bundle, libraries: [appKit], goBuildInfo: otherGoApp) == .native)
}

/// A runtime the bundle ships wins over one compiled in: an Electron app with a
/// Go launcher that happened to link MyGo is still drawing with Electron.
@Test func aBundledRuntimeOutranksTheModuleList() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try scratch.app(Data())
    _ = try scratch.write(Data(), to: "\(bundle.lastPathComponent)/Contents/Resources/app.asar")
    #expect(detect(bundle, libraries: [coreFoundation], goBuildInfo: myGoApp) == .electron)
}

/// An unreadable executable ends the enquiry before any binary-read rule, this
/// one included — the detector's long-standing fail-closed point.
@Test func anUnreadableExecutableIsNotMyGo() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try scratch.app(Data())
    #expect(detect(bundle, libraries: nil, goBuildInfo: myGoApp) == nil)
}

/// The production path end to end: a bundle on disk whose executable is a Go
/// image, read by the default readers, and the version the detail popover shows.
@Test func theProductionReadersAgreeOnAnImageOnDisk() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try scratch.app(image(buildInfo: section()))
    let reading = AppRuntimeDetector.read(
        bundleAt: bundle, isiOSAppOnMac: false, infoPlist: ["CFBundleExecutable": "demo"])
    #expect(reading.runtime == .mygo)
    #expect(RuntimeVersion.read(.mygo, bundleAt: bundle, scanningBinaries: false) == "0.2.14")

    let scanned = try #require(AppScanner(locations: []).readApp(at: bundle))
    #expect(scanned.runtime == .mygo)
}
