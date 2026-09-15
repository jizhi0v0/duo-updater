import Testing
import Foundation
@testable import DuoUpdaterCore

/// Builds a thin 64-bit arm64 Mach-O header with exactly the load commands a test
/// names, so every SDK case here is a fact about bytes the test wrote — not about
/// whichever SDK the binaries on the machine running it happen to carry.
private struct MachO {
    enum Command {
        /// `LC_BUILD_VERSION` with a `PLATFORM_*` code and a packed SDK.
        case buildVersion(platform: UInt32, sdk: UInt32)
        /// `LC_BUILD_VERSION` whose `cmdsize` claims less than the struct needs.
        case shortBuildVersion(platform: UInt32, sdk: UInt32)
        case versionMinMacOSX(sdk: UInt32)
        case versionMinIPhoneOS(sdk: UInt32)
        case loadDylib(String)
    }

    static let macOS: UInt32 = 1, iOS: UInt32 = 2, catalyst: UInt32 = 6, iOSSimulator: UInt32 = 7

    static func packed(_ major: UInt32, _ minor: UInt32, _ patch: UInt32 = 0) -> UInt32 {
        major << 16 | minor << 8 | patch
    }

    static func image(_ commands: [Command], cpuType: UInt32 = 0x0100_000c) -> Data {
        var body = Data()
        for command in commands {
            switch command {
            case .buildVersion(let platform, let sdk):
                body.le(0x32, 24, platform, packed(11, 0), sdk, 0)
            case .shortBuildVersion(let platform, let sdk):
                // 16 bytes: platform and minos fit, the sdk word is outside it.
                body.le(0x32, 16, platform, packed(11, 0))
                _ = sdk
            case .versionMinMacOSX(let sdk):
                body.le(0x24, 16, packed(10, 9), sdk)
            case .versionMinIPhoneOS(let sdk):
                body.le(0x25, 16, packed(9, 0), sdk)
            case .loadDylib(let name):
                var bytes = Array(name.utf8) + [0]
                while (24 + bytes.count) % 8 != 0 { bytes.append(0) }
                body.le(0xc, UInt32(24 + bytes.count), 24, 2, packed(1, 0), packed(1, 0))
                body.append(contentsOf: bytes)
            }
        }
        var header = Data()
        header.le(0xfeed_facf, cpuType, 0, 2, UInt32(commands.count), UInt32(body.count), 0, 0)
        return header + body
    }

    /// A universal file of the given thin images, each paired with its CPU type.
    static func fat(_ slices: [(cpu: UInt32, image: Data)]) -> Data {
        let alignment = 0x4000
        var file = Data()
        func be(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { file.append(contentsOf: $0) } }
        be(0xcafe_babe)
        be(UInt32(slices.count))
        var offsets: [Int] = []
        var next = alignment
        for slice in slices {
            offsets.append(next)
            next += (slice.image.count + alignment - 1) / alignment * alignment
        }
        for (slice, offset) in zip(slices, offsets) {
            be(slice.cpu); be(0); be(UInt32(offset)); be(UInt32(slice.image.count)); be(14)
        }
        for (slice, offset) in zip(slices, offsets) {
            file.append(Data(count: offset - file.count))
            file.append(slice.image)
        }
        return file
    }
}

private extension Data {
    mutating func le(_ words: UInt32...) {
        for word in words { Swift.withUnsafeBytes(of: word.littleEndian) { append(contentsOf: $0) } }
    }
}

private struct Scratch {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-sdk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func write(_ data: Data, to relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func plist(_ values: [String: Any], at relative: String) throws {
        try write(PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0),
                  to: relative)
    }

    func sdk(_ commands: [MachO.Command]) throws -> BuildSDK? {
        MachOImports.buildSDK(at: try write(MachO.image(commands), to: "image-\(UUID().uuidString)"))
    }
}

private let appKit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

// MARK: - Reading the number

