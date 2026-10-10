import Foundation
import Synchronization

/// What a command-line tool is built with — the CLI tab's answer to "Rust? Swift?
/// Python?", as `AppRuntime` is the app list's.
///
/// The same doctrine as `AppRuntime`: every case is decided from something a
/// toolchain or packager *wrote* — a Mach-O section it had to emit, the module
/// list Go records, a string the GHC runtime or Rust's standard library compiles
/// in, the interpreter a script names on its `#!` line. Nothing is guessed from a
/// tool's name or vendor, nothing is inferred from a marker's absence, and nil
/// means the UI shows nothing. `CLIRuntimeDetector` holds the evidence and the
/// order it is asked in.
public enum CLIRuntime: String, Sendable, Hashable, CaseIterable, Codable {
    /// The Bun runtime: `bun` itself, or a `bun build --compile` executable.
    case bun
    /// A `deno compile` executable. Deno's own binary is a Rust program and reads
    /// as `.rust` — see the rule in `CLIRuntimeDetector`.
    case deno
    /// A Node.js script, or a Node single executable application.
    case node
    case go
    case swift
    case haskell
    case rust
    case python
    /// sh, bash, zsh and the other POSIX-family shells, fish included.
    case shell
    case ruby
    case perl
}

extension CLIRuntime {
    /// The runtime's name, as the CLI tab's tag and `duo` print it. Languages and
    /// runtimes keep their own names in every language; "Shell" is a
    /// description and is translated — from the app's catalog in the app, and in
    /// English in `duo`, which has none (see `CLIToolWording`).
    public var displayName: String {
        switch self {
        case .bun:     "Bun"
        case .deno:    "Deno"
        case .node:    "Node.js"
        case .go:      "Go"
        case .swift:   "Swift"
        case .haskell: "Haskell"
        case .rust:    "Rust"
        case .python:  "Python"
        case .ruby:    "Ruby"
        case .perl:    "Perl"
        case .shell:   String(localized: "Shell", comment: "CLI runtime label: a shell script (sh, bash, zsh, …)")
        }
    }
}

/// What one read of a tool's file says.
public struct CLIRuntimeReading: Sendable, Equatable {
    /// What the program that does the work is built with. Nil only under a
    /// `launcher` whose native binary was found but carries no marker this file
    /// recognises: a Node launcher is known, what it execs is not.
    public let runtime: CLIRuntime?
    /// Set when the file the user runs is a launcher for another one — today
    /// only `.node`, for an npm package whose JavaScript bin execs the native
    /// executable of its platform package (`<name>-darwin-<arch>`).
    public let launcher: CLIRuntime?
    /// The file `runtime` was read from — the native binary under a launcher.
    public let binary: String
    /// What decided `runtime`; nil exactly when `runtime` is.
    public let evidence: CLIRuntimeEvidence?

    /// "Go"; "Node.js → Go" under a launcher; "Node.js launcher" when what the
    /// launcher starts could not be identified. Nil when the reading names
    /// neither, which `CLIRuntimeDetector` never returns.
    public var title: String? {
        switch (launcher, runtime) {
        case (let launcher?, let runtime?): "\(launcher.displayName) → \(runtime.displayName)"
        case (let launcher?, nil):
            String(localized: "\(launcher.displayName) launcher",
                   comment: "CLI runtime label: a Node.js script that starts a native binary whose toolchain is unknown")
        case (nil, let runtime?): runtime.displayName
        case (nil, nil): nil
        }
    }

    public init(runtime: CLIRuntime?, launcher: CLIRuntime? = nil, binary: String,
                evidence: CLIRuntimeEvidence?) {
        self.runtime = runtime
        self.launcher = launcher
        self.binary = binary
        self.evidence = evidence
    }
}

