# App onboarding status

Tracks which apps duo-updater has been taught to detect/changelog, and which
were deliberately skipped — so the same ground isn't re-covered. Updated
2026-06-04.

## How an app gets covered (source lever)

Sources are strict first-match-wins: MAS → Sparkle → HomebrewCask → GitHub →
VendorProbe. Pick the lever per app:

- **Sparkle** (`SUFeedURL` in Info.plist) → already detected + notes. Add nothing.
- **HomebrewCask, `auto_updates:false`** → cask wins detection. Add a
  `ChangelogRecipe` only if you want native notes.
- **`auto_updates:true` cask + GitHub releases, no Sparkle** → `GitHubReleaseRule`
  (gives detection **and** structured notes in one entry).
- **`auto_updates:true` + own updater (no Sparkle/GitHub)** → `VendorProbe`
  (detection) + optional `ChangelogRecipe` (notes).

> An `auto_updates` cask returns nil from `HomebrewCaskSource`, so self-updating
> Electron apps fall through to `.unknown` unless a GitHub rule / VendorProbe
> covers them. Being a brew cask is **not** enough for detection.

## ✅ Done (covered)

**ChangelogRecipe** (native release notes) — `ChangelogRecipe.swift`:
Slack, Notion, Obsidian, Figma, 1Password, Sublime Text, Calibre, Audacity,
Blender, OpenCode. (Plus the pre-existing set: VS Code, Zed, Ghostty, VLC,
Postman, RustDesk, Warp, LM Studio, OrbStack, Tailscale, CleanShot, TablePlus,
JetBrains Air, Ollama, AppCleaner, …)

**VendorProbe** (detection-only, self-updaters) — `VendorProbeRecipe.swift`:
Discord, Figma, Obsidian, Notion, Slack, 1Password, Sublime Text, Sublime Merge,
Plex, Alfred, Shottr, The Unarchiver, Orion, Dropbox.

**GitHubReleaseRule** (detection + notes) — `GitHubReleasesSource.swift`:
GitHub Desktop, Stats, DBeaver, Beekeeper Studio, Insomnia, Zen.

**Sparkle-covered, no recipe needed** (have `SUFeedURL`): iTerm2, Arc, Rectangle,
IINA, Proxyman, MonitorControl, Maccy, Vivaldi, HandBrake. Keka and OBS are
expected Sparkle apps from cask metadata, but still need downloaded-bundle
verification in this audit set.

All new recipes are validated against the live endpoint and covered by an offline
fixture test; `DuoUpdaterCore` = 240 tests passing.

## ⛔ Skipped — do NOT re-attempt (with reason)

- **Brave**, **Feishu/Lark** — `CFBundleShortVersionString` is Chromium-major-
  prefixed (Brave `148.1.90.128`, Feishu `131.0.6778.268`) but every vendor feed
  only carries the bare app version (`1.90.128` / `7.69.9`). No order-preserving
  match → any probe phantom-updates or phantom-downgrades. Needs a Chromium-major
  source that doesn't exist publicly.
- **Telegram (macOS)** — ships via Mac App Store (`ru.keepcoder.Telegram`, id
  747648890); MAS source already gives version + "what's new". `overtake/
  TelegramSwift` has no GitHub releases. A recipe would be redundant.
- **Discord changelog**, **WhatsApp**, **Spotify**, **Zoom changelog** — no
  server-rendered, dated, per-version notes page exists (Discord's blog is
  date-only, no version). Spotify's version API is also account-token-gated
  (see VendorProbeRegistry "Known-unfeasible"). Detection for these is via their
  VendorProbe where one exists; notes are not feasible.

(See the `Known-unfeasible` comment atop `VendorProbeRegistry` for the older
list: Spotify, Paste, ToDesk, WeLink, etc.)

## 🔲 TODO / not done

- **zoom** — not installed. Its cask is a **pkg** installer needing `sudo`; can't
  be installed non-interactively. Run `brew install --cask zoom` locally. (It has
  Sparkle/self-update, so detection likely works once installed — verify.)
- **Blender ChangelogRecipe is version-PINNED** to
  `developer.blender.org/docs/release_notes/5.1/`. Bump the URL each Blender minor
  release (Blender exposes no released-only index to auto-follow).
- **Single-channel on-machine verification done (2026-06-04)** — 44 single-channel
  apps verified on real bundles (20 pre-installed + 24 install/verify/uninstall via
  the new `channel-verify --check` full-chain mode); found+fixed a LibreWolf recipe
  bug (wrong bundle id `org.mozilla`→`net.librewolf.librewolf` + stale GitLab endpoint
  → Codeberg). Full suite green: **270 tests in 11 suites**. Evidence:
  `application-test/records/_single-channel-sweep.md`. Skipped: Office pkg apps +
  Docker (need sudo).
- **App/ target not build-verified** — the recipe work is in `DuoUpdaterCore`
  (270 tests green). The bundled `App/Sources/*` UI + `Install/*` WIP committed
  in 599e8dd was not separately built. Run `cd App && xcodegen generate &&
  xcodebuild … build` (or `make install`) to confirm.
- **Long-tail apps not attempted** (no clean source found yet or lower priority):
  Karabiner-Elements / Google Drive / OneDrive / Microsoft Teams (pkg installers,
  need sudo), and Audacity/Blender/Calibre changelog is done but their detection
  rides Homebrew cask (auto_updates:false) — no probe needed.
- **OpenCode detection** — `ChangelogRecipe` exists, but downloaded cask
  verification found no `SUFeedURL`; cask `opencode-desktop` is
  `auto_updates:true`, so Homebrew will not detect it.
