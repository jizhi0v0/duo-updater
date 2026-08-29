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

    /// The `Info.plist` inside `bundleURL`, wherever this bundle keeps it.
    ///
    /// Presence of the `WrappedBundle` symlink is the discriminator — the same one
    /// `AppScanner` derives `isiOSAppOnMac` from, and it is a fact about the
    /// bundle on disk rather than anything we were told about it, so a reader that
    /// only has a path can still get this right.
    public static func infoPlistURL(
        for bundleURL: URL, fileManager: FileManager = .default
    ) -> URL {
        let wrapped = bundleURL.appendingPathComponent("WrappedBundle")
        guard fileManager.fileExists(atPath: wrapped.path) else {
            return bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist")
        }
        return wrapped.appendingPathComponent("Info.plist")
    }
}
