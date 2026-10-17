import Testing
import Foundation
@testable import DuoUpdaterCore

/// The Java and Flutter readers of `RuntimeComposition`. Fixture bundles hold
/// empty files at the paths the readers look at; the Flutter reader's Mach-O read
/// is injected.

private func javaComponents(_ files: [String]) throws -> [String] {
    let bundle = try compositionBundle(files)
    defer { try? FileManager.default.removeItem(at: bundle) }
    return RuntimeComposition.read(.java, compositionContext(bundle, sections: [:])).map(\.id)
}

// MARK: Java

@Test func javaIDEAShape_listsJCEFThenSkiko() throws {
    #expect(try javaComponents([
        "jbr/Contents/Home/lib/libawt_lwawt.dylib",
        "plugins/jcef-plugin/jcef/libjcef.dylib",
        "lib/skiko-awt-runtime-all/libskiko-macos-arm64.dylib",
        "plugins/javaFX/lib/javaFX.jar",
    ]) == ["java.jcef", "java.skiko"])
}

@Test func javaAndroidStudioShape_listsSkikoOnly() throws {
    #expect(try javaComponents([
        "jbr/Contents/Home/lib/libawt_lwawt.dylib",
        "lib/skiko-awt-runtime-all/libskiko-macos-arm64.dylib",
        "plugins/android/lib/android.jar",
    ]) == ["java.skiko"])
}

@Test func javaAirShape_findsSkikoInAppLibsAndNoJCEF() throws {
    // Air has the JCEF jars and a CEF license listing, but no native library.
    #expect(try javaComponents([
        "app/libs/libskiko-macos-arm64.dylib",
        "app/code-cache/b33cfdd5/fleet.plugins.jcef.frontend.jar",
        "app/code-cache/a83b1cc7/jcef.jar",
        "license/fleet.jcef-262.834.44-third-party-libraries.json",
        "jbr/Contents/Home/lib/libawt_lwawt.dylib",
    ]) == ["java.skiko"])
}

@Test func javaJCEFInAJetBrainsRuntime() throws {
    #expect(try javaComponents(["jbr/Contents/Home/lib/libjcef.dylib"]) == ["java.jcef"])
    #expect(try javaComponents(["jbr/Contents/Frameworks/Chromium Embedded Framework.framework/"]) == ["java.jcef"])
    #expect(try javaComponents(["runtime/Contents/Home/lib/libjcef.dylib"]) == ["java.jcef"])
}

@Test func javaJCEFNeedsTheLibraryNotAName() throws {
    #expect(try javaComponents([
        "license/jcef-third-party.json",
        "plugins/jcef-plugin/lib/jcef-plugin.jar",
        "plugins/jcef-plugin/jcef/jcef.version",
        "lib/intellij.platform.trialPromotion.idesWithFreeTier.jcef.jar",
        "app/code-cache/ab/cef-helper.bin",
    ]).isEmpty)
}

@Test func javaSkikoFromAJpackageComposeApp() throws {
    #expect(try javaComponents(["app/skiko-awt-0.150.1.jar", "runtime/Contents/Home/lib/libjvm.dylib"])
        == ["java.skiko"])
    #expect(try javaComponents(["Java/libskiko-macos-arm64.dylib"]) == ["java.skiko"])
}

@Test func javaSkikoNeedsTheLibraryNotAName() throws {
    #expect(try javaComponents([
        "lib/intellij.libraries.skiko.jar",
        "app/skikotool.txt",
        "app/libs/skiko.sha256",
    ]).isEmpty)
}

@Test func javaFXFromTheToolkitOrItsJars() throws {
    #expect(try javaComponents(["runtime/Contents/Home/lib/libglass.dylib"]) == ["java.javafx"])
    #expect(try javaComponents(["app/javafx-graphics-21.0.2-mac-aarch64.jar"]) == ["java.javafx"])
    #expect(try javaComponents(["Java/javafx-graphics-17.jar", "runtime/Contents/Home/lib/libjcef.dylib"])
        == ["java.jcef", "java.javafx"])
}

/// A JetBrains IDE's `plugins/javaFX` is its support for JavaFX projects, not the
/// toolkit its own windows use.
@Test func javaFXIDEPluginIsNotJavaFX() throws {
    #expect(try javaComponents([
        "plugins/javaFX/lib/javaFX.jar",
        "plugins/javaFX/lib/javaFX-common.jar",
        "plugins/javaFX/lib/rt/javafx-rt.jar",
        "app/javafx-readme.txt",
    ]).isEmpty)
}

@Test func plainJavaRuntimeShipsNothingToReport() throws {
    // AWT and Swing are in every full runtime, so they are not reported.
    #expect(try javaComponents([
        "runtime/Contents/Home/lib/libawt_lwawt.dylib",
        "runtime/Contents/Home/lib/libosxui.dylib",
        "app/app.jar",
    ]).isEmpty)
}