@Test func readsTheSDKFromLCBuildVersion() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    #expect(try scratch.sdk([.buildVersion(platform: MachO.macOS, sdk: MachO.packed(27, 0))])
            == BuildSDK(platform: .macOS, version: "27.0"))
    // The patch component is printed only when there is one, as `vtool` does —
    // a mutation that always prints three parts, or never, fails one of these two.
    #expect(try scratch.sdk([.buildVersion(platform: MachO.macOS, sdk: MachO.packed(26, 5, 1))])
            == BuildSDK(platform: .macOS, version: "26.5.1"))
}

@Test func readsTheOlderVersionMinCommands() throws {
    // Binaries linked before `LC_BUILD_VERSION` existed record the SDK in the
    // `version_min_command` — the word *after* the minimum OS, so an off-by-four
    // read reports the minimum instead (10.9 / 9.0 in these images).
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    #expect(try scratch.sdk([.versionMinMacOSX(sdk: MachO.packed(10, 10))])
            == BuildSDK(platform: .macOS, version: "10.10"))
    #expect(try scratch.sdk([.versionMinIPhoneOS(sdk: MachO.packed(14, 4))])
            == BuildSDK(platform: .iOS, version: "14.4"))
}

@Test func thePlatformTravelsWithTheNumber() throws {
    // A Catalyst binary and a wrapped iOS binary: before the 26 releases these
    // carried iOS-numbered SDKs, so "16.0" without its platform would be a
    // different claim.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    #expect(try scratch.sdk([.buildVersion(platform: MachO.catalyst, sdk: MachO.packed(16, 0))])
            == BuildSDK(platform: .macCatalyst, version: "16.0"))
    #expect(try scratch.sdk([.buildVersion(platform: MachO.iOS, sdk: MachO.packed(26, 4))])
            == BuildSDK(platform: .iOS, version: "26.4"))
}

@Test func aZipperedImageReportsItsMacOSSDKWhicheverOrderItListsThem() throws {
    // The shape of the Swift back-deployment dylibs apps embed: one image, a
    // macOS and a Catalyst build version with unrelated numbers. Listed Catalyst
    // first here so "take the first one" gives the wrong answer.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let catalystFirst = try scratch.sdk([
        .buildVersion(platform: MachO.catalyst, sdk: MachO.packed(16, 0)),
        .buildVersion(platform: MachO.macOS, sdk: MachO.packed(13, 0)),
    ])
    #expect(catalystFirst == BuildSDK(platform: .macOS, version: "13.0"))
    let macOSFirst = try scratch.sdk([
        .buildVersion(platform: MachO.macOS, sdk: MachO.packed(13, 0)),
        .buildVersion(platform: MachO.catalyst, sdk: MachO.packed(16, 0)),
    ])
    #expect(macOSFirst == catalystFirst)
}

@Test func anUnrecordedSDKIsNilNotZero() throws {
    // `vtool` prints `n/a` for a zero — a linker given no SDK. A platform this scan
    // cannot be looking at (a simulator build) is not an answer either, and an
    // image that records no version at all is not one.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    #expect(try scratch.sdk([.buildVersion(platform: MachO.macOS, sdk: 0)]) == nil)
    #expect(try scratch.sdk([.buildVersion(platform: MachO.iOSSimulator, sdk: MachO.packed(26, 0))]) == nil)
    #expect(try scratch.sdk([.loadDylib(appKit)]) == nil)
    // A zero macOS entry does not hide a real Catalyst one behind it.
    #expect(try scratch.sdk([
        .buildVersion(platform: MachO.macOS, sdk: 0),
        .buildVersion(platform: MachO.catalyst, sdk: MachO.packed(17, 0)),
    ]) == BuildSDK(platform: .macCatalyst, version: "17.0"))
}

@Test func aBuildVersionTooShortToHoldTheSDKIsNotReadPastItsEnd() throws {
    // `cmdsize` 16 is a valid, aligned size for the walk, so the walk continues —
    // but the sdk word would come from the *next* command. Here that is the
    // dylib command's first word (0xc), which would read as SDK "0.0.12".
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let url = try scratch.write(MachO.image([
        .shortBuildVersion(platform: MachO.macOS, sdk: MachO.packed(27, 0)),
        .loadDylib(appKit),
    ]), to: "short")
    let commands = try #require(MachOImports.loadCommands(at: url))
    #expect(commands.buildSDK == nil)
    #expect(commands.dylibs.keys.contains(appKit))
}

