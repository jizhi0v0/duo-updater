import Testing
import Foundation
@testable import DuoUpdaterCore

/// rustup's `CHANGELOG.md` and Rust's `RELEASES.md` as release notes. The
/// fixtures copy the two documents' shapes as fetched on 2026-10-01 — headings,
/// wrapping, nesting, anchors and reference links — with shortened text.
@Suite struct RustChangelogTests {

    static let rustup = """
        # Changelog

        ## [1.29.1] - 2026-08-13

        This new patch release has brought some minor improvements.

        The headlines of this release are:

        - Concurrency in certain `rustup` operations has been improved:
          - When running `rustup update`, rustup will first check for possible updates
            in parallel. [pr#4752]

        - `rustup doc` now supports the `--serve` flag which allows serving the docs
          over local HTTP. [pr#4986]

        - The cURL backend is deprecated, see [the announcement][blog post].

          ```sh
          rustup set auto-self-update disable
          ```

        [1.29.1]: https://github.com/rust-lang/rustup/releases/tag/1.29.1
        [pr#4752]: https://github.com/rust-lang/rustup/pull/4752
        [pr#4986]: https://github.com/rust-lang/rustup/pull/4986
        [blog post]: https://blog.rust-lang.org/example

        ### Detailed changes

        * chore(deps): lock file maintenance by @renovate[bot] in https://github.com/rust-lang/rustup/pull/4321
        * Run a parallel pre-check before updating toolchains by @someone in https://github.com/rust-lang/rustup/pull/4752

        ## [1.27.1] - 2024-04-14

        ### Added

        - Prebuilt binaries for a new host. [pr#3700][]

        ### Changed

        - Fixed a regression in proxies. [pr#3701]

        ### Thanks

        - Somebody Example
        - Someone Else

        [pr#3700]: https://github.com/rust-lang/rustup/pull/3700
        [pr#3701]: https://github.com/rust-lang/rustup/pull/3701

        ## [Unreleased]

        - not a release
        """

