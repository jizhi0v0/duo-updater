import Foundation

/// The outline of each runtime's own mark, as SVG path data in a 24×24 box.
///
/// The artwork is **Simple Icons** (simpleicons.org), whose icon files are
/// released under CC0 1.0 — public domain. The marks themselves remain the
/// trademarks of their owners, and they are used here the way a "works with"
/// badge uses one: to identify the technology an installed app is built with,
/// never to suggest the vendor endorses this one.
///
/// Why real artwork rather than something hand-drawn: it was hand-drawn first,
/// and being close is not the same as being right. The first Electron mark was
/// three closed symmetric ellipses, which is *React's* logo, not Electron's; the
/// first Tauri mark was a hexagon, which resembles nothing Tauri publishes. A
/// reader who knows these logos reads a near-miss as a mistake, because it is one.
///
/// Five runtimes are absent, each for its own reason:
/// - **Java** because there is no icon here to use. Simple Icons carries no Java
///   mark — Oracle's is a trademark they were asked to drop — and OpenJDK's Duke,
///   the obvious substitute, is a mascot whose silhouette at 12pt reads as a
///   penguin. The category takes a coffee cup, the way everything that cannot use
///   Oracle's artwork does.
/// - **Chromium** is a bucket rather than a product: Chrome, its forks, and
///   anything embedding CEF (Spotify, CapCut). Its disc is drawn from geometry in
///   the app instead — it is three arcs and a hub, so there is nothing to
///   approximate.
/// - **Mac Catalyst**, **iOS App** and **Native** are not products with logos.
public enum RuntimeArtwork {

