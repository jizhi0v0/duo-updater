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
        let beta = "\0\(series)-beta-"
        let taggedBeta = "\0HEAD\0\(series)-beta\0"
        let alpha = "\0\(series)-alpha-"
        let maintenance = "\0\(series)\0\(version)-"
        let tracks: [(ReleaseChannel, String)] = [
            (.beta, beta),
            (.beta, utf16Marker(beta)),
            (.beta, taggedBeta),
            (.beta, utf16Marker(taggedBeta)),
            (.alpha, alpha),
            (.alpha, utf16Marker(alpha)),
            (.nightly, maintenance),
            (.nightly, utf16Marker(maintenance)),
            (.stable, tagged),
            (.stable, utf16Marker(tagged)),
        ]
        for (channel, marker) in tracks {
            switch ExecutableMarker.presence(marker, inMainExecutableOf: bundleURL) {
            case .present: return channel
            case .absent: continue
            case .unknown: return nil
            }
        }
        // The old SCons releases had no current Git marker. Use the signed
        // identity of the specific official Intel bundles we inspected.
        guard let cdhash = legacyReleaseHashes[version],
              (try? SignatureVerifier.verifyCodeSignatureCapturingCdhash(appAt: bundleURL)) == cdhash
        else { return nil }
        return .stable
    }

    private static let legacyReleaseHashes = [
        "2.1.8": "0717c8182f96938a641befe870c64f8ccaf8f635",
        "2.2.3": "c172946db2dadb6f6ddc758f6b0d1d2702a4fa45",
        "2.2.4": "bbee698017062eb2429c1d2a699783370ed91cc2",
    ]
    // 2.3 already writes the Git marker but predates the current signer, too.
    static let legacyVersionAlternatives = (
        legacyReleaseHashes.keys.sorted().map(NSRegularExpression.escapedPattern(for:))
        + [#"2\.3\.[0-9]+"#]
    ).joined(separator: "|")

    // Every marker component is ASCII. Interleaving NULs gives the UTF-16LE
    // bytes of the Qt literal to the cached executable marker reader.
    private static func utf16Marker(_ value: String) -> String {
        value.map { "\($0)\0" }.joined()
    }
}