/// The fact a verdict rests on, for a detail line and for the record.
public enum CLIRuntimeEvidence: Sendable, Equatable {
    /// `__BUN,__bun`. `compiled` is whether the section holds a module graph (a
    /// `bun build --compile` output) or the empty placeholder `bun` itself ships.
    case bunSection(compiled: Bool)
    /// `__SUI,d3n0l4nd`, where `deno compile` puts its payload.
    case denoSection
    /// A `NODE_SEA` segment — Node's single-executable blob.
    case nodeSEASegment
    /// `__go_buildinfo`, with the Go release that linked it where it parses.
    case goBuildInfo(goVersion: String?)
    /// `__TEXT,__swift5_entry`: the program's entry point is Swift.
    case swiftEntryPoint
    /// GHC's runtime-system info table in `__TEXT,__cstring`.
    case ghcRuntime
    /// cargo-auditable's `.dep-v0` dependency section.
    case cargoAuditable
    /// Rust standard-library source paths (`/rustc/<commit>/`) in `__TEXT,__cstring`.
    case rustStandardLibrary
    /// The interpreter a script's `#!` line names.
    case shebang(interpreter: String)
    /// A Python virtual environment's `pyvenv.cfg`.
    case pythonVirtualEnvironment

    /// Technical and untranslated — section names and interpreter names are
    /// the same words in every language, like the runtime names.
    public var summary: String {
        switch self {
        case .bunSection(let compiled):
            compiled ? "__BUN,__bun section (bun build --compile)" : "__BUN,__bun section (the Bun runtime)"
        case .denoSection: "__SUI,d3n0l4nd section (deno compile)"
        case .nodeSEASegment: "NODE_SEA segment (Node single executable)"
        case .goBuildInfo(let version): version.map { "__go_buildinfo section (\($0))" } ?? "__go_buildinfo section"
        case .swiftEntryPoint: "__swift5_entry section"
        case .ghcRuntime: "GHC runtime system strings"
        case .cargoAuditable: ".dep-v0 section (cargo auditable)"
        case .rustStandardLibrary: "Rust standard library paths"
        case .shebang(let interpreter): "#! \(interpreter)"
        case .pythonVirtualEnvironment: "pyvenv.cfg (Python virtual environment)"
        }
    }
}

