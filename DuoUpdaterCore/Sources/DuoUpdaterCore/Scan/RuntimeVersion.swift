import Foundation

/// The version of the runtime an app was built with — "Electron 42.4.1", "Qt 6.2".
///
/// Only where a version can be read as a *fact*. The rest are left blank on
/// purpose, and the reasons are worth keeping because each looks like it would
/// work:
///
/// - **Flutter**'s embedder carries the *app's* version, not the framework's:
///   LocalSend's `FlutterMacOS.framework` says 1.18.2, which is LocalSend. Two
///   other Flutter apps say a placeholder 1.0.
/// - **Native**, **Catalyst** and **iOS App** are not versioned things.
///
/// **Chromium used to be on that list and no longer is**, which is worth spelling
/// out because the reason it was there is still true of the obvious source. Its
/// framework *plist* reports three different things depending on the app — Chrome's
/// own says the Chrome version (152.0.7977.65), Spotify's embedded CEF says the CEF
/// version (146.0.10.0), and Helium's fork says *Helium's app version* (0.16.2.1),
/// so printing that after the word "Chromium" would be wrong for two apps in three.
/// `chromiumVersion` reads no plist: it takes the `Chrome/<version>` token out of
/// the framework's user-agent string, which is the engine describing itself and
/// agrees for all three.
public enum RuntimeVersion {

