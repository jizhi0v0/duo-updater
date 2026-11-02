# OpenCode 1 and OpenCode 2 are two lines

2026-10-31. OpenCode 1.19.5's TUI prints a `/update to upgrade to OpenCode 2.0`
banner, and `duo` said the install was current: this note records what was
measured, and why DuoUpdater reports OpenCode 2 without ever running its upgrade.

Source it explains: `DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/OpencodeCheck.swift`,
with `OpencodeRelease.swift` (the two channels) and `OpencodeInstall.swift` (the
version literal, the `autoupdate` setting).

## What the vendor says (measured 2026-10-31)

- `registry.npmjs.org/opencode-ai/latest` → `1.19.5`. That package carries no 2.x
  version at all — it is OpenCode 1's channel.
- `registry.npmjs.org/@opencode/cli/latest` → `2.2.5`: OpenCode 2's package.
- `opencode.ai/update/api/latest/cli/npm` →
  `{"channel":"latest","name":"cli","distribution":"npm","version":"2.2.5",…}`.
  This is what OpenCode 2's own installer reads, and what `OpencodeRelease`
  reads for the 2.x side.
- `api.github.com/repos/anomalyco/opencode/releases/latest` → `v1.19.5`, while the
  same repository already lists `v2.2.5` and the rest of `v2.2.x` as published,
  non-prerelease releases. The repository's **Latest** flag is still on 1.19.5,
  and the 1.x installer says it must not be relied on: "GitHub's Latest release
  may be OpenCode 2, so it's never used" (its `install` script, read the same
  day). Before this change DuoUpdater read exactly that endpoint, which is why
  the row said "up to date".
- `opencode.ai/install` (the 1.x installer) refuses a 2.x `--version` outright:
  "… is not an OpenCode 1 release, so this installer can't install it", then
  points at `curl -fsSL https://opencode.ai/v2/install | bash` and
  `opencode upgrade --major`. `opencode.ai/v2/install` installs
  `@opencode/cli-<target>@<version>` from npm into the same
  `$HOME/.opencode/bin/opencode`.
- `opencode.ai/v2/docs/migrate-v1/` names the three breaking changes: the plugin
  API, the server API and `tui.json(c)` → `cli.json` (auto-migrated). V1 and V2
  "both use the `opencode` command and are no longer installed side by side by
  default"; `opencode upgrade --major` "upgrade[s] to OpenCode 2 and remove[s]
  OpenCode 1" (its own flag description).
- The 1.19.5 TUI's own rule is an announcement, not a probe: it returns
  `{type:"major"}` whenever the newest **1.x** is not newer than what is
  installed — the 2.x version number never enters the comparison.

## Why the scanner had to change too

The version is compiled in, and the literal changed shape with the line:

| line | literal |
|---|---|
| OpenCode 1.19.5 | `--user-agent=opencode/1.19.5` |
| OpenCode 2.2.5 (`@opencode/cli-darwin-arm64`) | `--user-agent=opencode/latest/2.2.5/cli` |

The old reader took everything after `--user-agent=opencode/` up to the next
space, so a migrated install would have read `latest/2.2.5/cli` — not a version
— and the row would have shown "couldn't read the installed version" instead of
moving to 2.x.

## The decision, and its reasons

- **1.x reads npm.** It is the channel the 1.x installer installs from, and the
  one a one-click can act on.
- **2.x is reported, never clicked** (`CLIToolWithheld.ownUpgrade`): the 1.x
  installer exits 1 on a 2.x version, and the vendor's way across
  (`opencode upgrade --major`) runs the installed binary and removes OpenCode 1.
  DuoUpdater never runs an installed OpenCode — everything before 1.18.34 is ad
  hoc signed — so the row names the version and hands the command over to copy,
  with the migration guide in the note and in the detail pane.
- **A pending 1.x release wins the row.** One row carries one version, and the
  1.x patch is the one DuoUpdater can install itself; the 2.x notice returns on
  the next check.
- **A 2.x install is compared with 2.x's channel.** Otherwise a migrated install
  would be "ahead" of the 1.x line forever.

## How to re-check

```sh
curl -s https://registry.npmjs.org/opencode-ai/latest | grep -o '"version":"[^"]*"'
curl -s https://opencode.ai/update/api/latest/cli/npm
curl -s https://api.github.com/repos/anomalyco/opencode/releases/latest | grep -m1 tag_name
```

and then `duo check`'s OpenCode line: with 1.x current it should read
`1.19.5 → 2.2.5 [latest]`, `held back: OpenCode has its own upgrade command` and
`to update it yourself: opencode upgrade --major`.
