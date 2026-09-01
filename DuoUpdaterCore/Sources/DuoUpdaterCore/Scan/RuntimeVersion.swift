import Foundation

/// The version of the runtime an app was built with — "Electron 42.4.1", "Qt 6.2".
///
/// Only for the four runtimes where a version can be read as a *fact*. The others
/// are left blank on purpose, and the reasons are worth keeping because each looks
/// like it would work:
///
/// - **Chromium** publishes three different things under one roof. Chrome's own
///   framework reports the Chrome version (152.0.7977.65), Spotify's embedded CEF
///   reports the CEF version (146.0.10.0), and Helium's fork reports *Helium's app
///   version* (0.16.2.1). Printing any of them after the word "Chromium" would be
///   wrong for two apps out of three.
/// - **Flutter**'s embedder carries the *app's* version, not the framework's:
///   LocalSend's `FlutterMacOS.framework` says 1.18.2, which is LocalSend. Two
///   other Flutter apps say a placeholder 1.0.
/// - **Native**, **Catalyst** and **iOS App** are not versioned things.
public enum RuntimeVersion {

    /// Reads the runtime version, or nil where there is nothing trustworthy to read.
    ///
    /// - Parameter scanningBinaries: whether to allow the one reader that has to
    ///   walk the executable (Tauri, and the two rebranded Electron shapes). Off
    ///   during a scan, where it would be paid for every app on the machine, and on
    ///   when a single app's detail is being shown.
    ///
    ///   `.tauri` is the exception: it arrives here with scanning on even during a
    ///   scan, because for that runtime the walk *is* the detection — but only for
    ///   the two or three bundles `AppRuntimeDetector` has already narrowed to. See
    ///   `carriesTauriCrate(bundleAt:infoPlist:)`.
    public static func read(
        _ runtime: AppRuntime,
        bundleAt bundleURL: URL,
        appVersion: String?,
        scanningBinaries: Bool
    ) -> String? {
        // Three of these readers can walk a whole binary — a second on a large one
        // — so the answer is remembered against the app's own version.
        //
        // The lookup deliberately sits *above* the `scanningBinaries` guard: a
        // remembered answer costs nothing, so a caller that forbade scanning still
        // gets it. That is what lets a version paid for once, by opening one app's
        // detail, be available to everything afterwards. An app that has
        // not been updated cannot have changed its runtime, and one that has gets a
        // new key rather than a stale answer. Nil is cached too: "no Tauri crate in
        // here" is an answer, and it is the expensive one to reach.
        let key = "\(bundleURL.path)|\(appVersion ?? "?")|\(runtime.rawValue)"
        if let remembered = cached(key) { return remembered }

        let version: String?
        switch runtime {
        case .electron:
            // The re-signed case needs a scan; the ordinary one does not, and
            // `electronVersion` takes the cheap path first either way.
            version = electronVersion(bundleAt: bundleURL, scanning: scanningBinaries)
        case .qt:       version = qtVersion(bundleAt: bundleURL)
        case .java:     version = javaVersion(bundleAt: bundleURL)
        case .tauri:
            guard scanningBinaries else { return nil }
            version = tauriVersion(bundleAt: bundleURL)
        case .chromium:
            guard scanningBinaries else { return nil }
            version = chromiumVersion(bundleAt: bundleURL)
        case .flutter, .native, .catalyst, .iOSApp:
            version = nil
        }
        remember(version, for: key)
        return version
    }

    /// Remembered answers, keyed by bundle path, app version and runtime. Only ever
    /// grows by one entry per app per update, and only for apps whose detail has
    /// actually been opened.
    ///
    /// `Synchronization.Mutex` would be the modern way to hold this and needs
    /// macOS 15; the package targets 14. A lock around a dictionary is what the
    /// rest of this package does.
    private nonisolated(unsafe) static var cache: [String: String?] = [:]
    private static let cacheLock = NSLock()

    /// `.some(nil)` is a remembered "there is no version here" — the expensive
    /// answer, and the one most worth not paying for twice.
    private static func cached(_ key: String) -> String?? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func remember(_ version: String?, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[key] = version
    }

