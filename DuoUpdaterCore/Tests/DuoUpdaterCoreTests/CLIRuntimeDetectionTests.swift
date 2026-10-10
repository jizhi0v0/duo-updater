import Testing
import Foundation
@testable import DuoUpdaterCore

/// `CLIRuntimeDetector` against synthetic Mach-O images and scripts written into
/// an invented `ZZFixture-*` directory, so nothing depends on what this machine
/// has installed. Each image is a real thin (or fat) Mach-O whose sections carry
/// exactly the bytes under test, read through the production `MachOImports`.
@Suite(.serialized)
struct CLIRuntimeDetectionTests {

    // MARK: - Packaged runtimes

    @Test func bunCompiledOutputWithRustPathsIsBun() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        // A `bun build --compile` output: the module graph's length up front, and
        // — as measured in Claude Code and OpenCode — Rust std paths about.
        let url = try scratch.binary("claude", [
            ("__TEXT", "__cstring", cstring(rustPath)),
            ("__BUN", "__bun", length(4096) + Data("/$bunfs/root/x.js".utf8)),
        ])
        let reading = CLIRuntimeDetector.read(path: url.path)
        #expect(reading?.runtime == .bun)
        #expect(reading?.evidence == .bunSection(compiled: true))
    }

    @Test func bunRuntimeItselfIsBun() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("bun", [("__BUN", "__bun", Data(count: 64))])
        #expect(CLIRuntimeDetector.read(path: url.path)?.evidence == .bunSection(compiled: false))
    }

    @Test func denoCompileOutputIsDeno() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("app", [
            ("__TEXT", "__cstring", cstring(rustPath)),
            ("__SUI", "d3n0l4nd", Data("eszip".utf8)),
        ])
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == .deno)
    }

    /// Deno's own binary carries the trailer string as a constant and Rust's std
    /// paths, and no `__SUI` section: it is a Rust program.
    @Test func denoItselfIsRust() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("deno", [
            ("__TEXT", "__literals", Data("d3n0l4nd".utf8)),
            ("__TEXT", "__cstring", cstring(rustPath)),
        ])
        let reading = CLIRuntimeDetector.read(path: url.path)
        #expect(reading?.runtime == .rust)
        #expect(reading?.evidence == .rustStandardLibrary)
    }

    @Test func nodeSingleExecutableIsNode() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("sea", [
            ("__TEXT", "__cstring", cstring(rustPath)),
            ("NODE_SEA", "__NODE_SEA_BLOB", Data("blob".utf8)),
        ])
        #expect(CLIRuntimeDetector.read(path: url.path)?.evidence == .nodeSEASegment)
    }

    /// `node` itself has the fuse string and no segment.
    @Test func nodeBinaryWithOnlyTheFuseIsNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("node", [
            ("__TEXT", "__cstring", cstring("NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2:0")),
        ])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    // MARK: - Go, Swift, Haskell

    @Test func goBeatsRustPaths() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("helm", [
            ("__TEXT", "__cstring", cstring(rustPath)),
            ("__DATA", "__go_buildinfo", Data("not a parsable header".utf8)),
        ])
        let reading = CLIRuntimeDetector.read(path: url.path)
        #expect(reading?.runtime == .go)
        #expect(reading?.evidence == .goBuildInfo(goVersion: nil))
    }

    /// The `duo` case: a Swift program whose strings mention bun (and here Rust's
    /// std paths too) is Swift.
    @Test func swiftWithBunAndRustStringsIsSwift() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("duo", [
            ("__TEXT", "__cstring", cstring("bun", "~/.bun/bin/bun", "---- Bun! ----", rustPath)),
            ("__TEXT", "__swift5_types", Data(count: 8)),
            ("__TEXT", "__swift5_entry", Data(count: 4)),
        ])
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == .swift)
    }

    /// Swift metadata without the entry section — `/usr/bin/codesign`'s shape —
    /// says only that some Swift is linked in.
    @Test func swiftMetadataWithoutEntryIsNotSwift() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("codesign", [
            ("__TEXT", "__swift5_types", Data(count: 8)),
            ("__TEXT", "__swift5_proto", Data(count: 8)),
        ])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    @Test func haskellBeatsRustPaths() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("ghcup", [
            ("__TEXT", "__cstring", cstring("Flag -with-rtsopts", #" [("GHC RTS", "YES")"#, " ]", rustPath)),
        ])
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == .haskell)
    }

    @Test func ghcTextOutsideCstringIsNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("x", [("__TEXT", "__const", Data(#" [("GHC RTS", "YES")"#.utf8))])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    // MARK: - Rust

    @Test func rustStdPathIsRust() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("zoxide", [("__TEXT", "__cstring", cstring("hello", rustPath))])
        #expect(CLIRuntimeDetector.read(path: url.path)?.evidence == .rustStandardLibrary)
    }

    @Test func cargoAuditableIsRust() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("uv", [("__DATA", ".dep-v0", Data([0x78, 0x9c]))])
        #expect(CLIRuntimeDetector.read(path: url.path)?.evidence == .cargoAuditable)
    }

    /// `/rustc/` alone, a short or uppercase hash, or no closing slash is not
    /// the remapped std path.
    @Test(arguments: malformedRustPaths)
    func malformedRustPathIsNothing(_ text: String) throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("x", [("__TEXT", "__cstring", cstring(text))])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    /// Where Bun-compiled outputs keep theirs: in the payload, not `__cstring`.
    @Test func rustPathOutsideCstringIsNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("x", [("__TEXT", "__const", Data(rustPath.utf8))])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    /// The loose substrings that were false positives on the real machine.
    @Test func looseZigAndBunSubstringsAreNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("x", [("__TEXT", "__cstring", cstring("zig_", "ZIG_PROGRESS", "bun", "deno"))])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    @Test func oversizedCstringIsNotRead() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let strings = cstring(rustPath)
        let url = try scratch.binary("x", [("__TEXT", "__cstring", strings)])
        let commands = try #require(MachOImports.loadCommands(at: url))
        #expect(CLIRuntimeDetector.machOVerdict(commands, at: url, cstringLimit: UInt64(strings.count)).0 == .rust)
        #expect(CLIRuntimeDetector.machOVerdict(commands, at: url, cstringLimit: UInt64(strings.count - 1)).0 == nil)
    }

    /// Section offsets count from the slice; a reader that forgot the slice
    /// offset would read the x86_64 slice's bytes instead and find nothing.
    @Test func fatBinaryReadsTheArm64Slice() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arm = image([("__TEXT", "__cstring", cstring(rustPath))])
        let intel = image([("__TEXT", "__cstring", cstring("nothing here at all, padded out to the same size......."))])
        let url = scratch.root.appendingPathComponent("fat")
        try fat(intel: intel, arm64: arm).write(to: url)
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == .rust)
    }

    @Test func plainMachOIsNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("fx", [("__TEXT", "__cstring", cstring("hello"))])
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    /// The cache is keyed by the file's identity, so a tool replaced in place by
    /// an update is read again.
    @Test func replacedFileIsReadAgain() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.binary("tool", [("__BUN", "__bun", Data(count: 8))])
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == .bun)
        let replacement = scratch.root.appendingPathComponent("tool.new")
        try image([("__DATA", "__go_buildinfo", Data(count: 64))]).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == .go)
    }

    // MARK: - Scripts

    @Test(arguments: shebangs)
    func shebangNamesTheRuntime(_ script: String, _ expected: CLIRuntime) throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.file("tool", script)
        #expect(CLIRuntimeDetector.read(path: url.path)?.runtime == expected)
    }

    /// No `#!`, no verdict — not from an extension, not from a comment.
    @Test(arguments: unusableScripts)
    func noUsableShebangIsNothing(_ name: String, _ text: String) throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let url = try scratch.file(name, text)
        #expect(CLIRuntimeDetector.read(path: url.path) == nil)
    }

    @Test func symlinkIsFollowed() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let target = try scratch.file("real", "#!/bin/bash\n")
        let link = scratch.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let reading = CLIRuntimeDetector.read(path: link.path)
        #expect(reading?.runtime == .shell)
        #expect(reading?.binary == target.resolvingSymlinksInPath().path)
    }

    @Test func pythonVirtualEnvironmentIsPython() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        _ = try scratch.file("venv/pyvenv.cfg", "home = /usr/bin\n")
        let reading = CLIRuntimeDetector.read(path: scratch.root.appendingPathComponent("venv").path)
        #expect(reading?.evidence == .pythonVirtualEnvironment)
        // A directory that is neither an npm package nor a venv proves nothing.
        _ = try scratch.file("other/README", "")
        #expect(CLIRuntimeDetector.read(path: scratch.root.appendingPathComponent("other").path) == nil)
    }

    // MARK: - npm launchers

    /// `@tencent-qqmail/agently-cli`'s shape: a JS bin, a declared platform
    /// package nested in the package, its Go binary at `bin/<command>`.
    @Test func nodeLauncherExecsPlatformBinary() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let root = try scratch.npmPackage(
            "lib/node_modules/@acme/tool", name: "@acme/tool", bin: ["tool": "scripts/run.js"],
            optional: ["@acme/tool-darwin-\(CLIRuntimeDetector.npmArchitecture)", "@acme/tool-linux-x64"])
        let platform = try scratch.npmPackage(
            "lib/node_modules/@acme/tool/node_modules/@acme/tool-darwin-\(CLIRuntimeDetector.npmArchitecture)",
            name: "@acme/tool-darwin-\(CLIRuntimeDetector.npmArchitecture)")
        try image([("__DATA", "__go_buildinfo", Data(count: 64))])
            .write(to: try scratch.directory(platform.appendingPathComponent("bin")).appendingPathComponent("tool"))
        let link = try scratch.binLink("tool", to: "../lib/node_modules/@acme/tool/scripts/run.js")

        for path in [link.path, root.path] {
            let reading = CLIRuntimeDetector.read(path: path)
            #expect(reading?.runtime == .go)
            #expect(reading?.binary.hasSuffix("tool-darwin-\(CLIRuntimeDetector.npmArchitecture)/bin/tool") == true)
        }
    }

    /// Hoisted beside the package rather than nested in it, unscoped.
    @Test func hoistedPlatformPackageIsFound() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        let root = try scratch.npmPackage(
            "lib/node_modules/tool", name: "tool", bin: ["tool": "bin/run.js"], optional: ["tool-darwin-\(arch)"])
        let platform = try scratch.npmPackage("lib/node_modules/tool-darwin-\(arch)", name: "tool-darwin-\(arch)")
        try image([("__TEXT", "__cstring", cstring(rustPath))]).write(to: platform.appendingPathComponent("tool"))
        let reading = CLIRuntimeDetector.read(path: root.path)
        #expect(reading?.runtime == .rust)
    }

    /// The platform package is on disk but the package does not declare it: the
    /// convention's claim is not made, and the bin is the Node script it is.
    @Test func undeclaredPlatformPackageIsIgnored() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        let root = try scratch.npmPackage("lib/node_modules/tool", name: "tool", bin: ["tool": "bin/run.js"])
        let platform = try scratch.npmPackage(
            "lib/node_modules/tool/node_modules/tool-darwin-\(arch)", name: "tool-darwin-\(arch)")
        try image([("__DATA", "__go_buildinfo", Data(count: 64))]).write(to: platform.appendingPathComponent("tool"))
        let reading = CLIRuntimeDetector.read(path: root.path)
        #expect(reading?.runtime == .node)
    }

    /// openclaw's shape: platform packages of *dependencies* (`node-pty`) are
    /// not the package's own.
    @Test func dependencysPlatformPackageIsNotTheTools() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        let root = try scratch.npmPackage(
            "lib/node_modules/claw", name: "claw", bin: ["claw": "claw.mjs"], optional: ["pty-darwin-\(arch)"])
        let platform = try scratch.npmPackage(
            "lib/node_modules/claw/node_modules/pty-darwin-\(arch)", name: "pty-darwin-\(arch)")
        try image([("__DATA", "__go_buildinfo", Data(count: 64))]).write(to: platform.appendingPathComponent("claw"))
        #expect(CLIRuntimeDetector.read(path: root.path)?.runtime == .node)
    }

    @Test func platformFileThatIsNotMachOIsIgnored() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        let root = try scratch.npmPackage(
            "lib/node_modules/tool", name: "tool", bin: ["tool": "bin/run.js"], optional: ["tool-darwin-\(arch)"])
        let platform = try scratch.npmPackage(
            "lib/node_modules/tool/node_modules/tool-darwin-\(arch)", name: "tool-darwin-\(arch)")
        try Data("#!/bin/sh\n".utf8).write(to: platform.appendingPathComponent("tool"))
        let reading = CLIRuntimeDetector.read(path: root.path)
        #expect(reading?.runtime == .node)
    }

    /// A platform package whose own `bin` names a script ahead of the native
    /// binary at `bin/<command>`: the script is passed over, not adopted — or the
    /// binary behind it would never be reached.
    @Test func nonMachOCandidateDoesNotShadowTheBinary() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        let root = try scratch.npmPackage(
            "lib/node_modules/tool", name: "tool", bin: ["tool": "bin/run.js"], optional: ["tool-darwin-\(arch)"])
        let platform = try scratch.npmPackage(
            "lib/node_modules/tool/node_modules/tool-darwin-\(arch)", name: "tool-darwin-\(arch)",
            bin: ["tool-helper": "helper.js"])
        try image([("__DATA", "__go_buildinfo", Data(count: 64))])
            .write(to: try scratch.directory(platform.appendingPathComponent("bin")).appendingPathComponent("tool"))
        let reading = CLIRuntimeDetector.read(path: root.path)
        #expect(reading?.runtime == .go)
    }

    /// A native binary with no marker: what runs is unknown, so nothing is said
    /// — not "Node.js", which only starts it.
    @Test func unidentifiedPlatformBinaryReadsAsNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        let root = try scratch.npmPackage(
            "lib/node_modules/tool", name: "tool", bin: ["tool": "bin/run.js"], optional: ["tool-darwin-\(arch)"])
        let platform = try scratch.npmPackage(
            "lib/node_modules/tool/node_modules/tool-darwin-\(arch)", name: "tool-darwin-\(arch)")
        try image([("__TEXT", "__cstring", cstring("hi"))]).write(to: platform.appendingPathComponent("tool"))
        #expect(CLIRuntimeDetector.read(path: root.path) == nil)
    }

    /// agent-browser's shape: the prefix's `bin/` link points straight at a
    /// native binary inside the package, past the JS `package.json` names.
    @Test func prefixBinLinkIntoPackageWins() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let root = try scratch.npmPackage(
            "lib/node_modules/browser", name: "browser", bin: ["browser": "./bin/browser.js"])
        try image([("__TEXT", "__cstring", cstring(rustPath))])
            .write(to: root.appendingPathComponent("bin/browser-darwin-arm64"))
        _ = try scratch.binLink("browser", to: "../lib/node_modules/browser/bin/browser-darwin-arm64")
        let reading = CLIRuntimeDetector.read(path: root.path)
        #expect(reading?.runtime == .rust)
    }

    /// A `dist/package.json` holding only `"type"` is not the package.
    @Test func namelessInnerManifestIsSkipped() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let arch = CLIRuntimeDetector.npmArchitecture
        _ = try scratch.npmPackage(
            "lib/node_modules/tool", name: "tool", bin: ["tool": "dist/run.js"], optional: ["tool-darwin-\(arch)"])
        _ = try scratch.file("lib/node_modules/tool/dist/package.json", #"{"type":"module"}"#)
        let platform = try scratch.npmPackage(
            "lib/node_modules/tool/node_modules/tool-darwin-\(arch)", name: "tool-darwin-\(arch)")
        try image([("__DATA", "__go_buildinfo", Data(count: 64))]).write(to: platform.appendingPathComponent("tool"))
        let script = scratch.root.appendingPathComponent("lib/node_modules/tool/dist/run.js")
        #expect(CLIRuntimeDetector.read(path: script.path)?.runtime == .go)
    }
}

