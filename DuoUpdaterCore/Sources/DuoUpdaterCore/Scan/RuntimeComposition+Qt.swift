import Foundation

extension RuntimeComposition {

    /// Qt's classic desktop toolkit: `QtWidgets`.
    static let qtWidgets = RuntimeComponent(id: "qt.widgets", name: "Qt Widgets")
    /// Qt's declarative scene-graph UI, written in QML: `QtQuick`.
    static let qtQuick = RuntimeComponent(id: "qt.quick", name: "Qt Quick")
    /// Qt's embedded Chromium: `QtWebEngineCore`.
    static let qtWebEngine = RuntimeComponent(id: "qt.webengine", name: "Qt WebEngine")
    /// A Chromium Embedded Framework browser, shipped beside the Qt UI.
    static let cef = RuntimeComponent(id: "cef", name: "CEF")

    /// Qt, from what the app's executable links and what its bundle ships.
    ///
    /// Qt is deployed either as frameworks (`QtWidgets.framework` in OBS and
    /// Audacity 4) or as versioned dylibs (`libQt5Widgets.5.15.18.dylib` in
    /// KeePassXC, `libQt6Quick.6.dylib` in Raspberry Pi Imager), so both
    /// spellings count. A module is matched by its whole name: `QtQuick` is not
    /// `QtQuickControls2` or `QtQuickWidgets`.
    ///
    /// **Widgets, Quick — from the executable's load commands.** These are the
    /// two ways a Qt app draws its windows, and the badge cannot tell them
    /// apart. A listing of `Frameworks` cannot either, because a deploy tool
    /// copies every module some other shipped piece links: the macOS style
    /// plugin `PlugIns/styles/libqmacstyle.dylib` links QtWidgets, so Moonlight
    /// and Raspberry Pi Imager ship it while their executables link only
    /// QtQuick; Qt's virtual-keyboard plugins link QtQuick, so DB Browser for
    /// SQLite ships it while its executable links only QtWidgets; and
    /// `QtWebEngineCore` itself links QtQuick, so every WebEngine app ships
    /// Quick. What the executable links is what the app's own code asked for:
    /// Audacity 4, CapCut and Parallels Desktop link both; OBS, KeePassXC and
    /// Macs Fan Control link Widgets alone; Moonlight and Raspberry Pi Imager
    /// link Quick alone. An executable that does not link QtCore is a launcher
    /// (calibre's starts Python, whose PyQt loads Qt), and says nothing either
    /// way.
    ///
    /// **WebEngine, CEF — from the bundle.** Each is a whole Chromium that no Qt
    /// module links, so shipping one is a choice the app made, and both are
    /// often loaded at run time rather than linked: HBuilderX ships
    /// `QtWebEngineCore.framework` (with `Helpers/QtWebEngineProcess.app`) and
    /// its executable links no WebEngine module. The wrapper modules
    /// `QtWebEngineWidgets` and `QtWebEngineQuick` need the core, so the core is
    /// the one name checked. OBS and CapCut ship `Chromium Embedded
    /// Framework.framework` beside their Qt frameworks; `AppRuntimeDetector`
    /// files both under Qt because Qt draws the windows, which leaves the
    /// embedded browser unmentioned anywhere else. Reported as "CEF" and not as
    /// Chromium: it is the browser engine of a panel, a different build from Qt
    /// WebEngine's.
    ///
    /// **Left out.** PyQt apps keep Qt inside the binding's own directory
    /// (`Resources/app_packages/PyQt6` in Anki, `PyQt6/` in Frameworks for
    /// PyInstaller bundles). Anki's `PyQt6` holds one `.abi3.so` per Qt module
    /// whether the app uses it or not (QtWebEngineWidgets, QtQuick3D and
    /// QtDesigner among them), so a listing says what the wheel contains and not
    /// what the app is built from. Nothing is returned for them.
    static func qt(_ context: Context) -> [RuntimeComponent] {
        var found: [RuntimeComponent] = []
        if let linked = context.executableLibraries.map(qtModuleNames),
           shipsQtModule("Core", in: linked) {
            if shipsQtModule("Widgets", in: linked) { found.append(qtWidgets) }
            if shipsQtModule("Quick", in: linked) { found.append(qtQuick) }
        }
        let frameworks = context.listing("Frameworks")
        if shipsQtModule("WebEngineCore", in: frameworks) { found.append(qtWebEngine) }
        if frameworks.contains("Chromium Embedded Framework.framework") { found.append(cef) }
        return found
    }

    /// The file names of linked install names, in the spelling
    /// `shipsQtModule` reads: `@rpath/QtWidgets.framework/Versions/A/QtWidgets`
    /// gives `QtWidgets.framework`, `@rpath/libQt6Quick.6.dylib` gives
    /// `libQt6Quick.6.dylib`.
    static func qtModuleNames(_ libraries: Set<String>) -> [String] {
        libraries.map { path in
            let parts = path.split(separator: "/")
            return String(parts.first { $0.hasSuffix(".framework") } ?? parts.last ?? "")
        }
    }

    /// Whether `names` holds Qt module `module` as `Qt<module>.framework` or as
    /// `libQt<major><module>.<…>.dylib`.
    static func shipsQtModule(_ module: String, in names: [String]) -> Bool {
        let framework = "Qt\(module).framework"
        return names.contains { name in
            if name == framework { return true }
            guard name.hasPrefix("libQt"), name.hasSuffix(".dylib") else { return false }
            let afterPrefix = name.dropFirst("libQt".count)
            let afterMajor = afterPrefix.drop(while: \.isNumber)
            // A major version is required, and the module name ends at a dot.
            return afterMajor.count < afterPrefix.count && afterMajor.hasPrefix("\(module).")
        }
    }
}
