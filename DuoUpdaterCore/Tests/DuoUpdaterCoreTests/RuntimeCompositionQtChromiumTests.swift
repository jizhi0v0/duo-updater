import Testing
import Foundation
@testable import DuoUpdaterCore

/// The Qt reader, and the Chromium and Electron readers that report nothing.

private func qtComponents(_ files: [String], runtime: AppRuntime = .qt) throws -> [String] {
    let bundle = try compositionBundle(files)
    defer { try? FileManager.default.removeItem(at: bundle) }
    return RuntimeComposition.read(runtime, bundleAt: bundle).map(\.id)
}

@Test func qtFrameworksReportWidgetsQuickAndWebEngineInOrder() throws {
    // calibre's and HBuilderX's shape.
    let ids = try qtComponents([
        "Frameworks/QtCore.framework/", "Frameworks/QtWebEngineCore.framework/Versions/A/Helpers/QtWebEngineProcess.app/",
        "Frameworks/QtQuick.framework/", "Frameworks/QtWidgets.framework/",
    ])
    #expect(ids == ["qt.widgets", "qt.quick", "qt.webengine"])
}

@Test func qtWidgetsAloneIsWidgetsOnly() throws {
    // OBS without its browser, Macs Fan Control.
    #expect(try qtComponents(["Frameworks/QtCore.framework/", "Frameworks/QtWidgets.framework/"]) == ["qt.widgets"])
}

@Test func qtQuickAloneIsReported() throws {
    #expect(try qtComponents(["Frameworks/QtCore.framework/", "Frameworks/QtQuick.framework/"]) == ["qt.quick"])
}

@Test func qtDylibSpellingsAreRecognised() throws {
    // KeePassXC (Qt 5, versioned) and Raspberry Pi Imager (Qt 6).
    #expect(try qtComponents(["Frameworks/libQt5Core.5.15.18.dylib", "Frameworks/libQt5Widgets.5.15.18.dylib"]) == ["qt.widgets"])
    #expect(try qtComponents([
        "Frameworks/libQt6Widgets.6.dylib", "Frameworks/libQt6Quick.6.dylib", "Frameworks/libQt6WebEngineCore.6.dylib",
    ]) == ["qt.widgets", "qt.quick", "qt.webengine"])
}

@Test func aQtShellShippingCEFReportsItLast() throws {
    // OBS and CapCut.
    let ids = try qtComponents([
        "Frameworks/QtWidgets.framework/", "Frameworks/QtQuick.framework/",
        "Frameworks/Chromium Embedded Framework.framework/",
    ])
    #expect(ids == ["qt.widgets", "qt.quick", "cef"])
    #expect(RuntimeComposition.cef.name == "CEF")
}

/// DingTalk's shape: Qt libraries with no UI toolkit among them.
@Test func qtLibrariesWithoutAUIToolkitReportNothing() throws {
    #expect(try qtComponents([
        "Frameworks/QtConcurrent.framework/", "Frameworks/QtNetwork.framework/",
        "Frameworks/QtOpenGL.framework/", "Frameworks/QtXml.framework/",
    ]).isEmpty)
}

/// Add-on modules are not the modules: `QtQuickControls2` and `QtQuickWidgets`
/// say nothing alone, and a WebEngine wrapper without its core is no browser.
@Test func qtModulesAreMatchedByWholeName() throws {
    #expect(try qtComponents([
        "Frameworks/QtQuickControls2.framework/", "Frameworks/QtQuickWidgets.framework/",
        "Frameworks/QtOpenGLWidgets.framework/", "Frameworks/QtPrintSupport.framework/",
        "Frameworks/QtWebEngineWidgets.framework/", "Frameworks/QtWebChannel.framework/",
        "Frameworks/libQt6QuickControls2.6.dylib", "Frameworks/libQt6QuickTemplates2.6.dylib",
        "Frameworks/libQt6WebEngineQuick.6.dylib",
    ]).isEmpty)
}

/// A dylib that merely starts with `libQt` and a module name, without a major
/// version, or a plain file called QtWidgets, is not Qt.
@Test func qtLookalikeNamesDoNotCount() throws {
    #expect(try qtComponents([
        "Frameworks/libQtWidgets.dylib", "Frameworks/QtWidgets.dylib", "Frameworks/libQt6Widgets",
        "Frameworks/libQt6WidgetsExtras.6.dylib", "Resources/QtWidgets.framework/",
    ]).isEmpty)
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