/// Reads a CLI tool's file and says what it was built with.
///
/// **Precedence**, and why each step sits where it does:
///
/// 1. **Packaged runtimes**, read off a Mach-O section their packager writes.
///    They come first because the program inside them is JavaScript, and the
///    native code around it is the runtime's — which carries other toolchains'
///    traces. Measured 2026-10-10: Claude Code (239 MB) and OpenCode (144 MB) are
///    Bun-compiled and have `/rustc/<hash>/` strings, all of them inside the
///    `__BUN,__bun` payload; Bun's own sources are now Rust besides.
///    - **Bun**: `__BUN,__bun`. `src/exe_format/macho.rs` writes it and
///      `StandaloneModuleGraph.rs` finds it by `getsegbyname("__BUN")`
///      (oven-sh/bun, main, 2026-10-10). The section opens with a u64 payload
///      length — zero in `bun` itself (1.4.2: a 16 KiB zeroed placeholder), the
///      module graph's size in a compiled output. Both read as Bun.
///    - **Deno**: `__SUI,d3n0l4nd`. `deno compile` calls
///      `libsui::Macho::write_section("d3n0l4nd", …)` (denoland/deno
///      `cli/standalone/binary.rs`), and libsui puts named sections in segment
///      `__SUI` (denoland/sui `lib.rs`, `SEGNAME`). That is arm64 only — on
///      x86_64 libsui appends the payload behind a sentinel instead, which this
///      does not read. Deno's *own* binary has no such section; it is a Rust
///      program and step 3 says so, which is the honest label for it.
///    - **Node SEA**: a `NODE_SEA` segment. Node's documentation has the blob
///      injected "as a section named NODE_SEA_BLOB in the NODE_SEA segment"
///      (nodejs.org/api/single-executable-applications.html), and postject
///      prefixes the section `__` (nodejs/postject `postject-api.h`). Matched
///      by segment so either spelling of the section counts. The `node` binary
///      itself carries only the sentinel fuse string, which is not this.
///
///    Not here: vercel/pkg (an appended payload with no section or documented
///    trailer to find it by) and PyInstaller (its archive cookie sits at the end
///    of an appended archive, ahead of the code signature, and none was installed
///    to measure against). Both read as whatever the rules below find, usually
///    nothing.
/// 2. **Go, Swift, Haskell** — each a mark only its own toolchain makes.
///    - **Go**: the `__go_buildinfo` section `MachOImports` already locates
///      (see `GoBuildInfo`). Its presence decides; the parsed Go version is
///      only for the detail line.
///    - **Swift**: `__TEXT,__swift5_entry`, which the Swift compiler emits for
///      the module holding the program's entry point. Deliberately not the other
///      `__swift5_*` sections or a `libswiftCore` link: those say only that some
///      Swift is linked in, and measured 2026-10-10 `/usr/bin/codesign` and
///      `/usr/bin/log` have them without the entry section.
///    - **Haskell**: ` [("GHC RTS", "YES")` in `__TEXT,__cstring` — what GHC's
///      `printRtsInfo` prints for `+RTS --info` (ghc/ghc `rts/RtsUtils.c`; the
///      compiler drops its trailing newline into a `puts`). Every GHC-linked
///      program carries its runtime system, so it carries this.
/// 3. **Rust, last.** Its evidence is real but not exclusive: any program that
///    statically links a Rust library carries it. So it decides only once
///    nothing stronger has.
///    - cargo-auditable's `.dep-v0` section ("placed in a linker section named
///      `.dep-v0`", rust-secure-code/cargo-auditable README), or
///    - `/rustc/<40 hex>/` in `__TEXT,__cstring`: rustup's standard library is
///      built with its source paths remapped to `/rustc/<commit hash>/`, and
///      panic locations keep them. Read from `__cstring` only, which is where
///      every Rust binary measured kept them (uv, zoxide, mise, rustup, deno,
///      pnpm 12) — and not where the Bun payloads above did.
/// 4. **Scripts**, by the interpreter their `#!` line names — through `env`,
///    with its options skipped. A file with no `#!` reads as nothing, whatever
///    its extension says: `nvm.sh` is sourced, not run, and declares no shell.
///
/// A **directory** is read by what its tool wrote into it: `package.json` makes
/// it an npm package, read through the command it runs (below); `pyvenv.cfg`
/// makes it a Python virtual environment — the file `venv` writes into every
/// environment it creates (docs.python.org/3/library/venv.html), which uv's
/// environments carry too. bub's row is its venv, so that is what it reads by.
///
/// A Node script inside an npm package gets one more look: when the package
/// declares a platform package `<name>-darwin-<arch>` among its
/// `optionalDependencies` or `dependencies` (the convention esbuild popularised;
/// scoped names keep their scope) and that package holds a Mach-O executable
/// named for one of the package's commands, the verdict is that binary's, under
/// a `.node` launcher. The launcher's JavaScript is never parsed — whether it
/// really execs that binary is the convention's claim, not this file's.
///
/// **Cost.** Steps 1 and 2 (bar Haskell) are the load-command pass `MachOImports`
/// makes, bounded by the load-command region whatever the file's size. Only a
/// binary none of them settles pays for a byte read, and that read is one
/// section, `__TEXT,__cstring`, capped at `cstringLimit` — not the file. Each
/// binary's verdict is kept for the process, keyed by path, inode, size and
/// modification time, so a re-check of an unchanged tool reads nothing.
public enum CLIRuntimeDetector {

    /// Larger than any `__TEXT,__cstring` measured (Node's: 10.4 MB) with room
    /// to spare. A bigger section is not read, and neither Haskell nor Rust is
    /// then claimed from it.
    static let cstringLimit: UInt64 = 32 << 20

    /// The npm architecture name for the platform package this host would run.
    static let npmArchitecture: String = {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }()

