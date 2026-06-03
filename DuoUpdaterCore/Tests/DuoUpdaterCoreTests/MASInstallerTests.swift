import Testing
import Foundation
@testable import DuoUpdaterCore

/// mas draws its download bar to a (pseudo-)TTY using ANSI clear-line + cursor
/// moves instead of newlines. The tailer normalizes those into line breaks and
/// strips colors so the phase markers and "N% downloaded" ticks come out as clean
/// lines; `stage(for:)` then maps them to install stages. This is the exact byte
/// shape captured from a real `mas install … --force` run under `script`.
@Test func parsesLiveProgressFromAnsiBar() {
    let esc = "\u{1B}"
    let raw =
        "\(esc)[2K\(esc)[0G\(esc)[1;34m==>\(esc)[0m Downloading LocalSend (1.17.0)\r" +
        "\(esc)[2K\(esc)[0G------------------------------------ 0% downloaded" +
        "\(esc)[2K\(esc)[0G#################################### 87% downloaded" +
        "\(esc)[2K\(esc)[0G#################################### 100% downloaded\r" +
        "\(esc)[1;34m==>\(esc)[0m Installing LocalSend (1.17.0)\r"

    // Reproduce the tailer's normalization pipeline.
    var s = raw.replacingOccurrences(of: "\r", with: "\n")
    s = MASInstaller.replaceCursorMovesWithNewlines(s)
    s = MASInstaller.stripANSI(s)
    let lines = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    let stages = lines.compactMap { MASInstaller.stage(for: $0) }
    #expect(stages.contains(.downloading(fraction: 0)))
    #expect(stages.contains(.downloading(fraction: 0.87)))
    #expect(stages.contains(.downloading(fraction: 1.0)))
    #expect(stages.contains(.installing))
}

/// Phase-marker and percentage mapping, independent of ANSI handling.
@Test func mapsMasLinesToStages() {
    #expect(MASInstaller.stage(for: "==> Downloading Microsoft Excel (16.109.3)") == .downloading(fraction: 0))
    #expect(MASInstaller.stage(for: "45% downloaded") == .downloading(fraction: 0.45))
    #expect(MASInstaller.stage(for: "==> Downloaded Microsoft Excel (16.109.3)") == .downloading(fraction: 1.0))
    #expect(MASInstaller.stage(for: "==> Installing Microsoft Excel (16.109.3)") == .installing)
    // The terminal line and unrelated noise produce no stage (completion is the
    // caller's job; "Install progress cannot be displayed" must not be mistaken).
    #expect(MASInstaller.stage(for: "==> Installed Microsoft Excel (16.109.3) in /Applications/Microsoft Excel.app") == nil)
    #expect(MASInstaller.stage(for: "Install progress cannot be displayed") == nil)
}
