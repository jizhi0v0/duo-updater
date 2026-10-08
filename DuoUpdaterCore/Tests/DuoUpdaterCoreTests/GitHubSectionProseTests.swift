import Testing
import Foundation
@testable import DuoUpdaterCore

/// Prose that is the only content of a block under a notice heading
/// (Migration, Upgrade notes, Breaking change, …) — the section itself, or a
/// bold-labelled paragraph inside it — survives as items in a body that also
/// has bullets (`GitHubMarkdownParser.sectionProse`).
///
/// Real bodies, fetched 2026-10-08 from the GitHub releases API:
/// - Jan v0.8.5 (`janhq/jan`), verbatim. The API returns it with CRLF line
///   breaks; the literal holds it with LF and `jan085CRLF` puts the CRLFs
///   back, which gives the API's bytes exactly.
/// - Jan v0.6.7, verbatim, as an escaped literal (CRLF breaks).
/// - uv 0.12.23 (`astral-sh/uv`), trimmed: everything from `## Install uv`
///   on is cut.
struct GitHubSectionProseTests {

    private static func entry(_ body: String, _ version: String) throws -> Changelog.Entry {
        try #require(GitHubMarkdownParser.parse(body: body, version: version, date: nil)?.entries.first)
    }

    static var jan085CRLF: String { jan085.replacingOccurrences(of: "\n", with: "\r\n") }

    // MARK: - Jan v0.8.5

    @Test func janMigrationNotesSurvive() throws {
        let entry = try Self.entry(Self.jan085CRLF, "v0.8.5")
        let engine = "Jan no longer downloads a llama.cpp backend for your machine on first run or when one is updated. The engine (llama.cpp 0.5.0, build b11146) is bundled in the installer, runs in its own worker process, and updates together with the app, so the backend version and engine auto-update settings are gone. On Windows and Linux, NVIDIA GPUs use the bundled CUDA 13 build; other GPUs, and NVIDIA GPUs or drivers that cannot run CUDA 13 (Pascal cards such as the GTX 10 series, for example), use Vulkan. (In 0.8.4 such systems could download a CUDA 11 or 12 backend; that option is gone.) macOS uses Metal."
        let intel = "Intel-based Macs have not been supported since v0.8.0, and the bundled engine is built for Apple Silicon only. On an Intel Mac, Jan v0.8.5 still opens and works with remote and custom providers, but llama.cpp models will not load. If you rely on local models on an Intel Mac, stay on v0.8.4."
        #expect(Array(entry.content.prefix(3)) == [
            .heading("Migration"),
            .note("**The llama.cpp engine now ships with the app.**"),
            .note(engine),
        ])
        let label = try #require(entry.items.firstIndex(of: "**Local models no longer run on Intel Macs.**"))
        #expect(entry.items[label + 1] == intel)
        // A labelled block with a list keeps only its list, as before.
        #expect(!entry.items.contains("**The `jan` CLI is no longer part of the desktop app.**"))
        #expect(!entry.items.contains { $0.hasPrefix("The desktop app no longer bundles") })
        #expect(entry.items.contains { $0.hasPrefix("macOS and Linux: a `jan` that v0.8.4 installed") })
        // `## This release is fixes only` is prose under no notice heading.
        #expect(!entry.items.contains { $0.hasPrefix("No new features are announced in v0.8.5.") })
        // The closing lines are not notes.
        #expect(!entry.items.contains { $0.hasPrefix("Update Jan from the app") })
        #expect(!entry.items.contains { $0.contains("Full Changelog") })
        #expect(entry.items.count == 49)
    }

    @Test func crlfAndLfReadTheSame() throws {
        #expect(try Self.entry(Self.jan085CRLF, "v0.8.5") == Self.entry(Self.jan085, "v0.8.5"))
    }

    /// A paragraph hard-wrapped over CRLF lines is one paragraph.
    @Test func crlfWrappedParagraphIsOneItem() throws {
        let body = "## Added\r\n\r\n- Dark mode for the editor.\r\n\r\n## Upgrade notes\r\n\r\nSettings from 1.x are\r\nmigrated on first launch.\r\n"
        let entry = try Self.entry(body, "2.0")
        #expect(entry.items == ["Dark mode for the editor.", "Settings from 1.x are migrated on first launch."])
    }

    // MARK: - What stays out

    @Test func janContributorSectionStaysOut() throws {
        let entry = try Self.entry(Self.jan067, "v0.6.7")
        #expect(entry.items == [
            "fix: should not include reasoning text in the chat completion request @louis-menlo",
            "fix: gpt-oss thinking block @urmamur",
            "fix: react state loop from hooks useMediaQuery @urmamur",
        ])
        #expect(!entry.content.contains(.heading("Contributor")))
    }

    @Test func uvReleaseDateLineStaysOut() throws {
        let entry = try Self.entry(Self.uv0_12_23, "0.12.23")
        #expect(!entry.items.contains("Released on 2026-10-03."))
        #expect(entry.items.first == "Add CPython 3.15.0rc3 ([#22164](https://github.com/astral-sh/uv/pull/22164))")
        #expect(entry.items.count == 7)
    }

    /// Text above the first heading, prose beside a list, prose under a
    /// heading that is no notice, a long run of prose and a row of links are
    /// not kept; a short notice is.
    @Test func onlyShortProseOnlyBlocksUnderANoticeHeadingAreKept() throws {
        let body = """
        Welcome to 2.0! We worked hard on this one.

        ## Added

        This release adds one thing.

        - Dark mode for the editor.

        ## Upgrade notes

        Settings from 1.x are migrated on first launch.

        ## Overview

        A quieter, faster release.

        ## Breaking changes

        The first paragraph of a long story.

        The second paragraph of a long story.

        The third paragraph of a long story.

        ## Known issues

        [Full changelog](https://example.com/compare/v1.9...v2.0) · [Project website](https://example.com)
        """
        let entry = try Self.entry(body, "2.0")
        #expect(entry.items == ["Dark mode for the editor.", "Settings from 1.x are migrated on first launch."])
        #expect(entry.content == [
            .heading("Added"), .note("Dark mode for the editor."),
            .heading("Upgrade notes"), .note("Settings from 1.x are migrated on first launch."),
        ])
    }

    /// Below two category headings nothing is styled, so no prose is kept.
    @Test func proseUnderALoneHeadingStaysOut() throws {
        let body = """
        - Fixed a crash on launch.

        ## Upgrade notes

        Settings are migrated on first launch.
        """
        #expect(try Self.entry(body, "2.0").items == ["Fixed a crash on launch."])
    }

    /// With no bullet in the body, the lenient and prose passes decide, as
    /// they always did: a numbered list wins over the prose next to it.
    @Test func bodyWithoutBulletsIsLeftToTheOtherPasses() throws {
        let body = """
        ## Changes

        1. Fixed a crash on launch.

        ## Upgrade notes

        Settings are migrated on first launch.
        """
        #expect(try Self.entry(body, "2.0").items == ["Fixed a crash on launch."])
    }

    // MARK: - Fixtures

    static let jan085 = #"""