    /// Reads the runtime version, or nil where there is nothing trustworthy to read.
    ///
    /// - Parameter scanningBinaries: whether to allow the readers that walk a whole
    ///   binary — the two rebranded Electron shapes, and Chromium's user-agent. Off
    ///   when the caller would pay it for every app on the machine, on when a single
    ///   app's detail is being shown.
    ///
    ///   It is **not** a promise that a library-wide scan never walks a binary, and
    ///   it stopped being one in this branch: `.tauri` arrives here with scanning on
    ///   from inside the scan itself, because for that runtime the walk *is* the
    ///   detection. What keeps that affordable is not this flag but the filter in
    ///   `AppRuntimeDetector`, which admits six bundles out of about a hundred and
    ///   fifty. See `carriesTauriCrate(bundleAt:)`.
    public static func read(
        _ runtime: AppRuntime,
        bundleAt inputBundleURL: URL,
        scanningBinaries: Bool
    ) -> String? {
        // Read from wherever the runtime actually is. For a wrapper whose interface
        // is a nested bundle — Docker's `Contents/MacOS/Docker Desktop.app` — every
        // reader below would look in a `Contents/Frameworks` that does not exist and
        // report no version for a bundle that carries one. For the ordinary bundle it
        // returns the bundle it was given and nothing changes. See #208.
        //
        // The cache key follows, because it is derived from `bundleURL` below: the
        // entry is keyed on the nested executable, which is the one whose bytes the
        // answer was read from and the one an update rewrites.
        //
        // `.tauri` is deliberately exempt, for two reasons that happen to want the
        // same thing. It is the one runtime that is *compiled into the executable*
        // rather than shipped beside it, so a crate path found in a nested binary
        // is a fact about that binary and about nothing else — following the
        // redirect would let a nested bundle lend its identity to its wrapper,
        // which is the error this whole rule exists to prevent.
        //
        // And it is the edge that would close a cycle. `carriesTauriCrate` is this
        // function; `AppRuntimeDetector` calls it, `interfaceBundle` calls the
        // detector, so a redirect here would run detector → proof → detector. The
        // detector's own `followingNestedBundle` guard does not cover that, because
        // the path leaves the detector and comes back in. On a bundle whose
        // `Contents/MacOS` holds a symlink to itself the descent then terminates
        // only when the path outgrows PATH_MAX, having walked the executable once
        // per level: 0.38s of CPU against 0.02s for the same bundle without the
        // symlink, ~26 walks of a 60 MB binary where one was intended. (Measured
        // after #216 made `probe` use `Data.range(of:)`; against the byte loop it
        // replaced the same pair read 1.48s against 0.05s.) Nothing ships that
        // layout; the guard is here so the invariant is stated in code rather than
        // left to the shape of what happens to be installed.
        let bundleURL = runtime == .tauri
            ? inputBundleURL
            : AppRuntimeDetector.interfaceBundle(at: inputBundleURL)
        // Some of these readers walk a whole binary, so the answer is remembered —
        // against the *executable's own identity*, its size and modification date,
        // rather than against a version string.
        //
        // A version string was the first key and it was the wrong one twice over.
        // Plenty of apps ship a new build under an unchanged marketing version
        // (Amp: ten builds in a day, all `1.0`), so that key cannot see an update
        // it is supposed to invalidate on; and it cannot see a bundle rewritten
        // underneath it either, which is exactly what an install does while a scan
        // may be running. Size-and-mtime changes whenever the bytes this answer was
        // read from change, which is the only thing that can make it stale.
        //
        // The lookup deliberately sits *above* the `scanningBinaries` guard, so a
        // caller that forbade scanning still gets an answer someone else paid for.
        // It is not free — building the key parses `Contents/Info.plist` and stats
        // the executable — but that is microseconds against a walk of the file.
        //
        // Nil is cached too: "no Tauri crate in here" is an answer, and the
        // expensive one to reach. An *unreadable* binary is not — but only `.tauri`
        // gets that distinction, because only there is the nil a verdict. The
        // Electron and Chromium readers go through `scan`, which flattens
        // `.unreadable` into the same nil as a real absence, so a framework binary
        // that is briefly unreadable pins "no version" for the process. The key is
        // the *main* executable's stat, which can still succeed while the framework
        // binary does not, so this is reachable — and it costs a missing version
        // label, not a wrong runtime.
        let executable = executableURL(bundleAt: bundleURL)
        let key = executable.flatMap { executableIdentity(of: $0) }
            .map { "\(bundleURL.path)|\(runtime.rawValue)|\($0)" }
        if let key, let remembered = cached(key) { return remembered }

        let version: String?
        switch runtime {
        case .electron:
            // The re-signed case needs a scan; the ordinary one does not, and
            // `electronVersion` takes the cheap path first either way.
            version = electronVersion(bundleAt: bundleURL, scanning: scanningBinaries)
        case .qt:       version = qtVersion(bundleAt: bundleURL, executable: executable)
        case .java:     version = javaVersion(bundleAt: bundleURL)
        case .tauri:
            guard scanningBinaries, let executable else { return nil }
            // The one place the difference between "proved absent" and "could not
            // read" matters, because a nil here is a *verdict* — `carriesTauriCrate`
            // turns it into "this app is not Tauri" and the cache would keep that
            // for the life of the process. A half-read binary must therefore leave
            // no trace: no answer, nothing remembered, asked again next time.
            switch probe(executable, for: "tauri-", components: 3) {
            case .found(let found): version = found
            case .absent:           version = nil
            case .unreadable:       return nil
            }
        case .chromium:
            guard scanningBinaries else { return nil }
            version = chromiumVersion(bundleAt: bundleURL)
        case .flutter, .native, .catalyst, .iOSApp:
            version = nil
        }
        // A nil reached under `scanningBinaries: false` is not an answer about the
        // app, it is an answer about the caller — and both callers share a key. So
        // no nil is remembered from such a read, for any runtime: for `.electron`
        // it would be actively wrong (a single such read of a re-signed framework
        // would pin "no version" for the life of the process, since its cheap path
        // and its scanning path are one function), and for `.qt`, `.java` and the
        // unversioned runtimes it costs nothing, because their nil is reached
        // without walking anything.
        //
        // No production caller passes false today — `RuntimeTag` and
        // `carriesTauriCrate` both pass true. This closes the trap rather than a
        // live bug, and the trap is newly unconditional: the caller-supplied
        // `appVersion` used to be the one thing that could vary between two callers
        // of the same bundle.
        if let key, version != nil || scanningBinaries { remember(version, for: key) }
        return version
    }

    /// What the answer was read from, as far as staleness is concerned: the main
    /// executable's size and modification date. Nil when it cannot be stat-ed, and
    /// a nil identity means the answer is simply not cached — better to re-read
    /// than to remember something under a key that cannot expire.
    ///
    /// The main executable stands in for the whole bundle, including for Electron,
    /// where the bytes actually read live in a framework. An update that changes a
    /// bundled framework and leaves the app's own binary byte-identical would go
    /// unnoticed; no packager produces that, since the executable is re-signed
    /// either way.
    ///
    /// Two places where it stands in rather than measures: `attributesOfItem` does
    /// not follow symlinks while `FileHandle` does, so a bundle whose executable is
    /// a symlink would be keyed on the link (whose size is the length of its path)
    /// rather than on the bytes read; and a filesystem with coarse timestamps could
    /// in principle hold two same-sized binaries under one key. Neither shape
    /// appears in `/Applications`.
    private static func executableIdentity(of executable: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return "\(size.int64Value)-\(modified.timeIntervalSince1970)"
    }

