import Foundation

/// The real body of `sw-update.obdev.at/update-feeds/littlesnitch6.plist` as
/// read on 2026-08-29, verbatim. One copy, shared by every test that needs a
/// Little Snitch feed, so the two cannot drift apart.
///
/// Two things about this snapshot are load-bearing for the tests that use it:
///  - the `nightly` entry is listed FIRST, so a recipe reading the `final`
///    entry cannot rely on document order (`ChannelGuardTests`);
///  - `final` (6.4.1/7212) is capped at `MaximumSystemVersion` 26.99 while
///    `nightly` (6.5/7301) says 27.99 — the window between a macOS release and
///    the vendor raising its cap, which is exactly what `VendorProbeOSBoundTests`
///    measures. The live feed moved on (2026-09-15: both entries 6.5, both
///    27.99); the snapshot is kept because the live one no longer shows the gap.
enum LittleSnitchFeedFixture {
    static let body20260829 = #"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>ReleaseLifecycle</key>
        <string>nightly</string>
        <key>BundleVersion</key>
        <string>7301</string>
        <key>BundleShortVersionString</key>
        <string>6.5</string>
        <key>MinimumSystemVersion</key>
        <string>14.0</string>
        <key>MaximumSystemVersion</key>
        <string>27.99</string>
        <key>ReleaseNotesURL</key>
        <string>https://sw-update.obdev.at/update-feeds/releasenotes-legacy-swu.php?product=3&amp;version=7301&amp;installed=</string>
        <key>DownloadPageURL</key>
        <dict>
            <key>en</key>
            <string>https://obdev.at/littlesnitch/download-nightly.html</string>
            <key>de</key>
            <string>https://obdev.at/de/littlesnitch/download-nightly.html</string>
        </dict>
        <key>DownloadURL</key>
        <string>https://sw-update.obdev.at/ftp/pub/Products/LittleSnitch/nightly/LittleSnitch-6.5-nightly-(7301).dmg</string>
        <key>InstallationObject</key>
        <string>Little Snitch.app</string>
        <key>InstallationMechanism</key>
        <string>ReplaceBundle</string>
    </dict>
    <dict>
        <key>ReleaseLifecycle</key>
        <string>final</string>
        <key>BundleVersion</key>
        <string>7212</string>
        <key>BundleShortVersionString</key>
        <string>6.4.1</string>
        <key>MinimumSystemVersion</key>
        <string>14.0</string>
        <key>MaximumSystemVersion</key>
        <string>26.99</string>
        <key>ReleaseNotesURL</key>
        <string>https://sw-update.obdev.at/update-feeds/releasenotes-legacy-swu.php?product=3&amp;version=7212&amp;installed=</string>
        <key>DownloadPageURL</key>
        <dict>
            <key>en</key>
            <string>https://obdev.at/littlesnitch/download.html</string>
            <key>de</key>
            <string>https://obdev.at/de/littlesnitch/download.html</string>
        </dict>
        <key>DownloadURL</key>
        <string>https://sw-update.obdev.at/ftp/pub/Products/LittleSnitch/LittleSnitch-6.4.1.dmg</string>
        <key>InstallationObject</key>
        <string>Little Snitch.app</string>
        <key>InstallationMechanism</key>
        <string>ReplaceBundle</string>
    </dict>
</array>
</plist>
"""#
}
