import Testing
import Foundation
@testable import DuoUpdaterCore

/// GrandPerspective's `best_release.json`, captured verbatim 2026-08-16
/// (`curl https://sourceforge.net/projects/grandperspectiv/best_release.json`,
/// HTTP 200). Unlike the other two fixtures below, this project ships the SAME
/// dmg for every platform, so `release`, `platform_releases.mac` and
/// `platform_releases.windows` all happen to name the same file here — the trap
/// this group guards against simply doesn't bite THIS project. The recipe still
/// reads only `platform_releases.mac`, on principle, so it stays correct if
/// GrandPerspective ever does split by platform.
private let grandPerspectiveFixture = #"""
{"release": {"bytes": 4407902, "date": "2026-05-31 13:36:48", "date_modified": "2026-05-31 13:36:48", "file_type": "zlib compressed data", "filename": "/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg", "md5sum": "ea716b0649c197800f42287fe5793aa9", "mime_type": "application/zlib; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 63987273, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows", "mac", "linux", "android", "bsd", "solaris", "others"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "https://sourceforge.net/projects/grandperspectiv/files/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg/download", "vscan": "OK", "vscan_when": "2026-05-31 15:51:54"}, "platform_releases": {"mac": {"bytes": 4407902, "date": "2026-05-31 13:36:48", "date_modified": "2026-05-31 13:36:48", "file_type": "zlib compressed data", "filename": "/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg", "md5sum": "ea716b0649c197800f42287fe5793aa9", "mime_type": "application/zlib; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 63987273, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows", "mac", "linux", "android", "bsd", "solaris", "others"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/grandperspectiv/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg?ts=gAAAAABqHFpOqL5HwvYZk7nQGy3867ZLpVW-x0ocdJx-VXjzcZSLnJLQVGSkh3X2lhq3y_lGpyZIyOzJqjgtUYJT_lzYTDRo4w%3D%3D", "vscan": "OK", "vscan_when": "2026-05-31 15:51:54"}, "windows": {"bytes": 4407902, "date": "2026-05-31 13:36:48", "date_modified": "2026-05-31 13:36:48", "file_type": "zlib compressed data", "filename": "/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg", "md5sum": "ea716b0649c197800f42287fe5793aa9", "mime_type": "application/zlib; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 63987273, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows", "mac", "linux", "android", "bsd", "solaris", "others"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/grandperspectiv/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg?ts=gAAAAABqHFpOqL5HwvYZk7nQGy3867ZLpVW-x0ocdJx-VXjzcZSLnJLQVGSkh3X2lhq3y_lGpyZIyOzJqjgtUYJT_lzYTDRo4w%3D%3D", "vscan": "OK", "vscan_when": "2026-05-31 15:51:54"}, "linux": {"bytes": 4407902, "date": "2026-05-31 13:36:48", "date_modified": "2026-05-31 13:36:48", "file_type": "zlib compressed data", "filename": "/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg", "md5sum": "ea716b0649c197800f42287fe5793aa9", "mime_type": "application/zlib; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 63987273, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows", "mac", "linux", "android", "bsd", "solaris", "others"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/grandperspectiv/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg?ts=gAAAAABqHFpOqL5HwvYZk7nQGy3867ZLpVW-x0ocdJx-VXjzcZSLnJLQVGSkh3X2lhq3y_lGpyZIyOzJqjgtUYJT_lzYTDRo4w%3D%3D", "vscan": "OK", "vscan_when": "2026-05-31 15:51:54"}}}
"""#

/// TigerVNC's `best_release.json`, captured verbatim 2026-08-16
/// (`curl https://sourceforge.net/projects/tigervnc/best_release.json`, HTTP
/// 200). The TigerVNC recipe no longer reads this endpoint (it reads the
/// stable RSS below); the fixture stays because it pins two things: the
/// `mac` entry lagging the release, and the trap: top-level `release.filename`
/// is `/stable/1.16.0/tigervnc64-1.16.0.exe` — a Windows binary — while
/// `platform_releases.mac.filename` is `/stable/1.16.0/TigerVNC-1.16.0.dmg`,
/// the macOS artifact. A recipe reading the top-level key would still produce
/// a version-shaped string (`1.16.0`, same number here) on a good day, but on
/// a day the two platforms ship out of step it would silently report whichever
/// platform happened to release first — never verified against what's actually
/// installed on this machine.
private let tigerVNCFixture = #"""
{"release": {"bytes": 4596360, "date": "2026-01-27 14:25:02", "date_modified": "2026-01-27 14:25:02", "file_type": "PE32 executable", "filename": "/stable/1.16.0/tigervnc64-1.16.0.exe", "md5sum": "dbb9de325493d75067eb3379cb9bdf65", "mime_type": "application/vnd.microsoft.portable-executable; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 60900144, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "https://sourceforge.net/projects/tigervnc/files/stable/1.16.0/tigervnc64-1.16.0.exe/download", "vscan": "OK", "vscan_when": "2026-01-27 14:33:22"}, "platform_releases": {"mac": {"bytes": 6844016, "date": "2026-01-27 14:24:13", "date_modified": "2026-01-27 14:24:13", "file_type": "zlib compressed data", "filename": "/stable/1.16.0/TigerVNC-1.16.0.dmg", "md5sum": "f3d8db3ebbbb3dd802c1ac5d8c77682c", "mime_type": "application/zlib; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 60900082, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["mac"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/tigervnc/stable/1.16.0/TigerVNC-1.16.0.dmg?ts=gAAAAABpxS92YRGIhZ0NwRXrQBv8g546kXOw-bed0d59mFcrDbosNlxER7yoHrgqtskbnRRboJ42AmPHVUY6i9BTi79tD1HSlg%3D%3D", "vscan": "OK", "vscan_when": "2026-01-27 14:33:40"}, "windows": {"bytes": 4596360, "date": "2026-01-27 14:25:02", "date_modified": "2026-01-27 14:25:02", "file_type": "PE32 executable", "filename": "/stable/1.16.0/tigervnc64-1.16.0.exe", "md5sum": "dbb9de325493d75067eb3379cb9bdf65", "mime_type": "application/vnd.microsoft.portable-executable; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 60900144, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/tigervnc/stable/1.16.0/tigervnc64-1.16.0.exe?ts=gAAAAABpxS920ecjRBnvnb6bR7555aSpIelbCHX7_6aU4kE5WUiyxP9tbC_nMqAkM8aym484BYpu1P8jldb7Bw7Q40PPFtV3tQ%3D%3D", "vscan": "OK", "vscan_when": "2026-01-27 14:33:22"}, "linux": {"bytes": 649799, "date": "2026-03-26 11:53:06", "date_modified": "2026-03-26 11:53:06", "file_type": "Java archive data (JAR)", "filename": "/stable/1.16.2/VncViewer-1.16.2.jar", "md5sum": "21d9a757df08f9143bc350ce53265a8f", "mime_type": "application/java-archive; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 62329599, "sf_package_id": null, "sf_platform": [], "sf_platform_default": [], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/tigervnc/stable/1.16.2/VncViewer-1.16.2.jar?ts=gAAAAABpxS923_sqBpL6Ir1uepuF2Thia1SlyKF2U_1pvLt_PyVQVaFKtnjd9melKRUagklciGVIs5-2A-EGHEBWaW3_Ji-SNg%3D%3D", "vscan": "OK", "vscan_when": "2026-03-26 12:00:38"}}}
"""#

/// A slice of `https://sourceforge.net/projects/tigervnc/rss?path=/stable`,
/// captured 2026-10-10 with `User-Agent: DuoUpdater/0.1` (HTTP 200, 100 items).
/// Items kept verbatim, in feed order: the first item (a 1.16.2 Windows exe),
/// the only dmg in the feed (item 73 of 100), the 1.16.2 jar uploaded the same
/// second, and the last item (a 1.16.1 deb). The channel header is trimmed to its title.
private let tigerVNCStableRSSFixture = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:files="https://sourceforge.net/api/files.rdf#" xmlns:media="http://video.search.yahoo.com/mrss/" xmlns:doap="http://usefulinc.com/ns/doap#" xmlns:sf="https://sourceforge.net/api/sfelements.rdf#" version="2.0">
  <channel xmlns:files="https://sourceforge.net/api/files.rdf#" xmlns:media="http://video.search.yahoo.com/mrss/" xmlns:doap="http://usefulinc.com/ns/doap#" xmlns:sf="https://sourceforge.net/api/sfelements.rdf#">
    <title>TigerVNC</title>
    <item>
      <title><![CDATA[/stable/1.16.2/vncviewer64-1.16.2.exe]]></title>
      <link>https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/vncviewer64-1.16.2.exe/download</link>
      <guid>https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/vncviewer64-1.16.2.exe/download</guid>
      <pubDate>Thu, 26 Mar 2026 11:55:34 UT</pubDate>
      <description><![CDATA[/stable/1.16.2/vncviewer64-1.16.2.exe]]></description>
      <files:sf-file-id xmlns:files="https://sourceforge.net/api/files.rdf#">62329744</files:sf-file-id>
      <files:extra-info xmlns:files="https://sourceforge.net/api/files.rdf#">PE32+ executable</files:extra-info>
      <media:content xmlns:media="http://video.search.yahoo.com/mrss/" type="application/vnd.microsoft.portable-executable; charset=binary" url="https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/vncviewer64-1.16.2.exe/download" filesize="24072224"><media:hash algo="md5">62d89206d118deed93b7df651499b456</media:hash></media:content>
    </item>
    <item>
      <title><![CDATA[/stable/1.16.2/TigerVNC-1.16.2.dmg]]></title>
      <link>https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/TigerVNC-1.16.2.dmg/download</link>
      <guid>https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/TigerVNC-1.16.2.dmg/download</guid>
      <pubDate>Thu, 26 Mar 2026 11:53:06 UT</pubDate>
      <description><![CDATA[/stable/1.16.2/TigerVNC-1.16.2.dmg]]></description>
      <files:sf-file-id xmlns:files="https://sourceforge.net/api/files.rdf#">62329598</files:sf-file-id>
      <files:extra-info xmlns:files="https://sourceforge.net/api/files.rdf#">zlib compressed data</files:extra-info>
      <media:content xmlns:media="http://video.search.yahoo.com/mrss/" type="application/zlib; charset=binary" url="https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/TigerVNC-1.16.2.dmg/download" filesize="6845311"><media:hash algo="md5">f304571d98c4b39bbd82f135f25d1830</media:hash></media:content>
    </item>
    <item>
      <title><![CDATA[/stable/1.16.2/VncViewer-1.16.2.jar]]></title>
      <link>https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/VncViewer-1.16.2.jar/download</link>
      <guid>https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/VncViewer-1.16.2.jar/download</guid>
      <pubDate>Thu, 26 Mar 2026 11:53:06 UT</pubDate>
      <description><![CDATA[/stable/1.16.2/VncViewer-1.16.2.jar]]></description>
      <files:sf-file-id xmlns:files="https://sourceforge.net/api/files.rdf#">62329599</files:sf-file-id>
      <files:extra-info xmlns:files="https://sourceforge.net/api/files.rdf#">Java archive data (JAR)</files:extra-info>
      <media:content xmlns:media="http://video.search.yahoo.com/mrss/" type="application/java-archive; charset=binary" url="https://sourceforge.net/projects/tigervnc/files/stable/1.16.2/VncViewer-1.16.2.jar/download" filesize="649799"><media:hash algo="md5">21d9a757df08f9143bc350ce53265a8f</media:hash></media:content>
    </item>
    <item>
      <title><![CDATA[/stable/1.16.1/ubuntu-22.04LTS/arm64/tigervnc-java_1.16.1-1ubuntu1_arm64.deb]]></title>
      <link>https://sourceforge.net/projects/tigervnc/files/stable/1.16.1/ubuntu-22.04LTS/arm64/tigervnc-java_1.16.1-1ubuntu1_arm64.deb/download</link>
      <guid>https://sourceforge.net/projects/tigervnc/files/stable/1.16.1/ubuntu-22.04LTS/arm64/tigervnc-java_1.16.1-1ubuntu1_arm64.deb/download</guid>
      <pubDate>Wed, 25 Mar 2026 02:57:18 UT</pubDate>
      <description><![CDATA[/stable/1.16.1/ubuntu-22.04LTS/arm64/tigervnc-java_1.16.1-1ubuntu1_arm64.deb]]></description>
      <files:sf-file-id xmlns:files="https://sourceforge.net/api/files.rdf#">62295057</files:sf-file-id>
      <files:extra-info xmlns:files="https://sourceforge.net/api/files.rdf#">Debian binary package (format 2.0), with control.tar.zst, data compression zst</files:extra-info>
      <media:content xmlns:media="http://video.search.yahoo.com/mrss/" type="application/vnd.debian.binary-package; charset=binary" url="https://sourceforge.net/projects/tigervnc/files/stable/1.16.1/ubuntu-22.04LTS/arm64/tigervnc-java_1.16.1-1ubuntu1_arm64.deb/download" filesize="5246"><media:hash algo="md5">d612ebea34a8f65696c36e3e35eb94d7</media:hash></media:content>
    </item>
  </channel>
</rss>
"""#

/// qBittorrent's `best_release.json`, captured verbatim 2026-08-16
/// (`curl https://sourceforge.net/projects/qbittorrent/best_release.json`,
/// HTTP 200). Also demonstrates the trap: top-level `release.filename` is the
/// Windows installer `qbittorrent_5.2.3_x64_setup.exe`, while
/// `platform_releases.mac.filename` is `qbittorrent-5.2.3.dmg`. Both name
/// version 5.2.3 today, same as GrandPerspective's fixture above, but nothing
/// guarantees the two tracks stay in lockstep — only the `mac` block is this
/// app's own release.
private let qBittorrentFixture = #"""
{"release": {"bytes": 43100219, "date": "2026-07-07 22:00:50", "date_modified": "2026-07-07 22:00:50", "file_type": "PE32 executable", "filename": "/qbittorrent-win32/qbittorrent-5.2.3/qbittorrent_5.2.3_x64_setup.exe", "md5sum": "c4c58fa22842733f566c4ef47306bfd3", "mime_type": "application/vnd.microsoft.portable-executable; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 64917119, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "https://sourceforge.net/projects/qbittorrent/files/qbittorrent-win32/qbittorrent-5.2.3/qbittorrent_5.2.3_x64_setup.exe/download", "vscan": "OK", "vscan_when": null}, "platform_releases": {"mac": {"bytes": 48317381, "date": "2026-07-07 21:56:24", "date_modified": "2026-07-07 21:56:24", "file_type": "zlib compressed data", "filename": "/qbittorrent-mac/qbittorrent-5.2.3/qbittorrent-5.2.3.dmg", "md5sum": "0fc4d1c986502e65228339b7d08c4ecf", "mime_type": "application/zlib; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 64917018, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["mac"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/qbittorrent/qbittorrent-mac/qbittorrent-5.2.3/qbittorrent-5.2.3.dmg?ts=gAAAAABqTYg6NDxVsQgB6DL15dSpuhDxlB_PYVhqdwJ87PtQOJHORqDIsYc0vkxAj2L2NyD9Yi9VyZ8ZQx5VR7JMY1OPmEh0dg%3D%3D", "vscan": "OK", "vscan_when": null}, "windows": {"bytes": 43100219, "date": "2026-07-07 22:00:50", "date_modified": "2026-07-07 22:00:50", "file_type": "PE32 executable", "filename": "/qbittorrent-win32/qbittorrent-5.2.3/qbittorrent_5.2.3_x64_setup.exe", "md5sum": "c4c58fa22842733f566c4ef47306bfd3", "mime_type": "application/vnd.microsoft.portable-executable; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 64917119, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["windows"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/qbittorrent/qbittorrent-win32/qbittorrent-5.2.3/qbittorrent_5.2.3_x64_setup.exe?ts=gAAAAABqTYg6I9tlCP0zm72iLYm9Jj_df1KITozfyHCWC2fVB2xQb7yNlKyHaf2auh-QmpiOm5eLLH3pEEDIThY5bYkChK1c8w%3D%3D", "vscan": "OK", "vscan_when": null}, "linux": {"bytes": 101222904, "date": "2026-07-07 21:59:14", "date_modified": "2026-07-07 21:59:14", "file_type": "ELF 64-bit LSB pie executable, x86-64 (SYSV), static-pie linked", "filename": "/qbittorrent-appimage/qbittorrent-5.2.3/qbittorrent-5.2.3_x86_64.AppImage", "md5sum": "29c2816b8bf8163af5c98906cd5429cb", "mime_type": "application/x-pie-executable; charset=binary", "release_notes_url": null, "sf_download_label": null, "sf_file_id": 64917083, "sf_package_id": null, "sf_platform": [], "sf_platform_default": ["linux"], "sf_release_id": null, "sf_release_notes_file": null, "sf_type": null, "staged_until": null, "url": "http://downloads.sourceforge.net/project/qbittorrent/qbittorrent-appimage/qbittorrent-5.2.3/qbittorrent-5.2.3_x86_64.AppImage?ts=gAAAAABqTYg6cIrT_h3ynWXOr71MXKRc3whvHTIFLtc6iNR0ltFw-xR_y-Ee-8KqtXfgm8RawcGzNq2bRdJFhTya5SzpoQuacg%3D%3D", "vscan": "OK", "vscan_when": null}}}
"""#

/// The three 2026-08-16 SourceForge recipes. GrandPerspective is wired through
/// the shared `sourceForgeMacRecipe` helper at the bottom of
/// `VendorProbeRecipe.swift`; TigerVNC reads the stable RSS; qBittorrent moved
/// to GitHub.
struct GroupCProbeRecipeTests {

    private func recipe(_ bundleID: String) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
    }

    // MARK: - GrandPerspective

    @Test func grandPerspectiveReadsTheMacVersion() throws {
        let recipe = try self.recipe("net.sourceforge.grandperspectiv")
        #expect(recipe.url.absoluteString
            == "https://sourceforge.net/projects/grandperspectiv/best_release.json")
        #expect(VendorProbeRecipe.extractVersion(
            from: grandPerspectiveFixture, pattern: recipe.versionPattern) == "3.7.2")
    }

    @Test func grandPerspectiveIsOneClick() throws {
        let recipe = try self.recipe("net.sourceforge.grandperspectiv")
        let spec = try #require(recipe.install)
        #expect(spec.kind == .dmg)
        guard case .bodyTemplate(let template, let fields) = spec.urlSource else {
            Issue.record("expected a body template"); return
        }
        #expect(fields.count == 1)
        let filename = try #require(
            VendorProbeRecipe.extractVersion(from: grandPerspectiveFixture, pattern: fields[0]))
        #expect(filename == "/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg")
        let resolved = template.replacingOccurrences(of: "{0}", with: filename)
        #expect(resolved
            == "https://sourceforge.net/projects/grandperspectiv/files"
            + "/grandperspective/3.7.2/GrandPerspective-3_7_2.dmg/download")
    }

    // MARK: - TigerVNC — read from the stable RSS, not best_release.json

    /// The reason TigerVNC left `best_release.json`: in the 2026-08-16 capture,
    /// `platform_releases.mac` names the 1.16.0 dmg while `linux` in the same
    /// document already names the 1.16.2 jar. The maintainer never moved the
    /// macOS default, although a notarized 1.16.2 dmg is on SourceForge. Pinned so
    /// nobody points this app back at that field without seeing the gap.
    @Test func tigerVNCBestReleaseMacEntryLagsTheRelease() throws {
        let macFilename = #""mac":\s*\{[^}]*?"filename":\s*"([^"]+)""#
        let linuxFilename = #""linux":\s*\{[^}]*?"filename":\s*"([^"]+)""#
        #expect(VendorProbeRecipe.extractVersion(from: tigerVNCFixture, pattern: macFilename)
            == "/stable/1.16.0/TigerVNC-1.16.0.dmg")
        #expect(VendorProbeRecipe.extractVersion(from: tigerVNCFixture, pattern: linuxFilename)
            == "/stable/1.16.2/VncViewer-1.16.2.jar")
        let recipe = try self.recipe("com.tigervnc.tigervnc")
        #expect(recipe.url.absoluteString
            == "https://sourceforge.net/projects/tigervnc/rss?path=/stable")
        guard case .responseBody = recipe.mode else {
            Issue.record("expected a response-body probe"); return
        }
    }

    @Test func tigerVNCReadsTheDmgFromTheStableFeed() throws {
        let recipe = try self.recipe("com.tigervnc.tigervnc")
        #expect(recipe.selectHighest)
        // Every other item in the slice (exe, jar, deb of 1.16.1 and 1.16.2) is
        // version-shaped; only the dmg title may match.
        #expect(VendorProbeRecipe.highestVersion(
            from: tigerVNCStableRSSFixture, pattern: recipe.versionPattern) == "1.16.2")
        let regex = try NSRegularExpression(pattern: recipe.versionPattern)
        let range = NSRange(tigerVNCStableRSSFixture.startIndex..., in: tigerVNCStableRSSFixture)
        #expect(regex.numberOfMatches(in: tigerVNCStableRSSFixture, range: range) == 1)
    }

    /// The backreference ties the folder to the filename, and the anchor on the
    /// `TigerVNC-` prefix and `.dmg` keeps every other artifact out.
    @Test func tigerVNCPatternRejectsOtherArtifactsAndMismatchedPaths() throws {
        let pattern = try self.recipe("com.tigervnc.tigervnc").versionPattern
        for title in [
            "/stable/1.16.2/tigervnc64-1.16.2.exe",
            "/stable/1.16.2/VncViewer-1.16.2.jar",
            "/stable/1.16.2/TigerVNC-1.16.1.dmg",
            "/beta/1.16.90/TigerVNC-1.16.90.dmg",
        ] {
            #expect(VendorProbeRecipe.extractVersion(
                from: "<title><![CDATA[\(title)]]></title>", pattern: pattern) == nil, "\(title)")
        }
    }

    @Test func tigerVNCIsOneClickFromTheResolvedVersion() throws {
        let recipe = try self.recipe("com.tigervnc.tigervnc")
        let spec = try #require(recipe.install)
        #expect(spec.kind == .dmg)
        guard case .versionTemplate(let template) = spec.urlSource else {
            Issue.record("expected a version template"); return
        }
        let version = try #require(VendorProbeRecipe.highestVersion(
            from: tigerVNCStableRSSFixture, pattern: recipe.versionPattern))
        let resolved = template.replacingOccurrences(of: "{version}", with: version)
        #expect(resolved
            == "https://sourceforge.net/projects/tigervnc/files"
            + "/stable/1.16.2/TigerVNC-1.16.2.dmg/download")
        // The same URL the feed itself publishes as the item's link.
        #expect(tigerVNCStableRSSFixture.contains("<link>\(resolved)</link>"))
    }

    /// A pattern shaped like the naive, un-scoped read `sourceForgeMacRecipe`
    /// deliberately avoids: applied to the whole document it finds the FIRST
    /// version-shaped filename, which is the top-level (Windows) `release` block,
    /// not `platform_releases.mac`. Pinned on TigerVNC's capture, the one where
    /// the two differ, against the helper's own filename capture (GrandPerspective
    /// still uses the helper).
    @Test func aTopLevelOnlyPatternWouldHaveReadTheWindowsBuild() throws {
        // What "just read release.filename" looks like as a pattern — no
        // scoping to platform_releases.mac at all.
        let bareTopLevelPattern = #""release":\s*\{[^}]*?"filename":\s*"([^"]+)""#
        let wrongValue = try #require(
            VendorProbeRecipe.extractVersion(from: tigerVNCFixture, pattern: bareTopLevelPattern))
        #expect(wrongValue == "/stable/1.16.0/tigervnc64-1.16.0.exe")
        #expect(!wrongValue.contains(".dmg"))
        // The helper's capture, scoped to platform_releases.mac, is immune.
        let spec = try #require(try self.recipe("net.sourceforge.grandperspectiv").install)
        guard case .bodyTemplate(_, let fields) = spec.urlSource else {
            Issue.record("expected a body template"); return
        }
        let correctValue = try #require(
            VendorProbeRecipe.extractVersion(from: tigerVNCFixture, pattern: fields[0]))
        #expect(correctValue == "/stable/1.16.0/TigerVNC-1.16.0.dmg")
    }

    // MARK: - qBittorrent — moved to a GitHub release rule

    /// qBittorrent was read from SourceForge until 2026-08-16 and now comes from
    /// GitHub Releases (the same dmg, published by the same project). Two things
    /// have to stay true, and neither is obvious from the rule alone.
    ///
    /// 1. There must be no leftover SourceForge recipe. Two sources for one bundle
    ///    id is not a harmless duplicate here — the vendor probe runs LAST, so a
    ///    stale recipe would sit unused until the GitHub rule missed, then answer
    ///    with whatever `best_release.json` happens to say.
    /// 2. It stays detection-only. Upstream signs with its own certificate
    ///    (`Authority=qbittorrent macos`, `TeamIdentifier=not set`; `spctl` rejects
    ///    it) — verified 2026-08-16 by mounting BOTH the SourceForge dmg and
    ///    GitHub's `qbittorrent-5.2.3.dmg`, which are the same build. Changing
    ///    where we read from cannot change that, so no install asset pattern.
    @Test func qBittorrentReadsFromGitHubAndStaysDetectionOnly() throws {
        #expect(VendorProbeRegistry.recipes
            .first { $0.bundleID == "org.qbittorrent.qBittorrent" } == nil,
            "the SourceForge recipe must be gone, not merely unused")

        let rule = try #require(GitHubReleaseRegistry.rules
            .first { $0.bundleID == "org.qbittorrent.qBittorrent" })
        #expect(rule.owner == "qbittorrent")
        #expect(rule.repo == "qBittorrent")
        #expect(rule.installAssetPattern == nil)
        #expect(rule.installerKind == nil)

        // The real tag shape, and the old `v3.x` tags the anchor exists to reject.
        #expect(VendorProbeRecipe.extractVersion(
            from: "release-5.2.3", pattern: rule.versionPattern) == "5.2.3")
        #expect(VendorProbeRecipe.extractVersion(
            from: "v3.3.16", pattern: rule.versionPattern) == nil)
    }

    // MARK: - The UA override these three depend on

    /// SourceForge's edge 403s the browser-like UA `VendorProbeSource` sends by
    /// default: measured 2026-08-16 on `best_release.json` with the UA as the only
    /// variable (curl's own UA → 200, `DuoUpdater/0.1` → 200, the Safari string →
    /// 403). All three recipes here went red in `duo verify` for exactly that
    /// reason and only came back with this header, so drop it and they break.
    @Test func sourceForgeRecipesOverrideTheBrowserUserAgent() throws {
        for id in ["net.sourceforge.grandperspectiv",
                   "com.tigervnc.tigervnc"] {
            let recipe = try self.recipe(id)
            let ua = recipe.requestHeaders["User-Agent"]
            #expect(ua != nil, "\(id) must send its own User-Agent")
            #expect(ua?.contains("Mozilla") == false, "\(id) must not send a browser UA")
        }
    }
}
