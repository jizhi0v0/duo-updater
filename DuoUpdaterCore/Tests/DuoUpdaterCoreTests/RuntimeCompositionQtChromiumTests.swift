import Testing
import Foundation
@testable import DuoUpdaterCore

/// The Qt reader, and the Chromium and Electron readers that report nothing.

private func qtComponents(_ files: [String], runtime: AppRuntime = .qt) throws -> [String] {
    let bundle = try compositionBundle(files)
    defer { try? FileManager.default.removeItem(at: bundle) }
    return RuntimeComposition.read(runtime, bundleAt: bundle).map(\.id)
}

/// The Qt reader against a bundle holding `files` whose executable links `linked`.
private func qtComponents(_ files: [String] = [], linking linked: Set<String>?) throws -> [String] {
    let bundle = try compositionBundle(files)
    defer { try? FileManager.default.removeItem(at: bundle) }
    return RuntimeComposition.read(.qt, compositionContext(bundle, sections: [:], libraries: linked)).map(\.id)
}

private func framework(_ module: String) -> String { "@rpath/\(module).framework/Versions/A/\(module)" }

@Test func qtExecutableLinkingBothToolkitsReportsBoth() throws {
    // Audacity 4, CapCut, Parallels Desktop.
    #expect(try qtComponents(linking: [framework("QtCore"), framework("QtQuick"), framework("QtWidgets")])
            == ["qt.widgets", "qt.quick"])
}

@Test func qtWidgetsAloneIsWidgetsOnly() throws {
    // OBS without its browser, Macs Fan Control.
    #expect(try qtComponents(linking: [framework("QtCore"), framework("QtWidgets")]) == ["qt.widgets"])
}

@Test func qtQuickAloneIsReported() throws {
    #expect(try qtComponents(linking: [framework("QtCore"), framework("QtQuick")]) == ["qt.quick"])
}

/// Moonlight and Raspberry Pi Imager ship QtWidgets for the style plugin, and
/// DB Browser for SQLite ships QtQuick for the virtual keyboard: what the
/// executable links decides, not what the deploy tool copied.
@Test func aToolkitShippedOnlyForAPluginIsNotReported() throws {
    #expect(try qtComponents(
        ["Frameworks/QtWidgets.framework/", "Frameworks/QtQuick.framework/", "PlugIns/styles/libqmacstyle.dylib"],
        linking: [framework("QtCore"), framework("QtQuick"), framework("QtQuickControls2")]
    ) == ["qt.quick"])
    #expect(try qtComponents(
        ["Frameworks/QtWidgets.framework/", "Frameworks/QtQuick.framework/", "Frameworks/QtVirtualKeyboard.framework/"],
        linking: [framework("QtCore"), framework("QtWidgets")]
    ) == ["qt.widgets"])
}

/// calibre's and HBuilderX's shape: WebEngine is shipped and loaded at run time,
/// and it links QtQuick itself, which says nothing about the app's own UI.
@Test func webEngineComesFromTheBundleAndBringsNoQuick() throws {
    #expect(try qtComponents(
        ["Frameworks/QtWebEngineCore.framework/Versions/A/Helpers/QtWebEngineProcess.app/",
         "Frameworks/QtQuick.framework/", "Frameworks/QtWidgets.framework/"],
        linking: [framework("QtCore"), framework("QtWidgets")]
    ) == ["qt.widgets", "qt.webengine"])
}

/// calibre's executable is a launcher that links no Qt: it says nothing about
/// the toolkits, and the bundle still says WebEngine.
@Test func aLauncherExecutableLeavesOnlyWhatTheBundleShips() throws {
    #expect(try qtComponents(
        ["Frameworks/QtWebEngineCore.framework/", "Frameworks/QtQuick.framework/", "Frameworks/QtWidgets.framework/"],
        linking: ["/usr/lib/libSystem.B.dylib"]
    ) == ["qt.webengine"])
    #expect(try qtComponents(["Frameworks/QtWidgets.framework/"], linking: nil).isEmpty)
}