// MARK: - Fixtures

private let rustHash: String = String(repeating: "0123456789", count: 3) + "abcdefabcd"
private let rustPath: String = "/rustc/\(rustHash)/library/core/src/fmt/mod.rs"
private let malformedRustPaths: [String] = [
    "/rustc/",
    "/rustc/\(rustHash.dropLast())/",
    "/rustc/\(rustHash.uppercased())/",
    "/rustc/\(rustHash)x",
]
private let shebangs: [(String, CLIRuntime)] = [
    ("#!/bin/bash\necho", .shell),
    ("#!/bin/sh -e\n", .shell),
    ("#!/usr/bin/env zsh\n", .shell),
    ("#!/usr/bin/env -S node --no-warnings\n", .node),
    ("#!/usr/bin/env node\n", .node),
    ("#!/Users/x/.venv/bin/python\n", .python),
    ("#!/usr/bin/env python3.12\n", .python),
    ("#!/usr/bin/env FOO=1 bun\n", .bun),
    ("#!/usr/bin/env -u HOME deno run\n", .deno),
    ("#!/usr/bin/ruby\n", .ruby),
    ("#!/usr/bin/perl -w\n", .perl),
]
private let unusableScripts: [(String, String)] = [
    ("nvm.sh", "# Node Version Manager\n# Implemented as a POSIX-compliant function\n"),
    ("run.js", "console.log('hi')\n"),
    ("tool", "#!/usr/bin/osascript\n"),
    ("tool", "#!/usr/bin/env\n"),
]