    @Test func rustupSections() throws {
        let changelog = try #require(RustChangelog.parseRustup(Self.rustup))
        #expect(changelog.itemSyntax == .markdown)
        #expect(changelog.entries.map(\.version) == ["1.29.1", "1.27.1"])
        let latest = changelog.entries[0]
        #expect(latest.date == "2026-08-13")
        #expect(latest.items == [
            "Concurrency in certain `rustup` operations has been improved:",
            "When running `rustup update`, rustup will first check for possible updates in parallel. "
                + "[pr#4752](https://github.com/rust-lang/rustup/pull/4752)",
            "`rustup doc` now supports the `--serve` flag which allows serving the docs over local HTTP. "
                + "[pr#4986](https://github.com/rust-lang/rustup/pull/4986)",
            "The cURL backend is deprecated, see [the announcement](https://blog.rust-lang.org/example).",
        ])
        let older = changelog.entries[1]
        #expect(older.items == [
            "Prebuilt binaries for a new host. [pr#3700](https://github.com/rust-lang/rustup/pull/3700)",
            "Fixed a regression in proxies. [pr#3701](https://github.com/rust-lang/rustup/pull/3701)",
        ])
        #expect(older.content.first == .heading("Added"))
        #expect(older.content.contains(.heading("Changed")))
    }

    /// Kills the mutation that stops skipping rustup's pull-request list and
    /// thanks: renovate's lock-file bump and the contributors' names would read
    /// as changes.
    @Test func rustupSkipsThePullRequestListAndThanks() throws {
        let changelog = try #require(RustChangelog.parseRustup(Self.rustup))
        let all = changelog.entries.flatMap(\.items)
        #expect(!all.contains { $0.contains("lock file maintenance") })
        #expect(!all.contains { $0.contains("Somebody Example") })
    }

    static let releases = """
        Version 1.99.0 (2026-10-01)
        ==========================

        <a id="1.99.0-Language"></a>

        Language
        --------
        - [Stabilize C-variadic function definitions](https://github.com/rust-lang/rust/pull/155697)
        - We now [guarantee](https://github.com/rust-lang/rust/pull/159730) that an `UnsafeCell` can be read
          - [The `invalid_reference_casting` lint was adjusted accordingly](https://github.com/rust-lang/rust/pull/159960)


        <a id="1.99.0-Platform-Support"></a>

        Platform Support
        ----------------
        - [Promote `riscv64-unknown-linux-musl` to Tier 2 with host tools](https://github.com/rust-lang/rust/pull/158766)


        Refer to Rust's [platform support page][platform-support-doc]
        for more information on Rust's tiered platform support.

        [platform-support-doc]: https://doc.rust-lang.org/rustc/platform-support.html

        <a id="1.99.0-Rustdoc"></a>

        Rustdoc
        -----
        - [Add new `unused_footnote_definition` rustdoc lint](https://github.com/rust-lang/rust/pull/137858)

        Version 1.98.1 (2026-09-03)
        ===========================

        <a id="1.98.1"></a>

        * [Remove new methods added to `std::os::windows::fs::OpenOptionsExt`](https://github.com/rust-lang/rust/pull/153491)
          The new methods were unstable, but the trait itself is not sealed.

        Version 1.62.1 (2022-07-19)
        ==========================

        Rust 1.62.1 addresses a few recent regressions.

        - [The `x86_64-fortanix-unknown-sgx` target added a mitigation for the
          MMIO stale data vulnerability][98126], advisory [INTEL-SA-00615].

        [98126]: https://github.com/rust-lang/rust/pull/98126
        [INTEL-SA-00615]: https://www.intel.com/example

        Version 0.3  (2012-07-12)
        ========================

           * Rewrote the scheduler entirely
        """

    @Test func rustSections() throws {
        let changelog = try #require(RustChangelog.parseRust(Self.releases))
        #expect(changelog.entries.map(\.version) == ["1.99.0", "1.98.1", "1.62.1", "0.3"])
        #expect(changelog.entries.map(\.date) == ["2026-10-01", "2026-09-03", "2022-07-19", "2012-07-12"])

        let minor = changelog.entries[0]
        #expect(minor.items == [
            "[Stabilize C-variadic function definitions](https://github.com/rust-lang/rust/pull/155697)",
            "We now [guarantee](https://github.com/rust-lang/rust/pull/159730) that an `UnsafeCell` can be read",
            "[The `invalid_reference_casting` lint was adjusted accordingly](https://github.com/rust-lang/rust/pull/159960)",
            "[Promote `riscv64-unknown-linux-musl` to Tier 2 with host tools](https://github.com/rust-lang/rust/pull/158766)",
            "[Add new `unused_footnote_definition` rustdoc lint](https://github.com/rust-lang/rust/pull/137858)",
        ])
        let headings = minor.content.compactMap { block -> String? in
            if case .heading(let heading) = block { return heading }
            return nil
        }
        #expect(headings == ["Language", "Platform Support", "Rustdoc"])
        #expect(!minor.items.contains { $0.contains("<a id") || $0.contains("platform-support-doc") })

        #expect(changelog.entries[1].items == [
            "[Remove new methods added to `std::os::windows::fs::OpenOptionsExt`](https://github.com/rust-lang/rust/pull/153491)"
                + " The new methods were unstable, but the trait itself is not sealed.",
        ])
    }

    /// Kills the mutation that resolves references line by line: this one
    /// wraps across two source lines.
    @Test func wrappedReferenceLinksResolve() throws {
        let changelog = try #require(RustChangelog.parseRust(Self.releases))
        #expect(changelog.entries[2].items == [
            "[The `x86_64-fortanix-unknown-sgx` target added a mitigation for the MMIO stale data vulnerability]"
                + "(https://github.com/rust-lang/rust/pull/98126), advisory [INTEL-SA-00615](https://www.intel.com/example).",
        ])
    }

    @Test func referenceForms() {
        let links = ["a": "https://a.example", "pr#1": "https://p.example/1", "96881": "https://r.example/96881"]
        #expect(RustChangelog.resolve("see [x][a] and [pr#1] and [pr#1][]", links: links)
            == "see [x](https://a.example) and [pr#1](https://p.example/1) and [pr#1](https://p.example/1)")
        #expect(RustChangelog.resolve("[enable `[OsStr]::join`.][96881]", links: links)
            == "[enable `[OsStr]::join`.](https://r.example/96881)")
        // Inline links, unknown labels and checkbox-like brackets stay.
        #expect(RustChangelog.resolve("[t](https://x) [unknown] `[T; N]`", links: links) == "[t](https://x) [unknown] `[T; N]`")
    }

    @Test func notReleaseNotesIsNil() {
        #expect(RustChangelog.parseRust("404: Not Found") == nil)
        #expect(RustChangelog.parseRustup("<html><body>Not Found</body></html>") == nil)
    }

    /// Beta and nightly toolchains read the same document; it has no section
    /// above the stable release, so the cut is the newest stable sections, all
    /// already in the toolchain — nothing new, and not an error.
    @Test func nightlyReaderGetsStableSectionsAsAlreadyTaken() throws {
        let changelog = try #require(RustChangelog.parseRust(Self.releases))
        let cut = try #require(CLIToolChangelog.relevant(
            changelog, installed: "1.101.0-nightly (21b707e3f 2026-09-30)",
            latest: "1.101.0-nightly (0a1b2c3d4 2026-10-01)"))
        #expect(cut.entries.first?.version == "1.99.0")
    }
}
