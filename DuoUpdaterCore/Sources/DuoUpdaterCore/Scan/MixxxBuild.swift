import Foundation

public enum MixxxBuild {
    public static let bundleID = "org.mixxx.mixxx"

    /// The executable's Git describe value distinguishes packages with the same
    /// numeric plist version. Tagged packages store detached HEAD and the bare
    /// version as adjacent strings. Snapshots retain their track or build suffix.
    public static func channel(bundleAt bundleURL: URL, version: String?) -> ReleaseChannel? {
        guard let version,
              version.range(of: #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#, options: .regularExpression) != nil
        else { return nil }
        let series = version.split(separator: ".").prefix(2).joined(separator: ".")
        let tagged = "\0HEAD\0\(version)\0"
        let maintenance = "\0\(series)\0\(version)-"
        let tracks: [(ReleaseChannel, String)] = [
            (.stable, tagged),
            (.stable, utf16Marker(tagged)),
            (.beta, utf16Marker("\0\(series)-beta-")),
            (.alpha, utf16Marker("\0\(series)-alpha-")),
            (.nightly, maintenance),
            (.nightly, utf16Marker(maintenance)),
        ]
        for (channel, marker) in tracks {
            switch ExecutableMarker.presence(marker, inMainExecutableOf: bundleURL) {
            case .present: return channel
            case .absent: continue
            case .unknown: return nil
            }
        }
        return nil
    }

    // Every marker component is ASCII. Interleaving NULs gives the UTF-16LE
    // bytes of the Qt literal to the cached executable marker reader.
    private static func utf16Marker(_ value: String) -> String {
        value.map { "\($0)\0" }.joined()
    }
}
