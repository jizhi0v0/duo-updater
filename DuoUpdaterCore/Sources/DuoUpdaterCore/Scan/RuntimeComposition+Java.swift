import Foundation

extension RuntimeComposition {

    /// A Chromium browser embedded in the Java UI (JetBrains Runtime's JCEF).
    static let javaJCEF = RuntimeComponent(id: "java.jcef", name: "JCEF")
    /// Skia drawing for Compose Multiplatform, through the Skiko library.
    static let javaSkiko = RuntimeComponent(id: "java.skiko", name: "Skiko")
    /// JavaFX scene graph, with its native glass toolkit.
    static let javaJavaFX = RuntimeComponent(id: "java.javafx", name: "JavaFX")

    /// A Java bundle, from file names at the known places a JVM app keeps its
    /// native libraries. Nothing is read inside a file and no directory is
    /// walked: each check lists one directory, so a multi-gigabyte JetBrains IDE
    /// costs the same as a small jpackage app.
    ///
    /// **Swing and AWT** are left out. Every full JDK runtime ships
    /// `libawt_lwawt.dylib` (IntelliJ IDEA 2026.2.3, Android Studio 2025.2 and Air
    /// 262.834.44 each carry one in `jbr/Contents/Home/lib`), so it would repeat
    /// the badge for every app that is not a jlink-trimmed command-line tool.
    ///
    /// **JCEF.** The native library is the evidence, not a name that contains
    /// "cef": Air ships `license/fleet.jcef-*-third-party-libraries.json` and
    /// `jcef.jar` in its code cache, yet no `libjcef.dylib` anywhere in the
    /// bundle, and a file-name search for "cef" matches both. IntelliJ IDEA
    /// 2026.2.3 ships `plugins/jcef-plugin/jcef/libjcef.dylib`; Android Studio
    /// 2025.2 has no `jcef-plugin` and no JCEF. The `jbr` and `runtime` paths are
    /// the layout of a JetBrains Runtime built with JCEF (the library in the
    /// runtime's `lib`, the Chromium framework in `Frameworks`); that is from the
    /// runtime's build layout, and none of the three apps above has it, so those
    /// paths are unobserved.
    ///
    /// **Skiko.** `libskiko-macos-arm64.dylib` sits in
    /// `lib/skiko-awt-runtime-all/` in IntelliJ IDEA and Android Studio, and in
    /// `app/libs/` in Air. A jpackage app built with Compose Desktop keeps
    /// `skiko-awt-*.jar` in `app`; that layout is unobserved.
    ///
    /// **JavaFX.** `libglass.dylib` (the toolkit) in a runtime's `lib`, or a
    /// `javafx-graphics-*.jar` beside the app's own jars. IntelliJ IDEA's
    /// `plugins/javaFX` directory is the IDE's support for editing JavaFX
    /// projects and holds none of these (only `javaFX*.jar` plugin code), so it is
    /// not looked at. No installed bundle ships JavaFX itself, so this reader's
    /// positive case is unobserved on real bundles.
    static func java(_ context: Context) -> [RuntimeComponent] {
        var found: [RuntimeComponent] = []
        if hasJCEF(context) { found.append(javaJCEF) }
        if hasSkiko(context) { found.append(javaSkiko) }
        if hasJavaFX(context) { found.append(javaJavaFX) }
        return found
    }

    private static func hasJCEF(_ context: Context) -> Bool {
        [
            "plugins/jcef-plugin/jcef/libjcef.dylib",
            "jbr/Contents/Home/lib/libjcef.dylib",
            "jbr/Contents/Frameworks/Chromium Embedded Framework.framework",
            "runtime/Contents/Home/lib/libjcef.dylib",
            "runtime/Contents/Frameworks/Chromium Embedded Framework.framework",
        ].contains { context.exists($0) }
    }

    private static func hasSkiko(_ context: Context) -> Bool {
        for directory in ["lib/skiko-awt-runtime-all", "app/libs", "app", "Java", "lib"] {
            let match = context.listing(directory).contains { name in
                (name.hasPrefix("libskiko-") && name.hasSuffix(".dylib"))
                    || (name.hasPrefix("skiko-awt") && name.hasSuffix(".jar"))
            }
            if match { return true }
        }
        return false
    }

    private static func hasJavaFX(_ context: Context) -> Bool {
        for directory in ["runtime/Contents/Home/lib", "jbr/Contents/Home/lib"]
        where context.listing(directory).contains("libglass.dylib") {
            return true
        }
        for directory in ["app", "Java", "lib"]
        where context.listing(directory).contains(where: { $0.hasPrefix("javafx-graphics") && $0.hasSuffix(".jar") }) {
            return true
        }
        return false
    }
}
