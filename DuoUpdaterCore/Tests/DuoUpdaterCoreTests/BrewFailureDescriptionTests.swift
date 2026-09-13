import Testing
import Foundation
@testable import DuoUpdaterCore

/// What a failed `brew` run reports as its one-line description
/// (`HomebrewInstaller.failureDescription`). Every surface renders it with
/// `.lineLimit(1)`, so the first thing in it is all the user sees.
///
/// Each case goes through both `BrewError` enums, so a copy that stops calling the
/// shared helper fails here rather than drifting back to the old tail on its own.
@Suite struct BrewFailureDescriptionTests {

    private static func descriptions(code: Int32, output: String) -> [String?] {
        [
            BrewFormulaService.BrewError.failed(code: code, output: output).errorDescription,
            HomebrewInstaller.BrewError.failed(code: code, output: output).errorDescription,
        ]
    }

    /// The trust block's wording follows brew 7.0.0's `diagnostic.rb` template
    /// (tap names invented); the rest is the `brew upgrade --formula` output of a
    /// no-bottle formula on a machine with outdated Command Line Tools, observed
    /// 2026-09-13. None of the trust block may be surfaced as the error, and
    /// neither may brew's remediation after the `Error:` line.
    static let outdatedCLTWithTrustWarning = """
        Warning: The following taps are not trusted:
          zzfixture/untrusted
          zzfixture/other
        Homebrew is currently ignoring formulae, casks and commands
        from these taps because tap trust is required.
        Untap them with:
          brew untap zzfixture/untrusted zzfixture/other
        Trust specific formulae, casks and commands with:
          brew trust --formula <user>/<tap>/<formula>
        ==> Upgrading zzfixture/tap/zzfixture-alpha
          1.3.14 -> 1.4.2
        Error: Your Command Line Tools are too outdated.

        Update them from Software Update in System Settings.

        If that doesn't show you any updates, run:
          sudo rm -rf /Library/Developer/CommandLineTools
          sudo xcode-select --install

        Alternatively, manually download them from:
          https://developer.apple.com/download/all/.
        You should download the Command Line Tools for Xcode 27.0.

        """

    /// Mutation: return the tail unconditionally (the pre-fix body) → both copies
    /// report `brew failed (1): Alternatively, manually download them from: …`.
    /// Mutation: one `BrewError` copy keeps its own tail → that copy's entry fails.
    @Test func leadsWithTheErrorLineNotTheTrailingAdvice() {
        for description in Self.descriptions(code: 1, output: Self.outdatedCLTWithTrustWarning) {
            #expect(description == "brew failed (1): Error: Your Command Line Tools are too outdated.")
        }
    }

    /// With `HOMEBREW_COLOR` set brew colours the label: `ESC[31mError:ESC[0m …`
    /// (bytes captured 2026-09-13 from `HOMEBREW_COLOR=1 brew info <missing>`
    /// through a pipe, brew 7.0.0).
    /// Mutation: check the prefix before stripping escapes → no line starts with
    /// `Error:`, and the tail comes back. Mutation: strip only for the check and
    /// return the raw line → escapes leak into the description.
    @Test func aColouredErrorLineIsFoundAndStripped() {
        let esc = "\u{1B}"
        let output = Self.outdatedCLTWithTrustWarning.replacingOccurrences(
            of: "Error: Your Command Line Tools",
            with: "\(esc)[31mError:\(esc)[0m Your Command Line Tools")
        for description in Self.descriptions(code: 1, output: output) {
            #expect(description == "brew failed (1): Error: Your Command Line Tools are too outdated.")
        }
    }

    /// No `Error:` line: exactly the old tail, last three non-empty lines joined.
    /// Mutation: fall back to the first lines (or to nothing) → the expected tail
    /// is not what comes back.
    @Test func withoutAnErrorLineTheTailIsKept() {
        let output = """
            ==> Upgrading zzfixture-alpha
            ==> Pouring zzfixture-alpha--1.0.arm64_tahoe.bottle.tar.gz
            zzfixture-alpha: post-install step exited 2
            Warning: zzfixture-alpha was not linked

            """
        for description in Self.descriptions(code: 2, output: output) {
            #expect(description == "brew failed (2): ==> Pouring zzfixture-alpha--1.0.arm64_tahoe.bottle.tar.gz zzfixture-alpha: post-install step exited 2 Warning: zzfixture-alpha was not linked")
        }
    }

    /// Several `Error:` lines: the first one, which is the cause; later ones are
    /// consequences.
    /// Mutation: `.last { … }` instead of `.first { … }` → the second error.
    @Test func withSeveralErrorLinesTheFirstLeads() {
        let output = """
            ==> Upgrading zzfixture-alpha
            Error: zzfixture-alpha: Failed to download resource "zzfixture-alpha--1.0"
            Download failed: https://zzfixture.invalid/zzfixture-alpha-1.0.tar.gz
            Error: Some upgrades failed: zzfixture-alpha
            If reporting this issue please do so at (not Homebrew/*):
              https://zzfixture.invalid/issues

            """
        for description in Self.descriptions(code: 1, output: output) {
            #expect(description == #"brew failed (1): Error: zzfixture-alpha: Failed to download resource "zzfixture-alpha--1.0""#)
        }
    }
}