    /// Remembered answers, keyed by bundle path, runtime, and what the executable
    /// looked like when the answer was read.
    ///
    /// Grows by one entry per app per update, for every app whose detail has been
    /// opened *and* for every cargo-bundled WebView app on the machine, since the
    /// scan proves those to classify them — six bundles here. Two scans that
    /// overlap can both miss and both walk the same binary; they write the same
    /// value, so the cost is a duplicated read rather than a wrong answer, and
    /// de-duplicating in flight is not worth a second lock.
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
    private static func qtVersion(bundleAt bundleURL: URL, executable: URL?) -> String? {
        if let executable,
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

    /// Whether this bundle is Tauri at all — `AppRuntimeDetector`'s proof, and the
    /// version it displays, from one read.
    ///
    /// Tauri compiles into the executable, so its only trace is the Cargo
    /// dependency path Rust bakes into panic metadata:
    /// `…/registry/src/…/tauri-2.11.5/src/lib.rs`. Either that path is there or it
    /// is not, and if it is, the version is right beside it — so the detector
    /// asking "is this Tauri" during a scan and the detail view asking "which
    /// Tauri" later share one cache entry, and the walk happens once per binary
    /// rather than once per asker.
    ///
    /// `tauri-runtime-wry-2.11.4` deliberately does not match: the character after
    /// the prefix has to be a digit, so only the framework crate itself is read.
    ///
    /// Two shapes this cannot see, both of which read as *not Tauri*:
    ///
    /// - **A `tauri` taken as a git or path dependency.** Cargo lays those out as
    ///   `git/checkouts/tauri-<hash>/<rev>/…`, with no version to find. Rare for a
    ///   shipped app, which takes the crates.io release, but not hypothetical — the
    ///   Longbridge audit in `docs/app-audits/` shows exactly that layout for two
    ///   of its own dependencies.
    /// - **A universal binary's other slice.** The gate that admits a bundle here
    ///   parses the arm64 slice (`MachOImports`); this walks the file end to end,
    ///   so on a fat binary it also passes over the Intel one. Both slices come out
    ///   of the same `cargo build` and carry the same crate paths, so the answer
    ///   agrees — it is the bytes read, not the verdict, that are larger than they
    ///   need to be. One of the six candidates here (CC Switch) is fat.
    public static func carriesTauriCrate(bundleAt bundleURL: URL) -> Bool {
        read(.tauri, bundleAt: bundleURL, scanningBinaries: true) != nil
    }

    /// Walks a binary looking for `<needle><version>` in chunks, so that a 261 MiB
    /// executable never lands in memory at once — see the pool in `probe`, without
    /// which that sentence was false.
    ///
    /// Three outcomes, because two of them are not the same thing. A binary that
    /// was read to the end and does not contain the needle is *evidence*; a binary
    /// that could not be opened or could not be read through is the absence of
    /// evidence, and only the first may be remembered as an answer.
    enum Probe: Equatable {
        case found(String)
        case absent
        case unreadable
    }

    /// How much of each chunk is carried into the next: enough that a match cut by
    /// a boundary is whole in one window, and one byte more than that, so the window
    /// also holds the character *before* such a match. Both of `firstVersion`'s
    /// rules need context the chunk alone cannot supply.
    ///
    /// It is therefore also the longest match that can be seen across a boundary —
    /// `Chrome/` plus four components is under 30 bytes. A differential fuzz of
    /// 20,000 random layouts against a whole-file reference found no disagreement,
    /// and the only way to manufacture one was a "version" of over a hundred digits,
    /// which fails toward *missing* the match — or toward returning a later, real
    /// one — rather than toward inventing a version that is not there.
    ///
    /// Internal rather than a local, because the test that pins the boundary rules
    /// has to place its payload on the seam this number defines. Written as a
    /// literal there, the test passes against the unfixed reader — which is what it
    /// did until round 3 of review noticed.
    static let scanOverlap = 128

    /// How much is read at a time. Internal for the same reason as `scanOverlap`:
    /// the boundary tests place their payload where these two numbers put the seam,
    /// and a literal on the test side goes stale silently — the test keeps passing
    /// while testing nothing.
    static let scanChunkSize = 4 * 1024 * 1024

    private static func probe(_ binary: URL, for prefix: String, components: Int) -> Probe {
        guard let handle = try? FileHandle(forReadingFrom: binary) else { return .unreadable }
        defer { try? handle.close() }
        return probe(reading: { try handle.read(upToCount: scanChunkSize) },
                     for: prefix, components: components)
    }

    /// The walk itself, over a source of chunks rather than over a file.
    ///
    /// The seam exists because of what it is like not to have it. Three rounds of
    /// review found three real defects in this loop — a match discarded when the
    /// read *after* it failed, a short read read as end-of-file, and the first bytes
    /// of a file going unexamined for the rest of the walk — and not one of them was
    /// expressible as a test, because `probe` opened its own `FileHandle` and no
    /// test can make a real file throw halfway through or hand back a short read.
    /// Every fix was verified by hand and pinned by nothing: putting the old body
    /// back left the entire suite green.
    ///
    /// A closure that hands back one chunk at a time is enough to say all of it, and
    /// it is the shape this file's neighbours already use (`LibraryReader`,
    /// `TauriProof`).
    static func probe(
        reading next: () throws -> Data?,
        for prefix: String,
        components: Int
    ) -> Probe {
        let needle = Data(prefix.utf8)


        // `try?` is not available here, and the reason is the whole point of this
        // type: `read(upToCount:)` returns nil *at end of file*, and `try?` flattens
        // a thrown error into that same nil — so a completed walk and a failed one
        // would be indistinguishable, which is exactly the confusion `Probe` exists
        // to end. `do`/`catch` keeps them apart.
        var failed = false
        func read() -> Data? {
            do { return try next() }
            catch { failed = true; return nil }
        }

        // One chunk of lookahead, so a window knows whether it is the last.
        //
        // Asking the file for its size up front is the obvious way to know that,
        // and it is wrong in both directions. A file truncated under the walk never
        // reaches the recorded size, so *no* window is ever final and a version
        // ending at the real EOF is discarded — which for `.tauri` is a cached
        // verdict of "not Tauri", precisely the class `.unreadable` was added to
        // keep out of the cache. A file appended to keeps being read past that size
        // with every later window wrongly calling itself final. A lookahead cannot
        // go stale, and it keeps this working on anything unseekable besides.
        var carry = Data()
        // Where `window[0]` sits in the file. `carry.isEmpty` looks like the same
        // question and is not: if a window is no longer than `scanOverlap`, the
        // carry is the whole of it and the next window still begins at offset 0.
        // Asking about the offset directly is what keeps `from: 1` from blinding
        // the first bytes of the file for the rest of the walk.
        var windowStart = 0
        var pending = read()
        if failed { return .unreadable }
        var outcome: Probe?

        while let chunk = pending, !chunk.isEmpty {
            // A pool per window, because `read(upToCount:)` hands back a bridged
            // `NSData` that is autoreleased. Without one nothing drains until the
            // walk returns, and the "never lands in memory at once" above is false
            // in the most literal way — the whole file lands, one chunk at a time.
            // Measured on Longbridge's 261 MiB binary, peak footprint for a single
            // probe: **+278 MiB without the pool, +30 MiB with it**. That comment
            // has been shipping since before this branch and was describing an
            // intent rather than a measurement; the pool is what makes it true, and
            // this branch is what made it matter, by moving the walk onto the scan.
            autoreleasepool {
                let following = read()
                // A short read is legal mid-file; only an empty one is the end.
                // Finality is decided by the *next* read rather than by this one's
                // length — treating a short read as the end would report a
                // truncated binary as proof of absence. A read that *threw* says
                // nothing about the end either, so it must not claim finality.
                let isFinal = failed ? false : (following?.isEmpty ?? true)

                var window = carry
                window.append(chunk)
                let version = firstVersion(
                    in: window, after: needle, components: components,
                    // In a continuation window the first byte is there only to be
                    // the character before the second: a match starting *on* it has
                    // no predecessor in this window, and was already whole in the
                    // previous one, which had `scanOverlap` bytes of room after it.
                    from: windowStart == 0 ? 0 : 1,
                    // And only the last window may read "my buffer ended" as "the
                    // version ended".
                    isFinal: isFinal
                )

                // Deliberately before the `failed` check. A match is positive
                // evidence and complete in itself; bytes *after* it failing to read
                // says nothing about it, and discarding it would turn a proven
                // Tauri app into a native one for that scan. Only the absence of a
                // match depends on having read the whole file, and that is the case
                // this hands to `.unreadable`.
                if let version { outcome = .found(version); return }
                if failed { outcome = .unreadable; return }

                carry = window.suffix(scanOverlap)
                windowStart += window.count - carry.count
                pending = isFinal ? nil : following
            }
            if let outcome { return outcome }
        }
        return .absent
    }

    /// The version alone, for the readers where a failure to read and a genuine
    /// absence lead to the same place — nothing is shown either way.
    private static func scan(_ binary: URL, for prefix: String, components: Int) -> String? {
        if case .found(let version) = probe(binary, for: prefix, components: components) {
            return version
        }
        return nil
    }

    /// The first `<needle><major>.<minor>.<patch>` in `bytes`, where the character
    /// before the needle is not part of a longer identifier.
    ///
    /// `bytes` is one window of a larger file, and both of those rules need to know
    /// it. Reading the edge of the buffer as the edge of the file gets each rule
    /// wrong in its own direction, and neither is theoretical — both were
    /// reproduced against this code:
    ///
    /// - **The digit run.** `tauri-2.11.50` cut by a boundary returned `2.11.5`:
    ///   three components, last one a digit, looks finished. `isFinal` says whether
    ///   a run that reached the end of the buffer may be trusted; when it may not,
    ///   the candidate is skipped and the carry presents it whole next time.
    /// - **The identifier guard.** `index > 0` is a claim about the *file*, and in
    ///   a continuation window index 0 is not the start of anything — its real
    ///   predecessor is in the previous chunk. `xtauri-2.11.5` positioned there
    ///   passed a guard that rejects it everywhere else. `start` is 1 for those
    ///   windows, so every position examined has its predecessor in hand.
    ///
    /// This second one is why the fix belongs in this branch rather than after it:
    /// it hands out a `tauri-` match that is not one, which for a *displayed
    /// version* was cosmetic and for a *verdict* is the exact false positive the
    /// rest of this change exists to prevent.
    ///
    /// Finding the needle is `Data.range(of:)`'s job rather than a byte loop's, and
    /// that is a measurement rather than a preference. Two separate comparisons, and
    /// they are worth keeping apart because each answers a different question:
    ///
    /// - **The same loop, debug against release: ~200×** (#214 measured 104 s and
    ///   0.50 s for one library-wide sweep). `-Onone` optimises none of it, and
    ///   every one of those hundreds of millions of iterations pays full
    ///   bounds-checking and retain/release. This is why a release build never
    ///   showed the problem.
    /// - **Loop against `Data.range(of:)`, both in a debug build: ~500×.** Measured
    ///   over Longbridge's 261 MiB executable, chunked exactly as `probe` chunks it:
    ///   **75.2 s and 0.151 s**, same match positions on every binary tried.
    ///
    /// The second is the one this code turns on: `range(of:)` lives in a Foundation
    /// that is already compiled with optimisations, so it does not care how *this*
    /// module was built. (That attribution is measured rather than looked up — the
    /// numbers are solid, the explanation for them is not from Apple's documentation.)
    ///
    /// That gap was not academic: three scan tests walk the real `/Applications`,
    /// and #206 put this walk on that path — `scanFindsRealApps` went from 0.24 s to
    /// 107 s, which is issue #214. The shipped app, being a release build, never saw
    /// it. Keep the search out of Swift here; the parse below runs a few bytes per
    /// match and can stay.
    ///
    /// Only the *search* moved. Both window-edge rules and the identifier guard are
    /// unchanged, and so is the order they run in.
    private static func firstVersion(
        in bytes: Data,
        after needle: Data,
        components: Int,
        from start: Int = 0,
        isFinal: Bool = true
    ) -> String? {
        guard bytes.count > needle.count, start <= bytes.count - needle.count - 1 else { return nil }
        let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        let dot = UInt8(ascii: ".")
        let dash = UInt8(ascii: "-")
        // Offsets are relative to `startIndex`, not to zero. `carry` is a *slice* of
        // the previous window, and a `Data` slice keeps the indices it was cut from
        // — `window.startIndex` is 128, not 0, from the second window on. The
        // `Array(window)` this replaced re-based to zero as a side effect of
        // copying; nothing does that now, so `bytes[0]` would be a crash and
        // `index > 0` would be the identifier guard silently skipped.
        var searchFrom = bytes.startIndex + start
        while searchFrom < bytes.endIndex,
              let match = bytes.range(of: needle, in: searchFrom..<bytes.endIndex) {
            let index = match.lowerBound
            // Every position is a candidate, exactly as in the loop: a rejected
            // match must not hide a real one that overlaps it.
            searchFrom = index + 1
            if index > bytes.startIndex {
                let before = bytes[index - 1]
                let isIdentifier = digits.contains(before) || before == dash
                    || (before | 0x20) >= UInt8(ascii: "a") && (before | 0x20) <= UInt8(ascii: "z")
                if isIdentifier { continue }
            }
            var cursor = match.upperBound
            var version = ""
            var dots = 0
            while cursor < bytes.endIndex {
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
            // A run that stopped because the buffer did, in a window that is not the
            // end of the file, is not a finished version — whatever digits follow
            // are in the next chunk.
            if !isFinal, cursor == bytes.endIndex { continue }
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