## This release is fixes only

No new features are announced in v0.8.5. Work in progress stays in the nightly channel: [Cowork](https://jan.ai/docs/desktop/cowork) and the current agent work ship there until they are announced, and a stable build does not show them.

One thing a first launch will notice: the first-run setup is now a guided wizard - welcome, engine setup, a first model, and the consent page - instead of opening straight into the chat with no engine or model set up. It is onboarding rather than a new capability, so it is not a headline; it is written down here so a new install is not a surprise.

---

## Migration

**The llama.cpp engine now ships with the app.**

Jan no longer downloads a llama.cpp backend for your machine on first run or when one is updated. The engine (llama.cpp 0.5.0, build b11146) is bundled in the installer, runs in its own worker process, and updates together with the app, so the backend version and engine auto-update settings are gone. On Windows and Linux, NVIDIA GPUs use the bundled CUDA 13 build; other GPUs, and NVIDIA GPUs or drivers that cannot run CUDA 13 (Pascal cards such as the GTX 10 series, for example), use Vulkan. (In 0.8.4 such systems could download a CUDA 11 or 12 backend; that option is gone.) macOS uses Metal.

Backends downloaded by earlier versions, in `llamacpp/backends` (and `llamacpp/lib`, if present) inside your Jan data folder, are no longer used and are safe to delete.

**Local models no longer run on Intel Macs.**

Intel-based Macs have not been supported since v0.8.0, and the bundled engine is built for Apple Silicon only. On an Intel Mac, Jan v0.8.5 still opens and works with remote and custom providers, but llama.cpp models will not load. If you rely on local models on an Intel Mac, stay on v0.8.4.

**The desktop executable is now `Jan-Desktop`.**

The app is still called Jan, and its menu entries, shortcuts and `Jan.app` bundle keep working, but the executable inside was renamed. On Linux the `.deb` installs `/usr/bin/Jan-Desktop` instead of `/usr/bin/Jan`, and on macOS it is `Jan.app/Contents/MacOS/Jan-Desktop`; scripts that launch the old path need updating. On Windows, the in-app update moves the Start-menu and desktop shortcuts to the new executable.

**The `jan` CLI is no longer part of the desktop app.**

The desktop app no longer bundles the `jan` command-line agent, installs it, or adds it to your `PATH`; it is now a separate install (see the [agent quickstart](https://jan.ai/docs/agent/quickstart)).

- macOS and Linux: a `jan` that v0.8.4 installed (in `/usr/local/bin` or `~/.local/bin`) is left in place but stays at v0.8.4. Reinstall it from the quickstart to keep it current.
- Windows: updating from v0.8.4 removes the `jan.exe` it put in the app's `resources\bin` folder, so `jan` stops working until you install the CLI from the quickstart. The Windows installer now puts it in `%USERPROFILE%\.local\bin`, the same place as on macOS and Linux, not in the desktop app's folder, so a later app update cannot remove it. The update leaves that folder's entry in your user `PATH`; you can [delete the entry](https://jan.ai/docs/desktop/troubleshooting#jan-is-not-recognized-after-updating-the-desktop-app).

**The Local API Server checks Trusted Hosts when bound to `0.0.0.0`.**

Previously, binding to `0.0.0.0` accepted any `Host` header. Now a request whose host is not `localhost`, `host.docker.internal`, a loopback or private LAN IP, or an entry in **Trusted Hosts** is rejected with `403`. If clients reach Jan by another name - a machine name such as `my-pc.local`, a domain behind a reverse proxy, or a non-private IP - add it to **Settings > Local API Server > Trusted Hosts** (or `*` to allow any host).

**The agent's `bash` tool is now called `shell`.**

On Windows it runs in PowerShell, so Git Bash is no longer needed; on macOS and Linux it is still bash. Agent definitions and tool allowlists that name `bash` stop matching: Jan reports the old name as an error, and renaming it to `shell` fixes it. Past conversations that used `bash` still display normally.

**Settings that change on update**

- llama.cpp **Parallel Sequences**: a value of `1` (the old default) becomes `0`, which lets llama.cpp pick the slot count.
- A model whose `model.yml` carries the `n_gpu_layers: 100` an earlier version wrote has it removed, so GPU offload is decided automatically again.
- llama.cpp **Remember Conversations Between Sessions** is on by default: each conversation's prompt cache is kept on disk in `llamacpp/thread-cache`, capped by **Conversation Cache Disk Limit** (8192 MiB). Turn it off in **Settings > Model Providers > Llama.cpp**.
- Windows and Linux: **Settings > Local API Server** has a **Run in background** toggle, on by default (the previous behavior). Turn it off to make closing the window quit Jan and stop the server.

---

## Bug Fixes

**llama.cpp & Local Models**

- Setting `parallel` no longer halves the per-slot context window.
- Context-shifted chat history is trimmed instead of being sent back whole.
- llama.cpp runs in a separate worker process, so an engine crash no longer takes the app down with it.
- llama.cpp is upgraded to 0.5.0, and per-model chat-template and grammar files can be given as paths.
- Building Jan from source on Fedora and RHEL finds the llama.cpp libraries.

**Chat, Projects & Providers**

- A new chat inside a project uses that project's assistant.
- The predefined Azure provider has a Base URL field, so it can point at your Azure endpoint.
- A message that failed is no longer sent again inside your next one, and a local server (Jan's own engine, Ollama, LM Studio or anything on `localhost`) is not retried after an error, so a failing prompt runs once instead of three times.

**MCP**

- Tool results are capped before they enter conversation history, so a single large result can no longer blow the context window.
- A failing `shell` tool now reports as an error instead of a successful result.

**Desktop & Platform**

- The sidebar's Jan label no longer overlaps the macOS traffic lights.
- Windows: the maximize button turns into Restore while the window is maximized.
- Zoom shortcuts are scoped to chat message text, so zooming a message no longer rescales the whole app.
- Hub search ranks exact model id matches first.
- Log rotation no longer deletes the llama.cpp and worker logs.
- An in-app update stops the running engine, MCP servers and agent shells before the installer runs. If 0.8.4 left its engine running after an update, Jan stops it at the next start.
- The Linux AppImage shows its icon again.

**Agent & Tooling**

- A session heals from malformed or poisoned tool-call history instead of failing every turn after it.
- Session token spend is counted honestly, including marginal spend.
- A compacted turn resumes from where it stopped, and orphan tool rows are retired.
- Compaction retries on llama-server context-overflow responses, and the compaction prompt is appended rather than rewriting the request prefix.
- The `shell` tool works on Windows (in PowerShell, inside the sandbox), and TUI scrollback follows the terminal's scroll wheel.

**Security**

- Binding the Local API Server to `0.0.0.0` now enforces the Trusted Hosts allowlist (GHSA-x6p8-7cp8-c3p6); see Migration above. Thanks to the reporter.
- An "allow always" grant for a shell command now covers only plain invocations of that command. Commands that redefine aliases or functions, change `PATH` or similar variables, or wrap another command in a way the scanner cannot follow ask again instead of running under the grant.

---

## Known issues

- A failed in-app update closes the update dialog without an error; the reason is only in the log ([#9137](https://github.com/janhq/jan/issues/9137)).
- Windows, inside the sandbox the `shell` tool runs in: `git` cannot read the workspace, and tools whose install folder denies access to app containers (Node.js installed from its MSI, for example) cannot start. PowerShell in Constrained Language Mode, which some managed machines enforce, also stops the `shell` tool.
- Ubuntu 24.04: the default AppArmor policy blocks the sandbox the `shell` tool runs in, so Jan does not offer the tool in chat. Everything else works.

---

## Nightly

Cowork and the in-progress agent work are available in the nightly channel:

- macOS (universal): https://app.jan.ai/download/nightly/mac-universal
- Windows (x64): https://app.jan.ai/download/nightly/win-x64
- Linux (x64): https://app.jan.ai/download/nightly/linux-amd64-deb or https://app.jan.ai/download/nightly/linux-amd64-appimage

---

## Engineering

- The desktop end-to-end suite now runs on all four platforms on a nightly schedule, with a mock provider covering the chat critical path.
- Building the engine on Windows no longer fails on the 260-character `MAX_PATH` limit.

---

Update Jan from the app, or [download the latest](https://jan.ai/).

**Full Changelog**: https://github.com/janhq/jan/compare/v0.8.4...v0.8.5

"""#

    static let jan067 = "## Changes\r\n- fix: should not include reasoning text in the chat completion request @louis-menlo (#6072)\r\n- fix: gpt-oss thinking block @urmamur (#6071)\r\n- fix: react state loop from hooks useMediaQuery @urmamur (#6031)\r\n\r\n## Contributor\r\n\r\n@louis-menlo and @urmauur\r\n"

    static let uv0_12_23 = #"""
## Release Notes

Released on 2026-10-03.

### Python

- Add CPython 3.15.0rc3 ([#22164](https://github.com/astral-sh/uv/pull/22164))

### Preview features

- Sync from `uv.lock` without a workspace manifest using `uv sync --frozen` with `frozen-lockfile` ([#22018](https://github.com/astral-sh/uv/pull/22018))
- Export from `uv.lock` without a workspace manifest using `uv export --frozen` with `frozen-lockfile` ([#22007](https://github.com/astral-sh/uv/pull/22007))
- Inspect dependency trees from `uv.lock` without a workspace manifest using `uv tree --frozen` with `frozen-lockfile` ([#22016](https://github.com/astral-sh/uv/pull/22016))
- Inspect workspace metadata and optionally sync its environment from `uv.lock` without a workspace manifest using `uv workspace metadata --frozen` with `frozen-lockfile` ([#22017](https://github.com/astral-sh/uv/pull/22017), [#22018](https://github.com/astral-sh/uv/pull/22018))

### Bug fixes

- Reject alternate sources for workspace members across conflicting dependency selections, avoiding lockfiles that cannot be installed ([#22153](https://github.com/astral-sh/uv/pull/22153))
- Allow x86-64 Python interpreters running under emulation on Windows ARM64 to install compatible `win_amd64` wheels instead of building from source ([#22099](https://github.com/astral-sh/uv/pull/22099))


"""#
}
