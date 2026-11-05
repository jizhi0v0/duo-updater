# Beta channel verification — 2026-11-05

Production revision: 8e389320d645856cf7440e721687a36b3db7fc6c.
Host macOS 27.3 (26C5035r). Signed Release installed with `make install`.

## Installed UI, Cua Driver 0.38.0

The Codex computer-use service failed repeatedly, including after reset. The
user explicitly requested Cua Driver instead. Its daemon and native AX tools
successfully operated `/Applications/DuoUpdater.app` (pid 46485).

- Settings → Updates initially showed Stable.
- Selected Beta from the real popup. AX readback showed Beta; `defaults read
  com.duoupdater.app DuoUpdaterBetaChannel` returned 1.
- Feedback button opened GitHub's new-issue page. Read the real Markdown field:
  DuoUpdater 0.5.22 (140), Channel Beta, macOS 27.3 (26C5035r), reproduction /
  expected / actual headings, and a Diagnostics attachment reminder. No issue
  was submitted. Closed only the test browser tab and verified the previous tab.
- Restored Stable through the popup. AX readback showed Stable and preference
  readback returned 0. Other update toggles were not changed.
- [Window-only screenshot](settings-beta.png).

The selection is a subscription preference, not the installed build's channel.
Overwriting an installation does not reset it. A fresh preference defaults to
Stable, including when the initial package is a Beta. Restart/overwrite behavior
was inspected in code, not exercised by replacing the user's installed app twice.

## Real Sparkle engine and local HTTP fixture

Compiled the pinned Sparkle checkout's command-line driver against the pinned
binary framework. Build-only SPU_OBJC_DIRECT macros were defined empty. This
uses the real Sparkle updater, not a reimplementation of its version filtering.
The fixture has a separate bundle ID and lives in a unique temporary directory.

Five real network probes passed: Stable excludes Beta; Beta discovers Beta;
leaving Beta does not downgrade; a newer Stable catches up; Beta subscribers also
receive a newer Stable. [Raw output](sparkle-probes.txt).

A separate fixture then installed build 1 → build 2 with `--channels beta`.
Created a temporary Ed25519 key, signed the archive bytes, and ad-hoc signed the
fixture bundle. Sparkle fetched the feed and ZIP, extracted and installed, exited
0, and disk Info.plist read build 2. [Raw output](sparkle-install.txt).
No production keys, production feeds or user app bundles were changed by this
fixture. Servers exited. This validates Sparkle's real install path; it is not
a claim that the installed DuoUpdater GUI was itself upgraded from a local feed.

## Remaining limits

No public GitHub Beta was published. The full production publishing/notarization
pipeline has not been run for a beta. CI Swift failed with insufficient-space
errors on the runner; no disk threshold or test was weakened.
