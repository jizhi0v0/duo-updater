/// Developer identities authorized for unattended root package installation.
///
/// These are reviewed code, compiled into the signed helper. Never populate this
/// table from installed bundles, preferences, Homebrew metadata or nightly scan
/// state: all can change independently of an approved helper. An unknown app or
/// a vendor signing change must use macOS Installer until its binding is reviewed.
public enum PackageInstallTrust {
    public static func teamIdentifier(for bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        return teams[bundleIdentifier]
    }

    // Pins recorded from Developer ID Installer signatures of the vendor PKGs;
    // corresponding installed app signatures must have the same identity too.
    // Channels sharing an exact bundle identifier share this binding; identifiers
    // from other editions are not accepted by a prefix or vendor-name match.
    private static let teams: [String: String] = [
        "cc.ffitch.shottr": "2Y683PRQWN",
        "com.microsoft.Excel": "UBF8T346G9",
        "com.microsoft.OneDrive": "UBF8T346G9",
        "com.microsoft.Outlook": "UBF8T346G9",
        "com.microsoft.Powerpoint": "UBF8T346G9",
        "com.microsoft.Word": "UBF8T346G9",
        "com.microsoft.edgemac": "UBF8T346G9",
        "com.microsoft.edgemac.Beta": "UBF8T346G9",
        "com.microsoft.edgemac.Dev": "UBF8T346G9",
        "com.microsoft.m365copilot": "UBF8T346G9",
        "com.microsoft.onenote.mac": "UBF8T346G9",
        "com.microsoft.teams2": "UBF8T346G9",
        "com.netease.uuremote": "PU9BNSBJW7",
        "com.tclementdev.timemachineeditor.application": "68GTH78H6S",
        "com.tencent.wechatdevtools": "FN2V63AD2J",
        "io.nekohasekai.screensharing": "P8XK3KHB48",
        "io.tailscale.ipn.macsys": "W5364U7YZB",
        "org.xquartz.X11": "NA574AWV7E",
    ]
}
