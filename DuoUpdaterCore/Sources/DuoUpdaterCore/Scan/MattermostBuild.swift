import Foundation

/// Mattermost coerces the macOS marketing version, losing RC/nightly suffixes.
/// The updater reads the complete version from its own bundled package.json.
/// Share that identity between scanning and install/relaunch recovery: comparing
/// a raw 6.2.5 against a target 6.2.5-rc.5 would otherwise declare an old RC current.
/// History: docs/app-audits/Mattermost-Desktop.md#历史与实测
enum MattermostBuild {
    static func version(in bundle: URL, bundleID: String?, plistVersion: String?) -> String? {
        guard bundleID == "Mattermost.Desktop", let plistVersion else { return nil }
        let asar = bundle.appendingPathComponent("Contents/Resources/app.asar")
        guard let data = AsarEntryReader.packedEntry("package.json", inAsarAt: asar),
              let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              package["name"] as? String == "mattermost-desktop",
              let version = package["version"] as? String,
              version.range(
                of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:-(?:rc\.?[0-9]+|nightly\.[0-9]{8}))?$"#,
                options: .regularExpression) != nil,
              version == plistVersion || version.split(separator: "-", maxSplits: 1).first.map(String.init) == plistVersion
        else { return nil }
        return version
    }
}