/// NUL-terminated strings, as a `__cstring` section holds them.
private func cstring(_ strings: String...) -> Data {
    Data(strings.flatMap { Array($0.utf8) + [0] })
}

/// A little-endian u64 — Bun's module-graph length header.
private func length(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

/// A thin arm64 Mach-O with one `LC_SEGMENT_64` per segment named, in order of
/// first appearance, each section's bytes laid down after the load commands.
private func image(_ sections: [(segment: String, name: String, bytes: Data)]) -> Data {
    var segments: [String] = []
    for section in sections where !segments.contains(section.segment) { segments.append(section.segment) }
    let commandSize = segments.count * 72 + sections.count * 80
    var dataOffset = 32 + commandSize
    var file = Data()
    file.le32(0xfeed_facf, 0x0100_000c, 0, 2, UInt32(segments.count), UInt32(commandSize), 0, 0)
    var payload = Data()
    for segment in segments {
        let own = sections.filter { $0.segment == segment }
        file.le32(0x19, UInt32(72 + 80 * own.count))
        file.name(segment)
        file.le64(0, 0, 0, 0)
        file.le32(5, 5, UInt32(own.count), 0)
        for section in own {
            file.name(section.name)
            file.name(section.segment)
            file.le64(0, UInt64(section.bytes.count))
            file.le32(UInt32(dataOffset), 0, 0, 0, 0, 0, 0, 0)
            payload.append(section.bytes)
            dataOffset += section.bytes.count
        }
    }
    return file + payload
}

/// A universal file: an x86_64 slice first, the arm64 one second.
private func fat(intel: Data, arm64: Data) -> Data {
    let alignment = 0x4000
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
    mutating func name(_ value: String) {
        append(contentsOf: Array(value.utf8) + [UInt8](repeating: 0, count: 16 - value.utf8.count))
    }
}

private struct Scratch {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-cliruntime-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func directory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func binary(_ name: String, _ sections: [(String, String, Data)]) throws -> URL {
        let url = root.appendingPathComponent(name)
        try image(sections.map { (segment: $0.0, name: $0.1, bytes: $0.2) }).write(to: url)
        return url
    }

    func file(_ relative: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try directory(url.deletingLastPathComponent())
        try Data(text.utf8).write(to: url)
        return url
    }

    /// A package directory with a `package.json`, and a `#!/usr/bin/env node`
    /// script at each bin target.
    func npmPackage(_ relative: String, name: String, bin: [String: String] = [:],
                    optional: [String] = []) throws -> URL {
        let url = try directory(root.appendingPathComponent(relative))
        var manifest: [String: Any] = ["name": name, "version": "1.0.0"]
        if !bin.isEmpty { manifest["bin"] = bin }
        if !optional.isEmpty { manifest["optionalDependencies"] = Dictionary(uniqueKeysWithValues: optional.map { ($0, "1.0.0") }) }
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appendingPathComponent("package.json"))
        for target in bin.values {
            _ = try file("\(relative)/\(target)", "#!/usr/bin/env node\nrequire('child_process')\n")
        }
        return url
    }

    /// `<root>/bin/<name>` → a relative destination, as npm links them.
    func binLink(_ name: String, to destination: String) throws -> URL {
        let bin = try directory(root.appendingPathComponent("bin"))
        let link = bin.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
        return link
    }
}