    // MARK: - Electron

    /// Electron's version, from its framework — by plist where that can be
    /// trusted, and from the framework's user-agent string where it cannot.
    ///
    /// Three shapes, found by asking three questions in order. The plist is only
    /// trustworthy for the first:
    ///
    /// - **Renamed, identifier intact.** QQ ships it as `QQNT.framework` and still
    ///   declares `com.github.Electron.framework` with the real version. Found by
    ///   identifier rather than by directory name, so the rename costs nothing.
    /// - **Re-signed under the app's own prefix.** Kiro's declares
    ///   `dev.kiro.desktop.com.github.Electron.framework` and its `CFBundleVersion`
    ///   is `1.0.411` — *Kiro's* version. Its real Electron is 39.6.0, which only
    ///   the binary knows.
    /// - **Re-identified entirely.** ChatGPT ships `Codex Framework.framework` as
    ///   `com.openai.codex.framework`; nothing says Electron anywhere in the plist.
    ///   The `<product> Framework.framework` naming is the last thread, and it is a
    ///   sound one — it is Chromium's own convention, and `Sparkle.framework`
    ///   sitting beside it does not match.
    ///
    /// Only the first is free. The other two pay for a scan, cached against the
    /// app's version. Verified against six installed Electron apps: VS Code 42.8.1,
    /// Notion 42.4.1, Claude 42.10.0, Cursor 40.10.3 and QQ 40.0.0 take the instant
    /// path and agree with their user-agent to the digit; Kiro needs the scan and
    /// yields 39.6.0.
    ///
    /// ChatGPT is the one that yields nothing, and it is worth writing down so the
    /// next person does not go looking again. It *is* Electron — its Info.plist
    /// carries `ElectronAsarIntegrity`, which only Electron writes — but OpenAI has
    /// rebranded the framework completely: renamed to `Codex Framework.framework`,
    /// re-identified as `com.openai.codex.framework`, versioned by directory the way
    /// Chrome does (`Versions/151.0.7922.174/`), and with the `Electron/` token
    /// stripped from the user-agent, which reads only `Chrome/151.0.7922.174`. The
    /// runtime identifies itself as `owl` rather than as Electron, which is why the
    /// token is missing rather than merely hidden. That number is the Chromium
    /// build, not the Electron release, and turning one into the other needs a
    /// mapping table this does not have. No version is the honest answer.
    private static func electronVersion(bundleAt bundleURL: URL, scanning: Bool) -> String? {
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        var resigned: URL?
        var unmarked: URL?
        for name in names where name.hasSuffix(".framework") {
            let framework = frameworks.appendingPathComponent(name)
            if name.hasSuffix(" Framework.framework") { unmarked = framework }
            guard let plist = frameworkPlist(framework),
                  let identifier = plist["CFBundleIdentifier"] as? String,
                  identifier.hasSuffix(electronFrameworkID)
            else { continue }
            if identifier == electronFrameworkID,
               let version = plist["CFBundleVersion"] as? String, !version.isEmpty {
                return version
            }
            resigned = framework
        }
        guard scanning, let framework = resigned ?? unmarked else { return nil }
        let executableName = String(framework.lastPathComponent.dropLast(".framework".count))
        for path in ["Versions/A/\(executableName)", executableName] {
            let binary = framework.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: binary.path) else { continue }
            return scan(binary, for: "Electron/", components: 3)
        }
        return nil
    }

    private static let electronFrameworkID = "com.github.Electron.framework"

    // MARK: - Qt

    /// Qt's version, from the executable's own load command for QtCore.
    ///
    /// Read from the link record rather than from `QtCore.framework/Info.plist`
    /// because only some apps have one: `macdeployqt` produces frameworks for some
    /// builds and bare dylibs for others, and a dylib carries no plist. Measured on
    /// six installed Qt apps — Moonlight, DB Browser, HBuilderX, CapCut and
    /// Parallels ship frameworks; KeePassXC ships `libQt5Core.5.15.18.dylib` and
    /// Raspberry Pi Imager ships `libQt6Core.6.dylib`, and neither had anything to
    /// read. The linker's `current_version` is there in every case, and it is more
    /// precise besides: DingTalk's plist-less QtCore records 5.15.2 where a
    /// framework plist would have said 5.15.
    ///
    /// The plist stays as a fallback for an app that reaches Qt indirectly — if
    /// nothing in the main executable names QtCore, there is no load command to read.
    private static func qtVersion(bundleAt bundleURL: URL) -> String? {
        if let executable = executableURL(bundleAt: bundleURL),
           let dylibs = MachOImports.loadedDylibs(at: executable),
           let entry = dylibs.first(where: { isQtCore($0.key) }),
           entry.value != "0.0.0" {
            return entry.value
        }
        let core = bundleURL.appendingPathComponent("Contents/Frameworks/QtCore.framework")
        guard let plist = frameworkPlist(core),
              let version = plist["CFBundleShortVersionString"] as? String, !version.isEmpty
        else { return nil }
        return version
    }

    /// `@rpath/QtCore.framework/Versions/5/QtCore` or `@rpath/libQt6Core.6.dylib`.
    private static func isQtCore(_ installName: String) -> Bool {
        installName.contains("/QtCore.framework/")
            || installName.range(of: #"/libQt[0-9]*Core\."#, options: .regularExpression) != nil
    }

    /// The bundle's main executable, from its own Info.plist.
    private static func executableURL(bundleAt bundleURL: URL) -> URL? {
        let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist"))
        guard let name = info?["CFBundleExecutable"] as? String, !name.isEmpty else { return nil }
        let url = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Java

    /// The bundled runtime's own `release` file — `JAVA_VERSION="21.0.8"`.
    /// JetBrains keeps it under `jbr`; `jpackage` output uses `runtime`.
    private static func javaVersion(bundleAt bundleURL: URL) -> String? {
        for directory in ["jbr", "runtime"] {
            let release = bundleURL
                .appendingPathComponent("Contents/\(directory)/Contents/Home/release")
            guard let text = try? String(contentsOf: release, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.hasPrefix("JAVA_VERSION=") {
                let value = line.dropFirst("JAVA_VERSION=".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"\r "))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    // MARK: - Tauri

    /// Tauri compiles into the executable, so the only record of its version is the
    /// Cargo dependency path Rust bakes into panic metadata:
    /// `…/registry/src/…/tauri-2.11.5/src/lib.rs`.
    ///
    /// `tauri-runtime-wry-2.11.4` deliberately does not match: the character after
    /// the prefix has to be a digit, so only the framework crate itself is read.
    private static func tauriVersion(bundleAt bundleURL: URL) -> String? {
        guard let executable = executableURL(bundleAt: bundleURL) else { return nil }
        return scan(executable, for: "tauri-", components: 3)
    }

    /// Whether this bundle is Tauri at all — `AppRuntimeDetector`'s proof, not a
    /// display value.
    ///
    /// One read answers both questions, so they share one cache entry: either a
    /// crate path is there or it is not, and if it is, its version is right beside
    /// it. The detector asks this during a scan and the app's detail view asks
    /// `read(_:bundleAt:appVersion:scanningBinaries:)` later; both land on the same
    /// key, so the walk happens once per app version rather than once per asker.
    ///
    /// The key's version comes from the same `CFBundleShortVersionString` the scan
    /// stores as `InstalledApp.shortVersion` and the detail view passes back. The
    /// two agree for everything that can reach here — the scan rewrites that string
    /// only for Xcode and JetBrains bundles, and neither is cargo-bundled — and if
    /// they ever disagreed the cost would be a second walk, not a wrong answer.
    ///
    /// A nil is a real answer and is remembered as one: proving that a 262 MB
    /// binary contains no `tauri-` crate means reading all of it, which is the
    /// expensive case and so the one most worth paying for exactly once.
    public static func carriesTauriCrate(bundleAt bundleURL: URL, infoPlist: [String: Any]) -> Bool {
        read(.tauri, bundleAt: bundleURL,
             appVersion: infoPlist["CFBundleShortVersionString"] as? String,
             scanningBinaries: true) != nil
    }

    /// Walks a binary looking for `<needle><version>`, in chunks so a 261 MB
    /// executable never lands in memory at once.
    private static func scan(_ binary: URL, for prefix: String, components: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: binary) else { return nil }
        defer { try? handle.close() }

        let needle = Array(prefix.utf8)
        // Read in chunks, overlapping by enough that a version straddling a
        // boundary is still whole in one of them.
        let chunkSize = 4 * 1024 * 1024
        let overlap = 64
        var carry = Data()
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            var window = carry
            window.append(chunk)
            if let version = firstVersion(in: Array(window), after: needle, components: components) {
                return version
            }
            carry = window.suffix(overlap)
            if chunk.count < chunkSize { break }
        }
        return nil
    }

    /// The first `<needle><major>.<minor>.<patch>` in `bytes`, where the character
    /// before the needle is not part of a longer identifier.
    private static func firstVersion(in bytes: [UInt8], after needle: [UInt8], components: Int) -> String? {
        guard bytes.count > needle.count else { return nil }
        let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        let dot = UInt8(ascii: ".")
        let dash = UInt8(ascii: "-")
        outer: for index in 0...(bytes.count - needle.count - 1) {
            for offset in 0..<needle.count where bytes[index + offset] != needle[offset] { continue outer }
            if index > 0 {
                let before = bytes[index - 1]
                let isIdentifier = digits.contains(before) || before == dash
                    || (before | 0x20) >= UInt8(ascii: "a") && (before | 0x20) <= UInt8(ascii: "z")
                if isIdentifier { continue }
            }
            var cursor = index + needle.count
            var version = ""
            var dots = 0
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if digits.contains(byte) {
                    version.append(Character(UnicodeScalar(byte)))
                } else if byte == dot, dots < components - 1, !version.isEmpty, version.last != "." {
                    dots += 1
                    version.append(".")
                } else {
                    break
                }
                cursor += 1
            }
            if dots == components - 1, let last = version.last, last.isNumber { return version }
        }
        return nil
    }

    // MARK: - Chromium

    /// The Chromium build an app embeds, read from the user-agent string its
    /// framework carries: `Chrome/152.0.7977.65`.
    ///
    /// The framework's `CFBundleShortVersionString` is the obvious place and it is
    /// only sometimes the right number. Measured across four apps: Chrome's own
    /// framework reports the Chrome version (which is the Chromium version), an
    /// embedded CEF reports the *CEF* version (146.0.10.0 — the leading number is
    /// the Chromium major and the rest is CEF's own), and Helium, a Chrome fork,
    /// reports **its own app version** (0.16.2.1). The user-agent is the one field
    /// that means the same thing in all three: Helium's says 152.0.7977.64, which
    /// is the Chromium it actually ships.
    ///
    /// It costs a walk of the framework binary — about a second — which is why this
    /// only runs on demand and why the answer is cached against the app's version.
    private static func chromiumVersion(bundleAt bundleURL: URL) -> String? {
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        guard let name = names.first(where: { $0.hasSuffix(" Framework.framework") }) else { return nil }
        let framework = frameworks.appendingPathComponent(name)
        let executableName = String(name.dropLast(".framework".count))
        for path in ["Versions/A/\(executableName)", executableName] {
            let binary = framework.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: binary.path) else { continue }
            return scan(binary, for: "Chrome/", components: 4)
        }
        return nil
    }

    // MARK: -

    /// A framework's `Info.plist`, which sits under `Versions/A` in a versioned
    /// bundle and directly under `Resources` in a flat one.
    private static func frameworkPlist(_ framework: URL) -> [String: Any]? {
        for path in ["Versions/A/Resources/Info.plist", "Resources/Info.plist"] {
            let url = framework.appendingPathComponent(path)
            if let plist = NSDictionary(contentsOf: url) as? [String: Any] { return plist }
        }
        return nil
    }
}