    /// The `d` attribute of the mark's single path, or nil where the runtime has
    /// no vendor artwork.
    public static func pathData(for runtime: AppRuntime) -> String? {
        switch runtime {
        case .electron:
            // Electron — simple-icons/icons/electron.svg
            return "M12.0111 0c-.85 0-1.5392.6891-1.5392 1.5392 0 .8501.6891 1.5393 1.5392 1.5393.595 0 1.11-.338 1.3662-.832 2.2208 1.2675 3.847 5.4728 3.847 10.3623 0 2.0715-.2891 4.056-.825 5.7685a.3215.3215 0 0 0 .2107.403.322.322 0 0 0 .4033-.2111c.5558-1.7763.8542-3.8251.8542-5.9604 0-5.1927-1.7717-9.686-4.3206-11.0027.001-.0223.0035-.0443.0035-.0669 0-.85-.6891-1.5392-1.5393-1.5392zm0 .6432a.896.896 0 1 1 0 1.792.896.896 0 1 1 0-1.792zm-5.486 4.3052c-2.067.0074-3.6473.6646-4.3885 1.9485-.7375 1.2774-.5267 2.971.5113 4.7813a.3217.3217 0 0 0 .558-.32C2.271 9.7274 2.089 8.266 2.6938 7.2185c.821-1.422 3.033-1.9552 5.9321-1.4271a.3216.3216 0 0 0 .1153-.6329c-.784-.1428-1.5271-.2125-2.216-.21zm11.0522.0176a.3216.3216 0 0 0-.0084.6432c1.8337.0239 3.1556.5956 3.7502 1.6256.8192 1.419.1798 3.5947-1.7182 5.837a.322.322 0 0 0 .0377.4535.3215.3215 0 0 0 .4532-.0377c2.0535-2.426 2.7708-4.8661 1.7845-6.5744-.7257-1.257-2.26-1.9207-4.299-1.9472zm-2.6984.2924a.3225.3225 0 0 0-.0647.0072c-1.8568.3979-3.8333 1.1755-5.7314 2.2714-4.5699 2.6384-7.5924 6.4948-7.3601 9.3717-.4726.2628-.7928.7664-.7928 1.3455 0 .85.6892 1.5392 1.5393 1.5392.85 0 1.5392-.6891 1.5392-1.5392 0-.8501-.6891-1.5393-1.5392-1.5393-.038 0-.0754.003-.1128.0057-.1002-2.5597 2.7434-6.1412 7.048-8.6265 1.8413-1.063 3.7551-1.8163 5.5445-2.1997a.3217.3217 0 0 0-.07-.636zm-2.8787 6.2364a1.1192 1.1192 0 0 0-.2243.0255c-.6012.1301-.983.7225-.8533 1.3238.1302.6012.7226.9832 1.3238.8533.6012-.1302.9832-.7226.8533-1.3238-.1139-.526-.5816-.8844-1.0995-.8788zM4.532 13.341a.321.321 0 0 0-.2318.0835.3214.3214 0 0 0-.0214.4542c1.2682 1.3936 2.9157 2.701 4.7946 3.7857 4.4146 2.5489 9.1056 3.2849 11.5608 1.8392a1.53 1.53 0 0 0 .8966.2899c.8501 0 1.5392-.6891 1.5392-1.5392 0-.8501-.689-1.5393-1.5392-1.5393-.85 0-1.5392.6892-1.5392 1.5393 0 .276.0737.5344.201.7584-2.2448 1.214-6.631.5002-10.7976-1.9054-1.8228-1.0524-3.418-2.3181-4.6404-3.6614a.3206.3206 0 0 0-.2226-.1049zm-2.0628 4.0172a.896.896 0 1 1 0 1.792.896.896 0 1 1 0-1.792zm19.0616 0a.896.896 0 1 1 0 1.792.891.891 0 0 1-.5864-.2194c-.0025-.004-.0039-.0083-.0066-.0123a.3195.3195 0 0 0-.0957-.0914.896.896 0 0 1 .6887-1.4689zm-14.0045 1.368a.3215.3215 0 0 0-.3207.4296C8.2793 22.154 10.036 24 12.0111 24c1.4406 0 2.7735-.9822 3.8128-2.711a.3215.3215 0 0 0-.11-.4413.3219.3219 0 0 0-.4415.11c-.934 1.5537-2.0812 2.399-3.2613 2.399-1.6407 0-3.2075-1.6465-4.2-4.4179a.3216.3216 0 0 0-.2848-.2126z"
        case .tauri:
            // Tauri — simple-icons/icons/tauri.svg
            return "M13.912 0a8.72 8.72 0 0 0-8.308 6.139c1.05-.515 2.18-.845 3.342-.976 2.415-3.363 7.4-3.412 9.88-.097 2.48 3.315 1.025 8.084-2.883 9.45a6.131 6.131 0 0 1-.3 2.762 8.72 8.72 0 0 0 3.01-1.225A8.72 8.72 0 0 0 13.913 0zm.082 6.451a2.284 2.284 0 1 0-.15 4.566 2.284 2.284 0 0 0 .15-4.566zm-5.629.27a8.72 8.72 0 0 0-3.031 1.235 8.72 8.72 0 1 0 13.06 9.9131 10.173 10.174 0 0 1-3.343.965 6.125 6.125 0 1 1-7.028-9.343 6.114 6.115 0 0 1 .342-2.772zm1.713 6.27a2.284 2.284 0 0 0-2.284 2.283 2.284 2.284 0 0 0 2.284 2.284 2.284 2.284 0 0 0 2.284-2.284 2.284 2.284 0 0 0-2.284-2.284z"
        case .flutter:
            // Flutter — simple-icons/icons/flutter.svg
            return "M14.314 0L2.3 12 6 15.7 21.684.013h-7.357zm.014 11.072L7.857 17.53l6.47 6.47H21.7l-6.46-6.468 6.46-6.46h-7.37z"
        case .qt:
            // Qt — simple-icons/icons/qt.svg
            return "M21.693 3.162H3.33L0 6.49v14.348h20.671L24 17.51V3.162zM12.785 18.4l-1.562.728-1.35-2.217c-.196.057-.499.09-.924.09-1.579 0-2.683-.425-3.305-1.276-.622-.85-.932-2.2-.932-4.033 0-1.84.319-3.206.949-4.098.63-.892 1.726-1.341 3.288-1.341 1.562 0 2.658.441 3.28 1.333.63.883.94 2.25.94 4.098 0 1.219-.13 2.2-.384 2.945-.261.752-.679 1.325-1.268 1.718zm4.736-1.587c-.858 0-1.447-.196-1.766-.59-.32-.392-.483-1.136-.483-2.232v-3.534H14.11V9.051h1.162V6.843h1.644V9.05h2.094v1.415h-2.094v3.346c0 .622.05 1.03.14 1.227.09.204.326.303.695.303l1.243-.05.073 1.326c-.67.13-1.186.196-1.546.196zm-8.58-9.08c-.95 0-1.604.311-1.963.94-.352.63-.532 1.629-.532 3.011 0 1.374.172 2.364.515 2.953.344.589 1.006.892 1.98.892.973 0 1.628-.295 1.971-.876.335-.58.507-1.57.507-2.953 0-1.39-.172-2.396-.523-3.026-.352-.63-1.006-.94-1.955-.94Z"
        case .java, .chromium, .catalyst, .iOSApp, .native:
            return nil
        }
    }

    /// The side of the box the path data is authored in. Simple Icons is 24×24
    /// throughout; a mark drawn at any other scale would silently render at the
    /// wrong size, so callers scale by this rather than assuming.
    public static let viewBox: CGFloat = 24
}
