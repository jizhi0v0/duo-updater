import Foundation

/// What an installed app is built with — the runtime that draws its windows.
///
/// This is a *different axis* from how an app updates itself. A Sparkle app can be
/// AppKit or Electron; an App Store app can be Catalyst or SwiftUI. `InstalledApp`
/// already carries the update axis (`hasSparkleUpdater`, `isMASApp`,
/// `electronUpdate`), and mixing the two into one label would answer neither
/// question reliably — so this enum names only the runtime and stays silent when
/// the bundle does not say.
///
/// Every case is decided from something the packager *wrote*: a framework it had
/// to bundle, a directory its launcher needs, the dylibs its executable links, or
/// a Cargo path baked into it. Nothing here guesses from an app's name or vendor,
/// and nothing is inferred from the absence of a marker. See `AppRuntimeDetector`
/// for the evidence behind each case.
public enum AppRuntime: String, Sendable, Hashable, CaseIterable, Codable {
    /// A wrapped iPhone/iPad app running on Apple Silicon.
    case iOSApp = "ios"
    /// A UIKit app built for the Mac with Mac Catalyst.
    case catalyst
    /// Chromium + Node, bundled by Electron.
    case electron
    /// A Rust app built on the Tauri framework, drawing into the system WebView.
    /// Requires the `tauri` crate itself: wry — the WebView layer Tauri sits on —
    /// is embedded by apps that are not Tauri at all.
    case tauri
    /// Flutter's macOS embedder.
    case flutter
    /// Qt (5 or 6), deployed with its frameworks inside the bundle.
    case qt
    /// A JVM app shipping its own runtime — JetBrains IDEs, `jpackage` output.
    case java
    /// A Chromium shell that is not Electron: Chrome and its forks, or an app
    /// embedding CEF.
    case chromium
    /// A native Mac app — AppKit and/or SwiftUI, whatever language it is written in.
    case native

    /// Whether this case was decided by something the packager had to *ship* — a
    /// framework, a runtime directory, a payload archive, a crate compiled in —
    /// rather than by which of Apple's frameworks a binary links.
    ///
    /// The distinction matters in exactly one place: attributing a nested bundle's
    /// runtime to the app that wraps it. A bundled runtime is evidence about that
    /// bundle and nothing else, so it travels; "links AppKit" is true of a helper
    /// process and of the interface alike, so it does not. `.iOSApp` is decided by
    /// a wrapper layout that cannot occur one level down inside `Contents/MacOS`.
    var isBundled: Bool {
        switch self {
        case .electron, .tauri, .flutter, .qt, .java, .chromium: true
        case .native, .catalyst, .iOSApp: false
        }
    }
}

/// Which of Apple's UI frameworks a bundle's executable actually links.
///
/// A **set**, not a label, and that is the whole point. It is tempting to reduce
/// this to "a SwiftUI app" or "an AppKit app" and the evidence does not support
/// it: of the 77 native apps installed on the machine this was written on, 47%
/// link AppKit alone, 53% link AppKit *and* SwiftUI, and none link SwiftUI alone.
/// A one-word answer would be a guess dressed as a fact for half of them.
///
/// (A SwiftUI-only binary is perfectly possible — a demo app built for exactly
/// this question links SwiftUI and no AppKit at all. It just isn't what shipping
/// apps look like, because a real one reaches for `NSApplication`,
/// `NSWorkspace` or an `@NSApplicationDelegateAdaptor` sooner or later.)
///
/// Frameworks only, deliberately, and the Swift runtime is the one that keeps
/// asking to be let in. It carries no information where it matters: of 143
/// readable binaries on the development machine, 44 link SwiftUI and **every one
/// of them** links `libswiftCore` too — SwiftUI is a Swift-only framework, so it
/// cannot be otherwise. Where SwiftUI is absent it says only that some Swift is
/// present, which an Objective-C app with a single Swift file also manages. Beside
/// AppKit and SwiftUI it would read as a third framework, and as a claim about
/// what the app is written in that this cannot make.
public struct LinkedFrameworks: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let appKit = LinkedFrameworks(rawValue: 1 << 0)
    public static let swiftUI = LinkedFrameworks(rawValue: 1 << 1)
    /// UIKit, whether through Catalyst's `/System/iOSSupport` or an iOS binary.
    public static let uiKit = LinkedFrameworks(rawValue: 1 << 2)

    /// In a fixed order, so a row does not reshuffle its own description between
    /// launches the way an unordered set would.
    public var names: [String] {
        var names: [String] = []
        if contains(.appKit) { names.append("AppKit") }
        if contains(.swiftUI) { names.append("SwiftUI") }
        if contains(.uiKit) { names.append("UIKit") }
        return names
    }
}