@Test func theSDKAndTheLinkListComeFromOnePass() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let url = try scratch.write(MachO.image([
        .loadDylib(appKit),
        .buildVersion(platform: MachO.macOS, sdk: MachO.packed(26, 2)),
    ]), to: "both")
    let commands = try #require(MachOImports.loadCommands(at: url))
    #expect(commands.dylibs == [appKit: "1.0.0"])
    #expect(commands.buildSDK == BuildSDK(platform: .macOS, version: "26.2"))
    // The two older accessors still answer from the same parse.
    #expect(MachOImports.linkedLibraries(at: url) == [appKit])
    #expect(MachOImports.buildSDK(at: url) == commands.buildSDK)
}

@Test func aUniversalBinaryReportsItsArm64SlicesSDK() throws {
    // x86_64 first, and with a different SDK, so taking the first slice is
    // visible in the answer rather than only in which bytes were parsed.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let url = try scratch.write(MachO.fat([
        (0x0100_0007, MachO.image([.buildVersion(platform: MachO.macOS, sdk: MachO.packed(14, 0))],
                                  cpuType: 0x0100_0007)),
        (0x0100_000c, MachO.image([.buildVersion(platform: MachO.macOS, sdk: MachO.packed(27, 0))])),
    ]), to: "universal")
    #expect(MachOImports.buildSDK(at: url) == BuildSDK(platform: .macOS, version: "27.0"))
}

@Test func notAMachOIsNil() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let script = try scratch.write(Data("#!/bin/sh\n".utf8), to: "script")
    #expect(MachOImports.buildSDK(at: script) == nil)
    #expect(MachOImports.loadCommands(at: scratch.root.appendingPathComponent("missing")) == nil)
}

// MARK: - Which binary, end to end through the scanner

/// A minimal scannable bundle whose declared executable is a real Mach-O header.
private func nativeBundle(
    _ scratch: Scratch, name: String, executable: String,
    image: Data, extraPlist: [String: Any] = [:]
) throws -> URL {
    var plist: [String: Any] = [
        "CFBundleIdentifier": "com.example.zzfixture.\(name.lowercased())",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundleExecutable": executable,
    ]
    plist.merge(extraPlist) { $1 }
    try scratch.plist(plist, at: "\(name).app/Contents/Info.plist")
    try scratch.write(image, to: "\(name).app/Contents/MacOS/\(executable)")
    return scratch.root.appendingPathComponent("\(name).app")
}

@Test func theScannerRecordsTheSDKOfAnOrdinaryApp() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try nativeBundle(
        scratch, name: "ZZFixtureNative", executable: "ZZFixtureNative",
        image: MachO.image([.loadDylib(appKit),
                            .buildVersion(platform: MachO.macOS, sdk: MachO.packed(27, 0))]))
    let app = try #require(AppScanner().scan(bundlesAt: [bundle]).first)
    #expect(app.runtime == .native)
    #expect(app.buildSDK == BuildSDK(platform: .macOS, version: "27.0"))
}

@Test func anAppWithNoRuntimeLabelStillHasItsSDK() throws {
    // The runtime and the SDK are separate questions: a binary that links neither
    // AppKit nor a bundled toolkit gets no label, and its SDK is still a fact.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try nativeBundle(
        scratch, name: "ZZFixturePlain", executable: "ZZFixturePlain",
        image: MachO.image([.loadDylib("/usr/lib/libSystem.B.dylib"),
                            .buildVersion(platform: MachO.macOS, sdk: MachO.packed(15, 2))]))
    let app = try #require(AppScanner().scan(bundlesAt: [bundle]).first)
    #expect(app.runtime == nil)
    #expect(app.buildSDK == BuildSDK(platform: .macOS, version: "15.2"))
}

