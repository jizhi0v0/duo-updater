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

    /// Qt, from the names in `Contents/Frameworks` and nothing else.
    ///
    /// Qt is deployed either as frameworks (`QtWidgets.framework` in calibre,
    /// OBS and Audacity) or as versioned dylibs (`libQt5Widgets.5.15.18.dylib` in
    /// KeePassXC, `libQt6Widgets.6.dylib` in Raspberry Pi Imager), so both
    /// spellings count. A module is matched by its whole name: `QtQuick` is not
    /// `QtQuickControls2` or `QtQuickWidgets`, which are extra pieces of an app
    /// that already ships Quick.
    ///
    /// **Widgets, Quick.** These are the two ways a Qt app draws its windows,
    /// and the badge cannot tell them apart. calibre, HBuilderX, CapCut,
    /// Audacity 4, Moonlight and Parallels Desktop ship both; OBS, Macs Fan
    /// Control and KeePassXC ship Widgets alone. Quick alone is reported as
    /// well, since "Qt Quick" with no Widgets is itself the answer to "how is
    /// this drawn". Packaging is not use: Raspberry Pi Imager is a QML
    /// application and still ships `libQt6Widgets`, which Quick Controls and the
    /// platform dialogs can pull in — the "ships, not shows" caveat.
    ///
    /// **WebEngine.** `QtWebEngineCore` is Qt's whole Chromium (calibre and
    /// HBuilderX ship it, with `Helpers/QtWebEngineProcess.app`), a heavy piece
    /// nothing links by accident. The wrapper modules `QtWebEngineWidgets` and
    /// `QtWebEngineQuick` need the core, so the core is the one name checked.
    ///
    /// **CEF.** OBS and CapCut ship `Chromium Embedded Framework.framework`
    /// beside their Qt frameworks; `AppRuntimeDetector` files both under Qt
    /// because Qt draws the windows, which leaves the embedded browser
    /// unmentioned anywhere else. Reported as "CEF" and not as Chromium: it is
    /// the browser engine of a panel, a different build from Qt WebEngine's.
    ///
    /// **Left out.** DingTalk ships only Qt's non-UI libraries
    /// (`QtConcurrent`, `QtNetwork`, `QtOpenGL`, `QtXml`) and gets nothing.
    /// PyQt apps keep Qt inside the binding's own directory
    /// (`Resources/app_packages/PyQt6` in Anki, `PyQt6/` in Frameworks for
    /// PyInstaller bundles). Anki's `PyQt6` holds one `.abi3.so` per Qt module
    /// whether the app uses it or not (QtWebEngineWidgets, QtQuick3D and
    /// QtDesigner among them), so a listing says what the wheel contains and not
    /// what the app is built from. Nothing is returned for them.
    static func qt(_ context: Context) -> [RuntimeComponent] {
        let frameworks = context.listing("Frameworks")
        var found: [RuntimeComponent] = []
        if shipsQtModule("Widgets", in: frameworks) { found.append(qtWidgets) }
        if shipsQtModule("Quick", in: frameworks) { found.append(qtQuick) }
        if shipsQtModule("WebEngineCore", in: frameworks) { found.append(qtWebEngine) }
        if frameworks.contains("Chromium Embedded Framework.framework") { found.append(cef) }
        return found
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