/// Reads an installed bundle and says which runtime it was built with.
///
/// Three evidence sources, cheapest first:
///
/// 1. **Bundle layout.** A packager cannot hide the runtime it bundles: Electron
///    ships `Electron Framework.framework` (or an `app.asar`), Flutter ships
///    `FlutterMacOS.framework`, Qt ships its own frameworks, a JVM app ships a
///    runtime directory. One `contentsOfDirectory` on `Contents/Frameworks`
///    answers all of the framework rules at once.
/// 2. **Load commands.** "This is a native app" is not visible in the layout at
///    all — nothing on disk says AppKit. The executable's linked dylibs do, and
///    they also separate a Catalyst app (links out of `/System/iOSSupport/`) from
///    an AppKit one. See `MachOImports`.
/// 3. **Binary contents.** Tauri writes nothing to either — its only trace is a
///    Cargo path inside the executable. Reading a whole binary is far too
///    expensive to do for every app, so it runs only for the bundles the first
///    two sources have already narrowed to a handful. See the `tauri` rule below.
///
/// Returns nil when none of the three recognizes anything, which is the honest answer
/// for a launcher shell script, a Python app, or a C++ app that links neither
/// AppKit nor a bundled toolkit — the UI shows no badge rather than a wrong one.
public enum AppRuntimeDetector {

    /// Injected so the rules can be tested without a real Mach-O binary on disk.
    /// Production always passes `MachOImports.linkedLibraries(at:)`.
    public typealias LibraryReader = (URL) -> Set<String>?

    /// Whether a bundle's executable actually carries the Tauri framework crate —
    /// the one rule here that needs the *contents* of a binary rather than its
    /// header. Injected for the same reason as `LibraryReader`; production passes
    /// `RuntimeVersion.carriesTauriCrate(bundleAt:)`.
    public typealias TauriProof = (URL) -> Bool

    /// Everything one read of a bundle can say about how it was built.
    public struct Reading: Sendable, Equatable {
        public let runtime: AppRuntime?
        public let frameworks: LinkedFrameworks
    }

    /// The runtime alone, for callers that do not need the framework set.
    public static func detect(
        bundleAt bundleURL: URL,
        isiOSAppOnMac: Bool,
        infoPlist: [String: Any],
        linkedLibraries: LibraryReader = { MachOImports.linkedLibraries(at: $0) },
        carriesTauriCrate: TauriProof = RuntimeVersion.carriesTauriCrate(bundleAt:)
    ) -> AppRuntime? {
        read(bundleAt: bundleURL, isiOSAppOnMac: isiOSAppOnMac,
             infoPlist: infoPlist, linkedLibraries: linkedLibraries,
             carriesTauriCrate: carriesTauriCrate).runtime
    }

