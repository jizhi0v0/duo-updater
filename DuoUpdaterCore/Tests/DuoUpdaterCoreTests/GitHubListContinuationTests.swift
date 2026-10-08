import Testing
import Foundation
@testable import DuoUpdaterCore

/// A list item hard-wrapped onto the next line keeps the wrapped text
/// (`GitHubMarkdownParser.joiningListContinuations`).
///
/// Audacity 3.7.9 and 3.7.8 (`audacity/audacity`) are the real release bodies,
/// verbatim, fetched 2026-10-08 from the GitHub releases API — escaped literals,
/// because the API returns them with CRLF line breaks.
struct GitHubListContinuationTests {

    private static func items(_ body: String, _ version: String) -> [String] {
        GitHubMarkdownParser.parse(body: body, version: version, date: nil)?.entries.first?.items ?? []
    }

    @Test func audacityWrappedItemsKeepTheirSecondLine() {
        let items379 = Self.items(Self.audacity379, "3.7.9")
        #expect(items379.count == 8)
        #expect(items379.contains(
            "#11696 Fixed a freeze when double-clicking the timeline while a MIDI track is present MIDI playback now also starts from the set position instead of the beginning"))
        #expect(!items379.contains { $0.contains("Full Changelog") || $0.contains("UPDATE") })

        let items378 = Self.items(Self.audacity378, "3.7.8")
        #expect(items378.count == 11)
        #expect(items378[1]
            == "#10870, #10884, #10775, #10629 Fixed tone generation, waveform-scale setting, SetClip Name parameter, and clip-boundary command names for scripting and macros (Thank you, David Bailes (@DavidBailes)!)")
    }

    /// A lazy continuation (not indented) joins too; a hard break's trailing
    /// spaces read as one space.
    @Test func lazyContinuationJoinsTheItem() {
        let body = "## Fixed\n\n- Fixed a crash when closing  \nthe last window\n- Fixed a leak\n"
        #expect(Self.items(body, "1.0") == ["Fixed a crash when closing the last window", "Fixed a leak"])
    }

    /// What follows an item without continuing it stays out of the item: a
    /// line after a blank one, a heading, another item, a fence, an image, a
    /// quote and a thematic break.
    @Test func linesThatDoNotContinueAnItemStayOut() {
        let body = """
        ## Fixed

        - Fixed a crash on launch
          ![screenshot](https://example.com/shot.png)
        - Fixed a leak in the renderer
        > Quoted aside
        - Fixed scrolling in long lists
        ---
        - Fixed the dock icon badge

        A paragraph after the list.
        - Fixed a typo in settings
        ## Added
        - Added a dark theme
        ```
        - fenced bullet
        continued fence text
        ```
        """
        #expect(Self.items(body, "1.0") == [
            "Fixed a crash on launch",
            "Fixed a leak in the renderer",
            "Fixed scrolling in long lists",
            "Fixed the dock icon badge",
            "Fixed a typo in settings",
            "Added a dark theme",
            "fenced bullet",
        ])
    }

    static let audacity379 = "This is a patch release. It contains the following changes:\r\n\r\n   * #11690 Enabled ASIO support for the Windows builds, playback and recording device selection is remembered per-host now\r\n   * #11679 Added FFmpeg 9 support\r\n   * #11714 Fixed several sources of project corruption and data loss: when the disk runs out of space, when a drive is disconnected right after a project is closed, and when a recovered project is closed without saving\r\n   * #11709 Fixed crashes while a realtime effect editor is open, master track effect changes can now be undone\r\n   * #11696 Fixed a freeze when double-clicking the timeline while a MIDI track is present\r\n     MIDI playback now also starts from the set position instead of the beginning\r\n   * #11711 Fixed a crash after a failed recording attempt\r\n   * #11526 Fixed clips having the wrong tempo after opening a project (Thanks, David Bailes (@DavidBailes)!)\r\n   * #11623 Fixed a freeze on startup on systems with an incorrect font configuration\r\n\r\n**Full Changelog**: https://github.com/audacity/audacity/compare/Audacity-3.7.8...Audacity-3.7.9\r\n\r\n*UPDATE:* due to issues with our infra, the manual published earlier was corrupted and was replaced. There were no security risks involved."

    static let audacity378 = "This is a patch release. It contains the following changes:\r\n\r\n   * #10688 Fixed an exception thrown when pasting into a newly-created track (Thanks, David Bailes (@DavidBailes)!)\r\n   * #10870, #10884, #10775, #10629 Fixed tone generation, waveform-scale setting, SetClip Name parameter,\r\n     and clip-boundary command names for scripting and macros (Thank you, David Bailes (@DavidBailes)!)\r\n   * #11106 Fixed the loading of presets for the Distortion effect (A million thanks, David Bailes (@DavidBailes)!)\r\n   * #10947 Fixed paste into an empty audio track not preserving the source sample rate (Thanks, Juan Gabriel Colonna (@juancolonna)!)\r\n   * #10776 Allowed AltGr modifier in label and clip name editing (Thanks, Davide Peressoni (@DPDmancul)!)\r\n   * #9938 Added options to choose where silence is truncated (start/middle/end) (Thanks, Noah Rosenfield (@nosenfield)!)\r\n   * #9935 Added Podcast 2.0 chapters JSON export for label tracks (Thanks, Noah Rosenfield (@nosenfield)!)\r\n   * #10103 Improve UI on HiDPI displays on Linux/wxGTK (Thanks, Ivan A. Melnikov (@iv-m)!)\r\n   * #10099 Fixed MixerBoard Mute and Solo button display (Thanks, Ivan A. Melnikov (@iv-m)!)\r\n   * #10681 Fixed multichannel FLAC import\r\n   * #10999 Fixed envelope being broken after joining clips"
}