@Test func qtDylibSpellingsAreRecognised() throws {
    // KeePassXC (Qt 5, versioned) and Raspberry Pi Imager (Qt 6).
    #expect(try qtComponents(linking: ["@rpath/libQt5Core.5.dylib", "@rpath/libQt5Widgets.5.dylib"]) == ["qt.widgets"])
    #expect(try qtComponents(
        ["Frameworks/libQt6WebEngineCore.6.dylib"],
        linking: ["@executable_path/../Frameworks/libQt6Core.6.dylib", "@executable_path/../Frameworks/libQt6Quick.6.dylib"]
    ) == ["qt.quick", "qt.webengine"])
}

@Test func aQtShellShippingCEFReportsItLast() throws {
    // OBS and CapCut.
    let ids = try qtComponents(
        ["Frameworks/Chromium Embedded Framework.framework/"],
        linking: [framework("QtCore"), framework("QtWidgets"), framework("QtQuick")]
    )
    #expect(ids == ["qt.widgets", "qt.quick", "cef"])
    #expect(RuntimeComposition.cef.name == "CEF")
}

/// Qt libraries with no UI toolkit among them report nothing.
@Test func qtLibrariesWithoutAUIToolkitReportNothing() throws {
    #expect(try qtComponents(linking: [
        framework("QtCore"), framework("QtConcurrent"), framework("QtNetwork"), framework("QtXml"),
    ]).isEmpty)
}

/// Add-on modules are not the modules: `QtQuickControls2` and `QtQuickWidgets`
/// say nothing alone, and a WebEngine wrapper without its core is no browser.
@Test func qtModulesAreMatchedByWholeName() throws {
    #expect(try qtComponents(
        ["Frameworks/QtWebEngineWidgets.framework/", "Frameworks/libQt6WebEngineQuick.6.dylib"],
        linking: [
            framework("QtCore"), framework("QtQuickControls2"), framework("QtQuickWidgets"),
            framework("QtOpenGLWidgets"), "@rpath/libQt6QuickTemplates2.6.dylib",
        ]
    ).isEmpty)
}

/// A dylib that merely starts with `libQt` and a module name, without a major
/// version, or a plain file called QtWidgets, is not Qt.
@Test func qtLookalikeNamesDoNotCount() throws {
    #expect(try qtComponents(
        ["Frameworks/libQtWebEngineCore.dylib", "Resources/QtWebEngineCore.framework/"],
        linking: [
            framework("QtCore"), "@rpath/libQtWidgets.dylib", "@rpath/QtWidgets.dylib",
            "@rpath/libQt6Widgets", "@rpath/libQt6WidgetsExtras.6.dylib",
        ]
    ).isEmpty)
}

/// A PyQt app keeps Qt inside the binding, which lists the whole wheel: nothing.
@Test func pyQtPackagesReportNothing() throws {
    #expect(try qtComponents([
        "Resources/app_packages/PyQt6/QtWidgets.abi3.so", "Resources/app_packages/PyQt6/QtWebEngineCore.abi3.so",
        "Resources/app_packages/PyQt6/Qt6/lib/QtWidgets.framework/", "Frameworks/Python.framework/",
    ]).isEmpty)
}

@Test func aQtBundleWithoutFrameworksReportsNothing() throws {
    #expect(try qtComponents([]).isEmpty)
}

@Test func chromiumShellsReportNothingEvenWithCEF() throws {
    // Spotify's and Chrome's shapes.
    #expect(try qtComponents([
        "Frameworks/Chromium Embedded Framework.framework/", "Frameworks/Spotify Helper (Renderer).app/",
    ], runtime: .chromium).isEmpty)
    #expect(try qtComponents(["Frameworks/Google Chrome Framework.framework/"], runtime: .chromium).isEmpty)
}

@Test func electronAppsReportNothing() throws {
    #expect(try qtComponents([
        "Frameworks/Electron Framework.framework/", "Frameworks/Squirrel.framework/", "Resources/app.asar",
    ], runtime: .electron).isEmpty)
}
