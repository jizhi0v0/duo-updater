import Foundation

public enum MixxxBuild {
    public static let bundleID = "org.mixxx.mixxx"

    /// The snapshot DMGs share stable's bundle ID and put a plain version in
    /// both plist keys. The executable keeps the build's Git describe value as
    /// a Qt UTF-16 string, for example "2.6-beta-505-g…". A version-shaped ASCII
    /// string such as "2.6.0-beta" can be a database migration key in any build.
    public static func channel(bundleAt bundleURL: URL, version: String?) -> ReleaseChannel? {
        guard let parts = version?.split(separator: "."), parts.count == 3,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        let series = parts.prefix(2).joined(separator: ".")
        for channel in [ReleaseChannel.beta, .alpha] {
            // The describe value starts after a UTF-16 NUL and has a build
            // number after the channel separator. Match that prefix only.
            let prefix = "\0\(series)-\(channel.rawValue)-"
            let marker = prefix.map { "\($0)\0" }.joined()
            if ExecutableMarker.found(marker, inMainExecutableOf: bundleURL) { return channel }
        }
        return nil
    }
}