    /// What the tool at `path` is built with. `path` may be a symlink, an
    /// executable, a script, or an npm package's directory (an npm row's path);
    /// nil when nothing proves anything. Blocking — reads files.
    public static func read(path: String) -> CLIRuntimeReading? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            if let program = programFile(inPackage: url) { return readFile(program, packageRoot: url) }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) {
                return CLIRuntimeReading(runtime: .python, binary: url.path, evidence: .pythonVirtualEnvironment)
            }
            return nil
        }
        return readFile(url, packageRoot: nil)
    }

    // MARK: - One file

    static func readFile(_ url: URL, packageRoot: URL?) -> CLIRuntimeReading? {
        switch verdict(at: url) {
        case .machO(let runtime, let evidence):
            guard let runtime else { return nil }
            return CLIRuntimeReading(runtime: runtime, binary: url.path, evidence: evidence)
        case .script(let interpreter):
            guard let runtime = runtime(ofInterpreter: interpreter) else { return nil }
            let own = CLIRuntimeReading(runtime: runtime, binary: url.path,
                                        evidence: .shebang(interpreter: interpreter))
            guard runtime == .node,
                  let root = packageRoot ?? enclosingPackage(of: url),
                  let native = platformExecutable(forPackageAt: root)
            else { return own }
            guard case .machO(let nativeRuntime, let evidence) = verdict(at: native) else { return own }
            return CLIRuntimeReading(runtime: nativeRuntime, launcher: .node, binary: native.path,
                                     evidence: evidence)
        case .unknown:
            return nil
        }
    }

    /// What one file is, as far as its own bytes say.
    enum Verdict: Sendable, Equatable {
        /// A Mach-O image; nil when no rule recognised it.
        case machO(CLIRuntime?, CLIRuntimeEvidence?)
        /// A `#!` script, by interpreter basename (`python3.12`, `bash`).
        case script(interpreter: String)
        /// Neither, or unreadable.
        case unknown
    }

    /// A file's identity for the cache: the same path can be replaced in place by
    /// an update, which changes at least one of the other three.
    struct FileKey: Hashable, Sendable {
        let path: String
        let inode: UInt64
        let size: UInt64
        let modified: Date
    }

    private static let cache = Mutex<[FileKey: Verdict]>([:])

    static func verdict(at url: URL) -> Verdict {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date
        else { return .unknown }
        let key = FileKey(path: url.path, inode: inode, size: size, modified: modified)
        if let known = cache.withLock({ $0[key] }) { return known }
        let found = uncachedVerdict(at: url)
        cache.withLock { $0[key] = found }
        return found
    }

    /// Forgets every remembered verdict. For tests, which rewrite one fixture
    /// path within the same second.
    static func clearCache() { cache.withLock { $0.removeAll() } }

    static func uncachedVerdict(at url: URL) -> Verdict {
        if let commands = MachOImports.loadCommands(at: url) {
            let (runtime, evidence) = machOVerdict(commands, at: url)
            return .machO(runtime, evidence)
        }
        if let interpreter = shebangInterpreter(at: url) { return .script(interpreter: interpreter) }
        return .unknown
    }

    // MARK: - Mach-O

    /// The rules, in the order the type's documentation gives.
    static func machOVerdict(
        _ commands: MachOImports.LoadCommands, at url: URL, cstringLimit: UInt64 = CLIRuntimeDetector.cstringLimit
    ) -> (CLIRuntime?, CLIRuntimeEvidence?) {
        // 1. Packaged runtimes.
        if let bun = commands.section("__BUN", "__bun") {
            let length = bun.range.size >= 8 ? readBytes(url, bun.range.offset, 8) : nil
            let compiled = length.map { $0.contains { $0 != 0 } } ?? false
            return (.bun, .bunSection(compiled: compiled))
        }
        if commands.section("__SUI", "d3n0l4nd") != nil { return (.deno, .denoSection) }
        if commands.sections.contains(where: { $0.segment == "NODE_SEA" }) { return (.node, .nodeSEASegment) }

        // 2. Go, Swift, Haskell.
        if let range = commands.goBuildInfo {
            return (.go, .goBuildInfo(goVersion: GoBuildInfo.read(at: url, section: range)?.goVersion))
        }
        if commands.section("__TEXT", "__swift5_entry") != nil { return (.swift, .swiftEntryPoint) }

        let strings: Data? = commands.section("__TEXT", "__cstring").flatMap { section in
            guard section.range.offset > 0, section.range.size <= cstringLimit else { return nil }
            return readBytes(url, section.range.offset, Int(section.range.size))
        }
        if let strings, contains(strings, ghcRuntimeInfo) { return (.haskell, .ghcRuntime) }

        // 3. Rust.
        if commands.sections.contains(where: { $0.name == ".dep-v0" }) { return (.rust, .cargoAuditable) }
        if let strings, containsRustStandardLibraryPath(strings) { return (.rust, .rustStandardLibrary) }
        return (nil, nil)
    }

    /// `printRtsInfo`'s opening line, as the compiler leaves it in `__cstring`.
    static let ghcRuntimeInfo = Data(#" [("GHC RTS", "YES")"#.utf8)

    /// `/rustc/` followed by a 40-digit lowercase hex commit hash and a slash.
    static func containsRustStandardLibraryPath(_ data: Data) -> Bool {
        let prefix = Array("/rustc/".utf8)
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                guard let hit = memmem(base + offset, raw.count - offset, prefix, prefix.count) else { return false }
                let start = base.distance(to: UnsafeRawPointer(hit))
                let hash = start + prefix.count
                if hash + 41 <= raw.count,
                   (0..<40).allSatisfy({ isLowerHex(raw[hash + $0]) }),
                   raw[hash + 40] == UInt8(ascii: "/") {
                    return true
                }
                offset = start + 1
            }
            return false
        }
    }

    private static func isLowerHex(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }

    static func contains(_ data: Data, _ needle: Data) -> Bool {
        data.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { needle in
                guard let h = haystack.baseAddress, let n = needle.baseAddress, needle.count > 0 else { return false }
                return memmem(h, haystack.count, n, needle.count) != nil
            }
        }
    }

    /// A bounded `read(2)`, never a mapping — see `ExecutableBytes` for why a
    /// mapped read of another vendor's executable can kill a hardened process.
    static func readBytes(_ url: URL, _ offset: UInt64, _ count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count), data.count == count
        else { return nil }
        return data
    }

    // MARK: - Scripts

    /// The interpreter's basename from a `#!` line, through `env` and its
    /// options (`#!/usr/bin/env -S node --flag`). Nil for anything that is not
    /// a `#!` file.
    static func shebangInterpreter(at url: URL) -> String? {
        guard let head = readBytes(url, 0, 2), head == Data("#!".utf8),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 512) else { return nil }
        return shebangInterpreter(line: bytes)
    }

    static func shebangInterpreter(line bytes: Data) -> String? {
        guard bytes.starts(with: Data("#!".utf8)) else { return nil }
        let line = bytes.dropFirst(2).prefix { $0 != UInt8(ascii: "\n") && $0 != UInt8(ascii: "\r") }
        let words = String(decoding: line, as: UTF8.self)
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard var interpreter = words.first.map({ ($0 as NSString).lastPathComponent }) else { return nil }
        if interpreter == "env" {
            var rest = words.dropFirst()
            while let word = rest.first {
                if word == "-u" || word == "-P" { rest = rest.dropFirst(2); continue }
                if word.hasPrefix("-") || word.contains("=") { rest = rest.dropFirst(); continue }
                break
            }
            guard let named = rest.first else { return nil }
            interpreter = (named as NSString).lastPathComponent
        }
        return interpreter.isEmpty ? nil : interpreter
    }

    /// An interpreter's basename → runtime, a trailing version stripped
    /// (`python3.12`, `bash5`). Nil for any interpreter not listed.
    static func runtime(ofInterpreter name: String) -> CLIRuntime? {
        let family = String(name.reversed().drop { $0.isNumber || $0 == "." }.reversed())
        switch family {
        case "sh", "bash", "zsh", "dash", "ksh", "mksh", "fish": return .shell
        case "node", "nodejs": return .node
        case "python", "pythonw": return .python
        case "bun": return .bun
        case "deno": return .deno
        case "ruby": return .ruby
        case "perl": return .perl
        default: return nil
        }
    }

    // MARK: - npm packages

    /// A package's `package.json`, or nil when it has none or it is not an object.
    static func manifest(_ root: URL) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: root.appendingPathComponent("package.json").path)
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `name` without its `@scope/`.
    static func unscoped(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// The package's commands, `bin` key → target relative to the package.
    static func commands(_ manifest: [String: Any]) -> [String: String] {
        if let map = manifest["bin"] as? [String: String] { return map }
        if let single = manifest["bin"] as? String, let name = manifest["name"] as? String {
            return [unscoped(name): single]
        }
        return [:]
    }

    /// The file an npm row's package runs: its command named after the package,
    /// or its only command. Through the prefix's `bin/` link when that link
    /// resolves into the package — npm or a postinstall may point it somewhere
    /// other than `package.json` says (agent-browser's points straight at its
    /// native binary) and the link is what runs.
    static func programFile(inPackage root: URL) -> URL? {
        guard let manifest = manifest(root), let name = manifest["name"] as? String else { return nil }
        let bins = commands(manifest)
        let command = bins[unscoped(name)] != nil ? unscoped(name) : (bins.count == 1 ? bins.keys.first : nil)
        guard let command, let target = bins[command] else { return nil }

        // `<prefix>/lib/node_modules/[@scope/]name` → `<prefix>/bin/<command>`.
        var prefix = root.deletingLastPathComponent()
        if prefix.lastPathComponent.hasPrefix("@") { prefix = prefix.deletingLastPathComponent() }
        if prefix.lastPathComponent == "node_modules",
           prefix.deletingLastPathComponent().lastPathComponent == "lib" {
            let link = prefix.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("bin").appendingPathComponent(command)
            let resolved = link.resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: resolved.path),
               resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") {
                return resolved
            }
        }
        let file = root.appendingPathComponent(target).standardizedFileURL.resolvingSymlinksInPath()
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The installed package a file belongs to: the nearest directory above it
    /// that sits directly in a `node_modules` (or in a scope inside one) and has
    /// a named `package.json`. A `package.json` deeper down without that place —
    /// a `dist/package.json` holding only `"type": "module"` — is passed over.
    static func enclosingPackage(of file: URL) -> URL? {
        var directory = file.deletingLastPathComponent()
        for _ in 0..<8 {
            let parent = directory.deletingLastPathComponent()
            let inNodeModules = parent.lastPathComponent == "node_modules"
                || (parent.lastPathComponent.hasPrefix("@")
                    && parent.deletingLastPathComponent().lastPathComponent == "node_modules")
            if inNodeModules, manifest(directory)?["name"] is String { return directory }
            if directory.lastPathComponent == "node_modules" || directory.path == "/" { return nil }
            directory = parent
        }
        return nil
    }

    /// The native executable of the package's own platform package, if it
    /// declares one and it is installed — nested in the package's
    /// `node_modules` or hoisted beside it.
    static func platformExecutable(forPackageAt root: URL) -> URL? {
        guard let manifest = manifest(root), let name = manifest["name"] as? String else { return nil }
        let platform = "\(name)-darwin-\(npmArchitecture)"
        let declared = ["optionalDependencies", "dependencies"].contains {
            (manifest[$0] as? [String: Any])?[platform] != nil
        }
        guard declared else { return nil }

        var hoisted = root.deletingLastPathComponent()
        if name.hasPrefix("@") { hoisted = hoisted.deletingLastPathComponent() }
        let places = [root.appendingPathComponent("node_modules"), hoisted]
            .map { $0.appendingPathComponent(platform) }
        let names = Array(Set(commands(manifest).keys).union([unscoped(name)])).sorted()
        let fm = FileManager.default
        for place in places where fm.fileExists(atPath: place.appendingPathComponent("package.json").path) {
            var candidates: [String] = []
            if let own = self.manifest(place) {
                candidates += commands(own).sorted { $0.key < $1.key }.map(\.value)
            }
            candidates += names.flatMap { ["bin/\($0)", $0] }
            for candidate in candidates {
                let url = place.appendingPathComponent(candidate).standardizedFileURL
                guard url.path.hasPrefix(place.path + "/") else { continue }
                if case .machO = verdict(at: url.resolvingSymlinksInPath()) { return url.resolvingSymlinksInPath() }
            }
        }
        return nil
    }
}