@Test func javaReaderDoesNotLookInsideFiles() throws {
    var asked = 0
    let bundle = try compositionBundle(["plugins/jcef-plugin/jcef/libjcef.dylib"])
    defer { try? FileManager.default.removeItem(at: bundle) }
    let context = RuntimeComposition.Context(bundle: bundle, executable: nil) { _, _ in
        asked += 1
        return nil
    }
    #expect(RuntimeComposition.read(.java, context).map(\.name) == ["JCEF"])
    #expect(asked == 0)
}

// MARK: Flutter

private let webKit = "/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit"
private let appKit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

/// The Flutter reader over a fixture bundle, `links` giving what each framework
/// (by name) links; a framework not listed cannot be read.
private func flutterComponents(
    _ frameworks: [String], links: [String: Set<String>], reads: UnsafeMutablePointer<[String]>? = nil
) throws -> [String] {
    let bundle = try compositionBundle(frameworks.map { "Frameworks/\($0).framework/\($0)" })
    defer { try? FileManager.default.removeItem(at: bundle) }
    let context = compositionContext(bundle, sections: [:])
    let found = RuntimeComposition.flutter(context) { url in
        reads?.pointee.append(url.lastPathComponent)
        return links[url.lastPathComponent]
    }
    return found.map(\.id)
}

@Test func flutterWebViewPluginLinkingWebKitIsReported() throws {
    #expect(try flutterComponents(
        ["FlutterMacOS", "App", "url_launcher_macos", "webview_flutter_wkwebview"],
        links: [
            "App": [appKit],
            "url_launcher_macos": [appKit],
            "webview_flutter_wkwebview": [appKit, webKit],
        ]
    ) == ["flutter.webview"])
}

@Test func flutterAppWithoutAWebKitPluginReportsNothing() throws {
    var reads: [String] = []
    #expect(try flutterComponents(
        ["FlutterMacOS", "App", "window_manager", "desktop_drop"],
        links: ["App": [appKit], "window_manager": [appKit], "desktop_drop": [appKit]],
        reads: &reads
    ).isEmpty)
    #expect(reads.sorted() == ["App", "desktop_drop", "window_manager"])
}

/// The engine itself is not asked: only the plugins beside it say anything.
@Test func flutterEngineLinkingWebKitIsNotEvidence() throws {
    var reads: [String] = []
    #expect(try flutterComponents(
        ["FlutterMacOS", "App"],
        links: ["FlutterMacOS": [appKit, webKit], "App": [appKit]],
        reads: &reads
    ).isEmpty)
    #expect(!reads.contains("FlutterMacOS"))
}

/// A framework named for WebKit that does not link it, and a library that only
/// has WebKit in its name, are not the evidence; the load command is.
@Test func flutterWebKitInANameIsNotEvidence() throws {
    #expect(try flutterComponents(
        ["FlutterMacOS", "flutter_webkit_helper", "App"],
        links: [
            "flutter_webkit_helper": [appKit, "/usr/lib/libWebKitless.dylib"],
            "App": [appKit],
        ]
    ).isEmpty)
}

@Test func flutterUnreadableFrameworkIsSkippedNotFatal() throws {
    #expect(try flutterComponents(
        ["FlutterMacOS", "broken", "desktop_webview_window"],
        links: ["desktop_webview_window": [webKit]]
    ) == ["flutter.webview"])
}

@Test func flutterReportsTheWebViewOnceHoweverManyPluginsLinkIt() throws {
    var reads: [String] = []
    #expect(try flutterComponents(
        ["FlutterMacOS", "a_webview", "b_webview", "c_webview"],
        links: ["a_webview": [webKit], "b_webview": [webKit], "c_webview": [webKit]],
        reads: &reads
    ) == ["flutter.webview"])
    // The first hit settles it; the others are not read.
    #expect(reads == ["a_webview"])
}

@Test func flutterFrameworkWithoutABinaryIsNotRead() throws {
    let bundle = try compositionBundle(["Frameworks/FlutterMacOS.framework/FlutterMacOS",
                                        "Frameworks/resources_only.framework/Resources/Info.plist"])
    defer { try? FileManager.default.removeItem(at: bundle) }
    var reads = 0
    let found = RuntimeComposition.flutter(compositionContext(bundle, sections: [:])) { _ in
        reads += 1
        return [webKit]
    }
    #expect(found.isEmpty)
    #expect(reads == 0)
}

/// The production reader on a bundle whose frameworks are not Mach-O images.
@Test func flutterRealReaderOnNonMachOFrameworksReportsNothing() throws {
    let bundle = try compositionBundle(["Frameworks/FlutterMacOS.framework/FlutterMacOS",
                                        "Frameworks/plugin.framework/plugin"])
    defer { try? FileManager.default.removeItem(at: bundle) }
    #expect(RuntimeComposition.read(.flutter, bundleAt: bundle).isEmpty)
}

@Test func flutterBundleWithoutFrameworksReportsNothing() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    #expect(RuntimeComposition.read(.flutter, compositionContext(bundle, sections: [:])).isEmpty)
}