@Test func aLauncherStubReportsItsPayloadsSDK() throws {
    // Audacity's shape: the declared executable is a launcher, the app is the
    // binary named after the bundle. The two SDKs differ so reading the stub's
    // shows up as the wrong number.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try nativeBundle(
        scratch, name: "ZZFixtureStubbed", executable: "Wrapper",
        image: MachO.image([.loadDylib("/usr/lib/libSystem.B.dylib"),
                            .buildVersion(platform: MachO.macOS, sdk: MachO.packed(11, 0))]))
    try scratch.write(MachO.image([.loadDylib(appKit),
                                   .buildVersion(platform: MachO.macOS, sdk: MachO.packed(26, 5))]),
                      to: "ZZFixtureStubbed.app/Contents/MacOS/ZZFixtureStubbed")
    let app = try #require(AppScanner().scan(bundlesAt: [bundle]).first)
    #expect(app.runtime == .native)
    #expect(app.buildSDK == BuildSDK(platform: .macOS, version: "26.5"))
}

@Test func aWrapperReportsItsNestedInterfacesSDK() throws {
    // Docker's shape: a launcher that ships no frameworks, and the one nested
    // bundle that ships Electron. The label comes from the nested bundle, so the
    // SDK has to as well.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let wrapper = try nativeBundle(
        scratch, name: "ZZFixtureDock", executable: "backend",
        image: MachO.image([.loadDylib(appKit),
                            .buildVersion(platform: MachO.macOS, sdk: MachO.packed(14, 0))]))
    let nested = "ZZFixtureDock.app/Contents/MacOS/ZZFixture Desktop.app/Contents"
    try FileManager.default.createDirectory(
        at: scratch.root.appendingPathComponent("\(nested)/Frameworks/Electron Framework.framework"),
        withIntermediateDirectories: true)
    try scratch.plist(["CFBundleExecutable": "ZZFixture Desktop"], at: "\(nested)/Info.plist")
    try scratch.write(MachO.image([.buildVersion(platform: MachO.macOS, sdk: MachO.packed(26, 2))]),
                      to: "\(nested)/MacOS/ZZFixture Desktop")
    let app = try #require(AppScanner().scan(bundlesAt: [wrapper]).first)
    #expect(app.runtime == .electron)
    #expect(app.buildSDK == BuildSDK(platform: .macOS, version: "26.2"))
}

@Test func aWrappedIOSAppReportsTheSDKOfTheBinaryInsideTheWrapper() throws {
    // No `Contents/` at all: the binary sits at the root of the inner bundle,
    // reached through the `WrappedBundle` link the scanner keys on.
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let inner = "ZZFixturePhone.app/Wrapper/ZZFixtureInner.app"
    try scratch.plist([
        "CFBundleIdentifier": "com.example.zzfixture.phone",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundleExecutable": "ZZFixtureInner",
    ], at: "\(inner)/Info.plist")
    try scratch.write(MachO.image([.buildVersion(platform: MachO.iOS, sdk: MachO.packed(26, 4))]),
                      to: "\(inner)/ZZFixtureInner")
    let bundle = scratch.root.appendingPathComponent("ZZFixturePhone.app")
    try FileManager.default.createSymbolicLink(
        atPath: bundle.appendingPathComponent("WrappedBundle").path,
        withDestinationPath: "Wrapper/ZZFixtureInner.app")
    let app = try #require(AppScanner().scan(bundlesAt: [bundle]).first)
    #expect(app.runtime == .iOSApp)
    #expect(app.buildSDK == BuildSDK(platform: .iOS, version: "26.4"))
}

@Test func anUnreadableExecutableHasNoSDK() throws {
    let scratch = try Scratch(); defer { scratch.cleanUp() }
    let bundle = try nativeBundle(
        scratch, name: "ZZFixtureJunk", executable: "ZZFixtureJunk", image: Data("not a binary".utf8))
    let app = try #require(AppScanner().scan(bundlesAt: [bundle]).first)
    #expect(app.buildSDK == nil)
}
