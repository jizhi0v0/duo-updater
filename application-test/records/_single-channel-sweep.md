# Single-channel on-machine verification sweep

Verified **2026-06-04** with `channel-verify` against **real installed bundles**
on this machine. Goal: prove every single-channel (stable-only) app duo-updater
integrates is (a) detected as `stable` and (b) answered by a production source
with a sane, non-phantom verdict — using the shipping `AppScanner.scan()` +
`UpdateChecker` chain, not a re-implementation.

Two harness modes were used:
- `--check <bundleID>` (added this sweep): runs the **full** production source
  chain (`MacAppStore → Sparkle → Homebrew → GitHub → VendorProbe` + Toolbox),
  reporting which source actually *won* — the authoritative answer for apps that
  resolve through MAS/Sparkle/Homebrew/GitHub/Toolbox, not just VendorProbe.
- `<path-to-.app>`: detect() + VendorProbe only (used to prove a specific probe
  recipe fires regardless of which source wins in the chain).

Method for the 24 not-yet-installed app casks: `brew install --cask` →
`--check` → `brew uninstall` (install/verify/clean, per the run request). The 5
`.pkg` Office apps + Docker (now a sudo-gated install) were **skipped** — they
can't be installed non-interactively.

## A. Already installed (20) — all `stable`, all up to date

| App | bundle id | winning source | verdict |
|-----|-----------|----------------|---------|
| VS Code | `com.microsoft.VSCode` | Vendor | up to date |
| IntelliJ IDEA | `com.jetbrains.intellij` | Toolbox (managed) | up to date |
| JetBrains Toolbox | `com.jetbrains.toolbox` | Vendor | up to date |
| Microsoft Word | `com.microsoft.Word` | App Store | up to date |
| Microsoft Excel | `com.microsoft.Excel` | App Store | up to date |
| Claude | `com.anthropic.claudefordesktop` | Vendor | up to date |
| VLC | `org.videolan.vlc` | Vendor | up to date |
| Codex | `com.openai.codex` | Vendor | up to date |
| ChatWise | `app.chatwise` | Vendor | up to date |
| LM Studio | `ai.elementlabs.lmstudio` | Vendor | up to date |
| Conductor | `com.conductor.app` | Vendor | up to date |
| AweSun | `com.oray.sunlogin.macclient` | Vendor | up to date |
| Postman | `com.postmanlabs.mac` | Vendor | up to date |
| Android Studio | `com.google.android.studio` | Toolbox (managed) | up to date |
| MacUpdater | `com.corecode.MacUpdater` | Vendor | up to date (discontinued upstream) |
| Tailscale | `io.tailscale.ipn.macsys` | Vendor | up to date |
| Pearcleaner | `com.alienator88.Pearcleaner` | GitHub | up to date |
| RustDesk | `com.carriez.rustdesk` | GitHub | up to date |
| Alcove | `com.henrikruscon.Alcove` | GitHub | up to date |
| Macs Fan Control | `com.crystalidea.macsfancontrol` | GitHub | up to date |

> Word/Excel resolve via **App Store**, not their VendorProbe recipe — MAS has a
> receipt and wins the priority chain. The Office VendorProbe (`versionIsBuild`)
> recipe is therefore not exercised by a MAS install; it remains **needs-verify**
> for a non-MAS Office (skipped this sweep — pkg/sudo). Android Studio resolves
> via Toolbox (managed), short-circuiting its VendorProbe recipe.

## B. Installed → verified → uninstalled (24 app casks; 23 clean + 1 fixed)

| App | bundle id | winning source | verdict |
|-----|-----------|----------------|---------|
| Bartender | `com.surteesstudios.Bartender` | Sparkle | up to date |
| ImageOptim | `net.pornel.ImageOptim` | Sparkle | up to date |
| Shottr | `cc.ffitch.shottr` | Vendor | up to date |
| The Unarchiver | `com.macpaw.site.theunarchiver` | Vendor | up to date |
| Stats | `eu.exelban.Stats` | GitHub | up to date |
| Alfred | `com.runningwithcrayons.Alfred` | Vendor | up to date |
| Cursor | `com.todesktop.230313mzl4w4u92` | Vendor | up to date |
| Raycast | `com.raycast.macos` | Vendor | up to date |
| Slack | `com.tinyspeck.slackmacgap` | Vendor | up to date |
| Notion | `notion.id` | Vendor | up to date |
| Obsidian | `md.obsidian` | Vendor | up to date |
| Figma | `com.figma.Desktop` | Vendor | up to date |
| Sublime Text | `com.sublimetext.4` | Vendor | up to date |
| Sublime Merge | `com.sublimemerge` | Vendor | up to date |
| DBeaver | `org.jkiss.dbeaver.core.product` | GitHub | up to date |
| Beekeeper Studio | `io.beekeeperstudio.desktop` | GitHub | up to date |
| Insomnia | `com.insomnia.app` | GitHub | up to date |
| GitHub Desktop | `com.github.GitHubClient` | GitHub | up to date |
| Plex | `tv.plex.desktop` | Vendor | up to date |
| Orion | `com.kagi.kagimacOS` | Vendor | up to date |
| Dropbox | `com.getdropbox.dropbox` | Vendor | up to date |
| 1Password | `com.1password.1password` | Vendor | up to date |
| **LibreWolf** | `net.librewolf.librewolf` | Vendor (Codeberg) / Homebrew | **FIXED** — see `net-librewolf-librewolf.md` |

## C. Bug found + fixed: LibreWolf

Two defects in the LibreWolf VendorProbe recipe, both invisible until run on a
real bundle (full detail in `net-librewolf-librewolf.md`):
1. **Wrong bundle id** — recipe keyed `org.mozilla.librewolf`; the installed app
   is `net.librewolf.librewolf`. The recipe never matched → LibreWolf was never
   detected via VendorProbe (a brew install was rescued by Homebrew; a direct
   download would have shown `.unknown`).
2. **Stale version endpoint** — recipe read GitLab project `44042130` (caps at
   `147.0.4`); LibreWolf migrated to **Codeberg**. Now reads
   `codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest` (returns
   `151.0.3-1`, matching the install).

## D. Skipped (cannot install non-interactively — need sudo)

Teams `com.microsoft.teams2`, OneDrive `com.microsoft.OneDrive`, PowerPoint
`com.microsoft.Powerpoint`, OneNote `com.microsoft.onenote.mac`, Outlook
`com.microsoft.Outlook` (all `.pkg` casks), and Docker `com.docker.docker`
(cask `docker-desktop` now requires sudo). Office VendorProbe path stays
needs-verify; Docker's recipe stays needs-verify on a real bundle.

## E. Note on the temporary worktree compile error (resolved)

The sweep was first run from a throwaway git **worktree** cut from committed
`068d823`, where `swift test` would not compile: `ChannelGuardTests.githubSourceMatchesCorrectChannel`
calls `GitHubReleaseRule(channel:)` but that worktree's source had no `channel`
field. This was a **worktree-vintage artifact, not a real gap** — the GitHub
`channel` feature lives in the main working tree (uncommitted at the time). After
the LibreWolf fix was folded into the main tree, the **full suite is green: 270
tests in 11 suites passed**. No outstanding breakage.

## Commands
```
# full production chain (winning source) for an installed app:
swift run --package-path application-test channel-verify --check <bundleID> --expect stable
# VendorProbe-only, against a bundle path:
swift run --package-path application-test channel-verify "/Applications/<App>.app" --expect stable
```
