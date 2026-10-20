import Foundation

/// One UI technology a bundle ships beside the runtime its badge names — Qt
/// Quick inside a Qt app, a CEF browser inside a Qt shell, MyGo's own UI inside a
/// MyGo app.
///
/// `name` is the technology's own spelling and stays Latin in every language,
/// like the runtime names. `id` is what tests and the bench compare.
public struct RuntimeComponent: Sendable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// What a bundle ships beside its runtime, for the badge's click-through detail.
///
/// The runtime badge names the framework an app is built on, and for most
/// frameworks that is not the whole answer: one app can carry several ways of
/// drawing its windows. Audacity 4 links both Qt Widgets and Qt Quick; OBS is
/// Qt Widgets with a CEF browser beside it; IntelliJ IDEA is Swing with Skiko and
/// JCEF; a MyGo app can show a WebView
/// page, MyGo's own GPU-drawn UI, or both. `LinkedFrameworks` is the same idea
/// for Apple's own stack, and stays where it is.
///
/// **Ships, not shows.** Every reader here answers from the bundle as it sits on
/// disk — what is packaged or linked — and none of it proves the technology is on
/// screen: OBS's CEF may only ever draw a browser source, and a WebView crate
/// linked into a GPUI app may never open a window. The detail line says "ships"
/// for that reason. A reader returns only what it found; absence is never
/// reported, and a component every app of the runtime has (Tauri's WKWebView) is
/// left out because it would say nothing the badge does not.
///
/// **Only when asked.** Some readers search a section of the executable, which
/// is affordable for the one app whose detail is open and not for a library
/// scan, so nothing calls this from the scan. The badge's popover reads it off
/// the main thread when it opens, as it reads the runtime version.
public enum RuntimeComposition {

    /// The components of the bundle at `bundleURL`, already identified as
    /// `runtime`, in the order the reader lists them and without duplicates.
    public static func read(_ runtime: AppRuntime, bundleAt bundleURL: URL) -> [RuntimeComponent] {
        read(runtime, Context(bundle: bundleURL))
    }

    static func read(_ runtime: AppRuntime, _ context: Context) -> [RuntimeComponent] {
        let found: [RuntimeComponent]
        switch runtime {
        case .mygo:     found = myGo(context)
        case .qt:       found = qt(context)
        case .chromium: found = chromium(context)
        case .electron: found = electron(context)
        case .java:     found = java(context)
        case .flutter:  found = flutter(context)
        case .gpui:     found = gpui(context)
        case .egui:     found = egui(context)
        case .nsh:      found = nsh(context)
        case .tauri:    found = tauri(context)
        case .wails:    found = wails(context)
        // Apple's stacks are `LinkedFrameworks`' job. Linking WebKit or Metal is
        // too common to mean anything there: an AppKit app links WebKit to show
        // one sign-in sheet as readily as to draw its whole window.
        case .native, .catalyst, .iOSApp, .reactNative: found = []
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    /// The bundle a reader asks about, with every read memoized: a reader asking
    /// twice for the same section or directory pays once.
    ///
    /// The executable and its sections are injectable so a reader can be tested
    /// without a real Mach-O on disk; production reads the bundle's declared
    /// executable as `AppRuntimeDetector` chooses it.
    final class Context {
        let bundle: URL
        let contents: URL
        let executable: URL?
        private let fm: FileManager
        private let sectionReader: (_ segment: String?, _ name: String) -> Data?
        private let libraryReader: () -> Set<String>?
        private var librariesMemo: Set<String>??
        private var sectionMemo: [String: Data?] = [:]
        private var listingMemo: [String: [String]] = [:]

        /// The most of one section a reader may search. A larger section is
        /// refused, not truncated — a partial search would turn "not found in what
        /// was read" into "absent".
        static let sectionLimit: UInt64 = 128 << 20

        init(bundle: URL, fm: FileManager = .default) {
            self.bundle = bundle
            self.contents = bundle.appendingPathComponent("Contents")
            self.fm = fm
            let plist = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
            let executable = AppRuntimeDetector.executableURL(bundleAt: bundle, infoPlist: plist, fm: fm)
            self.executable = executable
            var commands: MachOImports.LoadCommands??
            self.sectionReader = { segment, name in
                guard let executable else { return nil }
                if commands == nil { commands = .some(MachOImports.loadCommands(at: executable)) }
                guard let parsed = commands ?? nil,
                      let section = parsed.sections.first(where: {
                          $0.name == name && (segment == nil || $0.segment == segment)
                      }),
                      section.range.offset > 0, section.range.size <= Context.sectionLimit
                else { return nil }
                return CLIRuntimeDetector.readBytes(executable, section.range.offset, Int(section.range.size))
            }
            self.libraryReader = { executable.flatMap { MachOImports.linkedLibraries(at: $0) } }
        }

        /// For tests: a bundle on disk with the executable's sections supplied.
        init(bundle: URL, executable: URL?, fm: FileManager = .default,
             libraries: Set<String>? = nil,
             sections: @escaping (_ segment: String?, _ name: String) -> Data?) {
            self.bundle = bundle
            self.contents = bundle.appendingPathComponent("Contents")
            self.executable = executable
            self.fm = fm
            self.sectionReader = sections
            self.libraryReader = { libraries }
        }

        /// The install names the executable links, nil where it could not be
        /// parsed. What the app's own binary asked for, as opposed to what a
        /// deploy tool copied into the bundle because some other piece needed it.
        var executableLibraries: Set<String>? {
            if let memo = librariesMemo { return memo }
            let libraries = libraryReader()
            librariesMemo = .some(libraries)
            return libraries
        }

        /// The bytes of the executable's section `name` — in `segment`, or the
        /// first section of that name in any segment when `segment` is nil (Go
        /// has moved `__gopclntab` between segments). Nil where there is no such
        /// section, it has no bytes in the file, or it is over `sectionLimit`.
        func section(_ segment: String?, _ name: String) -> Data? {
            let key = "\(segment ?? "*"),\(name)"
            if let memo = sectionMemo[key] { return memo }
            let data = sectionReader(segment, name)
            sectionMemo[key] = data
            return data
        }

        /// Whether the executable's section holds `needle` anywhere.
        func sectionContains(_ segment: String?, _ name: String, _ needle: String) -> Bool {
            guard let data = section(segment, name) else { return false }
            return RuntimeComposition.contains(data, needle)
        }

        /// The entry names of the directory at `relative` (from `Contents`),
        /// empty where there is none.
        func listing(_ relative: String) -> [String] {
            if let memo = listingMemo[relative] { return memo }
            let names = (try? fm.contentsOfDirectory(atPath: contents.appendingPathComponent(relative).path)) ?? []
            listingMemo[relative] = names
            return names
        }

        /// Whether a file or directory exists at `relative` (from `Contents`).
        func exists(_ relative: String) -> Bool {
            fm.fileExists(atPath: contents.appendingPathComponent(relative).path)
        }
    }

    /// Whether `data` holds the bytes of `needle`.
    static func contains(_ data: Data, _ needle: String) -> Bool {
        let bytes = Array(needle.utf8)
        guard !bytes.isEmpty else { return false }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            return memmem(base, raw.count, bytes, bytes.count) != nil
        }
    }
}