    /// Both facts from a single pass. The executable's load commands are read at
    /// most once here — the scan calls this for every app on the machine, and the
    /// runtime and the framework set are two questions about the same list.
    ///
    /// - Parameter followingNestedBundle: whether a wrapper that ships no runtime
    ///   of its own may be answered from the single `.app` nested inside it. False
    ///   only in that recursive call, so the descent is one level deep by
    ///   construction and cannot loop on a bundle that nests itself.
    public static func read(
        bundleAt bundleURL: URL,
        isiOSAppOnMac: Bool,
        infoPlist: [String: Any],
        linkedLibraries: LibraryReader = { MachOImports.linkedLibraries(at: $0) },
        carriesTauriCrate: TauriProof = RuntimeVersion.carriesTauriCrate(bundleAt:),
        followingNestedBundle: Bool = true
    ) -> Reading {
        // A wrapped iOS app has no `Contents/` at all, so every rule below would
        // look in the wrong place, and its own executable sits inside the wrapper
        // rather than where the others keep theirs. Its wrapper is the evidence.
        if isiOSAppOnMac { return Reading(runtime: .iOSApp, frameworks: []) }

        let fm = FileManager.default
        let contents = bundleURL.appendingPathComponent("Contents")
        let frameworksDirectory = contents.appendingPathComponent("Frameworks")
        let frameworkNames = (try? fm.contentsOfDirectory(atPath: frameworksDirectory.path)) ?? []

        // The executable is read once, here, and both answers come out of that one
        // list. It is read even for the bundles the layout rules settle on their
        // own — an Electron app's shell links AppKit like any other — because the
        // read costs about 0.2ms and asking twice would cost more.
        let executable = executableURL(bundleAt: bundleURL, infoPlist: infoPlist, fm: fm)
        let libraries = executable.flatMap(linkedLibraries)
        let frameworks = libraries.map(Self.frameworks(in:)) ?? []
        func reading(_ runtime: AppRuntime?) -> Reading {
            Reading(runtime: runtime, frameworks: frameworks)
        }

        // Electron. The framework name is the obvious marker and the wrong one to
        // stop at: QQ ships it renamed to `QQNT.framework`, and the renamed case is
        // not rare enough to ignore. What an Electron app cannot do without is its
        // JavaScript payload, so the packaged (`app.asar`) and unpacked
        // (`Resources/app/package.json`, which is what VS Code and QQ both ship)
        // forms are checked too, along with electron-builder's own update
        // descriptor — the same file `ElectronUpdateConfig` reads.
        //
        // Deliberately NOT the helper processes: `<name> Helper (Renderer).app` in
        // `Contents/Frameworks` looks like the perfect Electron marker and is not
        // one — CEF lays its helpers out identically (Spotify, CapCut), so keying
        // on it would file every embedded-Chromium app under Electron.
        let electronMarkers = [
            "Resources/app.asar",
            "Resources/app-update.yml",
            "Resources/app/package.json",
        ]
        if frameworkNames.contains("Electron Framework.framework")
            || electronMarkers.contains(where: {
                fm.fileExists(atPath: contents.appendingPathComponent($0).path)
            }) {
            return reading(.electron)
        }

        if frameworkNames.contains("FlutterMacOS.framework") { return reading(.flutter) }

        // Qt before the Chromium rule below, deliberately: CapCut ships BOTH the Qt
        // frameworks and `Chromium Embedded Framework.framework`, and Qt is the one
        // drawing its windows — CEF is embedded inside it.
        if frameworkNames.contains(where: isQtComponent) { return reading(.qt) }

        if isJavaBundle(contents: contents, infoPlist: infoPlist, fm: fm) { return reading(.java) }

        // A Chromium shell that isn't Electron. Chrome, its forks and CEF all name
        // the framework "<product> Framework.framework" — Google Chrome Framework,
        // Helium Framework, Chromium Embedded Framework. Electron's follows the
        // same convention, which is why it is matched by name above first.
        if frameworkNames.contains(where: { $0.hasSuffix(" Framework.framework") }) {
            return reading(.chromium)
        }

        // A wrapper whose interface lives in a nested bundle. Docker's shape: the
        // outer `Docker.app` declares `com.docker.backend` — a 218 MB Go daemon
        // that links AppKit — ships no `Contents/Frameworks` at all, and keeps the
        // actual GUI at `Contents/MacOS/Docker Desktop.app`, where the Electron
        // framework and the `app.asar` are. Every rule above is correct about the
        // file it was pointed at and none of them is looking at the app. See #208.
        //
        // `Contents/MacOS/*.app` is also where *subprocesses* live, so recursing
        // into any nested bundle would start attributing a helper's runtime to its
        // host. Three conditions keep the two apart, measured over the 214 bundles
        // in `/Applications`, `~/Applications`, `/System/Applications` and their
        // Utilities folders — six have a nested `.app` and only Docker passes:
        //
        // 1. **The outer bundle ships no framework of its own.** An app with a GUI
        //    of its own has something in `Contents/Frameworks`; the other five here
        //    have 3 to 29 entries, Docker has no such directory. A wrapper that
        //    brings nothing is not the thing drawing the windows.
        // 2. **Exactly one nested `.app`.** Helpers come in sets — Parallels ships
        //    three, QQ four, WeChat two. A lone nested bundle is not proof, but a
        //    crowd of them is proof of the opposite.
        // 3. **The nested bundle names a runtime it *bundled*.** OrbStack's sole
        //    nested `scli.app` is a CLI helper and would pass 1 and 2 if OrbStack
        //    shipped no frameworks; it reads as nothing, so nothing is claimed.
        //    Only the cases decided by positive, bundled evidence are adopted —
        //    `.native` and `.catalyst` are read off a binary's load commands, which
        //    a helper links exactly like an interface, and adopting those would be
        //    guessing. The outer bundle's own answer stands instead.
        //
        // The whole rule therefore fails toward silence: a nested bundle that
        // cannot prove what it is leaves the label where it was.
        if followingNestedBundle,
           frameworkNames.isEmpty,
           let nested = nestedInterface(
            in: contents, linkedLibraries: linkedLibraries,
            carriesTauriCrate: carriesTauriCrate, fm: fm) {
            return nested.reading
        }

        // Everything left is decided by what the binary links, so an unreadable one
        // ends the enquiry.
        guard let libraries else { return reading(nil) }

        // Tauri — the one case decided by reading a binary's *contents*, and the
        // reason is worth stating because the cheaper rule was tried first and
        // broke.
        //
        // Tauri bundles nothing distinctive. Its frontend is compiled into the
        // binary and it draws into the system WebView, so there is no framework to
        // find. What its packager DOES leave is a plist fingerprint: tauri-bundler
        // (via cargo-bundle) writes the legacy pair `LSRequiresCarbon` +
        // `CSResourcesFileMapped`, which essentially nothing else still emits.
        //
        // That pair says "cargo-bundle", not "Tauri" — Warp and Zed are cargo-
        // bundled Rust apps with their own renderers and carry it too. Adding "and
        // links WebKit" separated those two and looked sufficient, on the reasoning
        // that a Tauri app must link WebKit to have a window at all. It is not
        // sufficient, and the counterexample was already installed: Longbridge
        // draws with GPUI — the same renderer as Zed, pulled from the same repo —
        // and embeds a renamed wry fork (`lb-wry-0.53.3`) for incidental web
        // content. Cargo-bundled, links WebKit, contains not one occurrence of the
        // string "tauri". It read as Tauri for exactly as long as the WebKit rule
        // stood. See issue #206.
        //
        // So the plist pair plus WebKit is kept as a *filter*, not a verdict: it
        // costs two dictionary lookups, and across the ~145 bundles in
        // `/Applications` and `~/Applications` here it admits six. Those six pay
        // for the proof — the `tauri-<semver>` Cargo path Rust bakes into the
        // binary, which is positive evidence and yields the version besides.
        //
        // Six candidates is 471 MiB of executable. Five stop when the needle is
        // found, which is later in each file than "early" suggests — measured
        // first-match offsets are 34%, 52%, 63%, 66% and 86% of the way in — and
        // only Longbridge's 261 MiB is walked end to end, to prove absence.
        // Whole-library sweep in a release build: 0.50s, against 0.05s for a second
        // sweep once everything is remembered. I/O is not the cost — the same
        // machine reads a cold 795 MB binary in 0.169s — the byte search is, which
        // is also why a debug build takes 104s for that sweep and a release build
        // half a second.
        //
        // The residual risk moved rather than vanished, and it moved to the safer
        // side: an app now reads as native when its binary keeps no `tauri-` crate
        // path — or when that binary could not be read at this moment, since the
        // proof cannot tell a caller "I don't know". Either beats an unrelated app
        // reading as Tauri, and both are labels: nothing routes on this value.
        // `RuntimeVersion.carriesTauriCrate` lists the two binary shapes that can
        // hide the path even when the read succeeds.
        if infoPlist["LSRequiresCarbon"] as? Bool == true,
           infoPlist["CSResourcesFileMapped"] as? Bool == true,
           MachOImports.links(libraries, framework: "WebKit"),
           carriesTauriCrate(bundleURL) {
            return reading(.tauri)
        }

        // Mac Catalyst apps link the iOS frameworks shipped under /System/iOSSupport.
        if libraries.contains(where: { $0.contains("/System/iOSSupport/") }) { return reading(.catalyst) }

        // Native covers anything drawing through Apple's own frameworks, including
        // an app that renders its whole interface itself on top of them — Zed's
        // GPUI links AppKit and Metal and draws every pixel with the latter. The
        // distinction this enum makes is against *cross-platform runtimes*, not
        // against custom renderers, and `frameworks` carries the detail.
        if frameworks.contains(.appKit) || frameworks.contains(.swiftUI) {
            return reading(.native)
        }

        return reading(nil)
    }

