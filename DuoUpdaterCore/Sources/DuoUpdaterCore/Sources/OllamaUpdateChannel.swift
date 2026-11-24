import Foundation

/// Ollama uses the same bundle identity for both tracks. Duo stores its own
/// Preview opt-in per installed path, since the vendor app stores no channel.
public enum OllamaUpdateChannel {
    public static let bundleID = "com.electron.ollama"
    static let previewPathsKey = "OllamaPreviewPaths"
    @TaskLocal static var preferencesSuite = Log.subsystem

    static func selected(for path: URL) -> ReleaseChannel {
        selected(for: path, in: UserDefaults(suiteName: preferencesSuite) ?? .standard)
    }

    public static func selected(for path: URL, in defaults: UserDefaults) -> ReleaseChannel {
        let paths = defaults.stringArray(forKey: previewPathsKey) ?? []
        return paths.contains(path.standardizedFileURL.path) ? .preview : .stable
    }

    public static func select(_ channel: ReleaseChannel, for path: URL, in defaults: UserDefaults) {
        let path = path.standardizedFileURL.path
        var paths = Set(defaults.stringArray(forKey: previewPathsKey) ?? [])
        switch channel {
        case .stable: paths.remove(path)
        case .preview: paths.insert(path)
        default: return
        }
        defaults.set(paths.sorted(), forKey: previewPathsKey)
    }
}
