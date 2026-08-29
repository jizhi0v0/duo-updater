import Foundation

/// Where a bundle's `Info.plist` actually lives.
///
/// A normal macOS app keeps it at `Contents/Info.plist`. An iPhone/iPad app
/// running on Apple Silicon is *wrapped*: the outer `.app` has no `Contents/` at
/// all — the real bundle sits at `Wrapper/<Inner>.app` (a flat iOS layout) behind
/// a `WrappedBundle` symlink, with its plist at that bundle's root.
///
/// Reading the wrong path doesn't fail loudly, it reads **nothing**: the file
/// isn't there, both version fields come back nil, and every caller that asks
/// "has the version changed?" answers "no" — forever, not once. That is how a
/// wrapped app's App Store update landed correctly and then spun out the
/// installer's full six-minute poll before reporting a timeout (Nowdex on
/// macOS 26, 2026-08-29: the bytes were on disk 15 seconds in, `versionChanged`
/// could never observe it). `AppScanner` has resolved this layout since wrapped
/// apps were first scanned; the readers on the install path had not, so the rule
/// lives here where all of them can share it rather than in any one of them.
public enum BundleLayout {

    /// The path, relative to the bundle root and ending in `/`, of the directory
    /// holding `Info.plist` and `_CodeSignature` — `Contents/` for a normal app,
    /// `Wrapper/<Inner>.app/` for a wrapped one.
    ///
    /// Presence of the `WrappedBundle` symlink is the discriminator — the same one
    /// `AppScanner` derives `isiOSAppOnMac` from, and a fact about the bundle on
    /// disk rather than anything we were told about it, so a reader holding only a
    /// path can still get this right.
    ///
    /// Returned relative, and resolved through the symlink's *destination* rather
    /// than the symlink itself, because one caller (`BackupManifest`) needs it to
    /// line up with a directory walk of the same bundle. That walk yields real
    /// paths (`Wrapper/<Inner>.app/…`) and never the `WrappedBundle` alias, so a
    /// prefix naming the alias would match none of them.
    public static func interiorPrefix(
        for bundleURL: URL, fileManager: FileManager = .default
    ) -> String {
        let wrapped = bundleURL.appendingPathComponent("WrappedBundle")
        guard fileManager.fileExists(atPath: wrapped.path) else { return "Contents/" }
        // The link's own text is the answer and costs no directory scan; it is
        // written relative to the bundle root ("Wrapper/Amp.app"). Fall back to
        // finding the single `.app` under `Wrapper/` if it can't be read, and to
        // the alias itself if even that fails — reading through the alias still
        // works, and only the seal-key mapping loses precision.
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: wrapped.path),
           !destination.hasPrefix("/") {
            return destination.hasSuffix("/") ? destination : destination + "/"
        }
        let wrapperDir = bundleURL.appendingPathComponent("Wrapper", isDirectory: true)
        if let inner = try? fileManager.contentsOfDirectory(atPath: wrapperDir.path)
            .first(where: { $0.hasSuffix(".app") }) {
            return "Wrapper/\(inner)/"
        }
        return "WrappedBundle/"
    }

    /// The `Info.plist` inside `bundleURL`, wherever this bundle keeps it.
    public static func infoPlistURL(
        for bundleURL: URL, fileManager: FileManager = .default
    ) -> URL {
        bundleURL.appendingPathComponent(
            interiorPrefix(for: bundleURL, fileManager: fileManager) + "Info.plist")
    }

    /// The bundle's `_CodeSignature/CodeResources` — the seal `BackupManifest`
    /// consults to tell shipped payload from runtime droppings. Absent for an
    /// unsigned bundle, which that caller already treats as "no seal to consult".
    public static func codeResourcesURL(
        for bundleURL: URL, fileManager: FileManager = .default
    ) -> URL {
        bundleURL.appendingPathComponent(
            interiorPrefix(for: bundleURL, fileManager: fileManager)
                + "_CodeSignature/CodeResources")
    }
}