    /// The bundle whose contents describe the app's interface: the bundle itself
    /// for everything ordinary, and the single nested `.app` for a wrapper that
    /// ships no runtime of its own — see the rule in `read`.
    ///
    /// Exists so that the runtime's *version* is read from the same place as the
    /// runtime's *name*. `RuntimeVersion` looks for an Electron framework under
    /// `Contents/Frameworks`, which for Docker is a directory that does not exist;
    /// without this the row would say Electron and the popover would have no
    /// version to show, from a bundle that plainly carries one.
    public static func interfaceBundle(at bundleURL: URL) -> URL {
        let contents = bundleURL.appendingPathComponent("Contents")
        let fm = FileManager.default
        let frameworksDirectory = contents.appendingPathComponent("Frameworks")
        guard ((try? fm.contentsOfDirectory(atPath: frameworksDirectory.path)) ?? []).isEmpty,
              let nested = nestedInterface(
                in: contents,
                linkedLibraries: { MachOImports.linkedLibraries(at: $0) },
                carriesTauriCrate: RuntimeVersion.carriesTauriCrate(bundleAt:),
                fm: fm)
        else { return bundleURL }
        return nested.bundle
    }

    /// The sole nested `.app` under `Contents/MacOS`, read one level deep, when it
    /// names a runtime it had to bundle. Nil for every other shape — no nested
    /// bundle, more than one, or one that proves nothing about itself.
    ///
    /// The caller has already established that the outer bundle ships no frameworks;
    /// this is the part both callers must agree on, so it lives in one place.
    private static func nestedInterface(
        in contents: URL,
        linkedLibraries: LibraryReader,
        carriesTauriCrate: TauriProof,
        fm: FileManager
    ) -> (bundle: URL, reading: Reading)? {
        let macOS = contents.appendingPathComponent("MacOS")
        let nestedNames = ((try? fm.contentsOfDirectory(atPath: macOS.path)) ?? [])
            .filter { $0.hasSuffix(".app") }
        guard nestedNames.count == 1 else { return nil }
        let nested = macOS.appendingPathComponent(nestedNames[0])
        let plist = NSDictionary(
            contentsOf: nested.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        let reading = read(
            bundleAt: nested, isiOSAppOnMac: false, infoPlist: plist ?? [:],
            linkedLibraries: linkedLibraries, carriesTauriCrate: carriesTauriCrate,
            followingNestedBundle: false)
        guard let runtime = reading.runtime, runtime.isBundled else { return nil }
        return (nested, reading)
    }

    /// Which of Apple's UI frameworks appear in a load-command list.
    static func frameworks(in libraries: Set<String>) -> LinkedFrameworks {
        var found: LinkedFrameworks = []
        if MachOImports.links(libraries, framework: "AppKit") { found.insert(.appKit) }
        if MachOImports.links(libraries, framework: "SwiftUI") { found.insert(.swiftUI) }
        if MachOImports.links(libraries, framework: "UIKit") { found.insert(.uiKit) }
        return found
    }

    /// `QtCore.framework`, `QtWidgets.framework`, `libQt6Core.dylib` — Qt is
    /// deployed either as frameworks or as dylibs depending on how `macdeployqt`
    /// was run, and both spellings live in `Contents/Frameworks`.
    private static func isQtComponent(_ name: String) -> Bool {
        (name.hasPrefix("Qt") && name.hasSuffix(".framework"))
            || (name.hasPrefix("libQt") && name.hasSuffix(".dylib"))
    }

    /// A JVM app ships the runtime it needs. `Java`/`runtime` are the `jpackage`
    /// and legacy `JavaAppLauncher` layouts; `jbr` is JetBrains' bundled runtime.
    private static func isJavaBundle(contents: URL, infoPlist: [String: Any], fm: FileManager) -> Bool {
        for directory in ["Java", "runtime", "jbr"] {
            var isDirectory: ObjCBool = false
            let path = contents.appendingPathComponent(directory).path
            if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue { return true }
        }
        let executable = infoPlist["CFBundleExecutable"] as? String
        return executable == "JavaAppLauncher" || executable == "JavaApplicationStub"
    }

    private static func executableURL(bundleAt bundleURL: URL, infoPlist: [String: Any], fm: FileManager) -> URL? {
        guard let name = infoPlist["CFBundleExecutable"] as? String, !name.isEmpty else { return nil }
        let url = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }
}
