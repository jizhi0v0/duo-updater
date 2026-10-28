# Managed tools in the CLI tab: a shared model for "manager → many items"

Design for jizhi0v0/duo-updater, branch `runtime-composition-detail`, HEAD `cbc6bcc1`. Repo paths: `C/` = `DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/`. Evidence IDs refer to the twelve research files; review verdicts override reports (corrections are applied inline and marked "corrected"). Anything not in that set is in §12.

**Status (2026-10-27): §0, P0, P1 (mise tools, PR #1613) and P2 (uv tools, pipx, PR #1712, merged 2026-10-26) written and through the Mac acceptance; P2 decisions taken while writing are in the status log for the owner. P3 (uv Python, nvm Node, fnm Node, pyenv, rbenv; PR #1715, merged 2026-10-27) written and through the Mac acceptance (real home, C1/C3–C6; C2 not holdable, as in P2); the P3 decisions taken while writing are in the status log for the owner. Owed: §12 item 16 (scan time after P3, not measured yet); P2's and P3's C2 could not be held on the Mac (status log). P3's fixtures (`~/.pyenv`, `~/.rbenv`, Homebrew pyenv/rbenv/ruby-build) stay on the Mac for long-term verification, by the owner's choice. P4 (cargo install, go install; PR #1717, merged 2026-10-27) written and through the Mac acceptance (real home, C1/C3–C6; C2 not holdable); its decisions are in the status log for the owner, and its fixtures (tokei, hexyl, gofumpt) stay on the Mac too, by the owner's choice. Every phase P0–P4 is written and merged.** The owner took every recommended option (§11), and later revised D12 and the UI (§5). §0's survey is `plans/cli-managers-int-on-main.md` (committed beside this file); the status log at the end of this file says what is in and what is not. Before each phase, read §13 (cancel, which every adapter must measure for real) and §8.1's note on where real-machine runs happen.

The research files (six reports, six reviews) stay on the owner's Mac, because they hold that machine's inventory. Every fact this design relies on is restated in §2 with its claim ID. Treat an ID as a pointer, not as something you can open from a cloud session. When a fact matters for your phase and you doubt it, re-verify it yourself the way §12 does: in an isolated home, with the command and its raw output.

---

## 0. Rebase on main first (the design read a stale branch)

The research and this design read `runtime-composition-detail`. That branch forked from main at `8c2a5933` (2026-10-17) and was **250 commits behind `origin/main`** on 2026-10-23. Over that range main changed the CLI code by +6251/−333 lines. Every `file:line` here, and the internal-code facts (INT-*), describe the old tree. Start from `origin/main`. Before P0, redo the internal survey on main and fix this document where it differs. In particular:

- **Run state moved into a reducer and a queue**: `C/CLIRunReducer.swift`, `C/CLIRunQueue.swift`, `C/CLIRunOffer.swift`, and `CLIToolsModel.send(_:)`. §3.4's "the three lookups by kind" and the `update`/`updateAll` description in §3.1 must be re-mapped onto `CLIRunEvent` and `CLIRunBatch`, not onto the old methods.
- **Cancel exists** for CLI rows and Update All (#1437 and follow-ups): `InstallJobs.run`, `InstallCommit`, `InstallCancelState`, `CLIToolsModel.cancel(_:)` / `cancelUpdateAll()` / `cancelRow()`, and `duo install` counting tools a signal kept from starting as cancelled. §13 builds on it.
- **New files touching CLI tools** since the fork (e.g. `RuntimeSecurityFeeds.swift`): list them with `git diff --stat 8c2a5933 origin/main -- DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools App/Sources/CLIToolsModel.swift CLI/Sources/DuoKit`, and say for each whether the managed model touches it.
- `lane(of:)` is now `nonisolated static` (`CLIToolsModel.swift:1633` on main). Re-check §3.4's lane plan against it.
- The breaking-hint pass (`loadBreaking`/`readBreaking`) is unchanged on main; D10's cap goes there.

Acceptance for this step: a short "INT on main" note committed beside this file, listing each §3 claim that still holds, moved (new location), or no longer holds (what replaced it).

**Done 2026-10-23: `plans/cli-managers-int-on-main.md`.** The branch is based on `origin/main` (`cbbe8a1`), so there was nothing to rebase; the note lists each §3 claim's state. Two kind-keyed places the design had missed are recorded there (`apply`'s `contexts`/`answered` and `runLane`'s per-tool filter) and handled in P0.

---

## 1. Summary

**The model.** One new `CLIToolKind` case, `.managed`, carries every item any manager keeps; which manager is a value (`ManagerID`), not a type. A `ManagerAdapter` (one per manager, registered in a list) answers four questions only — *where are the roots and items on disk* (no spawn), *what is the newest for each item within and beyond the user's request*, *which vendor command moves it*, *where are its notes* — and one shared `ManagedCheck` turns those answers into `CLIToolStatus` with the same state rules for every manager. Each adapter is wrapped in a `ManagedProvider: CLIToolProvider`, so the app's scheduling, lanes, Update All, announcements, rate-limit pause, duo's `list/check/install` and the UI see nothing new (INT-08/10/13/19/28 OK). Rows are identified by a stable `identity` string (manager | root | item key) instead of a directory that moves when a new version lands beside the old one. Adding a manager = one adapter folder + one line in the registry; no switch anywhere else changes.

**Phase plan.** P0 plumbing → P1 mise tools (#1605) → P2 uv tool + pipx → P3 version lines (uv python, nvm Node, fnm Node, pyenv, rbenv) → P4 cargo install, go install. asdf is not onboarded (§4.10). Existing integrations: rustup toolchains and npm/bun/pnpm/yarn stay as they are now; migration is reconsidered after P3 (§8.2); Homebrew formulae never migrate.

**Manager × onboarding** (✓ full, ◐ partial, ✗ not achievable now; "detection" = update detection in the app and duo):

| Manager | Detection | One-click | Changelog | Why / IDs |
|---|---|---|---|---|
| mise tools | ✓ `mise outdated --json` (+`--bump`) | ✓ `mise upgrade <tool>`; exact pins reported with `--bump` to copy | ◐ only items with `release_url`/GitHub-shaped backend ids, `core:node`, `npm:`, `pipx:` | MISE-20/21/39 OK, MISE-23 (collapses by name), MISE-46 corrected, MISE-49 |
| uv tool | ◐ ✓ on uv ≥0.10.10 (`--outdated`); PyPI JSON fallback below; ranged specifiers reported only until a PEP 440 matcher exists | ✓ `uv tool upgrade <name>`; `==` pins reported with `uv tool install <name>@latest` to copy | ◐ repo from dist-info `Project-URL` (24/25 sample) | UV-10/13/14c corrected/16/18/26/27 |
| uv python | ✓ offline, from uv's frozen list | ✓ `uv python upgrade <minor>` (≥0.10.0 stable; 0.7.14–0.9.x prints a warning) | ✗ no structured source verified | PY-01/04/06/07, PY-08 corrected |
| pipx | ✓ PyPI JSON per venv (no spawn) | ◐ `pipx upgrade <name>` runs an unsigned Python script → copy-command until the owner rules on trust (D5) | ◐ as uv tool | PX-07/08/13/14/15, PX-09 corrected (≥1.15.1) |
| nvm Node | ✓ `nodejs.org/dist/index.json`, no spawn | ✓ `nvm install <major> …` via `bash -c '. nvm.sh --no-use; …'` (nvm already exempt from the trust rule) | ✓ `CHANGELOG_V<major>.md` (raw, no API) — parser is new work | NVM-05/10/22/30/31/32, NODE-01/05, NVM-01 corrected |
| fnm Node | ✓ same index | ◐ `fnm install <major>`: fnm is a Homebrew keg → needs the keg trust rule extended (D5) | ✓ as nvm | FNM-02/03/10/30/31/32, FNM-04 corrected |
| pyenv | ✓ from local definitions, no network | ◐ `pyenv install <X.Y.Z>` compiles 2–3 min; pyenv is bash (trust D5) | ✗ python.org is HTML only | PY-08/13/14/15/19, PY-28 corrected |
| rbenv | ✓ from ruby-build definitions | ◐ `rbenv install <X.Y.Z>`; Homebrew layout needs `/opt/homebrew/bin` on PATH; trust D5 | ✓ GitHub releases `ruby/ruby` tag `v3_3_13` | RB-06/10/11/14/20, review missed fact 1 |
| cargo install | ✓ sparse index, ETag, no rate limit; git/path installs reported only | ◐ `cargo install <name> [--features …]` rebuilds from source (minutes); binstall never run | ✓ `repository` via crates.io API or `cargo info` | CARGO-05/07/12/13/14 narrow/16/17/22/23, BS-03/06/07, CUPD-04 corrected |
| go install | ✓ `go list -m -json <mod>@latest` (retraction-aware); `(devel)`/pseudo rows reported only | ✓ `go install <pkgpath>@latest` with `GOTOOLCHAIN=local` | ◐ GitHub module paths; vanity paths only via proxy.golang.org `Origin` | GO-03/04/05/07/09/10/12/14/16, GO-12 corrected |
| asdf | ✗ no outdated; latest needs plugin scripts that git-update and spend anonymous GitHub budget | ✗ no upgrade; `install`+`set`+`uninstall` | ✗ | ASDF-12/15/16/20/41, review missed fact 6 |

---

## 2. Verified-facts digest per manager

Only facts the design uses. "Scan" = what a GUI finds on disk with no shell env; "check" = what needs the network or a spawn.

### 2.1 mise
| | Fact | IDs |
|---|---|---|
| Roots | data `~/.local/share/mise` (installs, shims), config `~/.config/mise/config.toml`, state `~/.local/state/mise` (`tool-purgatory.json`); env overrides invisible to a GUI | MISE-02/04/07 |
| Items on disk | `installs/<slug>/<version>` real dirs beside alias symlinks (`20 -> 20.20.2`, `latest`); `.mise.backend.toml` in each tool dir (`short`, `full`) | MISE-04/05 |
| List | `mise ls --json`: map name → [{version, requested_version?, install_path, source?, installed, active, scheduled_for_pruning?, prune_after?, symlinked_to?, broken?}]; requested-but-missing rows appear with `installed:false` on all versions | MISE-10/11, MISE-12 narrow, MISE-14 corrected |
| Backend | not in `ls`; from `.mise.backend.toml` or `mise tool <n> --json` | MISE-13 |
| Outdated | `mise outdated --json`: newest *within the request* (what `mise upgrade` does); exact pins → `{}`; `--bump` compares to newest overall and gives `bump`; requested-not-installed rows have `current:null`; **keyed by name, so two requests of one tool collapse** (also with `--inactive`); `--inactive` lists unrequested installs; `--global` (≥2026.10.7) drops project config and `~/.tool-versions` | MISE-20/21/23/24/26/27, review missed fact 4 |
| Config read from a GUI cwd | from `/`: global config only; from `$HOME`: also `~/.tool-versions` and any `mise.toml` there | MISE-25/53 |
| Network | mise-versions.jdx.dev; api.github.com only as fallback, with `MISE_GITHUB_TOKEN` > `GITHUB_API_TOKEN` > `GITHUB_TOKEN` > gh hosts.yml…; `minimum_release_age` (default 24h since 2026.10.15) filters `latest` | MISE-28/29/29b, MISE-30 narrow |
| Upgrade | `mise upgrade <tool>`: config byte-identical; old version kept 24h in purgatory (≥2026.8.15) else removed at once; exit 0 for no-op, unknown tool and success; `--bump` rewrites config (and `mise.lock` if present); exact pin → message, nothing done; `mise upgrade tool@ver` installs unrequested things | MISE-31/32/33/34/35/36/39, review missed fact 2 |
| Locks | only `upgrade --global` takes an update lock; per-install lock otherwise | MISE-38 |
| Needs PATH | pipx backend → `uv`, asdf → bash/git, npm → node | MISE-76 |
| Versions | `outdated --json` prints nothing on stdout when nothing is outdated before 2025.2.8; `--bump` long form only (`-b` since 2026.8.x, `-l` deprecated); `release_url` ≥2026.8.15; `--local` 2026.3.2; `--inactive` 2026.5.5 | MISE-55/56/57 table |
| Notes | `release_url` present for aqua/github/gitlab/ubi/`core:rust`/packslip/versions-host data; absent for core:node, npm, pipx, vfox, cargo, go; `github:`/`ubi:`/`asdf:` ids are owner/repo | MISE-46 corrected, MISE-49 |
| Today | DuoUpdater runs mise only for `--version`, scans `~/.local/bin/mise` only, lists mise's node installs as npm prefixes; mise-installed copies of tools are dropped as "owned elsewhere" | INT-77/78/82, review missed fact 6 |

### 2.2 uv tool / uv python
| | Fact | IDs |
|---|---|---|
| Roots | tools `~/.local/share/uv/tools/<name>` (receipt `uv-receipt.toml`, venv), bins `~/.local/bin`; pythons `~/.local/share/uv/python/cpython-<X.Y.Z>-…` + minor symlink `cpython-<X.Y>-…` | UV-01/02/03/08, PY-03 |
| List | `uv tool list` text only; receipt (`requirements[].specifier`, `entrypoints`, `[tool.options] exclude-newer`) + dist-info version is the structured source; 0.5.0 receipts read fine by 0.13.4 | UV-06/07/08/28 |
| Outdated | `uv tool list --outdated` ≥0.10.10; output `name vX [latest: Y]` **plus `- exe` lines**; latest = newest on index for the env's Python, **ignores `==`/ranges**, honours receipt `exclude-newer` ≥0.11.0, ignores `UV_DEFAULT_INDEX`; one failing fetch aborts the run; `--offline` on an empty cache prints nothing, rc 0 | UV-10 narrow, UV-11 narrow, UV-12/13, UV-14c corrected, review missed facts 2/3/6 |
| Upgrade | `uv tool upgrade <name>`: in-place sync, old gone, entrypoints and receipt rewritten; `==` pin → "Nothing to upgrade" + hint, rc 0; range → newest in range; **any CLI flag persists into the receipt**; text on stderr, rc 1 on any failure; `.lock` serialises list/upgrade/install; running processes not checked | UV-14/15 narrow/16/17/18/19/20 |
| uv python | `uv python list --only-installed --output-format json` (≥0.5.19) lists *all* interpreters; managed = under `uv python dir`; `path` is cwd-relative → run from `/`; newest patch = `uv python list cpython-3.12 --only-downloads` **offline, frozen per uv release**; `uv python upgrade 3.12` since 0.7.14 (preview, warning only), stable 0.10.0; old patch dir kept, minor link repointed; tool venvs follow; `upgrade <minor>` installs a missing minor | PY-01/02/04/06/07/09, PY-08 corrected, review missed facts 1/4 |
| Network | PyPI simple only; python builds from releases.astral.sh; no GitHub API, no token | UV-14b, PY-10 |
| Notes | dist-info `Project-URL`; PyPI `project_urls` has a github repo for 24/25 sampled, key names vary, ansible's is wrong | UV-26/27 |

### 2.3 pipx
| | Fact | IDs |
|---|---|---|
| Roots | ≥1.15.1 `~/Library/Application Support/pipx`; ≤1.15.0 `~/.local/pipx`; an existing `~/.local/pipx` wins; bins `~/.local/bin`; binary at `~/.local/bin/pipx` (uv tool/pip) or `/opt/homebrew/bin/pipx` | PX-02/04/06, PX-03 corrected |
| List | `venvs/<name>/pipx_metadata.json` (= `pipx list --json` entry): `main_package.{package, package_or_url, package_version, pinned}`, `python_version`, `backend` (≥1.12); metadata version 0.2…0.12 | PX-07/08 |
| Outdated | `pipx list --outdated [--output json]` ≥1.15.1: `pip list --outdated` inside each venv, ignores the install specifier; skips editable/non-index; below 1.15.1 none → PyPI JSON `info.version` + `requires_python` | PX-10/12/13, PX-09/11 corrected |
| Upgrade | `pipx upgrade <name>` **strips `==`/ranges and rewrites `package_or_url`**; `pipx pin` is the only honoured pin ("Not upgrading pinned package"); injected packages untouched without `--include-injected`; stored `pip_args` reused only ≥1.10.1; backend from metadata, else uv if on PATH else pip; human text wraps at 80 cols → parse `--output json` | PX-14/15/16/20, PX-17 corrected, review missed fact 5 |
| Network | PyPI only | PX-12 |

### 2.4 nvm / fnm (Node lines)
| | Fact | IDs |
|---|---|---|
| Roots | nvm: `$NVM_DIR` = `~/.nvm` or `~/.config/nvm` (installer's XDG choice; nvm itself has no fallback order), versions `versions/node/vX.Y.Z`, `alias/<name>` text files; fnm: `~/.local/share/fnm` / `~/.fnm` / `~/Library/Application Support/fnm`, `node-versions/vX/installation`, `aliases/<n>` absolute symlinks | NVM-01 corrected, NVM-02/03, FNM-02/03/06 |
| List | directories; no JSON in either; `fnm list`/`default`/`alias` **create** the root dirs; `list-remote` writes nothing | NVM-10/12, FNM-10/11, FNM-04 corrected |
| Latest | neither has outdated; `index.json` (875 entries, 335 KB, ETag → 304, `lts` codename/false, `security` flag) is fnm's source and carries nvm's `index.tab` data; `nvm version-remote` **rewrites `alias/lts/*`** and returns `N/A` rc 3 for both "none" and "network down" | NVM-20/21/22/23/24, FNM-21/22, NODE-01/02/03 |
| Upgrade | `nvm install <major>` / `fnm install <major>`: new dir beside the old, nothing removed; `default` unchanged when literal (nvm) or always (fnm); nvm `--reinstall-packages-from=<old>` copies globals (not npm/corepack); fnm has no equivalent (#481 open); nvm `--save` writes `.nvmrc` (don't pass); nvm install lock since 0.40.7; fnm no lock; uninstall leaves a dangling nvm default / deletes fnm aliases | NVM-30/31/32/33/34/36/37, FNM-30/31/32/33/34/36, NVM-38 narrow |
| Invocation | nvm: `env -i HOME=… NVM_DIR=… PATH=/usr/bin:/bin /bin/bash -c '. "$NVM_DIR/nvm.sh" --no-use; nvm …'` works, 0.8–1.5 s; fnm binary `--fnm-dir <root>`; fnm's arch follows its binary | NVM-05, FNM-02/37 |
| Versions | nvm `version-remote`/`reinstall-packages-from` since 0.31, `--lts` 0.33; fnm `--filter/--lts/--sort/--latest` 1.36.0, `--latest` correct from 1.37.0, `default` no-arg 1.39.0 | NVM-50, FNM-50/51 |
| Notes | `raw.githubusercontent.com/nodejs/node/main/doc/changelogs/CHANGELOG_V<major>.md` (200, no API); GitHub releases per `vX.Y.Z` | NODE-05 |
| Today | `NodePrefixes` lists `~/.nvm/versions/node` (not `~/.config/nvm`) and the three fnm roots as npm prefixes; nvm itself is a kind exempt from the trust rule | NVM-60, FNM-60, NvmCheck.swift:13-16 |

### 2.5 pyenv / rbenv (Python/Ruby lines)
| | Fact | IDs |
|---|---|---|
| Roots | `~/.pyenv` (`PYENV_ROOT`), `~/.rbenv`; binaries `~/.pyenv/bin/pyenv`, `/opt/homebrew/bin/pyenv` (whole repo in Cellar), `/opt/homebrew/bin/{rbenv,ruby-build}` (ruby-build a separate keg) | PY-02/03/06, RB-02/03/04 |
| List | `versions/<name>` dirs; pyenv `--bare` includes `envs/`, alias links, hidden dirs unless filtered; rbenv `--bare` unsorted; a dir appears before its `bin/python3` exists during a build | PY-08 narrow/09, PY-10 narrow, RB-06 |
| Latest | **local definition files only, no network**: pyenv `plugins/python-build/share/python-build/` **plus `$PYENV_ROOT/plugins/*/share/python-build`** (raw python-build misses plugin defs); `pyenv latest -k <X.Y>` (≥2.3.6; pass the `X.Y` prefix, an exact name is returned as-is; `t` builds broken before 2.4.15); rbenv has no `latest`; `ruby-build --definitions`, `--resolve` only ≥v20260501; CRuby = bare numbers; staleness = age of the checkout | PY-13/14/15 narrow/16, PY-28 corrected, RB-08/09/10/11/13/16 |
| Upgrade | `pyenv install <X.Y>` / `rbenv install <X.Y.Z>`: new dir beside old, no file rewritten; pyenv prefix pins silently move, exact pins don't; rbenv pins are exact names; exists → rc 1 (prompt), `-s` → 0, unknown → 2; builds 1:55–2:19 using Homebrew libs; no locks | PY-17/19/20/21/23, RB-12/14/15/17 |
| Invocation | both work under `env -i` with HOME, `*_ROOT`, system PATH; **Homebrew rbenv cannot find `install` without `/opt/homebrew/bin` on PATH** | PY-07, RB-05, review missed fact 1 |
| Notes | pyenv: python.org HTML only; rbenv: GitHub releases `ruby/ruby` tag `v3_3_13` (1 KB body) | PY-26, RB-20 |
| Today | 0 hits in the repo | PY-30 |

### 2.6 cargo install (+binstall, cargo-update) / go install
| | Fact | IDs |
|---|---|---|
| cargo roots | `~/.cargo` (`CARGO_HOME`, `CARGO_INSTALL_ROOT`, `install.root` config — the latter two unseen by a GUI); `bin/` mixes rustup proxies (symlinks to rustup) with crate binaries | CARGO-01/02/03 |
| cargo list | `.crates.toml` is the authority: `"name ver (registry+…|sparse+…|git+…#rev|path+file://…)" = [bins]`; `.crates2.json` adds `version_req` (unused by cargo), `features`, `profile`, `target`, `rustc`, synced from v1 on every load; binstall writes `.crates.toml` + `binstall/crates-v1.json` and not v2 until a later sync backfills defaults; `cargo install --list` creates both files on a fresh root | CARGO-05/06/07/08, CARGO-25 narrow, BS-03 narrow |
| cargo latest | no stable outdated; sparse index `index.crates.io/<ab>/<cd>/<name>` one JSON per line **in publish order → sort by semver, skip yanked/pre-release**; ETag → 304, `max-age=600`, no rate limit; crates.io API needs a User-Agent and ≤1 req/s and gives `repository` | CARGO-09/12/13, CARGO-14 narrow |
| cargo upgrade | `cargo install <name>` rebuilds (20–30 s per small crate, more for big ones), replaces the binary, **drops features and `=ver` pin**; same-version-different-features is a rebuild; rc 0 for no-op ("Ignored") and success ("Replaced"), 101 on failure; tracker lock only around load/save; MSRV abort possible; `cargo-update` re-applies features but **calls `cargo-binstall` first whenever it is on PATH and trusts its exit**; binstall reads `GITHUB_TOKEN`/`GH_TOKEN`/`~/.config/gh/hosts.yml`, silently compiles from source on an exhausted anonymous budget (150 s, rc 0) | CARGO-10/11/15/16/17/18/19/20, CUPD-03, CUPD-04 corrected, BS-06 narrow, BS-07, review missed fact 8 |
| cargo notes | `repository` from crates.io API or `cargo info` (≥1.82) | CARGO-23 |
| go roots | `$GOBIN` else `$GOPATH/bin` else `~/go/bin`; `go env -w` values persist in `~/Library/Application Support/go/env` (the user's has `GOPROXY=https://goproxy.cn,direct`); shell exports unseen; `go env GOBIN` prints the effective dir only ≥1.27 | GO-01 corrected |
| go list | no registry file; `go version -m <dir>` → per binary `path` (package), `mod` (module, version, sum); `-json` (≥1.25) emits objects without file names → run per file; versions: tags, pseudo-versions, `(devel)`, `+dirty`, `command-line-arguments` | GO-02/03/04/05/06, review missed fact 4 |
| go latest | `go list -m -json <mod>@latest` (honours GOPROXY/GOPRIVATE, excludes retracted); direct proxy `@latest` ignores retractions and goproxy.cn omits `Origin`; each major suffix is a separate path | GO-07/08/09/10/11 |
| go upgrade | `go install <pkgpath>@latest`: new inode on change, only mtime touched when unchanged; rc 0/1; `GOTOOLCHAIN=auto` (default, also Homebrew's go.env) may download a toolchain; `local` fails with "requires go >= X" | GO-12 corrected, GO-13/14 |
| Today | `GoBuildInfo` reads build info from Mach-O but skips the `path` line; nothing reads crate trackers | CARGO-27, GO-17 |

### 2.7 asdf
Go rewrite since 0.16.0 (2025-01-30); data dir `~/.asdf` (`installs/<plugin>/<version>`, `plugins/`); no JSON, no outdated, no upgrade, no self-upgrade; `asdf latest` runs plugin scripts that may git-update and call api.github.com anonymously; `latest --all` reports only whether the latest is installed; plugin scripts need `asdf` on PATH; `install`/`set`/`uninstall` are three separate commands (ASDF-01/02/04/10/12/13/15/16/20/22, ASDF-14 corrected, review missed fact 6). mise's asdf backend keeps its own tree (ASDF-31).

---

## 3. The shared model in Core

### 3.1 Types (sketch)

```swift
// C/Managed/ManagerID.swift
public struct ManagerID: RawRepresentable, Hashable, Codable, Sendable { public let rawValue: String }
// "mise", "uv-tool", "uv-python", "pipx", "nvm-node", "fnm-node", "pyenv", "rbenv", "cargo", "go"

/// What the app needs to draw and schedule a manager, data not code.
public struct ManagerDescriptor: Sendable {
    public let id: ManagerID
    public let displayName: String          // group title: "mise tools", "uv tools", "uv Python", "pipx", "nvm Node", …
    public let signer: String?              // CLIToolWording.vendor equivalent; nil = nothing to sign
    public let logo: String?                // asset name the app already has or adds ("cli-mise", "cli-uv", "cli-nvm", …)
    public let tint: Tint                   // .label | .rgb(r,g,b)
    public let lane: String                 // CLIToolsModel.lane(of:) key: "mise", "uv", "pipx", "nvm", "fnm", "pyenv", "rbenv", "cargo", "go"
    public let updaterSpendsGitHubAPI: CLIToolKind.UpdaterGitHubAPI?   // mise → .ourTokenIfAny, others nil
    public let deadline: ChildProcess.Deadline                          // cargo/pyenv/rbenv minutes, others as MiseUpdater's
}

/// One manager install the adapter found: its data root and the binary that runs the commands.
public struct ManagedRoot: Sendable, Equatable, Codable {
    public let manager: ManagerID
    public let path: String                 // "~/.local/share/mise", "~/.nvm", "~/.cargo", "~/go/bin"
    public let binary: Binary?              // nil for pyenv/rbenv/nvm when the manager is not there, fnm/go/pipx when not found
    public struct Binary: Sendable, Equatable, Codable {
        public let path: String; public let version: String?
        public let trust: Trust             // .vendorSigned(team) | .homebrewKeg | .verifiedHash | .exempt(reason) | .untrusted(CLIToolTrust.Signature?) | .quarantined
    }
}

/// One row's payload: everything the pane shows and the check decided on.
public struct ManagedItem: Sendable, Equatable, Codable {
    public let manager: ManagerID
    public let root: String
    public let key: String                  // stable inside the root: "node@20", "npm:prettier@2.0.0", "ruff", "3.12", "v22", "tokei", "mvdan.cc/gofumpt"
    public let name: String                 // row title: "node", "ruff", "Python 3.12", "Node 22", "tokei", "gofumpt"
    public let installPath: String          // the directory/file on disk now (moves for lines)
    public let shape: Shape                 // .package (one version at a time) | .line (patches side by side) | .request (mise: one row per request)
    public let request: Request?            // .exact("1.6") | .range("20") | .alias("lts/*") | nil; where it came from (config path)
    public let installed: String?
    public let latestWithinRequest: String?
    public let latestOverall: String?       // beyond the request, when known (mise --bump, uv --outdated, pipx outdated)
    public let alsoInstalled: [String]      // older patches of a line; mise purgatory versions
    public let backend: String?             // "aqua:jqlang/jq", "pip", "registry+crates.io", "git+…"
    public let notes: NotesSource?          // .gitHubReleases(owner,repo) | .rawMarkdown(URL, parser) | .pypiProject(name) | .crate(name) | nil
    public let effects: [Effect]            // .oldKept(for: "24h") | .oldRemoved | .dropsSpecifier("==0.6.0") | .defaultStays("22.21.1") | .packagesNotCarried | .compilesFromSource | .configRewritten
    public let facts: [Fact]                // enumerated, localized by the app: .source(path), .backend, .request, .alsoInstalled, .default, .python("3.12.15"), .target, .asKnownBy("uv 0.13.4"), …
}

/// What an adapter's check decided for one item, before the shared rules.
public struct ManagedVerdict: Sendable, Equatable {
    public let item: ManagedItem
    public let vendorWouldUpgrade: Bool?    // nil = could not tell
    public let blocker: Blocker?            // .notRequested | .notIndexed(String) | .unknownVersionForm(String) | .channelUnreadable(String) | .rateLimited | .versionUnreadable | .runtimeTooOld(String)
    public let busy: String?                // the manager's own running install/upgrade, by argv
}

public protocol ManagerAdapter: Sendable {
    var descriptor: ManagerDescriptor { get }
    /// Disk only. Never spawns. Roots, items with installed versions and requests, the binary's trust.
    func scan() async -> ManagedScan                       // roots + items + sightings state strings
    /// Network and/or spawn, bounded like today's providers (≤15 s per request).
    func check(_ scan: ManagedScan) async -> [ManagedVerdict]
    /// The vendor's documented command that moves this item, spelled in full; nil when there is none.
    func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])?
    /// The command a user runs to lift a pin / move a request; copy only.
    func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand?
    /// Re-read what the item is after the command, by its key (a line's newest patch, a package's venv).
    func reread(_ item: ManagedItem) async -> String?
    func releaseNotes(for item: ManagedItem, force: Bool) async throws -> Changelog
}

public enum ManagerRegistry {
    /// The one list a new manager is added to. Order = order of the groups in the CLI tab.
    public static let adapters: [any ManagerAdapter] = [MiseToolsAdapter(), UvToolAdapter(), UvPythonAdapter(), PipxAdapter(), NvmNodeAdapter(), FnmNodeAdapter(), PyenvAdapter(), RbenvAdapter(), CargoAdapter(), GoAdapter()]
    public static func providers(home: URL = …) -> [any CLIToolProvider] { adapters.map { ManagedProvider($0, home: home) } }
}
```

`ManagedProvider: CLIToolProvider` (one per adapter) does what every provider does today, once: `scan()` → `CLIToolSighting(kind: .managed, path: identity, version: installed, state: "<installPath>|<request>|<trust>")`; `check()` → `adapter.check(scan)` → `ManagedCheck.status(verdict, root:)` → `CLIToolReport(kind: .managed, context: .managed(ManagerContext(root, binaryVersion)))`; `update()` → re-scan, re-run the busy gate, `CLIToolCommandRunner.run` with the adapter's environment (`HOME` = injected home, `PATH` = `CLIToolCommandRunner.path(prefix:)`, manager root variables, `NO_COLOR`), then `.updated(version: adapter.reread(item))`, failure message = vendor stderr lines + exit as `MiseUpdater.failureMessage` does (C/MiseUpdater.swift:189-204); `releaseNotes` → adapter, through the existing `DenoChangelog.gitHubReleases`/`NpmChangelog` fetchers. mise's token handoff (second run with `MISE_GITHUB_TOKEN` only after "No GitHub token was found", C/MiseUpdater.swift:122-141) moves into a shared `ManagedTokenRetry` the mise adapter opts into.

### 3.2 The shared state rules (`ManagedCheck`) — the one place a verdict becomes a row

| Situation (from the verdict) | `state` | `oneClick` | `latestVersion` | `withheld`/`manualCommand` | IDs motivating it |
|---|---|---|---|---|---|
| binary untrusted / quarantined / missing | `.unknown` (if `installed` known: still `.unknown`) | – | – | `.wrongSigner`/`.unverified`/`.updaterMissing` + note | INT-35/70, constraint 2 |
| `vendorWouldUpgrade == true` | `.updateAvailable` | adapter.upgrade | `latestWithinRequest` | – (or `.busy`) | MISE-21, UV-16, PX-14, NVM-30 |
| request is `.exact` and `latestOverall > installed` | `.pinned` | – | `latestOverall` | `manualCommand` = adapter.unpin | INT-03 (agreed 2026-10-13), MISE-39, UV-16, PX-15 |
| request is `.range`/`.alias`, installed == top of range, `latestOverall` newer | `.upToDate` | – | `latestWithinRequest` | fact `.beyondRequest(latestOverall, unpinCommand)` | UV-24, MISE-21 (D2) |
| installed == latest | `.upToDate` | – | installed | – | |
| installed > latest (uv python after a uv downgrade; cargo `(Homebrew)` builds) | `.ahead` | – | latest | – | PY-04 |
| blocker `.notIndexed` (git/path crate, editable/non-index pipx, `(devel)`/pseudo go) | `.unknown` | – | – | `.unsupportedInstaller` + note; row stays visible | CARGO-22, PX-10, GO-04 |
| blocker `.channelUnreadable`/`.rateLimited`/`.versionUnreadable` | `.unknown` | – | – | same cases as today | INT-69 |
| busy | `.updateAvailable` | – | latest | `.busy` | constraint 1 |

Every adapter must set `vendorWouldUpgrade` from the vendor's own notion (mise plain `outdated`; uv: `==` → false, no spec → outdated's answer, range → nil until D9; pipx: not pinned → outdated's answer; lines: newer patch in index/definitions; cargo/go: newer in index/proxy). The pane shows both numbers whenever they differ, as `NpmPackage.gap` does today (C/NpmPackage.swift:6-13).

### 3.3 Identity and persisted keys

- `CLIToolStatus` gains `public let identity: String` (init default = `path`). Managed rows set `identity = "<manager>|<root>|<key>"`; `path` stays the current `installPath`.
- App: `CLIToolStatus.toolID` becomes `CLIToolID(kind: kind, path: identity)` (App/Sources/CLIToolsModel.swift:16-18); `CLIToolSighting` gets the same `identity` and `name` fields (default path / nil) so `duo list` and the scan/check comparison (`Set(found) != Set(checkedSightings)`, :382) work on stable keys. `CLIToolID.tag` keeps its "no colon in the kind" rule; the tag of a managed row is `managed:mise|/Users/x/.local/share/mise|node@20`.
- Persisted `NotifiedCLIToolVersions` (App/Sources/Preferences.swift:103, key built at AppListModel.swift:9431 from `toolID.tag`): **no migration** — existing kinds keep `kind:path` because their identity defaults to path. Managed keys are new entries; the ledger prunes keys not in `liveKeys` and the baseline is already seeded, so a newly installed manager's current updates are announced once, as a newly installed tool's are today (UpdateAnnouncements.swift:44-58). Decision D-A below if the owner prefers a silent first pass per manager.
- Where the current `kind.rawValue + ":" + path` is spelled by hand it switches to `identity`: CLI/Sources/DuoKit/CLIToolRows.swift:189,214.
- Process watch: `CLIToolProcesses.target(of:)` uses `status.path` (a directory for most items → nil, as for toolchains and npm packages, INT-71); for cargo/go rows `path` is the binary, so the running dot and the stale-process line work unchanged.

### 3.4 Provider identity, lanes, pauses

- `CLIToolProvider` gains `var id: String { kind.rawValue }` (default). `ManagedProvider.id = "managed:<manager>"`. The three lookups by kind switch to `id`: `CLIToolsModel.provider(of:)` (:839-841) and `releaseNotes` (:1058), `CLIToolRows.breakingVersions/apply/after` (:204, :418, :431). A `CLIToolStatus.providerID` computed property (`kind == .managed ? "managed:\(item.manager)" : kind.rawValue`) feeds them.
- `CLITools.providers()` = today's 28 + `ManagerRegistry.providers()`; `inKindOrder` already keeps same-kind providers in given order (C/CLITools.swift:26-32), so `.managed` goes last in `CLIToolKind.allCases` and registry order decides the groups' order.
- `CLIToolsModel.lane(of:)` (:1030-1040) adds `case .managed(let item): return item.descriptor.lane` — so uv tools and uv python share uv's lane with uv itself and bub (`uv self update` replaces the binary the others run; `.lock` serialises list/upgrade, UV-19); mise tools share "mise" with `mise self-update`; nvm Node shares "nvm" with nvm's own update; cargo shares "rust" with rustup/toolchains (the toolchain's cargo is what compiles; `rustup update` replaces it). `CLIConcurrency` (Homebrew vs tool) is untouched.
- `CLIToolKind.updaterSpendsGitHubAPI` (C/CLITool.swift:477-483) gets a status-level twin that reads the descriptor for `.managed`; `applyingGitHubPause` and `CLIToolRows.check` call that. mise tools → `.ourTokenIfAny` (MISE-29b); every other adapter nil (UV-14b, PX-12, NVM-21, FNM-21, PY-13, RB-10, CARGO-12, GO-08).
- `readsGitHubAPI` stays `false` for all adapters: none asks api.github.com from our process during a check (release notes are excluded by the protocol's own doc, C/CLITool.swift:450-452).

### 3.5 What still has to be edited once (never per manager)

One `.managed` arm in each exhaustive switch: `CLIToolKind.displayName` (C/CLITool.swift:70 → "Managed tools"), `CLIToolWording.vendor(of:)` (:24 → nil; managed wording reads `item.descriptor.signer` in `reason(_:of status:)`), `Detail` + `Context` cases (:228, :310), `CLIToolsWorkbench.logo/tint` (:76, :118 → descriptor), `cliToolHeaderSummary` (WorkbenchWindowView.swift:1144), `CLIToolPresentation.facts(of:)` (:255 → generic managed facts), the two test switches (App/Tests/CLIToolsModelTests.swift:72,113), `CLIToolsTests.everyKindHasOneProviderInKindOrder` (→ non-managed kinds once each in order, then managed providers in registry order), `CLIToolGitHubAPITests:22` provider list, `CLIToolPresentation.groups` key (`kind.rawValue + ":" + …` → for `.managed` the `"<manager>|<root>"` part of identity, with `Group.manager`), `CLIToolPresentation.pinned`/`title` (name is always set for managed rows; `pinned` wording reads the request). Logos: reuse `cli-mise`, `cli-uv`, `cli-nvm`, `cli-rust`; add `cli-pipx`, `cli-fnm`, `cli-pyenv`, `cli-rbenv`, `cli-go` imagesets (assets are data; the switch is gone). Strings: generic managed wording keys (~30) once; a manager adds none unless it needs a special reason.

### 3.6 Check granularity

Per provider = per manager, exactly as today (`checkedAt[index]`, INT-13); an update re-checks its manager only (`check([provider])`, :827-831). No per-item re-check: the adapters' checks are one spawn or one index fetch for all items, so per-item would cost the same. Within a check an adapter may answer items in parallel (pipx: ≤8 PyPI requests at once, mirroring pipx's own `_MAX_OUTDATED_WORKERS`, PX-12).

---

## 4. Adapter specs

Common to all: `home` injected; scan reads only under `home` and the two Homebrew prefixes; the manager binary is run only when `root.binary.trust` is `.vendorSigned`, `.homebrewKeg` (D5), `.verifiedHash` or `.exempt` and not quarantined; child env is built from scratch (never the inherited one) plus the system proxy (`environmentWithSystemProxy`, INT-74); cwd `/` unless stated; no flags beyond the vendor's documented upgrade command.

### 4.1 mise tools (`mise`) — Phase 1, closes #1605
- **Root/binary**: `~/.local/share/mise` (+ `~/.config/mise`, `~/.local/state/mise`); binary = `MiseScanner` (reused: Team `4993Y37DX6`, not quarantined, C/MiseInstall.swift:75-137). Items need the binary for the check; with no trusted mise, items are listed from disk and reported `.updaterMissing`/`.wrongSigner`.
- **Scan** (no spawn): `installs/<slug>/<version>` real dirs (skip symlinks and dot-dirs as `NodePrefixes.versionDirectories` does, :124-137), name from `.mise.backend.toml` `short`/`full` (MISE-05); versions in `tool-purgatory.json` tagged (MISE-31). Sighting state = backend + version set + config mtime (`config.toml`, `~/.tool-versions`).
- **Check** (3 spawns, cwd `/` — D3's fallback, see §12 item 1; originally `$HOME`): `mise ls --json`, `mise outdated --json`, `mise outdated --bump --json`, env `HOME`, `PATH=<data>/shims:<~/.local/bin>:system`, `NO_COLOR=1`, `MISE_YES=1`? (no: `-y` only on upgrade). Empty stdout = `{}` (MISE-56). Rows: one per `ls` entry with `requested_version` (`shape: .request`, key `<name>@<requested>`), `installed:true`, not `scheduled_for_pruning`; `active:false` entries no config requests → not shown (D4), purgatory ones → `alsoInstalled` on the active row. Verdict: the `outdated` entry for `name` applies to the row whose `requested` equals its `requested`; a second request of the same tool with no entry → `blocker .notRequestedByOutdated` note "mise outdated reports one request per tool" (MISE-23, review fact 4). `current:null` rows (requested, not installed) are not rows (MISE-24). `latestWithinRequest` = plain `latest`; `latestOverall` = `--bump` `latest`; `vendorWouldUpgrade` = plain entry present. `request` kind from the string: three numeric parts or a full backend-exact version → `.exact`, else `.range`.
- **Upgrade**: `<mise> upgrade -y <name>` (MISE-31/41), never `@<version>` (MISE-36), never `--bump`. `unpin` = `mise upgrade --bump <name>` (copy only; rewrites config, MISE-34). Effects: `.oldKept(for: "24h")` when mise ≥ 2026.8.15 (from `--version`), else `.oldRemoved` (MISE-32/33). Token retry as `MiseUpdater` (§12 for the warning string on backend installs).
- **Busy**: a running `mise upgrade|install|use` from this binary (generic `ManagedActivity`, argv match like `MiseActivity.selfUpdating`, C/MiseActivity.swift:24-29).
- **Notes**: `release_url` → owner/repo → `DenoChangelog.gitHubReleases` (MISE-46 corrected); `github:`/`ubi:`/`asdf:<o>/<r>` ids → same (MISE-49); `core:node` → `CHANGELOG_V<major>.md`; `npm:<n>` → `NpmChangelog` with the packument's repository (INT-46); `pipx:<n>` → PyPI `project_urls` (UV-27 priority rule); else empty `Changelog`.
- **Header**: "mise tools" · `mise <binary version> · ~/.local/share/mise`.
- **Minimum**: 2024.12.6 tested; `--global`, `release_url`, pruning fields optional.

### 4.2 uv tool (`uv-tool`) — Phase 2
- **Root/binary**: `~/.local/share/uv/tools`, bins `~/.local/bin`; binary = `UvScanner`'s standalone `~/.local/bin/uv` (trusted by Team or verified hash, C/UvCheck.swift per UV-30).
- **Scan**: per `<tools>/<name>/uv-receipt.toml`: `requirements[0].specifier` (`==` → `.exact`, other → `.range`, none → nil), `[tool.options].exclude-newer`, `python`; installed version from `lib/python*/site-packages/<name>-<v>.dist-info/METADATA` (UV-05/08); malformed → `.versionUnreadable`.
- **Check**: uv ≥0.10.10: `uv tool list --outdated` (cwd `/`, env `PATH` only; no `--exclude-newer`), parse `^(\S+) v(\S+) \[latest: (\S+)\]$`, skip `- ` lines (UV-10 narrow); rc≠0 → `.channelUnreadable` for all (review fact 6). uv <0.10.10 (and 0.10.10, which ignores `exclude-newer`, UV-14c corrected): PyPI `https://pypi.org/pypi/<name>/json`, `info.version` filtered by `requires_python` against the venv's Python and by the receipt's `exclude-newer` (upload times in `releases`). `latestOverall` = that; `vendorWouldUpgrade`: nil spec → `latest > installed`; `.exact` → false; `.range` → nil (D9) → `.unknown` with note "uv tool upgrade follows `>=23,<24`; not checked" until the PEP 440 matcher lands.
- **Upgrade**: `<uv> tool upgrade <name>` (no flags, UV-17); `unpin` = `uv tool install <name>@latest` (copy; UV-16 hint). Effects `.oldRemoved`. Settle: dist-info re-read. Lane "uv".
- **Notes**: dist-info `Project-URL` → github repo (priority: Changelog/Repository/Source/Source Code/GitHub/Homepage; require `github.com/<o>/<r>` and `<r>` ≈ name, else none — UV-27's ansible case) → GitHub releases, else `CHANGES.md`-style raw file is *not* parsed (no verified format) → empty.
- **Header**: "uv tools" · `uv 0.13.4 · ~/.local/share/uv/tools`.

### 4.3 uv python (`uv-python`) — Phase 3
- **Scan**: `~/.local/share/uv/python/cpython-<X.Y.Z>-…` real dirs; `shape: .line`, key `cpython-3.12-<os>-<arch>`, name "Python 3.12", installed = newest patch dir, `alsoInstalled` = older ones (PY-03/07).
- **Check**: one spawn per line, offline: `uv python list cpython-3.12 --only-downloads --output-format json`, cwd `/` (review fact 1), `latest` = newest `version` for that minor; fact `.asKnownBy("uv 0.13.4")` (PY-04: the answer changes only when uv updates — the uv row's update is the prerequisite).
- **Upgrade**: `<uv> python upgrade 3.12` (PY-06/07); on 0.7.14–0.9.x it runs with a warning (PY-08 corrected/PY-09); below 0.7.14 → `.unsupportedInstaller`. Effects `.oldKept`, fact "tool venvs on this minor follow" (UV-22). Settle: newest patch dir. Lane "uv".
- **Notes**: none (✗).

### 4.4 pipx (`pipx`) — Phase 2
- **Roots**: `~/Library/Application Support/pipx/venvs` and `~/.local/pipx/venvs`, both scanned (PX-04); binary: `~/.local/bin/pipx` (symlink into a uv tool or a pip script) or `/opt/homebrew/bin/pipx`.
- **Scan**: `pipx_metadata.json` → name, `package_version`, `package_or_url` (specifier shown as a fact, **not** a request: pipx ignores it, PX-14), `pinned` → `.exact` request semantics (PX-15), `python_version`, `backend`.
- **Check** (no spawn): PyPI JSON per venv, `info.version` + `requires_python` vs `python_version` (PX-13); non-index `package_or_url` (URL/path/VCS) → `.notIndexed`. (`pipx list --outdated --output json`, ≥1.15.1, is equivalent and spawns; not used because the binary's trust is open, D5.)
- **Upgrade**: `<pipx> upgrade <name>`; **gated on D5** — until granted, offered as `manualCommand` under `.unverified` ("pipx is a Python script; nothing to verify"), as bub does today (BubCheck.swift:178-179). Effects `.dropsSpecifier("ruff==0.6.0")` when `package_or_url` carries one → `rowWarning` (D7). `unpin` = `pipx unpin <name>`. Lane "pipx".
- **Notes**: as uv tool.

### 4.5 nvm Node (`nvm-node`) — Phase 3
- **Roots**: `~/.nvm/versions/node` and `~/.config/nvm/versions/node` (NvmInstall.swift:69 already knows both dirs; NVM-60). `shape: .line` per major: key `v22`, name "Node 22", installed = newest `vX.Y.Z` dir, `alsoInstalled` older; facts: `default` alias text and what it resolves to (`alias/default`, NVM-31/42), LTS codename from the index (NODE-03).
- **Check**: `NodeDistIndex` fetcher shared with fnm: `https://nodejs.org/dist/index.json` with `versionFeedCachePolicy` (ETag → 304, NODE-01); latest = highest `version` of the major; `security` count of the skipped releases as a fact (NODE-02). No nvm spawn, so no `alias/lts` rewrite (NVM-23) and no `N/A` ambiguity (NVM-24).
- **Upgrade**: `/bin/bash -c '. "$NVM_DIR/nvm.sh" --no-use; nvm install <major> --reinstall-packages-from=<installed>'` with env `HOME`, `NVM_DIR=<root>`, `PATH` system, no mirror variable (NVM-05/32/70; D6). Trust: nvm's existing exemption (NvmCheck rule 4) covers the same `nvm.sh`. Effects `.oldKept`, `.defaultStays(<literal>)` when `alias/default` names the old patch exactly; fact + copy `nvm alias default <new>` (D6). Settle: newest dir of the major. Lane "nvm".
- **Notes**: `CHANGELOG_V<major>.md` raw (NODE-05c) — parser new (§12).

### 4.6 fnm Node (`fnm-node`) — Phase 3
- **Roots**: the three fnm roots (`NodePrefixes.swift:98` list), `node-versions/vX.Y.Z/installation`; aliases from `aliases/*` symlink targets (FNM-03/05). Binary `/opt/homebrew/bin/fnm` (FNM-01) → trust by D5 (Homebrew keg).
- **Check**: same `NodeDistIndex`.
- **Upgrade**: `<fnm> --fnm-dir <root> install <major>` (FNM-02/30; root exists, so FNM-04 corrected is moot); effects `.oldKept`, `.defaultStays`, `.packagesNotCarried` (FNM-31/33). Lane "fnm". Settle: newest dir.
- **Minimum**: install works 1.36.0+; nothing else of fnm is run.

### 4.7 pyenv (`pyenv`) — Phase 3
- **Roots**: `~/.pyenv/versions`; binary `~/.pyenv/bin/pyenv` (git checkout: bash, nothing to verify → D5) or `/opt/homebrew/bin/pyenv` (keg, D5).
- **Scan**: `versions/<name>` real dirs, skip symlinks, `envs`, hidden (PY-09, review on PY-08); only names matching `^\d+\.\d+\.\d+t?$` make rows (PY-18, review fact 4: flavors excluded); line per `X.Y[t]`; a dir without `bin/python3` → `.versionUnreadable` (PY-10 narrow). Facts: global pin (`$PYENV_ROOT/version` first lines, PY-22/25), `alsoInstalled`.
- **Check** (no network, no spawn): definitions = file names under `<pyenv>/plugins/python-build/share/python-build` **and** `$PYENV_ROOT/plugins/*/share/python-build` (PY-13, PY-28 corrected), filtered with pyenv-latest's rule (drop `-dev/-src/-latest`, `(a|b|rc)\d+$`, `t` unless the line has it, PY-15), highest for the line; fact `.asKnownBy("pyenv 2.8.13")` with "update pyenv for newer" (PY-14). Homebrew layout path per §12.
- **Upgrade**: `<pyenv> install <X.Y.Z>` (exact resolved; PY-19/20), env `HOME`, `PYENV_ROOT`, `PATH=/opt/homebrew/bin:system` (Homebrew libs, PY-17/33); deadline 20 min; effects `.compilesFromSource`, `.oldKept`, fact "prefix pins like `3.12` move to the new patch" (PY-23/31). Lane "pyenv". Settle: newest dir.
- **Notes**: none (✗, PY-26).

### 4.8 rbenv (`rbenv`) — Phase 3
- As pyenv with: `~/.rbenv/versions`, bare `X.Y.Z` names only (RB-07); definitions under `$RBENV_ROOT/plugins/ruby-build/share/ruby-build` or `/opt/homebrew/opt/ruby-build/share/ruby-build` (RB-03/04/10), excluding `-rc/-preview/-dev` (RB-10); upgrade `<rbenv> install <X.Y.Z>` with `PATH=/opt/homebrew/bin:system` (review fact 1); pins never move (RB-12/19). Notes: GitHub releases `ruby/ruby` tag `v<X>_<Y>_<Z>` (RB-20) ✓.

### 4.9 cargo install (`cargo`) and go install (`go`) — Phase 4
- **cargo scan**: `~/.cargo/.crates.toml` (authority) + `.crates2.json` features (CARGO-05/06/07), `binstall/crates-v1.json` for a "installed by binstall" fact (BS-03); row per package, `path` = `<root>/bin/<first bin>`, key = name; source `registry+`/`sparse+` → checkable, `git+`/`path+` → `.notIndexed` (CARGO-22/25). Binary: `~/.cargo/bin/cargo` **only when it is the rustup proxy symlink and `RustCheck` proved that rustup** (INT-35; CARGO-02/28a) — running the proxy runs the verified rustup; otherwise rows reported with `.unverified`.
- **cargo check**: sparse index per crate (`index.crates.io/<path>`, CARGO-12), `versionFeedCachePolicy` (ETag/304), parse lines, drop `yanked` and pre-release, **sort by semver** (CARGO-14 narrow); MSRV: keep the newest whose `rust_version` ≤ the active toolchain's rustc (from `.crates2.json`'s `rustc` of the row, CARGO-15) and show the skipped newer one as a `.runtimeTooOld`-style fact. No rate limit, no token (CARGO-13).
- **cargo upgrade**: `<cargo> install <name>` + `--features a,b` / `--no-default-features` / `--locked`? no — only the recorded `features`/`no_default_features` from `.crates2.json` (D8; what cargo-update passes, CUPD-03), env `CARGO_HOME`, `RUSTUP_HOME` (as RustUpdater, INT-34), `PATH` system; deadline 30 min; effects `.compilesFromSource`, `.oldRemoved`. cargo-update and cargo-binstall are never run (CUPD-04 corrected, BS-06/07). Lane "rust". Settle: `.crates.toml` re-read.
- **cargo notes**: crates.io API `/api/v1/crates/<name>` with a `User-Agent: DuoUpdater/<v> (<contact>)`, ≤1 req/s (CARGO-13) → `repository` → GitHub releases; cached per name for the session like npm's (INT-46).
- **go scan**: `GOBIN`/`GOPATH` from `~/Library/Application Support/go/env` if set, else `~/go/bin` (GO-01); each regular Mach-O → `GoBuildInfo` extended to keep `path` and `mod` (GO-05/17); rows only for a tagged `mod` version (`vX.Y.Z[-pre]`); `(devel)`, pseudo, `+dirty`, `command-line-arguments` → `.notIndexed` with the reason (GO-04). Binary: `/opt/homebrew/bin/go` (keg, D5) or `/usr/local/go/bin/go` (§12 signature).
- **go check**: `<go> list -m -json <module>@latest` per module, cwd `/`, env `HOME`, `GOENV` default (so GOPROXY/GOPRIVATE apply), `GOTOOLCHAIN=local`, `GOFLAGS=-mod=mod`; `Version` vs the binary's `mod` version (GO-07/09/11); same major path only, next major is not probed (GO-10).
- **go upgrade**: `<go> install <path>@latest` same env (GO-12/14); effects `.oldRemoved`, fact "GOTOOLCHAIN=local: a module needing a newer Go is reported, not fetched". Lane "go". Settle: re-read build info.
- **go notes**: module path under `github.com/<o>/<r>` → GitHub releases; else `proxy.golang.org/<mod>/@latest` `Origin.URL` when it is GitHub (GO-08/16); else empty.

### 4.10 asdf — not onboarded
Detection would run plugin scripts with network and git side effects and anonymous GitHub budget (ASDF-12/41, review fact 6); there is no upgrade (ASDF-15/20). The existing nodejs prefix stays. Revisit only on a user request, and then as "Node under asdf" through `NodeDistIndex`.

---

## 5. UI

Everything reuses what exists; one new element is called out.

- **Workbench CLI tab**: one `cliToolHeader(group)` per managed group (title = `descriptor.displayName`; summary = manager version · root via `headerSummary` reading `.managed(ManagerContext)`), then `CLIToolSidebarRow` per item exactly as now (icon via descriptor logo/tint; title = `status.name`; caption = `versionCaption` → "20.10.0 → 20.20.2", pinned wording from `CLIToolWording.pinned` generalised to the request; trailing = Update / copy glyph / nothing by the existing rules, CLIToolsWorkbench.swift:276-297). Each manager's items are a **top-level level of their own**, between Homebrew and "Other tools" (D12, revised twice on 2026-10-24): a `HomebrewGroupHeader` titled with the group ("mise tools") and its own Update All, a counts row (manager version · root), then the rows. Open by default; a closed one is remembered only for the window. "Other tools" keeps the standalone tools alone.
- **Rows represent**: mise — one row per (tool, request) in the user's config (two requests of node = two rows, MISE-51); uv tool/pipx/cargo/go — one row per package/binary; version lines — **one row per line (major for Node, minor for Python/Ruby)** showing the newest installed patch, older patches as an "Also installed" fact (D1). A mise node version also appears as an npm prefix header ("mise · node 20") — different thing (the packages in it), kept.
- **States and words**: `updateAvailable` → tinted `a → b` + Update; `pinned` → "Pinned to `1.6` in mise's config, so it doesn't follow new releases" + copy glyph for `mise upgrade --bump jq`; range held → caption shows installed, pane fact "26.12.1 available beyond `20` — `mise upgrade --bump node`"; `unknown` → existing reasons; busy → "mise is already changing its tools" (manager-specific wording via `reason(_:of status:)`). `rowWarning` (orange caption, already exists) carries `.dropsSpecifier` and `.packagesNotCarried` before the click (D7).
- **Detail pane** (`CLIToolDetailPane`): header name + install path (unchanged); facts from `ManagedItem.facts`/`effects` (Source config, Request, Backend, Also installed, Default alias, Python, Target, Known by, What the update does: "keeps the old version for 24 h" / "rebuilds from source" / "leaves `default` on 22.21.1"); release notes view unchanged.
- **Popover tool groups (2026-10-24, owner's pick after real-Mac trials)**: Homebrew stays its own row. "Other tools" gets a sideways chevron (› closed, ‹ open) between its title and its line, shown while at least one group has work. It slides in a page — `ToolsPage` — over the app list, at its own height (up to the list's 380 pt cap) — the owner tried holding a taller list's height and read the blank space below a few groups as a bug — and that height holds while it is open; it has its own search text, and the apps' search is never touched. With a "‹ Other tools" header: one row per group with work (named by the group: "Claude Code", "npm · nvm", "mise tools"), each with its own Update (`CLIToolsModel.updateAll(in:)`, the group's `CLIRowSnapshot.scoped`) and Cancel (`cancelRow(in:)`); the parent row keeps Update All. A row's name opens the workbench on that group's first copy with work, selected and scrolled to (`requestedWorkbenchCLITool`). The search field stays in place and searches the groups while the page is open. The page keeps the rows it opened with until it closes, so a group whose update ended does not leave from under the pointer; the page and the list are one strip moved by offset, so quick toggles leave no copies behind. Not remembered across popover opens.
- **Popover `CommandLineRow` lines**: managed rows are tool statuses, so "N updates", "held back", "Updating mise tools" (uses `kind.displayName`; for `.managed` the head line names the manager — `CLIPopoverRow.Line.updatingGroup` from `CLIRowSnapshot.Tool.groupTitle`; several copies just updated read "N updated", `.updatedCount`). Banner/badge: `offered.count` and `UpdateAnnouncementItem(key: tag, name: item name)` unchanged (AppListModel.swift:9429-9442).
- **New UI** (built 2026-10-24, from the owner's trials): the managers' own workbench levels and the popover's tool groups page (both above). Otherwise the "Also installed" fact and the effects facts are new *rows* in the existing facts table, not new controls.

---

## 6. duo CLI

- `list`/`check`/`install` rows: `tool: "managed"` plus new keys `manager` (id), `item` (key), `root`, `installPath`, `request` (string), `latestBeyondRequest`, `effects` ([String]); `name` = item name; `path` = install path (unchanged meaning). Adding keys is not a schema bump (NDJSON.swift:13-15) → **schema stays 2**; D-B offers 3 if the owner wants `tool` to carry the manager id instead.
- `list` (scan only) gets item names through `CLIToolSighting.name`.
- Name matching (`main.swift:61-67` rule): `names = [key, "<manager>/<key>", name]`, so `duo install mise/node` is unambiguous and `duo check node` errors as ambiguous when both mise and nvm have one — the existing "never a guess" rule.
- `install` runs managed rows through `provider.update` after the apps as now (Install.swift:79-82, 247); `--route` still excludes tools. Failure output: vendor lines + `exitStatus` as today (CLIToolRows.swift:440-446).
- Text output: `name  installed → latest  path`, with `held back: …`, `to update it yourself: …`, and a new detail line per effect ("keeps the old version for 24 h").
- Agreement contract: `ManagedCheck` is the only state logic, in Core; a test runs one provider with fixture adapters through both `CLIToolsModel` and `CLIToolRows` and compares states (new `ManagedAgreementTests`).
- What duo deliberately does not get: the administrator path (none of these needs root) — n/a; `pyenv`/`cargo` long builds stream progress line by line as today (stderr).

---

## 7. Scheduling and cost

| Stage | Trigger (unchanged) | Managed cost |
|---|---|---|
| scan | every popover/workbench open after the first, focus, launch (INT-14 narrow; review fact 1 notes mise/uv `--version` already spawn here) | **disk only, no spawn** for all ten adapters: directory listings, TOML/JSON reads, one Mach-O read per Go binary (bounded). Budget: a few ms per root. |
| check | first open, report ≥15 min old, scan disagreement, unanswered ≥60 s, background `checkFrequency` tick (INT-13/14/15) | mise: 3 spawns of mise (its own network to mise-versions); uv tool: 1 spawn (PyPI simple via uv) or N PyPI JSON; uv python: 1 offline spawn per line; pipx: N PyPI JSON (≤8 parallel); nvm+fnm: 1 `index.json` (335 KB, 304 after first); pyenv/rbenv: 0 network, 0 spawn; cargo: 1 index GET per crate (304 after first, no limit); go: 1 `go list` spawn per module (network through GOPROXY). Each adapter keeps the 15 s per-request rule (`CLIToolsModel.check` doc, :505-514). |
| breaking hint after check (`loadBreaking`, INT-72) | every `updateAvailable` row | GitHub API per repo for mise/uv/pipx/cargo/go rows → bounded by D10 (≤5 managed documents per pass; the rest fetched when the pane opens). Rate limit answers go through `GitHubRateLimitGate` as now. |
| update | click / Update All lanes | seconds (mise, uv, pipx, nvm, fnm, go) to minutes (pyenv/rbenv compile 2–3 min, cargo rebuild); deadlines per descriptor; Update All runs lanes in parallel (INT-19), so one long build holds only its lane but keeps the popover in "Updating…" for its length — a known cost, stated in D8/D11. |
| GitHub budget | `readsGitHubAPI` floor (INT-15) | no adapter reads the API during a check → no floor needed; mise's own process may fall back to api.github.com with its own token chain (MISE-29) — out of our gate, as mise self-update is today; `updaterSpendsGitHubAPI` pause applies to mise tools. |

---

## 8. Migration and phase plan

### 8.1 Phases (each: scope → files → executable acceptance)

**P0 — Plumbing (no new manager visible).** `C/Managed/{ManagerID,ManagerDescriptor,ManagedItem,ManagedVerdict,ManagerAdapter,ManagedCheck,ManagedProvider,ManagedActivity,ManagerRegistry}.swift`; `.managed` kind, `identity`, `providerID`, `CLIToolSighting.name/identity`; the one-time switch arms (§3.5); `CLIToolRows` fields; tests. Acceptance: `make test` exit 0; `CLIToolsTests` order test rewritten and green; a `FakeManagerAdapter` through `CLIToolsModelTests` proves: identity stable across a moved `installPath` (justUpdated and selection survive), lane by descriptor, pause by descriptor, pinned never counted in `offered`; `duo check --json` row for the fake carries the new keys and `schemaVersion: 2`; app rows unchanged for all 28 kinds (snapshot of `CLIToolPresentation.groups` over fixture statuses).

*Written 2026-10-23 (see the status log); CI's swift, app, release and test jobs green on `a9e6c01` (run 39932065312).*

**P1 — mise tools.** `C/Managed/Mise/{MiseToolsAdapter,MiseToolsLs,MiseToolsOutdated}.swift`, registry line, strings. Acceptance: unit fixtures from `r-mise-asdf/out-cur-ls.json`, `out-cur-outdated2.json`, `out-cur-outdated-bump.json`, `out-old-ls.json`, `out-old-outdated-bump.json`, the 2024.12.6 empty-stdout case; mutation checks (§9). Real machine, isolated: `HOME=<iso>` populated like the researchers did (`MISE_DATA_DIR` et al. point into `<iso>` because the adapter sets `HOME=<iso>` for the child), `<iso>/.local/bin/mise` a symlink to the real signed binary, tools `jq="1.6"`, `node="20"`, `npm:prettier="2.0.0"` installed at old versions; run the provider via a test executable with `home: <iso>`: expect rows node (`updateAvailable` 20.10.0→20.20.2), jq (`pinned`, copy `mise upgrade --bump jq`), prettier (`pinned`); one-click on node → `.updated("20.20.2")`, config byte-identical, purgatory entry present, `alsoInstalled` shows 20.10.0; `duo check --json`/`duo install mise/node` on the same iso home agree with the app's statuses; before/after `stat` of `~/.local/share/mise`, `~/.config/mise`, `~/Library/Caches/mise` identical (the researchers' `before.txt/after.txt` method); UI: duoshot of the workbench group header, a pinned row with the copy glyph, an updating row, the popover "Updating mise tools"; `make install` + real popover open shows the group without the user's real mise config being written (owner's OK needed only if the real home is used — it is not). **As run (2026-10-23/24):** the app and `duo` cannot read an isolated home, so the owner chose the real home, with the fixtures reset after each run; results under "Device verification" in PR #1613 and in the status log.

**P2 — uv tool, pipx.** Adapters + `PyPIProject` fetcher + `ProjectURLRepo` rule. Fixtures: `r-uv-pipx/pipx-list-*.json`, the `uv tool list --outdated` log text (with `- ` lines), receipts from `iso/uv-tools/*/uv-receipt.toml`, 0.5.0 receipt shape (UV-28). Real machine: iso `UV_TOOL_DIR` under `<iso>/.local/share/uv/tools` with ruff `==0.6.0` (pinned), black `>=23,<24` (reported, D9), cowsay unpinned (update); `pipx` venvs under `<iso>/Library/Application Support/pipx` with one `pipx pin`. Expect states as §3.2; uv one-click on cowsay → `Updated` on stderr parsed, settle by dist-info; pipx rows show copy command (until D5).

**P3 — lines: uv python, nvm Node, fnm Node, pyenv, rbenv.** `NodeDistIndex` + `NodeChangelog` parser; definitions readers; nvm bash runner. Fixtures: trimmed `index.json` (first 40 entries incl. a `security` one and the first Jod), `r-pyenv-rbenv` definition name lists (`ls share/python-build`), `rbenv versions --bare` unsorted sample. Real machine: `<iso>/.nvm` with v22.21.1 and the real `nvm.sh` copied (NVM-05 recipe) → one-click `nvm install 22 --reinstall-packages-from=22.21.1` yields v22.23.4 beside it, `default` unchanged, globals carried; fnm with `--fnm-dir <iso root>`; pyenv/rbenv one real build each (~2–3 min, as the reviewer did) only after D5; uv python 3.12.5 → upgrade → 3.12.15 with old dir kept.

**P4 — cargo, go.** Fixtures: `r-cargo-go` `.crates.toml`/`.crates2.json` samples, `api-tokei.json`, a sparse-index file in publish order (rand's tail `0.8.7, 0.9.5, 0.8.8, 0.10.3`), `go version -m` text samples (tagged, pseudo, devel, dirty). Real machine: `CARGO_HOME=<iso>/ch` with tokei 14.0.0 `--features yaml` → row `updateAvailable` 14.0.0→15.0.0 → one-click → 15.0.0 **with yaml kept** (D8); hexyl git row reported; `GOBIN=<iso>/go/bin` with gofumpt v0.9.1 → `go list` latest v0.12.0 → one-click → v0.12.0; `GOTOOLCHAIN=local` case reported.

Every phase P1–P4 also passes §13.2 (C1–C6) for each adapter it adds and delivers that adapter's §13.3 measurements. A phase is not done without them.

Every real-machine step: before/after `stat` proof attached to the PR (project rule: paste commands and raw output). **Where (learned in P1, 2026-10-23):** an isolated home works for the vendor's own binary (`HOME=<iso>`), but not for DuoUpdater or `duo`, which read `homeDirectoryForCurrentUser` and ignore `$HOME`. The owner chose the real home for P1, with the tools' versions recorded first and put back after (a `reset` script for the fixtures, backups of every binary an Update All touches); plan the same for each later adapter, or ask the owner again where the real home cannot be put back.

### 8.2 Existing integrations
| Integration | Decision | Why |
|---|---|---|
| Homebrew formulae | never | separate type family, lane, concurrency rule, announcement category, per-formula icons, disk-cached notes (INT-54..59); nothing in the managed model improves it |
| rustup toolchains | not now; reconsider when Rust code is next touched | already the manager→items shape with its own hash-based latest and trust chain (INT-32..37); the managed model would gain nothing but churn; the Rust group also hides fully pinned toolchains by an owner decision (INT-32) that differs from `.pinned` |
| npm / bun / pnpm / yarn | not in P0–P4; candidate after P3 | 4,000+ lines with per-prefix node/engines logic, specifier restore, three busy gates (INT-39..53, 60); `ManagedItem.request` covers their pin semantics, so a later `NodePackagesAdapter` could replace `NpmProvider/BunProvider/GlobalPackagesProvider` — but only once a migration of `NotifiedCLIToolVersions` keys (`npm:<dir>` → identity) is designed; until then their keys are untouched |
| mise-the-binary, nvm, uv (own rows) | stay as kinds | they are the managers' own self-updates; the managed groups reference their trust and lanes |
| `BubInstall`'s uv-tool/pipx venv knowledge | fold into P2 | bub's venv rows and a `uv-tool` row for `bub` would duplicate; P2 makes bub's uv-tool/pipx copies ordinary managed items and `BubProvider` keeps only the installer method (INT P4, UV-31) — owner's call in D-C |

---

## 9. Test strategy

- **Unit, fixture-driven, host-independent**: every adapter has a `Reader` seam (file contents by path, command output by argv, HTTP by URL) injected like `MiseScanner`'s `readVersion`; fixtures are the researchers' raw files named above, checked into `DuoUpdaterCore/Tests/Fixtures/Managed/<manager>/`. No test lists the host's `~`.
- **`ManagedCheck` table test**: one case per row of §3.2, each with the mutation that would break it named in the comment (project style): offer a `.pinned` row → fails; count a range-held row as outdated → fails; treat `scheduled_for_pruning` as a row → fails; treat `installed:false` as a row → fails; parse `- blackd` as a tool → fails; empty mise stdout → crash/`.channelUnreadable` instead of "nothing outdated" → fails; take the last sparse-index line instead of the semver max → fails (rand fixture); run `uv python list` without cwd `/` (relative path accepted) → fails; pass `--save`/`--bump`/`--exclude-newer`/`--force` anywhere → an argv assertion fails; run a manager binary whose trust is `.untrusted` → fails; `nvm` env contains `NVM_NODEJS_ORG_MIRROR` → fails.
- **Identity/model tests** in `CLIToolsModelTests` with `FakeProvider`s: moved `installPath`, same identity → one row, `justUpdated` kept, ledger key stable; two providers of kind `.managed` → `provider(of:)` picks by `providerID`.
- **Agreement test**: fixture adapter through `CLIToolsModel` and `CLIToolRows.check` → identical `(identity, state, oneClick, withheld)`.
- **Presentation tests**: `groups` splits managed by `(manager, root)`; `title` uses `name`; `pinned` wording for a mise request; header summary.
- **Real-machine checks** as in §8.1, run from a test executable that takes `--home <iso>`, never the default home; results pasted into the PR.
- **Coverage**: one-off, not a CI gate (project memory).

---

## 10. Risks and containment

| Risk | Containment |
|---|---|
| Scan cost creeps (ten more providers per open) | scans are disk-only by protocol; a test asserts no `ChildProcess` in any adapter's `scan`; measure per-open scan time before/after P1 and P3 (log line exists: "cli-tools check…", add one for scan) |
| mise reads an untrusted `~/mise.toml`/`.tool-versions` from `$HOME` and prompts or fails | §12 check; fall back to cwd `/` if it prompts; never answer prompts (`-y` only on upgrade) |
| Long builds (pyenv, rbenv, cargo) hold Update All lanes and the popover's "Updating…" | own lanes, own deadlines; the popover names the running manager; D11 lets the owner exclude compile-type managers from Update All (`joinsUpdateAll` false) |
| GitHub budget spent by breaking-hint fetches for many managed rows | D10 cap; raw-file notes (node) and crates.io/PyPI metadata first; API only through the gate |
| Vendor side effects on one-click (pipx drops `==`, cargo drops features/pin, nvm leaves `default`, mise removes old on <2026.8.15) | shown as `rowWarning`/facts before the click, listed in duo's text; D7/D8/D6 |
| `cargo`/`go` toolchain fetch or MSRV surprise | `GOTOOLCHAIN=local`; MSRV computed from the recorded rustc; both reported, never downloaded |
| Identity key leaks a path into `NotifiedCLIToolVersions` for a root that moves | key = manager|root|item; a moved root is a new install (announced once), same as a moved tool today |
| mise `outdated` collapses two requests of one tool | second request's row is `unknown` with the reason; the table output is not parsed (MISE-23) |
| `uv tool list --outdated` aborts on one failing index | whole group `.channelUnreadable` for that check; re-asked after 60 s (`mayClearByItself`) |
| nvm `N/A` ambiguity after a one-click | install result is judged by the new dir, not by nvm's exit (NVM-24/33) |
| Two sources for the same Node (nvm line row + npm prefix group header) confuse | header already says "nvm · node 22.21.1"; the line row is titled "Node 22" with "nvm" in the group title |

---

## 11. Decisions (owner, 2026-10-23: every recommendation taken)

| # | Decided | Instead of |
|---|---|---|
| D1 | Version lines: **one row per line** (Node by major, Python/Ruby by X.Y), newest installed patch on the row, older patches as an "Also installed" fact | one row per installed patch |
| D2 | Range held at its top: **`.upToDate`** + fact "newer beyond the request" with the unpin command | `.pinned` |
| D3 | mise scope: **cwd `$HOME`, no `--global`**. If §12 item 1 shows mise prompting on an untrusted `~/mise.toml`, fall back to cwd `/` (global config only) and record it here. **Fallback taken 2026-10-23 (P1):** from `$HOME` an untrusted `~/mise.toml` fails every command, and `-y` *trusts* it (§12 item 1) — so mise runs from `/` | `--global` |
| D4 | mise installs no config requests: **not rows** | rows as `unknown` |
| D5.1 | Homebrew-keg manager binaries (fnm, go, pyenv, rbenv, pipx): **extend the existing keg trust rule → one-click**. How "keg" is detected is §12 item 7 | copy command only |
| D5.2 | Script managers with nothing to verify (git-checkout pyenv/rbenv, pip/uv-installed pipx): **report + copy command** until a user asks | nvm-style exemption |
| D6 | nvm one-click: **`nvm install <major> --reinstall-packages-from=<installed>`**; when `alias/default` literally names the old patch, offer `nvm alias default <new>` as a copy command | bare `nvm install`; running `nvm alias default` ourselves |
| D7 | pipx `==` in `package_or_url`: **offer the update with an orange row warning** "pipx will drop `ruff==0.6.0`" | treat as pinned |
| D8 | cargo: **`cargo install <name>` + the `features`/`no_default_features` recorded in `.crates2.json`** | bare `cargo install`; `cargo install-update` |
| D9 | uv ranged specifiers: **report-only in P2** ("follows `>=23,<24`; not checked"); PEP 440 matcher in P2b | blind `uv tool upgrade` |
| D10 | Breaking-hint fetches for managed rows: **≤5 GitHub documents per check pass**, the rest when the row's pane opens | unchanged (no cap) |
| D11 | Compile-type managers **join Update All**, each in its own lane. Cancel/Cancel All must behave as §13 says | excluded from Update All |
| D12 | Managed groups **after the standalone kinds, in registry order**. **Revised 2026-10-24 (owner):** each manager is a top-level level of its own, not a group inside "Other tools"; the popover reaches them through "Other tools"' tool groups page (§5). **Revised again 2026-10-24 (owner):** the managers' levels sit right under Homebrew — the same kind, one manager and its many packages — and before "Other tools"; on the popover's page their groups come first too | interleaved after each manager's own row |
| D13 | go latest: **`go list -m -json <mod>@latest`** (honours GOPROXY/GOPRIVATE, skips retracted) | direct proxy HTTP |
| D14 | asdf: **not onboarded** | onboard |
| D-A | A newly scanned manager's current offers are **announced once** | silent first pass |
| D-B | duo JSON: **schema stays 2**, `tool: "managed"` + new `manager` key | schema 3 |
| D-C | bub's uv-tool/pipx venvs **fold into the managed rows in P2**; `BubProvider` keeps only bub's own installer method | keep `BubProvider` as is |

**D15 (owner, 2026-10-27): stop it, as a terminal's Ctrl-C would, but only where nothing can be damaged.** Built as §13.4: the command's writes are cloned before it starts and put back after a stop, so every stage is a safe one for a manager whose writes are measured; one whose writes cannot be covered keeps running to completion.

## 12. Needs verification before implementation

Each: the check to run, in an isolated home.
1. **mise from a GUI cwd `$HOME` with an untrusted config**: `env -i HOME=$ISO PATH=/usr/bin:/bin $ISO/.local/bin/mise ls --json` and `outdated --json` with an untrusted `$ISO/mise.toml` — does it prompt, skip, or fail? (MISE could-not-verify #7.) Decides D3.
   **Done 2026-10-23** (mise 2026.10.7 linux-x64, isolated home, stdin `/dev/null`): a `~/mise.toml` with only `[tools]` is read with no trust asked; one with `[env]` makes `ls --json` from `$HOME` fail — `mise ERROR Config files in ~/mise.toml are not trusted.`, exit 1, nothing on stdout. **`mise install -y` / `upgrade -y` run from `$HOME` trust it**: they wrote `~/.local/state/mise/trusted-configs/<home>` and installed its request. From `/`: only the global config is read (not `~/mise.toml`, not `~/.tool-versions`), and `install -y` / `upgrade -y jq` wrote no trusted-configs. → D3's fallback, cwd `/`.
2. **mise token retry string on backend installs**: with the anonymous budget spent, `mise upgrade -y jq` (aqua) and `github:BurntSushi/ripgrep` — is "No GitHub token was found" printed as for self-update (INT-80)? Decides whether `ManagedTokenRetry` applies.
   **Done 2026-10-24** (mise 2026.10.15 macOS, real home, anonymous budget spent): on default settings neither backend reaches the API, so no 403 and no marker; with `MISE_USE_VERSIONS_HOST=false`, `github:` ripgrep fails with the marker and the retry with `MISE_GITHUB_TOKEN` succeeds, while aqua jq exits 0 with nothing upgraded and no marker. `ManagedTokenRetry` applies to `github:` installs. Details and the aqua follow-up: status log, 2026-10-24.
3. **mise `upgrade -y` and PATH needs**: `env -i HOME=$ISO PATH=$ISO/.local/share/mise/shims:$ISO/.local/bin:/usr/bin:/bin mise upgrade -y npm:prettier` and `pipx:ruff` (MISE-76): do npm/pipx backends find node/uv? Record the exact PATH prefix needed.
   **npm done 2026-10-23**: with `"npm:prettier" = "2"`, `PATH=/usr/bin:/bin` alone (no node anywhere on it) upgraded 2.0.0 → 2.8.8 — 2026.10.7 runs its own node. The shims and `~/.local/bin` still lead `PATH` (§4.1). pipx not measured.
4. **Timing**: wall time of `mise ls --json`, `outdated --json`, `outdated --bump --json` warm and cold (**mise done 2026-10-23**: 15 ms; 520 ms cold / 15 ms warm; 194 ms / 17 ms, three tools); `uv tool list --outdated` with 10 tools; `go list -m -json X@latest` per module — all must fit the 15 s rule.
5. **mise default `minimum_release_age` in `outdated`**: observe on a release <24 h old (MISE-30 narrow measured only 400d).
   **Done 2026-10-27** (mise 2026.10.19 macOS, isolated home, cwd `/`, `github:jdx/mise` installed at 2026.10.19 while 2026.10.20 was 10.5 h old): with the default, `outdated --json` and `outdated --bump --json` are `{}` for both an exact request and a `"2026"` prefix, `latest` says 2026.10.19, `ls-remote` warns "1 newer … release hidden by minimum_release_age", and `upgrade --dry-run` says "All tools are up to date" with a WARN naming the release and when it becomes eligible. With `MISE_MINIMUM_RELEASE_AGE=0s` (the docs' off value; `=0` changed nothing) or `MISE_MINIMUM_RELEASE_AGE_EXCLUDES=github:jdx/mise`, `outdated` reports `latest: 2026.10.20` (after `mise cache clear` too). The adapter sets neither and reads `outdated`, so a mise tools row is offered exactly when the user's own `mise upgrade` would move it; no change needed.
6. **pyenv/rbenv Homebrew definition paths**: `ls "$(brew --prefix pyenv)/plugins/python-build/share/python-build" | wc -l` and `ls "$(brew --prefix ruby-build)/share/ruby-build" | wc -l` on a real `brew install` (reviewer used fixtures; could-not-verify #6).
7. **Signatures of keg/pkg manager binaries**: `codesign -dv --verbose=2 /opt/homebrew/bin/{fnm,go,pyenv,rbenv,pipx}` and `/usr/local/go/bin/go` (if present); decides how D5's keg rule is implemented (path-under-Cellar vs signature).
8. **`pyenv install` from a bare env**: `env -i HOME=$ISO PYENV_ROOT=$ISO/.pyenv PATH=/opt/homebrew/bin:/usr/bin:/bin pyenv install 3.12.15` succeeds (PY-33 "without brew not tested"); measure duration for the deadline.
9. **`~/.cargo/bin/cargo` proxy under a bare env**: `env -i HOME=$H CARGO_HOME=$ISO/ch RUSTUP_HOME=$HOME/.rustup PATH=/usr/bin:/bin ~/.cargo/bin/cargo install --list` and `cargo install tokei --features yaml` (CARGO could-not-verify "proxy under a GUI process"); confirm the proxy resolves the default toolchain without `PATH`.
10. **cargo `--features` re-application**: `cargo install tokei --features yaml` over an installed 14.0.0 (no features) → verify `.crates2.json` records `["yaml"]` and `tokei --version` shows yaml (CUPD-03 did this via cargo-update; do it with plain cargo).
11. **PyPI JSON caching**: `curl -sI https://pypi.org/pypi/ruff/json | grep -i 'etag\|cache-control'` and a conditional GET → 304? Decides whether pipx's per-venv requests revalidate cheaply.
12. **`CHANGELOG_V22.md` structure**: fetch and confirm a parsable heading per version (`## 2026-10-21, Version 22.23.4 'Jod' (LTS), @…`) for the Node notes parser; same for `CHANGELOG_V24.md`.
13. **`go list -m` under `GOTOOLCHAIN=local` with GOENV file**: `env -i HOME=$HOME GOTOOLCHAIN=local /opt/homebrew/bin/go list -m -json mvdan.cc/gofumpt@latest` from `/` honours `~/Library/Application Support/go/env` (GOPROXY=goproxy.cn) — check the `-v` log hostnames.
14. **`uv tool upgrade` for a range at its top** prints exactly "Nothing to upgrade", rc 0, stderr only (UV-24 observed once) — the parser's no-op signal; and `uv tool upgrade` of an unpinned tool with a receipt `exclude-newer` keeps the receipt byte-identical when no flag is passed (UV-17 inverse).
15. **nvm `~/.config/nvm/versions/node` real layout** on this Mac (`ls ~/.config/nvm`) — the second root the scan will read.
16. **Scan cost**: measure `scanAll` wall time before P1 and after P3 with `log stream --predicate 'subsystem == "…"'` on the "cli-tools" lane; target: no measurable change on a popover open (≤ a few ms).
   **Done 2026-10-27** (after P4, real home, release build, a throwaway Swift Testing probe calling `CLITools.inProviderOrder(…) { $0.scan() }` as `scanAll` does; 30 alternating rounds, warm): the 30 standalone providers alone median 2521 ms (p90 3425, 2192–3844); with the 10 managed providers too, median 2716 ms (p90 3978, 1986–6645) — the two ranges overlap, the difference is within the noise. Alone (15 rounds each): mise 369 ms, uv Python 71, cargo 13, pyenv 6, rbenv 4, the rest under 1 ms. mise's is `MiseScanner`'s signature check of the 138 MB `~/.local/bin/mise`, which the standalone mise row's scan also does; they run side by side, so it is not on the critical path. The 2.5 s floor is the standalone tools' own (not looked into here). Every popover open runs this scan (`CLIToolsModel.onOpen`), off the main actor.
17. **`pipx` binary target**: `readlink -f ~/.local/bin/pipx` and the shebang's interpreter signature — input to D5(b).

---

## 13. Cancel and Cancel All: every adapter measures for real

Owner requirement (2026-10-23): every managed row supports all four of update, Update All, Cancel and Cancel All, in the app and in duo. **The agent that implements an adapter tests its cancel on the real machine.** Reading the code or the vendor docs does not count as that test.

### 13.1 What managed rows inherit from main (no new mechanism)

Managed providers run through the same run path as every CLI row on main. Each row's update is its own `InstallJobs` job (`CLIToolsModel.jobID`).

- **Cancellable:**
  - waiting its turn in `CLIRunQueue`;
  - queued in a lane under Update All;
  - everything the provider does before the vendor command: re-scan, busy gate, trust check, and any network read or read-only spawn.
- **Commit point:** the vendor command's launch (`InstallCommit` in `CLIToolCommandRunner`). From there:
  - the Cancel greys out ("Installing — can't cancel now");
  - the command runs to completion (`.runToCompletion`);
  - the wrap-up runs whole: re-read, `settle`, re-check.
- **Cancel All:** queued rows are dropped, rows still preparing are cancelled, rows already running finish. The popover summary counts "N cancelled".
- **Cancelled is not failed:** no red line, no failure log, no re-check, not counted as updated.
- **duo:** Ctrl-C counts the tools it kept from starting as cancelled; a command already started finishes (`plans/update-cancellation.md` §7).

**What each adapter must do itself:**

- Every pre-command step must answer cancellation:
  - a read-only spawn uses `.terminateChild`;
  - a fetch uses the cancellable session path;
  - a sleep loop follows the `cancel-ok` rule (the source-scanning test enforces it).
- An update that runs the vendor command twice (mise's token retry, §3.1) has two commit points. A Cancel that lands between the two runs keeps the second from starting, as main already does for uv, bun and mise.
- Until D15 is decided, no adapter uses anything but `.runToCompletion` for its vendor command. With D11 that means **Cancel All does not stop a pyenv/rbenv compile or a cargo build that has started**: the popover stays "Updating…" until it ends. State this in the row's facts ("can't be cancelled once the build starts").

### 13.2 Real-machine cancel tests (part of every phase's acceptance)

These run per adapter, where §8.1 says (the real home, put back after, for the app and `duo`), against `make install`'s app and the installed `duo`. Paste every command and its raw output into the PR, with a before/after `stat` of the manager's root.

| # | Case | Expect |
|---|---|---|
| C1 | Cancel a row while it waits behind another lane's long update under Update All | never runs; row released; counted cancelled; root unchanged |
| C2 | Cancel a row during its pre-command stage | same as C1; no spawned child of ours left (`ps -o pid,pgid,command`) |
| C3 | Cancel a row after its vendor command started | button greys; command completes; row settles to updated (or to the vendor's failure); no red line from the cancel |
| C4 | Cancel All with one queued, one preparing, one running | summary counts match; the running one completes |
| C5 | `duo install <manager>/<item>`, Ctrl-C before the command and again during it | first: reported cancelled, exit as §7; second: command finishes, tally correct |
| C6 | Re-check after each case | state agrees between app and `duo check --json` |

Say how each window was held open long enough to click (for example, a long update in front in the same lane, or the check pointed at a slow local endpoint), so the test can be repeated.

### 13.3 D15 measurements: what each vendor leaves when interrupted

This is input for the owner's D15, measured for each adapter. In an isolated root, start the adapter's exact update command. Send SIGINT, then in a second run SIGTERM, to its process group at each stage the vendor has:

1. download;
2. build or extract;
3. the final install / link / receipt write.

Record for each run:

- the exit code;
- whether the old version still works;
- what partial new state is left (directory, venv, receipt, `.crates.toml` / `.crates2.json`, `pipx_metadata.json`, mise `installs/` and purgatory, nvm/fnm version dirs, pyenv/rbenv `versions/`, Go binary);
- whether the next plain run of the same command recovers by itself.

None of the following has been verified. Each is an assumption to test, not a fact to build on:

- cargo builds in a temporary target dir and replaces the binary only at the end;
- python-build and ruby-build remove a failed install dir;
- `uv tool upgrade` syncs the venv in place;
- nvm and fnm extract into the final version dir.

Deliverable: one table, manager × stage → {safe to stop / leaves X / breaks Y}.

**mise, measured 2026-10-23** (2026.10.7 linux-x64, isolated home, `mise upgrade -y node` from 22.1.0 to 22.23.4, signal sent to the process group 0.6 s and 2.8 s in):

| Stage | SIGINT | SIGTERM | Old version | Left behind | Next plain run |
|---|---|---|---|---|---|
| download (0.6 s) | exit 130 | signal 15 | runs (v22.1.0), still the request's | half-written `installs/node/22.23.4` (no `bin/node`), `downloads/node/22.23.4`; not in `mise ls` | completes it (exit 0, v22.23.4, download removed) |
| extract (2.8 s) | exit 130 | signal 15 | runs | the same | completes it |

The final link/purgatory write was not hit separately (the whole install took ~3.5 s). On this evidence mise is (b)-eligible for download and extract; D15 stays (a) until the owner rules. The owner then decides D15 for each manager:

- (a) keep `.runToCompletion` (today's rule);
- (b) allow `.terminateChild` in named stages only (e.g. a compile), with the row's Cancel live during them and greyed again at the stage that writes.

Until then, (a) holds everywhere.

**Ruled 2026-10-27, and neither:** the owner's words, "可以终止，用户如果命令行同样可以，要保证在可终止处终止，而不会损坏 anything" — stop it as a terminal would, but never leave anything damaged. Stages read from the vendor's output cannot promise that: the line arrives after the vendor has moved on, and the gap is a race. Freezing the group to look (SIGSTOP) crashes the app (`swift-subprocess` traps on a stopped child, 2026-10-23). §13.4 makes every stage safe instead.

### 13.4 D15 as built: snapshot, Ctrl-C, put back

- **Before the command** (`ManagedProvider.update`, only for an adapter whose `interruption` names its writes): `ManagedSnapshot.take` clones each named path with `clonefile(2)` (`CLONE_NOFOLLOW`; a directory in one call, metadata only) into an `itemReplacementDirectory` on its volume, records the paths that do not exist yet and their nearest existing ancestor, and lists each `NewEntries` rule's directory (entries a run names itself: cargo's `bin/cargo-install<random>/`, a new version's extra entry-point links, uv's new patch directory). A path that cannot be cloned (another volume) → no snapshot → the command runs to completion as before. The command gets no `TMPDIR` of ours: its temporary files go where they went before D15 (the owner's ruling after review 5, below).
- **The command** runs outside any commit (`interruptibleRunner`), so the row's Cancel stays live. A cancel sends SIGINT to its process group (`ManagedStop`; the child leads its own group, its compilers and `make`s are members) and to every other group of its session (mise's `node`, below) — the vendor's own interrupt handling runs — then, counted from the stop and whether or not the child itself has exited, SIGTERM at 30 s and SIGKILL at 45 s to whatever is left (review round 1: the ladder had only started once the child had exited, so a child ignoring SIGINT ran on to its deadline). The run returns only once no member is left. At 60 s it gives up: nothing is put back under processes still running, the snapshot is kept, and the row fails with where it is ("…, so nothing was put back; what was there before is kept in <dir>"). A deadline stops it the same way.
- **After a stop**: `restore` swaps each clone back in with `renamex_np(RENAME_SWAP)` (the path is never missing), removes each path that did not exist and the empty directories the run made above it, and removes each new entry a `NewEntries` rule matches. The row says "stopped; <manager>'s changes were put back" (`CLIToolUpdateOutcome.stopped`), or what could not be put back.
- **After it finished**: the clones are dropped and the result is taken inside `InstallCommit` (the Cancel greys). A cancel that lands between the exit and that commit is refused by the commit and puts the update back like a stop: a cancel means "not updated" whenever it is answered.
- **What it does not cover**: a write by something else into the same shared files while a run is stopped — another `cargo install` into the same `CARGO_HOME`, another mise or Python install, a user's own `pipx install` linking into `~/.local/bin` the same second — is undone with it. The app runs one CLI update at a time; this is about runs outside the app.

Measured (2026-10-27, isolated homes, the adapters' own argv and environment; 41 SIGINTs across early, download, build/extract and the final write/link, each followed by the snapshot's restore and a byte-for-byte comparison of the state):

| Manager | What `interruption` names | Stops that left state changed (before restore) | After restore |
|---|---|---|---|
| go install | `<GOBIN>/<name>` | k3: new binary already renamed in (exit −2) | identical |
| cargo install | the package's `bin/<each>`, `.crates.toml`, `.crates2.json`; new entries of `bin/` | c6, 0.03 s after "Finished": `bin/cargo-installH2vysO/tokei` | identical once new `bin/` entries are removed (the first plan, without that rule, left it) |
| uv tool upgrade | the venv whole; its links in `~/.local/bin`, and new ones into it | u3: new `bin/ruff`, old dist-info gone, `.tmp` in the new one | identical |
| uv python upgrade | the directory's links (minor links), `.temp`, links in `~/.local/bin` into it; new `cpython-*` entries and new links | p4/p5/p7: new patch renamed in, neither link moved | identical |
| pipx upgrade | the venv whole (metadata and `pipx_unfinished` inside); its apps' links | x4/x5: half-changed venv, old metadata, marked unfinished | identical (`logs/cmd_<time>.log` stays, a log) |
| mise upgrade | `installs/<tool>`, `installs/.mise-installs.toml`, `downloads/<tool>`, `shims`, `state/tool-purgatory.json`, `state/incomplete-installs` | m5: "✓ installed" printed after the SIGINT, exit 130; m7: old version in purgatory for removal in 24 h | identical |
| nvm install | `alias`, `.cache/locks`; new entries of `versions/node` | i3: `.cache/locks/v22.23.4` (without restore the next run waits 600 s on it); i4: version dir without the old globals; i5: same, **exit 0** | identical |
| fnm install | `node-versions/.downloads`, `aliases`; new `v*` in `node-versions` | i3/i4/i7: `.downloads/.tmp<random>` (never removed by a later run); i6: version renamed in whole | identical |
| pyenv install | `shims` (with `.pyenv-shim`), `version`; new entries of `versions` | i1–i5: nothing in the root (python-build's trap removes the prefix), 110 MB build dir in `TMPDIR`; i6, in the rehash: **the finished 3.12.16 deleted**, no lock left | identical |
| rbenv install | `shims` (with `.rbenv-shim`, which never expires), `version`; new entries of `versions` | i1–i4: nothing in the root, 150 MB in `TMPDIR`; i5, in the rehash: the finished 3.4.12 deleted | identical |

**On the Mac (real home, 2026-10-27, `make install` + `make cli` from this branch; the app driven in the background by computer-use's `app_*` tools and AX presses):**

- C5, `duo install cargo/tokei --yes` (tokei 14.0.0 `--features yaml` planted first), Ctrl-C written to its pty 3 s into "Compiling": `stopped; cargo install's changes were put back — not updated`, "0 installed, 0 failed, 1 cancelled", exit 130, 0.3 s after the ^C; `bin/`, `.crates.toml`, `.crates2.json` byte-identical (path, type, mode, size, sha256, link target), tokei still 14.0.0, no cargo/rustc left, no `duo-managed-*` scratch left.
- C3 (new meaning: the Cancel stays live while the command runs), tokei in the app: Cancel enabled beside "Compiling core-foundation-sys"; pressed → the row back to Update, no red line; the same three byte-identical.
- mise node 20.10.0 → 20.20.2 in the app, Cancel ~2 s in: **the first round left `installs/node/20.20.2` and `downloads/node/20.20.2` behind, with the row saying nothing.** Two causes, both fixed: (1) the plan snapshotted `item.installPath`, which at the click is `mise ls`'s `install_path` — the version's directory (`installs/node/20.10.0`), not the tool's — so neither the new version nor its download was in the snapshot; the unit fixture had used the scan's shape. The plan now takes the directory under `installs/`, and `ManagedInterruptionTests` runs both shapes. (2) The incomplete put-back was invisible: a cancel that stops something shows no line. `.stopped` now carries `complete`, the row and `duo` treat an incomplete one as a failure, and every stop is logged (`install`: "managed <identity>: stopped; …"). The same trace showed mise starting `…/installs/node/20.20.2/bin/node` **after** the SIGINT, in a group of its own (pgid = its pid, ppid 1 once mise had gone): The command now runs in a session of its own (`ChildProcess`'s `newSession`, `setsid`), and `ManagedStop` finds its members by session id — kept by every descendant whatever group it starts and whoever its parent becomes — signals each group once and waits for all of them; `aDescendantInAGroupOfItsOwnIsStoppedAndWaitedFor` holds a perl grandchild doing exactly that. (A first fix tracked descendants by parent link every 20 ms; under the full test suite's load the parent exited before the list caught the grandchild — review round 1's unverified point, seen in `make test`.)
- After the fixes, four rounds in the app (Cancel 0.6, 1.0, 1.6, 2.4 s after it appeared): each "stopped; mise tools's changes were put back" 0.27–0.56 s after the press, each byte-identical over `installs/node`, `.mise-installs.toml`, `downloads/node`, `shims`, `state/tool-purgatory.json`, `state/incomplete-installs` (5,567 entries). Then one-clicks with no cancel: mise node → 20.20.2, `duo install cargo/tokei` → 15.0.0.
- **The rounds above ran on builds before the session change** (the 20 ms parent-link tracker, `7cf4459c`/`6ad51aa`). Review round 2 asked for a record of the build that ships, since running the command as a session leader changes what a vendor does: mise's `should_use_pgroup()` is false when mise leads its session (`crates/mise-util/src/cmd.rs`, read by the reviewer at `v2026.10.15`), so it no longer puts its children in groups of their own.

**On the Mac again, on the session build (`3625bb49`, 2026-10-27, `make install` + `make cli`; app driven in the background):**

- A session probe beside each run (every 50 ms: the command's descendants by parent link, each one's `getsid`) and a direct check: 20 children started through `ChildProcess(newSession: true)` each reported `getsid == getpgid == pid`.
- mise node 20.10.0 → 20.20.2 in the app, Cancel 0.6, 1.6 and 2.4 s after it appeared: each "stopped; mise tools's changes were put back", 0.29–2.57 s after the press, byte-identical over the 5,567 entries. mise was its session's leader (`sid == pid == pgid`); its post-install `node` sat in mise's own group (pgid = mise's pid), not in one of its own, as the reviewer read from mise's source. One probe read mise's sid as 1, once, and could not be reproduced (the 20-run check above); taken to be a read as mise exited — not verified.
- cargo, tokei 14.0.0 → 15.0.0 in the app, Cancel 2 s into "Compiling": stopped 0.17 s after the press, `bin/`, `.crates.toml`, `.crates2.json` byte-identical. 148 descendants seen (rustc, build scripts): every one in cargo's group, and every one either in cargo's session or already gone when read (`ESRCH`) — none in another session.
- C5 (`duo install cargo/tokei`, Ctrl-C 3 s into "Compiling") also re-run on the session build: "stopped; cargo install's changes were put back — not updated", exit 130, byte-identical. Then plain runs: mise node → 20.20.2 and tokei → 15.0.0, both back where they were.
- Found on the way, not D15's: a mise tool whose only installed version is in mise's purgatory (`scheduled_for_pruning`, as after `mise upgrade` and a later `mise uninstall` of the new version) has no row at all (`MiseToolsLs.isRow`), so the whole group can vanish. Left for a follow-up.
**Review round 3, the evidence it asked for, and two local adversarial reviews (Opus, one risk each), 2026-10-27:**

- Measured: `getsid` from another session reads a live process's session (20 children × 5 reads, all `== pid`), and gives ESRCH for an exited one, zombie or reaped — so the once-read "sid 1" was not that; it matches the app's own read-only `mise ls --json` at the click (the app's session is 1, that child's pgid its pid), which the probe took for the leader. XNU (`bsd/kern/kern_fork.c`, apple-oss-distributions/xnu main) allocates pids upward from the last, wraps at `PID_MAX` to 100, and skips any id still used by a process, a group or a session (`phash_find_locked`, `pghash_exists_locked`, `session_find_locked`); this Mac used 860 pids in 45 s. `proc_pidinfo(PROC_PIDTBSDINFO)` fails with EPERM, as uid 501, on root's processes; `sysctl(KERN_PROC_PID/ALL)` reads them — the table is now read that way (`aMemberRunningAsAnotherUserIsSeenAndStopped`, with setuid `/usr/bin/top`).
- Measured (isolated homes, a session probe beside each full run): go, uv tool, uv python, nvm (npm included), fnm, pyenv and rbenv kept every descendant in the command's session. **pipx 1.18.4 does not**: it starts its uv/pip with `start_new_session=True` (`pipx/util.py`), stops that group itself on an interrupt (`fanout.stop_process_group`, SIGTERM), and its own comment says a grandchild can outlive the group's leader. Now: a process whose parent is a member and that leads a session of its own adds that session (`adoptSessions`, every 100 ms, 20 ms when stopping); such sessions get only the ladder's SIGTERM/SIGKILL, not the SIGINT (they are the member's to stop). With the real pipx in an isolated home, Cancel at 0.4/0.8/1.2 s: uv's session seen each time, none of it alive when the run returned, "stopped" each time.
- Fixed from the adversarial reviews: the ladder no longer runs past "gone" (a session or group leaves the followed set the first scan that finds it empty, and nothing is signalled once all are gone — a harness showed the 30 s SIGTERM reaching a session that reused the id); an unreadable process table counts as "still running" (it read as "none left"); a fork-and-exit chain that a table read followed by `getsid` misses is caught by asking each group seen with `killpg(group, 0)` (6 in 6 misses in review; `aForkAndExitRelayIsWaitedForAndKilled`); the wall-clock start-time filter is gone (redundant with the above, and a clock stepped back hid members); a cancel that lands after the command finished, while something it started still runs, puts nothing back (the update stands, the snapshot is kept, the row fails saying so); a stuck stop is never followed by mise's token retry; a kept snapshot has `paths.txt` naming each clone. The ladder runs on a thread of its own and repeats SIGKILL every 100 ms past `killAfter` until nothing is left: under a loaded test pool a `Task.sleep`-timed ladder once let a SIGINT- and SIGTERM-proof command run on to its 20 s deadline. Plans widened: mise, upgrading `python`, also snapshots every `installs/pipx-*` (mise reinstalls all `pipx:` tools against the new Python, `src/cli/upgrade.rs` at v2026.10.19) and the global `mise.lock` (made exact in round 5); pipx snapshots `shared/` (refreshed by `check_upgrade_shared_libs` when over 30 days old). cargo's `bin/` rule was narrowed to its `cargo-install*` staging directories here, and widened back in round 4 (below).
- On the Mac again after these fixes (the build that ships, `duo`): cargo tokei 14.0.0 → 15.0.0, Ctrl-C 3 s into "Compiling", and mise node 20.10.0 → 20.20.2, Ctrl-C 2 s in: each "stopped; …'s changes were put back — not updated", exit 130, byte-identical; then both run through to 15.0.0 and 20.20.2.
**Review round 4 (`fe955b1`), one blocking finding and one unverified claim, fixed in `303b7f4f`:**

- A Cancel landing between the runner's own check and the spawn (before `onLaunch`) ran a scan with nothing followed yet, which latched "gone": the child then got no SIGINT, ran to its end, and the put-back ran at once. A regression from the "gone" latch above. Now a scan before the launch drops and latches nothing, and a scan drops only the sessions it looked for (one `launched` or `adoptSessions` added meanwhile stays). `aStopAskedForBeforeTheLaunchReachesTheChild` interrupts first, then spawns `sleep 20`: it dies of SIGINT; with the old scan it ran its 20 s.
- cargo: a new binary name the newer version adds, left behind once the records are put back, is claimed by no package, and cargo refuses every later `cargo install` of that crate — `find_duplicates` lists any existing destination file, and an unclaimed one goes to `bail!("binary `X` already exists in destination … Add --force to overwrite")` (`src/ops/common_for_install_and_uninstall.rs`, rust-lang/cargo master, read 2026-10-27). So every new entry of `bin/` is removed again (`any: true`): a binary another `cargo install` added during the run is removed along with its record, which the known limit below already covers; the narrow rule broke the package itself with nothing else running.
- Checked for the claims it listed: swift-subprocess 1.0.2 sets `POSIX_SPAWN_SETSID` for `createSession` alone (`Subprocess+Spawn.swift`; the fork-first path only with `processGroupID` too), and XNU applies it inside `posix_spawn` (`setsid_internal`, `bsd/kern/kern_exec.c`), so the child leads its session before `onLaunch`. Measured on this Mac: a group holding only a zombie gives `killpg(g, 0)` EPERM (kept until reaped), ESRCH after the reap; `getsid` on a zombie gives ESRCH; `getsid(1)` and a root daemon's read their sessions as uid 501.
- On the Mac on `303b7f4f` (`make install` + `make cli`, the app driven in the background): mise node 20.10.0 → 20.20.2, Cancel at 0.6/1.6/2.4 s, and cargo tokei 14.0.0 → 15.0.0, Cancel ~2 s into "Compiling", in the app; `duo install cargo/tokei` with `^C` 3 s into "Compiling" (exit 130). Each "stopped; …'s changes were put back" and byte-identical. Then both ran through to 20.20.2 and 15.0.0 with `duo`.
- On the Mac on `0cb2f7ab` (rounds 4–5): cargo tokei in the app, Cancel ~2 s into "Compiling", stopped 0.19 s after it, and `duo install cargo/tokei` with `^C` at 16.12 s (exit 130): both byte-identical. mise was not rerun — the change since touches only its lockfile paths, and this Mac has no `mise*.lock`.
**Review round 5 (`303b7f4`), the same latch by a narrower path, fixed in `b723b6e0`:** a scan read the process table first and checked the launch after, so a Cancel whose table read predated the spawn, with the launch landing before that scan took the lock, dropped the child's session and latched "gone" again (it needs the cancelling thread preempted between its `sysctl` and the lock). Every scan now reads the followed sessions first and the table after, and reads no table before the launch (`noTableIsReadBeforeTheLaunch`; the old order reads one).

Checked for the paths it listed as unverified: mise names a backend tool's directory by kebab-casing it (`tool_directory_name`, `npm:prettier` → `installs/npm-prettier` on this Mac), so `installs/pipx-*` holds — but round 6 found the other spelling: `pypi:` is the same backend (`backend_type.rs`: `"pypi" | "pipx" => BackendType::Pipx`), `reinstall_all` takes both, and a `pypi:` tool lives in `installs/pypi-*`, which the plan now snapshots too; and round 7 found the third: a registry shorthand whose backend is pipx (`yamllint`, registry `pipx:yamllint`) lives in `installs/yamllint`, so the plan now takes the directories `installs/.mise-installs.toml` records with a `pipx:`/`pypi:` backend (its `full`), and any it does not account for (`misePipxInstallsComeFromTheIndex`) — which covers `pipx-*`/`pypi-*` too, so the spelling rule went (round 8: no test pinned it, because it could not change a result); pipx's shared libraries are `PIPX_HOME/shared` unless `PIPX_SHARED_LIBS` says otherwise (`pipx/paths.py`). mise's global lockfile is `mise.lock` beside the global config, or `mise.<env>.lock` under `MISE_ENV` (`lockfile_path_for_config`, `src/lockfile.rs` at v2026.10.19) — there is no `config.lock` — and it is written through `.mise.lock.<random>` in that directory, then renamed (`:1893`). The plan now snapshots every `mise*.lock` there and removes a new `.mise.lock.*` (`0cb2f7ab`; `misePythonPutsThePipxToolsAndLockfileBack` writes both, and each fails without its rule).

**Local adversarial review (Opus, xhigh, one risk: "nothing is left" while a writer of the command lives), at `808bbd8b`, 2026-10-27, fixed in `10dac841`:**

- A table read followed by each entry's `getsid` can miss every link of a fork-and-exit chain (the listed one gone, the next not listed yet), and the session was dropped on that one scan and never looked for again. The survivor then moved to a group of its own (`setpgrp`), which no scan ever found: the put-back ran with it alive and writing (the review's runs through the production runner: 5 in 5 with a 2 ms relay, 3 in 5 with 20 ms; one fork-then-exit then a group change, 0 in 200 — reproduced here by the test below failing on the old stop). Now a session is dropped only after two scans in a row find none of it, and never while a group recorded for it is left (`groups` maps each group to its session; `killpg(group, 0)` asks about all of it at once). `aRelayThatMovesToAGroupOfItsOwnIsStillStopped` fails on `0a1abf60`'s stop; `oneEmptyScanDropsNoSession` and `aSessionWithAGroupLeftIsKept` each fail without their rule. A third rule (a member gone before its `getsid` counts through its listed group) was tried and dropped: it is implied by the group rule, and no test could tell it apart.
- mise's token retry started a second command over the same snapshot while the first run's process still ran (the failure path dropped `leftovers`), and a stop of the retry put back under it — the receipt was rewritten after the put-back. Now `leftovers` is carried on a failure too, and no retry follows a run that left processes (`aFailedRunWithProcessesLeftIsNotRetried`; each of the three mutations fails it). Whether a real mise run that fails on the token leaves a process was not checked.
- The runner's own `leftovers` computation had no test (a mutation to `false` passed all of `ManagedStopTests`); the test above covers it.
- Checked by the review, no finding (its probes, not rerun here): `exec` never makes `getsid` or `killpg(g, 0)` answer ESRCH (3,000 self-execs, 3.48 M polls); a Cancel before the launch with the launch more than `termAfter` later still delivers the SIGINT at the launch (a `trap '' INT` shell died of it within 2 ms); zombie-only groups are kept (EPERM).
- Widened known limit: a member that starts a session of its own and exits before the next scan (100 ms while running, 20 ms when stopping) leaves that session unfollowed — adoption needs the parent listed in the same scan.

**Local adversarial review 2 (Opus, xhigh, the same risk, on the fix `0a1abf60..10dac841`), 2026-10-27:**

- The two-miss rule and the group hold kept a session followed, but the verdict "nothing left" came from `alive()`, which still trusted one scan: one that missed every member while every recorded group was empty said none, and the run put back under a survivor in a group never seen (its probe through the production runner, a relay changing group on every 2 ms hop and ignoring INT and TERM: 2 in 10 on `10dac841`). Now `alive()` is no verdict while a session is followed: it looks again until the session is found or dropped. Looks back to back still let it through (2 in 20: both can fall inside the hops), so a second miss counts only from a read begun `missGap` (50 ms) after the one that counted the first — which also keeps two scans reading at once from counting one gap twice. The probe then: 0 in 40. Each part is pinned (`oneEmptyScanIsNoVerdictWhileASessionIsFollowed`, `overlappingScansCountOneMiss`, `missesCountOnlyAGapApart`, `nothingIsAliveBeforeTheLaunch` — `alive` now loops, and before the launch it would loop forever); each fails under its mutation, and the relay test fails only under the old rule whole (its comment claimed the first-miss half alone; it survives that). A normal exit now ends ~50 ms later: confirming "none left" takes two looks a gap apart (review 3 measured 108 ms median at `17632e30` — `alive` slept once more after the look that dropped the session; it no longer does: 52–63 ms, median 56, over 20 runs here).
- No finding on the group hold, the zombie (EPERM) rule, signalling a stranger, or the provider's no-retry rule (`aFailedRunWithProcessesLeftIsNotRetried` fails under its mutation).
- Widened known limit: a relay that changes group on every hop can still be missed by two looks `missGap` apart; it is a bound on timing, not a proof.

**Local adversarial review 3 (Opus, xhigh, one risk each, at `17632e30`), 2026-10-28 — untrusted input, the scratch `TMPDIR`:** no way across the same-user → root line (the scratch is made and removed as the user, under the user's 0700 temporary directory; nothing root touches it). Four functional faults this PR had made, fixed:
- A failed build lost its log: the scratch was removed on every end, and ruby-build writes its log there and says only "See the full build log at <that path>" (probe through the real update path: the message named a file already gone). Before D15 it went to `/tmp` and stayed. Now the scratch goes only after a stop, or a run that ended with none of it left; a failure keeps it, and so does a run that left processes (the review's probe: a leftover wrote into the removed scratch and made it again, never swept).
- `NSTemporaryDirectory()/duo-managed-<UUID>` was 97 bytes: a socket bound under it — sccache's `sccacheXXXXXX/sock`, cargo's `rustc-wrapper` — overflows `sun_path` (104 bytes; the review's bind probe: "AF_UNIX path too long"; sccache itself not run, not installed here). Now `mkdtemp` makes `duo.XXXXXX` there: 0700, never one already there, 59 bytes here.
- A scratch that could not be made left the run stoppable with none, so a stop left the tool's temporary files in `/tmp`; now the run is not stoppable then, as without a snapshot.
- No test pinned cargo's `TMPDIR`. Tests: `aFailedOrLeftBehindRunKeepsItsScratch`, `noScratchDirectoryMeansNoStop`, the cargo plan's `scratchVariables`; each of six mutations fails one.
- The off-pool lint caught this round's tests waiting on semaphores on the cooperative pool; they hop now, and so do the two async callers of `alive()`, which may sleep between looks.

**Local adversarial review 3, process-control (the stop at `17632e30`):** no finding that the stop says "none left" sooner than `10dac841` — the change only waits longer. Two rules no test pinned, now pinned by the review's tests ported here: `alive` looking until the session is found or dropped, not a fixed two times (`aliveLooksUntilTheSessionIsFoundOrDropped`: another scan finds the member between `alive`'s two looks), and a miss counting from the end of the read that counted the last, not its start (`aReadBegunDuringACountingReadCountsNoSecondMiss`); each fails under its mutation. The extra sleep above was its third.

**Local adversarial review 3, data-loss (what a stopped mise upgrade puts back, against mise v2026.10.19's source):**
- The global lockfile's dependency graphs live in `locks/` beside it (`graph.rs` `sidecar_root`); saving prunes the old version's after the new lockfile is written, so putting the lockfile back named a graph already gone. `~/.config/mise/locks` is now in the plan.
- A shorthand whose index entry has `explicit_backend = false` gets its backend from the registry at the upgrade, not from the index's `full` (`backend_arg.rs`): a python upgrade now takes those too (`jq` on this Mac).
- `command-wrappers`, which mise syncs with the shims, is in the plan.
- Where the user's settings move mise's writes out of the plan, the update is not stoppable and runs to completion: the identity layout, a `shims_dir`, `shared_install_dirs` (any TOML under `~/.config/mise` or `/etc/mise`), or a global lockfile that is a link (mise rewrites its target, `lockfile.rs`). mise runs in `/` (the default working directory), so no project config or lockfile in the home folder applies.
- Tests: the node put-back writes `locks/` and `command-wrappers`; the index test has a non-explicit `jq`; `miseIsNotStoppedWhereItsSettingsMoveItsWrites` (each setting) and `miseIsNotStoppedWhenItsLockfileIsALink`. Each of the ten mutations fails one. None of these setups is on this Mac: checked by source and tests only.
- Known limits, not fixed: every mise command first prunes other tools' purgatory entries that are due (`tool_purgatory::auto_prune`), outside the snapshot — a stop then leaves that version half removed while the put-back schedules it again; nothing the user kept is lost, and the next mise command finishes it. pipx tools under `/usr/local/share/mise/installs` are not taken (not present here).

**Local adversarial review 4 (Opus, xhigh, one risk each, on the fix `17632e30..f8b1211c`), 2026-10-28.** Judged by the owner's bar set the same day: D15 is a light backstop — a stop must not be worse than the vendor's own Ctrl-C, and what makes a stop possible must not make an update that is not stopped any worse. What fails the second is fixed; what only a stop in an unusual setup meets, where Ctrl-C would leave the same, is a known limit.
- Untrusted input (scratch): a deadline's stop (python-build or ruby-build past 20 min, cargo past 30) still removed the scratch and the log the row names — the review-3 fault on another path. A deadline's stop now keeps it like any failure (`RunResult.timedOut`, `aDeadlinesStopIsTimedOut`); an empty scratch goes whatever the end (`anEmptyScratchIsNotKept`: a run that never started left one); a stuck stop keeping it is now tested. No way across the same-user → root line. Each of five mutations fails one.
- Data loss (mise): rust and dotnet install into the shared rustup/cargo homes and `DOTNET_ROOT` by default, outside the snapshot; their upgrades are not stoppable now (`miseRustAndDotnetAreNotStopped`). Two test comments named mutations their tests no longer caught; corrected.
- Process control: no finding. The no-sleep `break` and the hops change only latency; no test pins them (it would need a clock).
- Known limits (not fixed, by the bar above): the settings check misses a linked `conf.d` (the enumerator does not enter linked directories) and quoted, inline-table and multi-line TOML spellings of the three settings — `mise settings set` writes the bare form, which is caught; `/etc/mise` is read on the host and not tested; a writable `/etc/mise/mise.lock` would be rewritten unsnapshotted; kept scratches are not swept by the app (one per failed run, the vendor's own leftovers — before D15 they went to `/tmp`); a daemon that calls `setsid` between two adoption scans is not waited for (unchanged from before); a session adopted while another scan latches "gone" can be missed (needs a 50 ms preemption inside a few-microsecond window).

**Local adversarial review 5 (Opus, xhigh, data-loss and untrusted-input, on `f8b1211c..861c680d`), 2026-10-28, by the same bar:**
- Review 4's `rmdir` took an empty scratch away from a run that left processes; one making a temporary file later then failed (its probe: `mktemp: mkstemp failed … No such file or directory`), where before D15 it used `/tmp` — an update not stopped made worse. And, from sccache's source (not run: not installed here), a clean cargo run whose `rustc-wrapper` starts an sccache server — it detaches at once, so no scan sees it stay — had the scratch removed whole under that server, failing the user's later builds while it lives. Now only a cancel's stop takes the scratch whole; any other end with nothing left takes it only if empty, and with processes left it stays even empty. A real-runner cancel is checked not to read as a deadline's stop. Each of seven mutations fails a test.
- Known limit: a `[tool_alias]` of another name for `core:rust` or `core:dotnet` installs under that name and stays stoppable. mise's other core plugins write inside their install directory by default (its grep of v2026.10.19).

**The scratch `TMPDIR` removed (owner, 2026-10-28, after `eeb45ed2`).** Review 5's fix still failed the second bar: after a clean cargo run that started an sccache server, the scratch is empty, so `rmdir` removed it under the server (PR review round 13, from sccache v0.19.0's source; a daemonix-like probe on `eeb45ed2` confirmed it, on a clean run and on a cancel). Each round of the scratch's keep/remove rules (reviews 3–5) had made an update that was not stopped worse in a new way: a deleted build log, a socket path too long, a folder pulled out from under a leftover process, and then a daemon. The owner chose to drop it. The command now gets no `TMPDIR` of ours, as before D15, and a stop leaves the vendor's temporary files where a Ctrl-C in a terminal leaves them: cargo's `cargo-install*` target (~440–450 MB, measured in the P4 status log entry), and python-build's or ruby-build's build directory or node's compile cache (110–150 MB). Gone with it: `scratchVariables`, `RunResult.timedOut`, the provider's `temporaryDirectory`, and the tests `aFailedOrLeftBehindRunKeepsItsScratch`, `noScratchDirectoryMeansNoStop` and `anEmptyScratchIsNotKept`. A review-4 known limit (kept scratches not swept) no longer applies. `aStoppedUpgradeIsPutBack` now checks that the command gets no `TMPDIR`, and `aDeadlinesStopIsAFailureNotACancel` that a deadline's stop is worded as a failure; each fails under its mutation (a `TMPDIR` set for the run; the reason always "stopped"). Local adversarial review 6 (Opus, xhigh, data-loss and regressions to updates not stopped, on `44ef48b4`): no finding — on main the managed child got no `TMPDIR` either (`ChildProcess` replaces the environment, `ChildProcess.swift:451-460`), and no put-back depends on a folder of ours. Real machine (2026-10-28, real home, `44ef48b4`): `duo install cargo/tokei`, `^C` at 14.27 s, exit 130 at 14.47 s; tokei in the app, stopped 0.23 s after the Cancel; both byte-identical. With no `TMPDIR`, cargo put its stopped `cargo-install*` target in the per-user temporary folder (`getconf DARWIN_USER_TEMP_DIR`, `/var/folders/…/T/`; 132 MB and 112 MB), not `/tmp` — the folder a terminal's `TMPDIR` names, so where a Ctrl-C leaves it; both were removed by hand. A full `duo install cargo/tokei` to 15.0.0 then left none.

- **Known limits, not fixed:** a stop leaves the vendor's temporary files where a Ctrl-C leaves them (above); caches are not snapshotted — mise's among them, where erlang keeps kerl (`src/plugins/core/erlang.rs`, PR review round 13); the snapshot covers the whole run, not only the moment of the stop — a change another process makes to the same shared files during the run (`.crates.toml` and new entries of cargo's `bin/`, mise's index and shims, pyenv's/rbenv's `shims` and `version`, uv's Python links) is undone with it; a daemon a member double-forks and that calls `setsid` after its parent has exited is not followed, nor a session a member starts and leaves within one scan interval; the repeated SIGKILL past `killAfter` was not seen to be needed.

- Not run on the Mac: the other eight managers' stops in the app (each is covered by the isolated-home measurements above and `ManagedInterruptionTests`); C4 (Cancel All with one running).

Every process group was empty 0.05–0.16 s after the SIGINT (mise mid-extract 1.06 s, the builds up to 1.47 s); none needed SIGTERM. 66 stops in all (41 + 25), every one put back identical. A SIGINT in a build's configure step exits 1, not 130; nvm's globals step exits 0 with the globals missing. With no `TMPDIR` of ours (since the owner's ruling after review 5), a stopped python-build, ruby-build or node compile cache leaves its files in `/tmp` under names no later run removes (110–150 MB per stopped build), as a Ctrl-C in a terminal does. Not measured: the two rehash lock windows (between creating the lock and arming its trap), a new version that adds shim names, xattrs/ACLs. Nothing was written outside the isolated roots (`~/.rustup` unchanged). Cloning mise's node installs took ~1 s per update. Exit codes do not say whether anything changed (go −2 with the new binary in place; mise 130 after "installed"; pipx −2 fully upgraded), which is why the snapshot, not the status, decides. `ManagedInterruptionTests` replays each row's measured mid-run writes against the adapter's plan, and every path and rule of a plan is written by them, so dropping any one fails it (review round 1 found six that were not: pipx's and uv's links, uv Python's new link, fnm's aliases, pyenv's and rbenv's `version`; each mutation now fails).

---

## 14. Status log

### 2026-10-23 — §0 and P0 written (branch `plan/cli-managers-redesign`)

**In:**

- `C/Managed/`: `ManagerID`, `ManagerDescriptor` (+ `ManagerContext`), `ManagedItem` (+ `ManagedRoot`, `ManagedScan`), `ManagedVerdict`, `ManagerAdapter` (+ `ManagedTokenRetry`), `ManagedCheck`, `ManagedProvider`, `ManagedActivity`, `ManagerRegistry` (empty).
- `CLIToolKind.managed` (last), `CLIToolStatus.identity`/`providerID`/`managedItem`/`updaterSpendsGitHubAPI`, `Detail.managed`, `Context.managed`, `CLIToolSighting.identity`/`name`, `CLIToolProvider.id`/`attributionName`; `CLITools.providers()` = standalone + registry.
- App: `CLIToolID` by identity (+ `providerID`); the three lookups and the two kind-keyed places from the INT note by provider id; `lane(of:)` arm; `managedContexts`; `CLIToolIcon` reads the descriptor; group title and header summary; `CLIToolPresentation.groups` by `manager|root`, generic managed facts, D7 row warning; 23 new catalog keys with translations.
- duo: `Row.manager/item/root/request/latestBeyondRequest/effects`, names `[key, manager/key, name]`, breaking key and job id by identity, provider by id, effects and "beyond the request" lines in the text output, `install` payload keys. Schema stays 2.
- Tests: Core `ManagedModelTests` (§3.2 table, provider seams, token retry, activity), `CLIToolsTests` order test, `CLIToolGitHubAPITests`; App `CLIToolsModelManagedTests` (identity across a moved directory, lane, pause, pinned, two managed providers), `CLIToolPresentationTests` (groups, facts, D7); duo `CLIToolRowsTests` (JSON keys, names, text).

**Decisions taken while writing (owner to confirm or reverse):**

- §3.2 row 1 reads as "the binary's trust takes the click away, never the verdict": an untrusted or missing binary leaves the state the comparison gave and withholds with `.wrongSigner`/`.unverified`/`.updaterMissing`; `.unverified` keeps the command to copy (D5.2, bub's rule). An adapter whose *check* needs the binary answers `vendorWouldUpgrade: nil` and the row is `.unknown` as the table says.
- The D2 fact ("newer beyond the request") is not written by `ManagedCheck`; the pane and `duo` derive it from `latestOverall` (`ManagedCheck.beyondRequest`). An adapter may still put `.beyondRequest` in `facts` with the exact command.
- `ManagedItem.Fact.default` is spelled `defaultAlias`.
- A new `Effect.cannotBeCancelledOnceStarted` carries §13.1's "can't be cancelled once the build starts" line.
- `CLIToolReport`'s default sightings keep `name: nil` so existing providers' scan and report still compare equal (the INT note's §3.3).

**Not in P0 (P1):**

- Any registered adapter. `ManagerRegistry.adapters` is `[]`, so nothing is visible in the app or `duo`.
- Naming the manager in the popover's "Updating …" head and in `CLIToolsModel.summary` (both say "Managed tools").
- D10's cap in `readBreaking`.
- The "no `ChildProcess` in any adapter's `scan`" source-scan test (§10): written with the first adapter.
- Logos for the new managers (`cli-pipx`, `cli-fnm`, `cli-pyenv`, `cli-rbenv`, `cli-go`): assets, per adapter phase.

**Acceptance:** written on Linux with no Swift toolchain; CI compiled and ran it on a Mac — swift, app, release and test jobs green on `a9e6c01` (run 39932065312, 2026-10-23). The Python gates passed locally first.

**Review round 1 (`a9e6c01`), three blocking findings, all fixed in the next commit:**

- D2: `ManagedCheck` set the unpin command only on `.pinned`, so a range held at its top had nothing for the pane's and `duo`'s "beyond the request … — command" line. Now `manualCommand` carries the unpin command on that `.upToDate` row too (nothing to copy: `commandToCopy` hands nothing out for a current row). The pane and `duo` tests build that row through `ManagedCheck` now, not by hand.
- A quarantined manager binary read "Not the build <signer> published". `ManagedItem.binaryTrust` (set by `ManagedCheck` from the root) lets the wording say "Quarantined, so not run", as every other kind does.
- `.runtimeTooOld` on a managed row read npm's "Needs a newer Node". The managed arm words it from the verdict's note ("the newest release needs rustc 1.85").

### 2026-10-23 — P1 written (mise tools)

**In:**

- `C/Managed/Mise/`: `MiseToolsAdapter` (descriptor, a `Host` seam for every read of the Mac, scan, check, upgrade, unpin, busy, re-read, notes, token retry), `MiseToolsLs` and `MiseToolsOutdated` (the parsers and the join of §4.1). Registered: `ManagerRegistry.all(home:)` = `[MiseToolsAdapter]`.
- Shared, found while writing the adapter:
  - `ManagerAdapter.resolve(_:)` (default: the scan): what only running the binary reads — mise's `--version` — once per check, so `scan` stays disk-only while the header and the purgatory effect still get the version.
  - `ManagerAdapter.current(_:in:)` (default: the scan's item): the click's gate. A mise row is a request, which only `mise ls` can name, so the scan's items are per tool directory and the click re-reads with `ls` (`.terminateChild`, before the commit point).
  - `ManagerAdapter.workingDirectory(home:)` (default `/`) and `CLIToolCommandRunner.run(workingDirectory:)`: the provider passed none, so a `duo install` from a project ran the vendor command in that project — for mise, against the project's config.
  - `ManagedCheck`: a row with nothing known whose root's binary may not run is withheld by that binary's trust (`.wrongSigner`/`.unverified`/`.updaterMissing`), not "channel unreadable" (§3.2 row 1).
  - `NotesSource.gitHubReleases` carries the tag prefix (jq tags `jq-1.8.2`).
- App: the popover names the manager ("Updating mise tools", `CLIPopoverRow.Line.updatingGroup`) and the item ("node updated to 20.20.2", `.updatedItem`), from `CLIRowSnapshot.Tool.groupTitle`/`itemTitle`; existing catalog keys. D10's cap: ≤5 managed documents per breaking-hint pass (`CLIToolsModel.managedBreakingDocuments`).
- Tests: `MiseToolsAdapterTests` over mise's raw output (`Fixtures/managed/mise/`, 2026.10.7), including the source test that `scan()` names no spawn (§10); a popover case in `CLIRowViewTests`.

**Decisions taken while writing — owner kept all four (2026-10-24):**

- D3's fallback (cwd `/`), on §12 item 1's measurement. A request in `~/mise.toml`, `~/.tool-versions` or a project is not a row.
- Notes: none for `core:node` (P3's `CHANGELOG_V<major>.md` parser), `pipx:` (P2's PyPI rule) and `asdf:` — an asdf id names the plugin's repository, not the tool's (the design listed it with github/ubi).
- Two requests of one tool: the one `mise outdated` names is answered; the other is `.unknown` with the reason. Both carry a note that one click moves every request of the tool.
- Offline (review rounds 3–4): mise prints `{}` to both reads and exits 0, and what it warns depends on the backend (`core:node` "Error getting latest version for node", aqua's jq only "Remote versions cannot be fetched for jqlang/jq") and on `quiet` (nothing). So a row the two maps leave out is current only once `mise latest <tool>@<request>` printed a version, and a pin is held only once `--bump` or `mise latest <tool>` named what lies beyond it; otherwise `.unknown`. Online `mise latest` answered in 14–400 ms; offline it printed nothing for every backend tried. A `mise latest` that hits the 15 s deadline stops the rest of that check.
- `CLIToolsModel.summary` (a log line) still says "Managed tools ×N".

**Owed before P1 is accepted** (as written 2026-10-23; outcome in the next entry):

- `make test` on a Mac (CI). Done: green on `11c6b58`.
- §8.1's real-machine acceptance and §13.2 C1–C6 with `make install`'s app and `duo` on a Mac. Done 2026-10-23/24, in the real home (an isolated one is not possible, §8.1); signature and quarantine re-read (Team `4993Y37DX6`, not quarantined).
- §12 item 2 (the token-retry marker on a backend install): done 2026-10-24. Item 5 (`minimum_release_age`): still owed.

### 2026-10-24 — P1 on the Mac, and the managers' own levels

**Mac acceptance** (`make install`'s app and `make cli`'s `duo`, in the owner's real home — `duo` and the app read `homeDirectoryForCurrentUser`, not `$HOME`, so an isolated home was not possible): rows, signature, one-click node, `duo` agreeing with the app, offline, C1–C6 all passed; results and raw output are in PR #1613's description. Not seen: the popover line "node updated to 20.20.2" (it shows only when nothing else under "Other tools" is outdated).

**UI, from trials on the Mac** (§5, D12 revised):

- Workbench: one top-level level per manager (`managerLevels`), with its own Update All (`OtherToolsUpdateAllButton(scope:)`) and counts; `SidebarSelection.cliOrder(managers:)` walks them last.
- Core: `CLIRowSnapshot.scoped(to:updateAllOffered:updateAllStartable:)` — a group's own snapshot, running only while Update All holds one of its copies.
- `CLIToolsModel`: `updateAll(in:)` (while another Update All runs, a group's click queues its copies one by one), `rowSnapshot(in:)`, `cancelRow(in:)`.
- Popover: the tool groups page (§5); a row opens the workbench on its tool; the empty list's placeholder icons share one 41 pt box (the magnifier drew 34 pt beside the seal's 39); "N updated" when more than one copy was just updated, where it used to name the first ("jq updated to 1.8.2" after three).

**§12 item 2, app side** (2026-10-24, `scripts/github_api_mock.py --scenario exhausted` + `DUO_GITHUB_API_MOCK`, `0b8568d8`): with the app's GitHub budget at 0, the gate holds mise tools back — popover "mise tools, Hitting GitHub's rate limit · 3 held back", the level "3 held back", jq's pane "Update: Hitting GitHub's rate limit" and its notes "Couldn't load the release notes · Hitting GitHub's rate limit"; `duo check --json` gives the three rows `withheld: rateLimited`. `DUO_GITHUB_API_MOCK` reroutes only DuoUpdater's own requests. mise's can be sent to the same mock with `MISE_URL_REPLACEMENTS='{"https://api.github.com":"http://127.0.0.1:18765"}'` (corrected after review round 14; an earlier version of this line said mise had no such setting). Measured that way (cache empty, no token): aqua jq and `github:` ripgrep both fail, exit 1, with a 403 from `http://127.0.0.1:18765/repos/…`, and neither prints the marker. That is by mise's design, not the mock's fault: `show_github_rate_limit_err` (`src/main.rs:216-224` at v2026.10.15) prints "No GitHub token was found" only when the error contains `403 Forbidden) for url (https://api.github.com` and `resolve_token` finds nothing. So the marker can only be measured against the real api.github.com, which was done apart:

**§12 item 2, mise side** (2026-10-24, mise 2026.10.15, owner's OK to spend this Mac's anonymous budget: 60 requests to `/repos/jqlang/jq`, the 61st refused 403). `mise token github` finds no token on this Mac, in the normal environment too, so mise's own requests here are anonymous. Every run below from `/` with `GITHUB_TOKEN`/`GH_TOKEN`/`MISE_GITHUB_TOKEN` unset and `MISE_GITHUB_GH_CLI_TOKENS=false`:
- Default settings (`use_versions_host = true`), cache warm or moved aside: `mise upgrade -y jq` (aqua) → exit 0, "jq 1.6 → 1.8.2", resolved in 0 / 460 ms, verified; `mise install -y github:BurntSushi/ripgrep@latest` → exit 0, 15.2.0. Neither touched api.github.com in a way that failed, and neither printed the marker: on default settings a spent budget does not stop these two backends.
- `MISE_USE_VERSIONS_HOST=false`, cache empty: ripgrep → exit 1, "(403 Forbidden) for url (https://api.github.com/repos/BurntSushi/ripgrep/releases?per_page=100)", "github auth: no", and the marker "No GitHub token was found" (1 line) — so `ManagedTokenRetry` applies; the same command with `MISE_GITHUB_TOKEN` (the `gh` token) → exit 0, installed. jq (aqua) → three 403 retries on `/releases/latest`, "GitHub rate limit exceeded", "Error getting latest version for jq: no latest version found", then "All tools are up to date" and **exit 0** with jq still 1.6, and no marker: no retry, and `ManagedProvider.update` would return `.updated(version:)` with the unchanged 1.6 (not run in the app).
- Cleanup: cache restored from its copy, ripgrep uninstalled (and its three dangling alias links removed), fixtures reset, config sha256 `23fa2ec4…` unchanged throughout.

**Still owed:** item 5 (`minimum_release_age`); nothing else. The aqua case above is done: the owner chose "not updated" over "no update available", and a run that exits 0 with the version unmoved is now `.failed` ("not updated: jq is still 1.6; …"), the row keeping its update and button (`a46d0b30`, unit-tested; not reproduced in the app).

### 2026-10-27 — P2 written and on the Mac (uv tools, pipx; branch `cli-managers-p2`)

**In:**

- `C/Managed/Uv/`: `UvToolAdapter` (receipts and dist-info on disk; `uv tool list --outdated` for uv ≥0.11.0 — review round 1: 0.10.10–0.10.12's `--outdated` asked for no Python, index or `exclude-newer` of the tool's (`list.rs` at 0.10.12) — PyPI below it or for a uv that may not run; `uv tool upgrade <name>`; `uv tool install <name>@latest` to copy for a pin), `UvToolReceipt`, `UvToolOutdated`.
- `C/Managed/Pipx/PipxAdapter`: both roots; PyPI per venv (≤8 at once); `pipx upgrade <venv>` one-click only through a Homebrew keg (D5.1), the command handed out to copy for a pip/uv-installed pipx (D5.2, worded "pipx is a script, with no signature to check"); `pipx unpin` to copy; D7's warning.
- `C/Managed/Python/`: `PythonVersion` (PEP 440 order), `PythonSpecifier` (`Requires-Python`), `PythonDistribution` (dist-info), `PyPIProject` (the JSON document, revalidated every time), `ProjectURLRepo` (§4.2's rule). `C/Managed/ManagedNotes` (GitHub releases, or a PyPI project's repository — mise's `pipx:` tools use it too, the P1 leftover).
- Shared: `ManagerDescriptor.versionOrder` (`.pep440` for the Python managers: `VersionComparator` reads `1.0.post1` as older than `1.0`); `ManagedCheck` withholds an offered row as `.updaterMissing` when the root has no binary (pipx's check needs none). D-C: bub's uv-tool/pipx venvs are those managers' rows; `BubScanner` looks at the installer's venv only.
- App: `cli-pipx` logo (the X of pipx's MIT `logo.svg`, as a template, tinted #00CBA3); managers' levels and the popover's tool groups in registry order (`CLIToolPresentation.managerGroups`) — with three managers they had followed the statuses' order, outdated first. One new catalog key with ten translations.

**Measured (uv 0.13.4, pipx 1.11.1/1.18.4; isolated homes unless said):**

- `uv tool list --outdated`: `name vX [latest: Y]` plus `- exe` lines; current tools left out; offline → exit 2, nothing on stdout (6.7 s, three retries). 0.39–0.46 s for three tools in the real home. Its latest is for the venv's Python (black 25.11.0 on 3.9, PyPI's 26.10.1 needs ≥3.10).
- §12 item 14: `uv tool upgrade` → "Nothing to upgrade" (exit 0, stderr) both for `>=23,<24` at its top and for `==0.6.0` (plus the `@latest` hint); an unpinned tool "Updated cowsay v5.0 -> v6.1"; an unknown one exit 1. Receipts unchanged by a no-op.
- §12 item 11: PyPI's JSON is `max-age=900` with an ETag; a conditional GET answers 304. Sizes: cowsay 14 KB, black 922 KB, ruff 6.2 MB (1.1 MB gzipped) — over the in-memory cache's ~2 MB item limit, so ruff's is fetched whole each check.
- pipx: `upgrade` drops `==` (`httpie==3.2.1` → `httpie`, 3.2.4), keeps a `pipx pin` ("Not upgrading pinned package"), leaves a path install alone (exit 0), exit 1 for an unknown venv. ≥1.15.1 keeps venvs in Application Support, 1.11.1 in `~/.local/pipx`.
- §12 items 7/17 (real home): Homebrew's `/opt/homebrew/bin/pipx -> ../Cellar/pipx/1.18.4/bin/pipx -> ../libexec/bin/pipx`, a script (`#!/opt/homebrew/Cellar/pipx/1.18.4/libexec/bin/python`), "not signed at all"; the keg has its `INSTALL_RECEIPT.json`. So the keg rule is a path rule: the keg's `bin/pipx` or `libexec/bin/pipx`, nothing else. Every venv it installed with uv on `PATH` recorded `backend: uv`.
- §13.3 (D15 input), SIGINT and SIGTERM to the process group:

| Manager | Stage | Exit | Old version | Left behind | Next plain run |
|---|---|---|---|---|---|
| uv tool upgrade (ruff, 9 MB) | resolve/download (0.5–2.6 s) | −2 / −15 | runs (0.6.0), receipt as before | nothing seen | completes it |
| uv tool upgrade | install (after "Downloaded", <50 ms) | not hit | — | — | — |
| pipx 1.18.4 upgrade (black, 4.2 s) | 0.3–1.5 s | 1 | runs (23.12.1), metadata as before | `pipx_unfinished` in the venv | "was left half changed by an interrupted pipx run; reinstalling it first", completes |

  (An earlier pipx run read as "breaks the venv" was the fixture: httpie 3.2.1 does not import with urllib3 2.8 before any signal.) Both stay (a) until the owner rules.

**Adversarial review (two Opus reviewers, one risk each) and what changed:**

- Fixed: a tool `--outdated` leaves out is current only when no stderr warning names it, it is not a pre-release and `~/.config/uv/uv.toml` does not say `offline = true` (uv also leaves out a tool whose environment is gone, exit 0); uv tools from a path, URL or git are not on an index; receipt `constraints`/`overrides` narrow the request (report-only, D9); uv 0.2.x string receipts and fractional `exclude-newer`; pipx `lock_file` (pipx won't upgrade), `pip_args` with index options or `--pre` (not asked of PyPI), `cooldown_days` (the cut-off), `--suffix` venvs (asked by package name); `PIPX_HOME` rides in the command (run as `/usr/bin/env PIPX_HOME=… pipx …`, handed out as `PIPX_HOME='…' pipx …` through the new `CLIToolCommand.shellLine` — review round 1: unquoted, "Application Support" split the pasted line), so the copied command acts on the same venv; for pipx's uv backend only a uv `UvScanner` trusts goes on `PATH` — never `~/.local/bin` as such, whose uv pipx would have run unverified; PEP 440 order in `ManagedCheck`; PyPI's newest is nil for an unknown Python and skips an all-yanked `info.version`.
- Not changed, for the owner (same-user changes to the user's own files are out of the threat model, 2026-10-25): `uv tool list --outdated` runs each tool venv's `bin/python` to read the interpreter on every check (the design's §4.2 chose it; the PyPI path avoids it at the cost of uv's own index options); the binaries are trust-checked on the resolved file and run by their link (P1's shape too); `UvVerifiedFiles` identifies a file without ctime; the from-scratch environment re-links pipx/uv apps in the default bin dir when a user installed with `PIPX_BIN_DIR`/`UV_TOOL_BIN_DIR`.

**Mac acceptance (real home, 2026-10-27, app + duo from this branch):** fixtures ruff `==0.6.0`, black `>=23,<24`, cowsay 5.0 unpinned (receipt edited) as uv tools; `brew install pipx` (1.18.4) with isort `==5.12.0`, pyflakes 3.0.0 `pipx pin`ned, a local-path package — all removed after, `brew uninstall pipx`. Rows in the app and `duo check --all` agreed: cowsay and isort offered (isort with D7's orange warning), ruff and pyflakes pinned with their copy commands, black "not checked" (D9), duolocal "not on an index". One-click in the app: cowsay 5.0 → 6.1, isort 5.12.0 → 9.0.2 through Homebrew's pipx with the uv backend. C1 ✓, C3 ✓, C4 ✓ (one running, two queued; no "N cancelled" count, as in P1), C5 ✓, C6 ✓; **C2 not run**: before the vendor command these adapters only read the disk (rescan, trust, busy gate) — no child to hold, and stopping DuoUpdater itself crashes it. Windows were held by an outside process holding uv's `tools/.lock` or pipx's `venvs/.<name>.lock` with `flock`, not by stopping our children.

**Decisions taken while writing (owner to confirm or reverse):** Homebrew's pipx is preferred over `~/.local/bin/pipx` when both exist (only the keg gets the one-click); the uv tool check falls back to PyPI for a uv that may not run, so rows still show what is newer; the project-URL rule also accepts a repository named with a Python affix (`cowsay-python`, `python-x`, `pyx`, `x-py`); a pipx row with `pip_args` index options is "not on an index" rather than asked of PyPI.


### 2026-10-27 — P3 written (uv Python, nvm Node, fnm Node, pyenv, rbenv; PR #1715, merged 2026-10-27)

**In:**

- `C/Managed/Uv/UvPythonAdapter`: one row per CPython line under `~/.local/share/uv/python` (key = the minor's link name, `cpython-3.12-macos-aarch64-none`; free-threaded its own line), newest from `uv python list <line> --only-downloads --output-format json`, `uv python upgrade <line>` (uv ≥0.7.14). Pre-releases and PyPy/GraalPy make no row.
- `C/Managed/Node/`: `NodeDistIndex` (nodejs.org's `index.json`, revalidated; a release without this Mac's `osx-arm64-tar`/`osx-x64-tar` is never offered), `NodeLines` (one row per major), `NodeChangelog` (`CHANGELOG_V<major>.md`, §12 item 12 done: `## <date>, Version <x.y.z> 'Jod' (LTS), @…` per release). `NvmNodeAdapter`: `~/.nvm` and `~/.config/nvm`, `/bin/bash -c '. "$1" --no-use; nvm install "$2" --reinstall-packages-from="$3"'` with `NVM_DIR` the root; the root's own `nvm.sh` exempt (rule 4), a link into Homebrew's nvm keg (this Mac: `~/.nvm/nvm.sh -> /opt/homebrew/opt/nvm/libexec/nvm.sh`) `.homebrewKeg`, no file → Homebrew's `opt/nvm/nvm.sh`. `FnmNodeAdapter`: the three roots, `fnm --fnm-dir <root> install <major>`, Homebrew's keg run, the installer's binary handed out.
- `C/Managed/Build/`: `DefinitionLines`, `PyenvAdapter`, `RbenvAdapter`: newest from the definition files on disk, computed in the scan so the click names the same `x.y.z`; `<manager> install <x.y.z>` with `*_ROOT` and Homebrew's `bin` on `PATH`; effects compiles / old kept / can't be cancelled once started; 20 min deadline.
- `C/Managed/HomebrewKeg` (pipx's keg rule, shared; pipx unchanged).
- §12 item 15: this Mac's `~/.config/nvm` is a git checkout of nvm with no `versions/` — nvm's own row, no Node rows.

**Measured (isolated roots; commands as the adapters build them):**

- uv 0.13.4: `uv python install 3.12.5`, then `uv python upgrade cpython-3.12-macos-aarch64-none` → "Installed Python 3.12.15", exit 0, 3.12.5 kept, the minor's link repointed; again → "… is already on the latest supported patch release", exit 0. `--only-downloads` answered in 30 ms, the same bytes with `--offline`.
- nvm 0.40.8 (Homebrew's `nvm.sh`): `nvm install 22 --reinstall-packages-from=22.21.1` → v22.23.4 beside v22.21.1 in 29 s, cowsay carried, `alias/default` (`22.21.1`) unchanged. The exact argv with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` → exit 0.
- fnm 1.39.0: `fnm --fnm-dir <iso> install 22` → v22.23.4 in 7 s, `aliases/default` unchanged; again → "warning: Version already installed", exit 0. `codesign -dv /opt/homebrew/bin/fnm`: `Signature=adhoc`, no Team (§12 item 7, fnm).
- pyenv 2.8.14 (checkout): `env -i HOME PYENV_ROOT PATH=/opt/homebrew/bin:<system> pyenv install 3.12.15` → 1:58, `ssl`/`sqlite3`/`lzma` import (§12 item 8); `pyenv latest -k` 3.12 → 3.12.16, 3.13t → 3.13.18t, 3.14 → 3.14.10 — what the definitions rule here reads. 1,161 definitions.
- ruby-build 20261023 (checkout): 703 definitions, 3.4 line's newest 3.4.12; `rbenv install 3.4.11` from a bare env with Homebrew's `bin` built in 3:41.
- §12 items 6/7 (`brew install pyenv rbenv ruby-build`, 2026-10-27): `/opt/homebrew/bin/pyenv -> ../Cellar/pyenv/2.8.14/bin/pyenv` → `libexec/pyenv`, definitions in the keg's own `plugins/python-build/share/python-build` (1,148 — the 2.8.14 release; the checkout of `master` had 1,161); `rbenv` → `Cellar/rbenv/1.3.2/libexec/rbenv`; `opt/ruby-build/share/ruby-build` → `Cellar/ruby-build/20261023/share/ruby-build` (703). `codesign -dv`: pyenv and rbenv "not signed at all" (bash scripts); the keg rule is what makes them runnable.
- §13.3 (D15 input), SIGINT/SIGTERM to the process group:

| Manager | Stage | Exit | Old version | Left behind | Next plain run |
|---|---|---|---|---|---|
| uv python upgrade | download (1.5 s) | 130 / 143 | runs, link unmoved | nothing seen | completes |
| uv python upgrade | install | not hit (done by 7.6 s) | — | — | — |
| nvm install | before output (4 s) | 130 / 143 | runs | nothing | completes |
| nvm install | version dir present (extract or the packages' reinstall) | 130 / 143 | runs | v22.23.4 runnable, listed by `nvm ls`, **without the old globals**; the row would read current | reinstalls the globals, completes |
| fnm install | download (1 s) | 130 / 143 | runs | `node-versions/.downloads/.tmp…` | completes |
| fnm install | rename into place | not hit (exit 0 when the dir appears) | — | — | — |
| pyenv install | download (3 s) / configure (45 s, 90 s) | 130 / 1 / 143 | runs | nothing (`versions/3.12.16` removed) | builds it whole |
| pyenv install | compile, `make install` | not hit apart | — | — | — |
| rbenv install | download (3 s, 60 s, 150 s on a slow line) | 130 / 1 / 143 / 130 | runs | no `versions/3.4.12`; each run left `/tmp/ruby-build.<time>.<pid>.<rand>` (the half-downloaded source, 14–22 MB) and its `.log` | not run after (a plain run downloads anew) |
| rbenv install | configure, `make`, `make install` | not hit apart | — | — | — |

  All stay (a) until the owner rules.

**Mac acceptance (real home, 2026-10-27, app + `duo` from this branch, `make install` + `make cli`):** fixtures: the user's own uv Pythons (3.11.14, 3.12.12, 3.13.11), nvm v24.13.0 (`alias/default` `lts/*`), fnm v22.21.1 + v24.12.0 (`default` → v24.12.0); added for the run with the owner's OK: Homebrew pyenv/rbenv/ruby-build, `~/.pyenv` 3.12.15, `~/.rbenv` 3.4.11. Driven by AX (`AXPress` on the workbench's buttons; the popover opened by a synthetic click on its status item).

- Rows before: `duo check --all --json` and the workbench agreed — uv Python 3.11.14→3.11.17, 3.12.12→3.12.15, 3.13.11→3.13.16; nvm Node 24 24.13.0→24.22.1 (`nvm install 24 --reinstall-packages-from=24.13.0`); fnm Node 24 24.12.0→24.22.1, Node 22 22.21.1→22.23.4 (orange "does not carry global packages over"); pyenv Python 3.12 3.12.15→3.12.16; rbenv Ruby 3.4 3.4.11→3.4.12. Headers "N updates, <manager> <version> · <root>".
- **C3** (pyenv, then rbenv): the row's Cancel is grey "Installing — can't cancel now" from the click (no pre-command wait to hold) through the build; it ran through: pyenv 3.12.16 in the app, rbenv 3.4.12 in 120 s (download, `./configure`, `make -j 14`, `make install` shown on the row's line), then "Updated to …" and Up to date.
- **C1**: with pyenv building, Update All on uv Python, nvm Node and fnm Node queued six rows ("Queued" — one global CLI queue, as in P2); Cancel on the queued Python 3.11 row put it back to its Update button, no red line.
- **C4**: the popover's "Other tools — Updating pyenv" row offered "Cancel 5 queued updates"; pressed: the five were dropped, the running pyenv build stayed with its grey "Installing — can't cancel now" and completed. `stat` of the uv/nvm/fnm roots before/after identical (only `~/.pyenv/versions/3.12.16` new). No "N cancelled" count was shown, as in P1/P2.
- **C2 not run**, as in P2: these adapters' pre-command stage is disk only (rescan, trust, busy gate), nothing to hold.
- One-click, each group's Update All: uv Python 3.11.17, 3.12.15, 3.13.16 one after another (each "Downloading …", "Installed Python … in 8 s"; minor links repointed, old patches kept); nvm 24.22.1 ("Reinstalling global packages from v24.13.0…", "added 414 packages in 23s"; the nine globals present in v24.22.1); fnm 24.22.1 and 22.23.4 (`default` still v24.12.0). nvm and fnm ran one after the other although their lanes differ: the global queue.
- **C5** (`duo install fnm-node/v22 --yes`, Node 22 put back with `fnm uninstall 22.23.4` first): SIGINT to duo's process group 2.2 s in (after its check, before fnm): "cancelled before it started — not updated", "0 installed, 0 failed, 1 cancelled", exit 130, no fnm child, root unchanged. 0.3 s in (still checking) it printed "Nothing to install." and exit 130 — the interrupted check reads as nothing found; duo's, not this branch's. SIGINT 0.5 s after fnm started: "updated: 22.21.1 → 22.23.4", "1 installed, 0 failed", exit 130.
- **C6**: after a rescan, the five headers read "Up to date, …" and `duo check --all --json` gave the eight rows `upToDate` at the same versions.

**Not done:** logos — fnm, pyenv and rbenv publish no vector logo (fnm's `docs/fnm.svg` is an animated terminal recording; pyenv's repo has a terminal screenshot; rbenv's none; Simple Icons has none of the three), so their rows keep the terminal glyph; rbenv notes (`ruby/ruby` tags `v3_4_12`: the shared decoder's tag rule not checked, so no notes yet).

**Decisions taken while writing (owner to confirm or reverse):** D6's `nvm alias default <new>` (and fnm's `fnm default <new>`) is a pane fact ("to move default afterwards: …"), not a copy glyph — managed rows have one `manualCommand` slot; Homebrew's pyenv/rbenv/fnm preferred over a checkout or installer binary when both exist — except that a ruby-build or python-build checkout under the root is what even the keg runs, so that root's command is handed out (rbenv from the start; pyenv from review round 1); pyenv/rbenv install the exact newest (`3.12.16`), not the line (`3.12` would prompt when present); uv Python makes rows for CPython final releases only.

**Review (PR #1715):** round 1 found two blocking issues, both in pyenv, and both were fixed in `b47b8d6f`:
- Homebrew's pyenv was trusted, and offered the newest from the keg's definitions, even when a python-build checkout under `$PYENV_ROOT` was the `pyenv-install` it runs, because pyenv puts the root's `plugins/*/bin` first on `PATH`. Such a root now hands the command out, takes its newest only from the root's plugins, and names the checkout's version.
- Python 2.x lines never read their version, because CPython 2.x installs no `bin/python3`. `bin/python` now counts too.

Round 2: 0 blocking. Neither layout exists on this Mac, so both have unit tests only, and each new guard was mutation-checked.


### 2026-10-27 — P4 written (cargo install, go install; PR #1717, merged 2026-10-27)

**In:**

- `C/Managed/Cargo/`: `CrateTracker` (`.crates.toml` + `.crates2.json`), `SparseIndex` (crates.io's index; newest by version, not by line — rand's tail is in publish order), `CratesIO` (`repository`, `User-Agent`, one request a second, kept per crate), `RustupProof`, `CargoAdapter`: one row per package; crates.io's offered, git/path/other-registry reported; `<root>/bin/cargo install <name>` plus the recorded `--features`/`--all-features`/`--no-default-features` (D8), `CARGO_HOME`, `RUSTUP_HOME` and **`RUSTC=<root>/bin/rustc`**; lane "rust", 30 min. cargo runs only as rustup's proxy (`bin/cargo` and `bin/rustc` both links to `bin/rustup`) whose bytes `resolve` proved against rust-lang's published hash; the proof is kept by sha256 for the process, so the click's disk-only scan sees it.
- `C/Managed/Go/`: `GoAdapter` (`GOBIN`, else `GOPATH`'s first `bin`, else `~/go/bin`, from `go env -w`'s file; one row per Go binary keyed by its package; pseudo-versions, `(devel)`, `+dirty`, loose files, renamed copies reported; `go list -m -json <module>@latest` ≤4 at once; `go install <package>@latest` with `GOTOOLCHAIN=local GOFLAGS=-mod=mod GOBIN=<root>`; a newest whose `GoVersion` is above this go is `.runtimeTooOld`), `GoModule` (notes: GitHub off the path, else proxy.golang.org's `Origin`, `Subdir` as the tag prefix). `GoBuildInfo` keeps the `path` line.
- `ManagedItem.NotesSource.goModule`; `ManagedNotes` reads `.crate` and `.goModule`.

**Measured (2026-10-27; cargo 1.99.1 via rustup 1.29.x, Homebrew go 1.27.3):**

- §12 item 9: `env -i HOME CARGO_HOME=<iso> RUSTUP_HOME PATH=<system> ~/.cargo/bin/cargo install …` → `could not execute process rustc -vV (never executed)`, exit 101: the proxy does not put rustc on `PATH`. With `RUSTC=~/.cargo/bin/rustc`: built (51 s cold). `install --list` works without it.
- §12 item 10: `cargo install tokei --features yaml` over 14.0.0 (`--version 14.0.0 --features yaml`) → 15.0.0 in 17 s, `.crates2.json` `features: ["yaml"]`, `version_req` `=14.0.0` → null; `tokei --version`: "json, yaml".
- §12 item 13: `env -i HOME GOTOOLCHAIN=local GOFLAGS=-mod=mod go list -m -json mvdan.cc/gofumpt@latest` from `/`: every `-x` GET went to goproxy.cn (the env file's `GOPROXY`), 0.27 s for `golang.org/x/vuln`; answer has `GoVersion`, no `Origin`.
- §12 item 7 (go): Homebrew's `bin/go -> ../Cellar/go/1.27.3/bin/go -> ../libexec/bin/go`, `Signature=adhoc`, no Team: the keg rule. `/usr/local/go` is not on this Mac — its signature is **not measured**, so that go is found but never run.
- go upgrade: `go install mvdan.cc/gofumpt@latest` v0.9.1 → v0.12.0, exit 0, new inode; again exit 0, inode and mtime unchanged.
- Sparse index: `etag` + `cache-control: public,max-age=600`.
- §13.3 (D15 input), SIGINT/SIGTERM to the process group:

| Manager | Stage | Exit | Old version | Left behind | Next plain run |
|---|---|---|---|---|---|
| cargo install (tokei 14→15) | index/resolve (1.5 s) | −2 / −15 | runs, `.crates.toml`/`.crates2.json` unchanged | an empty `$TMPDIR/cargo-install*` | completes |
| cargo install | compile (12 s) | −2 / −15 | runs, records unchanged | **`$TMPDIR/cargo-install*` of ~440–450 MB each**, never removed | completes (builds anew) |
| cargo install | final replace | not hit apart | — | — | — |
| go install (gofumpt, own `GOMODCACHE`) | download/build (0.6 s, 3 s) | −2 / −15 | runs (v0.9.1) | partial module cache only | completes |
| go install | write of the binary | not hit (done in 2.9 s) | — | — | — |

  Both stay (a) until the owner rules; cargo's leftovers are a D15 cost to weigh.

**Mac acceptance (real home, 2026-10-27, `make install` + `make cli` from this branch; app driven by AX):** fixtures added with the owner's OK: `cargo install tokei --version 14.0.0 --features yaml`, `cargo install --git https://github.com/sharkdp/hexyl hexyl` (0.17.0), `go install mvdan.cc/gofumpt@v0.9.1`. The user's own cargo-zigbuild 0.23.0 (0.24.0 out) and govulncheck v1.3.0 (v1.9.0 out) were backed up and never clicked; byte-identical after.

- Rows: `duo check --all --json` and the workbench agreed — cargo-zigbuild 0.23.0→0.24.0 and tokei 14.0.0→15.0.0 offered (`cargo install tokei --features yaml`, "drops the recorded specifier =14.0.0"), cross/rustlings current, hexyl "not on an index: installed from git", the three path crates reported; gofumpt 0.9.1→0.12.0 and govulncheck 1.3.0→1.9.0 offered. Headers "2 updates, 4 not checked, cargo 1.99.1 · ~/.cargo", "go 1.27.3 · ~/go/bin".
- One-click in the app: tokei → 15.0.0 **with yaml** (`features: ["yaml"]`, D8); gofumpt → v0.12.0.
- **C3**: tokei's Cancel grey "Installing — can't cancel now" from the click; the build ran through to "15.0.0".
- **C1**: with tokei building, gofumpt "Queued" (one global CLI queue); its Cancel put it back to Update, no red line, binary inode/mtime unchanged.
- **C4**: the popover's "Updating cargo install" row with one queued (gofumpt): "Cancel queued update" dropped it; the button turned grey "Installing — can't cancel now" and tokei completed. No "N cancelled" count, as in P1–P3.
- **C2 not run**: the pre-command stage is disk only (rescan, rustup hash, trust, busy gate).
- **C5** (`duo install go/mvdan.cc/gofumpt --yes`, its process group signalled as a terminal's Ctrl-C would): SIGINT 6.25 s in (after the 6.4 s check, before go) → "cancelled before it started — not updated", "0 installed, 0 failed, 1 cancelled", exit 130, no go child, binary unchanged; SIGINT 0.4 s after `go install` started → "updated: 0.9.1 → 0.12.0", "1 installed, 0 failed", exit 130.
- **C6**: after a rescan the app and `duo check --json` agreed on all six rows.
- Notes in the pane: tokei's from crates.io → `XAMPPRocky/tokei` releases (15.0.0, 2026-09-06); gofumpt's through proxy.golang.org's `Origin` → `mvdan/gofumpt` (0.12.0, 2026-09-07).

**Not done:** cargo-binstall's "installed by binstall" fact (its `binstall/crates-v1.json` format was not measured here); a Go logo (no asset in the repo; rows keep the terminal glyph); `/usr/local/go`'s signature (§12 item 7).

**Follow-up (2026-10-27, branch `cli-p4-leftovers`):**

- cargo-binstall: measured in an isolated `CARGO_HOME` (cargo-binstall 1.26.1). Its record `binstall/crates-v1.json` is JSON objects back to back with no separator ("It is _not_ NLJSON", binstalk-manifests' `binstall_crates_v1.rs`), one per crate, replaced on its own upgrade and never pruned when cargo replaces the crate (hyperfine's stayed at 1.18.0 after `cargo install` made it 2.0.0). It never writes `.crates2.json`, so such a package has no rustc and no "built by" fact. A row whose package that record names **at the version `.crates.toml` has** now says "installed by cargo-binstall; the update builds it with cargo install", as other rows say how they were built (owner, 2026-10-27: consistent with the other groups' facts, so yes). On the Mac (review round 1 of #1724): cargo-binstall installed hyperfine 2.0.0 into the real `~/.cargo` (`--disable-telemetry --disable-strategies compile`); the app's pane for that row listed the note; then `cargo uninstall hyperfine` and binstall's files removed, the records byte-identical to before. `duo` prints no managed facts, so the note is the app's only.
- Go logo: none (owner, 2026-10-27). go.dev/brand: the Go logo is Google's trademark; modifying it or using it in a product needs approval from trademark@golang.org. A request was drafted in the owner's name; the rows keep the terminal glyph until it is answered.
- `/usr/local/go` (§12 item 7): go.dev's `go1.27.3.darwin-arm64.pkg` (sha256 as go.dev publishes it; "Developer ID Installer: Google LLC (EQHXZ8M8AV)", notarized) installed with the owner's sudo: `/usr/local/go/bin/go` is "Developer ID Application: Google LLC (EQHXZ8M8AV)", hardened runtime, `codesign --verify --strict` valid, Identifier `org.golang.go`; `pkg/tool/darwin_arm64/{compile,link,asm}` the same Team. `CLIToolTrust.signature(…, teamIdentifier: "EQHXZ8M8AV")` on it: `vendor` (another Team: `otherSigner`; the keg's go: `adHoc`). So that go now runs when Google's signature holds (`.vendorSigned`), still after Homebrew's keg; any other signature is `.untrusted` and withheld as the wrong signer.

**Decisions taken while writing (owner to confirm or reverse):** a crate whose newest needs a newer rustc than the default toolchain is reported (`.runtimeTooOld`), not offered at an older compatible version — `cargo install <name>` stops on it (measured in review round 1, toolchain 1.95.0: "cannot install package `hyperfine 2.0.0`, it requires rustc 1.97.0 or newer … `hyperfine 1.20.0` supports rustc 1.88.0", exit 101, nothing installed), and naming `--version` would record a pin; `--all-features` is passed again like `--features` (D8 named features and `no_default_features`); the build `PATH` is the system's only (a crate whose build script needs Homebrew's cmake fails with cmake's own message); go rows are keyed by package path, and a renamed copy is reported because `go install` would write the other name; group titles "cargo install" and "go install".

**Review (PR #1717):** round 1 found one blocking issue: `aGoOutsideTheKegIsNotRun` removed the keg's receipt and so left no go at all, so `check`'s `root.runnable` guard was never reached and could be deleted with the suite green. Replaced by `aGoThatMayNotRunIsNotRun`, run for the pkg installer's `/usr/local/go` (`.untrusted(nil)`) and for a quarantined keg: the root has a binary that may not run, nothing is spawned, the row is `.unverified` with no one-click. Deleting `root.runnable` turns both red (10 issues). The round's one unmeasured claim — that `cargo install` stops rather than pick an older crate for an old rustc — was measured (decisions above).

Round 2 (`5c21356`): 0 new blocking; finding 1 "partly fixed" — the new test's doc said such rows hand their command out to copy, which only the broken build does: with nothing asked no newer version is known, so the row is `.unknown`, says which go was not run and why, and has no `commandToCopy`. Doc corrected and those four facts asserted (`c69065f`). Round 3: 0 blocking, finding 1 fixed. The reviewer could not check cargo's stop-on-old-rustc behaviour itself (it checked hyperfine's `rust-version`s against its repository); it stands on the measurement above.

**UI tried and dropped (owner, 2026-10-27):** each manager's level wearing its logo on the header, its rows keeping an empty icon slot so the names line up with the other levels. Built and looked at on the Mac; the owner found it ugly, and it was reverted before the PR. Not to be proposed again in this form.

### 2026-10-27 — §12 item 5 measured (mise `minimum_release_age`)

mise's default 24 h age holds a release back from `outdated`, `latest` and `upgrade` alike, and the mise tools adapter inherits it with no code of its own; record and commands under §12 item 5. P1's last owed item is closed.

---

# 15. P5 — npm, bun, pnpm and Yarn global packages as managed items

**Owner, 2026-10-27: do it (D-P5-1), for consistency.** In the owner's words: "其他的我也希望迁移，保持一致性，other tools 始终保持没有分组的，这说明这是用户单独安装的，不归其他 creates 管理" — every package a manager keeps moves to that manager's own level; "Other tools" stays a flat list of what the user installed on its own, with no groups in it. D-P5-2…13 below are recommendations the owner has not ruled on yet; ask before P5.2 (the switch). This section's D15 line is superseded: the owner ruled D15 (§13.4) after it was written, so these adapters get `interruption` plans from their own measurements, like P1–P4's.

Design only; no code. Read on `origin/main` at `03331828` (2026-10-27). Paths: `C/` = `DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/`, `M/` = `C/Managed/`. Every line number below was read on that tree; nothing was built or run except read-only `ls` and one `defaults export` of the owner's preferences (§15.2).

## 15.0 What P5 is, and what it is not

§8.2 left npm/bun/pnpm/yarn out of P0–P4 "until a migration of `NotifiedCLIToolVersions` keys is designed". P5 replaces `NpmProvider`, `GlobalPackagesProvider(.pnpm/.yarn)` and the package half of `BunProvider` with adapters under `M/Node/Packages/`, and designs that migration.

Two facts shape the whole phase:

- **These rows' paths do not move.** npm replaces a package directory in place (same path, new inode, `C/NpmUpdater.swift:17-20`); bun's, Yarn's and pnpm's package paths stay too (pnpm 11's `global/v11/<hash>` link keeps its path across an update, `C/GlobalPackages.swift:8-11`). The managed identity's reason to exist (§3.3: "a directory that moves") does not apply. What P5 buys is one code path, the managers' own levels in the UI (D12), and `duo install npm/<name>`. What it costs is mostly the model extensions in §15.1's last column. D-P5-1 asks whether that trade is wanted.
- **The core logic stays.** `NpmCheck`, `NpmPick`, `NpmActivity`, `GlobalPackageActivity`, `BunActivity`, the specifier restore and the scanners are the behaviour; the adapters call them. Only the provider glue (`C/NpmProvider.swift` 112 lines, `C/GlobalPackagesProvider.swift` 79, the package half of `C/BunProvider.swift`) and the App's npm-only special cases go. Of §8.2's "4,000+ lines", 3,484 are `C/Npm*.swift`, `C/GlobalPackage*.swift`, `C/NodePrefixes.swift`, `C/BunProvider.swift` (`wc -l`), and most of that stays.

Proposed managers (D-P5-2): `npm`, `bun`, `pnpm`, `yarn` — four `ManagerID`s, four thin adapters over one shared `NodePackages` core. Provider ids `managed:npm` … (`M/ManagerDescriptor.swift:81-83`), distinct from the kinds `bun` (bun's own row, which stays) and today's `npm`/`pnpm`/`yarn` (which go).

---

## 15.1 Inventory: what today's providers do, and how the managed model says it

"Has" = an existing managed type or hook expresses it; "Lacks" = P5.0 must add it. One row per behaviour that must be preserved.

### Discovery and scan

| # | Behaviour (today) | Where | Managed model |
|---|---|---|---|
| S1 | Node prefixes from the layout only, never `PATH`: Homebrew `/opt/homebrew`, `/usr/local`; `~/.nvm/versions/node/*` (links kept); fnm's three roots `…/node-versions/*/installation`; mise `installs/node/*`; asdf `installs/nodejs/*`; `~/.npm-global`; `~/.npmrc` `prefix=` (`~`, `${HOME}` expanded) | `C/NodePrefixes.swift:81-118`, `:124-137` (nvm keeps links, :129), `:187-197` | Has: adapter `scan()` calls `NodePrefixes(home:).discover()`; one `ManagedRoot` per prefix (D-P5-3). |
| S2 | Each prefix once, by resolved path, first source wins | `C/NpmInstall.swift:295-315` (:299-300) | Has: adapter's scan; root path = the unresolved `prefix.path` (what today's `install.path` starts with, which the alias key needs, §15.2). |
| S3 | Only packages with a `bin` (`bin` string/map, `directories.bin`); dot entries skipped; `@scope/name` | `C/NpmInstall.swift:320-328`, `:342-344`, `:368-373` | Has (scan logic reused). Item key = install name (`@scope/x` contains no `|`, `M/ManagedItem.swift:246`). |
| S4 | npm, corepack, `@anthropic-ai/claude-code` excluded (Claude Code has its own group) | `C/NpmInstall.swift:272`, `:335`, `:347` | Has (reused). |
| S5 | Link (`npm link`, `i -g ./dir`) recorded; pnpm's links into its store are not links | `C/NpmInstall.swift:337-341`, `:359` | Has → verdict blocker `.notIndexed("linked to …")`. Wording differs (S-W below). |
| S6 | Prefix runtime: `bin/node` executable, `bin/npm` only with node, npm version from `lib/node_modules/npm/package.json`, node signature vs Team `HX7739G8FX`, quarantine, Homebrew keg | `C/NpmInstall.swift:375-392`; trust `:180-187`; keg `C/NodePrefixes.swift:149-163` | Has: `ManagedRoot.Binary` = the prefix's node; `Trust` = `.vendorSigned(team:)` / `.homebrewKeg` / `.untrusted(sig)` / `.quarantined` (`M/ManagedItem.swift:29-37`). Lacks: npm's own version and the npm script path ride in the payload (L1). |
| S7 | Node version from the layout, else `node --version` of a Node.js-signed unquarantined node, once per node, in the check | `C/NpmProvider.swift:81-111` | Has: `resolve(_:)` is exactly this hook ("what only running the binary can read", `M/ManagerAdapter.swift:22-27`). |
| S8 | Registry config: `registry`/`@scope:registry` from `~/.npmrc`, prefix `etc/npmrc`, npm's builtin npmrc, in npm's order; bun adds `~/.bunfig.toml` `[install]`/`[install.scopes]`; pnpm/Yarn read `~/.npmrc` | `C/NpmInstall.swift:412-436`; `C/BunInstall.swift:254-306`; `C/GlobalPackages.swift:129-135` | Has (scan logic reused) → blocker `.notIndexed(…custom registry…)`. |
| S9 | npmrc `prefix=` elsewhere (openclaw's bare `npm i -g` would go there) | `C/NpmInstall.swift:397-404` | Has (payload). |
| S10 | openclaw settings (`~/.openclaw/openclaw.json` channel/auto, `--tag` documented in both doc spellings); agent-browser marked | `C/NpmInstall.swift:242-256`, `:350-355` | Has (payload). |
| S11 | bun: `~/.bun/install/global/package.json` `dependencies` = the packages and their specifiers; node = Homebrew's `/opt/homebrew` or `/usr/local` `bin/node` | `C/BunInstall.swift:199-214`, `:218-224`, `:229-247` | Has: root `~/.bun/install/global`, binary = bun (Team Oven). Lacks: a second trust (the node, for engines and openclaw) → payload + gate (L2). |
| S12 | pnpm: projects `global/<n>` (≤10) and `global/v11/<hash>` links (≥11); per project the pnpm copy that reads its layout (major ≤10 vs ≥11), trusted first, newest first; node = that pnpm's when it is JavaScript, else Homebrew's | `C/NodePrefixes.swift:245-266`; `C/GlobalPackages.swift:42-76` (:54-57); `C/GlobalPackageManager.swift:262-271` | Has: root = pnpm home `~/Library/pnpm` (D-P5-3), key = name. Lacks: the manager per item (projects can need different pnpm copies) → payload; and a second trust (L2). |
| S13 | pnpm/Yarn copies: npm-installed, corepack (`lastKnownGood.json`), Homebrew keg (receipt), pnpm standalone (never run) | `C/GlobalPackageManager.swift:122-139`, `:144-161`, `:174-188`, `:199-232`, `:246-257`; trust `:69-75` | Has: `ManagedRoot.Binary` per root can carry the picked copy's trust as one `Trust` value. |
| S14 | Yarn 1 only: `~/.config/yarn/global`, manager major == 1 | `C/GlobalPackages.swift:105-123` (:109) | Has. |
| S15 | Sighting state: link, manifest name, registry, node signature, quarantine, node and npm versions, own-update settings, specifier, the pnpm/Yarn copy | `C/NpmProvider.swift:28-45` | Has: `ManagedScan.states[identity]` (`M/ManagedItem.swift` `ManagedScan`). Same string. |

### Check (verdict)

| # | Behaviour | Where | Managed model |
|---|---|---|---|
| K1 | One packument request per package name per check (cached across prefixes), filed under the package (`RequestAttribution.withApp(name)`) | `C/NpmCheck.swift:53-71` | Has: adapter `check` keeps the cache. |
| K2 | Registry fetch: `versionFeedCachePolicy`, 15 s, abbreviated packument | `C/NpmRegistry.swift:87-98` | Has (reused). |
| K3 | No version / not semver → `.unknown` `.versionUnreadable` | `C/NpmCheck.swift:95-97`, `:125-127` | Has: `ManagedCheck` row 1 / `.versionUnreadable` (`M/ManagedCheck.swift:40-47`). |
| K4 | Linked, alias install (`foo@npm:bar`), custom registry, not on registry, version not in registry → `.unknown` `.unsupportedInstaller` "reported only" | `C/NpmCheck.swift:98-124` | Has: `.notIndexed(reason)` → `.unsupportedInstaller` (`M/ManagedVerdict.swift:23`, `:36`). Note text changes from "…: reported only" to "not on an index: …" unless L4. |
| K5 | Registry unreadable → `.unknown` `.channelUnreadable` | `C/NpmCheck.swift:117-119`, `:146-147` | Has. |
| K6 | Track: `latest` for a release; a prerelease follows its word's tag, else the highest tag with that word, else `latest`; openclaw's channel (`dev` → reported only; `beta` unless `latest` newer) | `C/NpmRegistry.swift:137-159`; `C/NpmCheck.swift:131-140` | Has (adapter). Lacks: the tag on the row — `CLIToolStatus.channel` = tag today (`C/NpmCheck.swift:87`), `ManagedCheck` hard-codes `channel: nil` (`M/ManagedCheck.swift:138`) → L3. |
| K7 | Pick: newest above installed, ≤ the tag's version, not deprecated, `engines.node`/`engines.npm` met by this prefix (npm's `checkEngine` rule), prereleases only on a prerelease track; never a downgrade | `C/NpmRegistry.swift:162-199` | Has: `latestWithinRequest` = offered, `latestOverall` = tag's version. |
| K8 | Installed == tag → `.upToDate`; above → `.ahead` | `C/NpmCheck.swift:149-151` | Has (`M/ManagedCheck.swift:66-83`). |
| K9 | Exact specifier (bun/pnpm/Yarn) with newer → `.pinned`, unpin command to copy (`<tool> add -g <name>` / `yarn global add <name>`), checked **before** the runtime gates | `C/NpmCheck.swift:152-156`, `:224-243` | Has: `request: .exact`, `vendorWouldUpgrade: false` → `.pinned` + `unpin` (`M/ManagedCheck.swift:61-65`). Range specifiers → `request: .range` with `vendorWouldUpgrade` true: bun/pnpm/Yarn move past a range when given an exact version, so D2's "held at its top" never applies. |
| K10 | Newer exists but nothing runs here → `.updateAvailable` withheld `.runtimeTooOld`, `latestVersion` = tag's; counted as held back, not offered | `C/NpmCheck.swift:157-162`; `App/Sources/CLIToolsModel.swift:274-277` | **Lacks.** `.runtimeTooOld` is a `Blocker`, and every blocker makes the row `.unknown` (`M/ManagedCheck.swift:44-47`): the row would leave "held back" and read "not checked". → L2 (a gate that keeps the state). |
| K11 | Offered **and** a newer one that needs a newer node: note "X needs Node ≥ Y", pane fact "Newer release" | `C/NpmCheck.swift:171`, `:318-320`; `App/Sources/CLIToolPresentation.swift:646-651`; `C/NpmPackage.swift:6-13` | Lacks: `latestOverall > latestWithinRequest` reads as D2's "beyond the request" only on `.upToDate` rows (`M/ManagedCheck.swift:108-111`, `:154-158`), so no wrong line — but the gap itself has no field → payload (`NpmPackage.gap`) or `Fact.note`. |
| K12 | Tag's version is a prerelease (copy on releases) or deprecated → `.upToDate` with a note and `latestVersion` = the tag's | `C/NpmCheck.swift:163-170` | Has (corrected in review round 1 of #1725): for these rows only, set `latestWithinRequest` = the tag's version, leave `latestOverall` nil and pass `vendorWouldUpgrade: false` — `ManagedCheck` (`M/ManagedCheck.swift:39`, `:66-72`) then gives `.upToDate` with `latest` = the tag's version, as today, and its D2 line (`:108`, which reads only `latestOverall`) does not fire. K7's `latestWithinRequest = offered` mapping must not be applied to them. Lacks the note: `ManagedCheck` sets `note` on a current row only for `vendorWouldUpgrade == nil` (`:71-76`), and `ManagedVerdict` has no note field, so today's note ("latest's 2.0.0-rc.1 is a prerelease, and this copy follows releases", `C/NpmCheck.swift:169`) would vanish from the row and from `duo --json` (`CLI/Sources/DuoKit/CLIToolRows.swift:127`) — **L8** carries it (review round 2 of #1725). With L8, no difference to accept. |
| K13 | Gates in the order a user can act on them, each keeping `.updateAvailable`: npm — no own node/npm (`.noOwnNpm`), node quarantined (`.unverified`), ad hoc/unsigned non-keg (`.unverified`), other signer/invalid/nil (`.wrongSigner`), node version unreadable (`.versionUnreadable`); bun — no node, bun quarantined, bun not Oven's; pnpm/Yarn — no copy (`.updaterMissing`), standalone pnpm, its node untrusted, not a confirmable keg (`.unverified`), no node (`.versionUnreadable`) | `C/NpmCheck.swift:173-216`, `:259-299` | Partly: the root binary's trust already "takes the click, never the verdict" (`M/ManagedCheck.swift:113-129`). Lacks: every gate that is not the root binary's trust (`.noOwnNpm`, node version, bun's node, pnpm's node) → L2. Differences even where it fits: `.invalid`/`nil` signature maps to `.unverified` in `ManagedRoot.Trust.withheld` (`M/ManagedItem.swift:51-56`) but `.wrongSigner` in npm (`C/NpmCheck.swift:207-210`); and the managed gate hands the command out to copy (`M/ManagedCheck.swift:118-121`), which `commandToCopy` shows for `.unverified` (`C/CLITools.swift:113-120`) — npm rows today hand nothing out for an untrusted node (D-P5-7). |
| K14 | openclaw `update.auto.enabled: false` → `.updateAvailable` `.autoUpdateOff`, command to copy | `C/NpmCheck.swift:310-314` | Lacks → L2. |
| K15 | Busy → `.updateAvailable` `.busy`, click removed | `C/NpmCheck.swift:315-317` | Has: `ManagedVerdict.busy` (`M/ManagedCheck.swift:130-134`). |
| K16 | Order matters: busy is asked only after every other gate passed | `C/NpmCheck.swift:303-321` | Has: `ManagedCheck` asks busy last. |

### Busy gates (three)

| # | Behaviour | Where | Managed model |
|---|---|---|---|
| B1 | npm: a process whose executable resolves to this prefix's node and whose argv is npm's title (`npm install x`) or `…/npm install`, any of npm 11's changing commands and aliases; a bare `npm` title counts | `C/NpmActivity.swift:64-106` | Has: `busy(item, root, processes)` (`M/ManagerAdapter.swift:48-51`), asked at check and click (`M/ManagedProvider.swift:134-136`). Needs the `NpmInstall` → payload (L1). |
| B2 | Own updaters: `openclaw update` / `agent-browser upgrade` by argv; openclaw's titles `openclaw-update`/`-doctor`; openclaw ≥2026.9 by its `update_runs` ledger in `state/openclaw.sqlite` (pid + start time) | `C/NpmActivity.swift:111-218` | Has (same hook). |
| B3 | bun: `bun add|… -g` by this bun binary, plus openclaw's | `C/BunActivity.swift:50-71` | Has. |
| B4 | pnpm/Yarn: `pnpm <changing> -g`, `yarn global add|upgrade|upgrade-interactive|remove`, by program or the script after node | `C/GlobalPackageManager.swift:282-316` | Has. |

### Update (the click)

| # | Behaviour | Where | Managed model |
|---|---|---|---|
| U1 | npm: `<prefix>/bin/node <prefix>/bin/npm install -g --prefix <prefix> --engine-strict <name>@<offered>`, `bin` first on `PATH` | `C/NpmCheck.swift:380-383` | Has: `upgrade(item, root)` returns it. |
| U2 | openclaw: `node <pkg>/openclaw.mjs update --tag <v>` when `--tag` documented and no npmrc redirect; else npm with a "why" note; agent-browser always npm | `C/NpmCheck.swift:352-379` | Has (adapter) + note as fact. |
| U3 | bun: `<bun> add -g <name>@<v>`; openclaw via the found node only when that node is trusted | `C/NpmCheck.swift:413-430` | Has. |
| U4 | pnpm ≤10 `update -g <spec>`, ≥11 `add -g <spec>`; Yarn `global add <spec>`; JS copies run as `node <script>` | `C/NpmCheck.swift:401-411`; `C/GlobalPackageManager.swift:81-90` | Has. |
| U5 | Re-asked at the click: busy; bun still Oven's; pnpm/Yarn copy still trusted (keg receipt, files present); node still trusted, when the command runs it | `C/NpmUpdater.swift:94-121`, `:164-174`, `:221-244` | Partly: `ManagedProvider.update` re-scans and re-asks `root.runnable` and busy (`M/ManagedProvider.swift:119-136`). Lacks: the second trust (node under bun/pnpm/Yarn) → L2's gate re-asked at the click (the adapter's `current` returns an item the gate refuses). |
| U6 | Child environment = inherited minus `npm_config_prefix`, `OPENCLAW_UPDATE_PACKAGE_SPEC`, and (pnpm/Yarn) the global-dir redirects; `PNPM_HOME` + its `bin` on `PATH`; Homebrew Yarn's `PREFIX`; bun's `BUN_INSTALL` | `C/NpmUpdater.swift:187-216`, `:285-288` | Has, stricter: managed builds the environment from scratch (`HOME`, `PATH`, `NO_COLOR`, proxy, `M/ManagedProvider.swift:138-142`), so the redirects cannot leak; the four additions go in `upgrade().environment`. **Not measured**: whether openclaw's `update`/`doctor`/gateway restart needs anything the inherited environment had (`USER`, `TMPDIR`, `LANG`…) — §15.5. |
| U7 | stdin = an empty pipe (openclaw prompts only on a TTY; `duo` in a terminal would hand it one) | `C/NpmUpdater.swift:246-249`, `:270` | **Lacks**: `ManagedProvider.commandRunner` passes no `standardInput` (`M/ManagedProvider.swift:69-71`), and ChildProcess then inherits stdin (`Support/ChildProcess.swift:32`) → L5. |
| U8 | Commit point and landed rule (`succeeded || uncaughtSignal || timedOut`), `.runToCompletion` | `C/NpmUpdater.swift:257-274` | Has: same rule in `CLIToolCommandRunner.run` (`C/CLIToolCommandRunner.swift`, `InstallCommit` with the same `landed`). |
| U9 | Deadline 30 min (openclaw's steps) | `C/NpmUpdater.swift:53-57` | Has: `ManagerDescriptor.deadline` (default 10 min, `M/ManagerDescriptor.swift:76-77`) → set 30 min. |
| U10 | Success = exit 0 **and** `package.json` reads exactly the offered version (openclaw exits 0 having skipped); pnpm's read follows links | `C/NpmUpdater.swift:139-149`, `:427-433` | Partly: managed fails only when the re-read equals the old version (`M/ManagedProvider.swift:163-172`). Lacks "equals the target" → L6. |
| U11 | Specifier read before, restored after in the user's style (`^`/`~` move, satisfied ranges stay, else `^v`; exact stays exact), one value edited in place; Yarn's `yarn.lock` key line gets the pattern added, both files or neither | `C/NpmUpdater.swift:123-126`, `:150-156`, `:317-422` | **Lacks**: no pre/post hook around the run → L6. |
| U12 | Failure line: npm's `npm error` reason, openclaw's `Update Result`/`OpenClaw update failed` reason, else the shared rule | `C/NpmUpdater.swift:438-472` | Lacks: managed uses the shared rule + "(exit n)" (`M/ManagedProvider.swift:76-79`) → L6 (adapter `failureMessage`). |
| U13 | Lane: an npm prefix is one lane, shared with Claude Code installed by npm in the same prefix (`node:<canonical prefix>`); bun packages share `bun` with bun's own row; pnpm, yarn their own | `App/Sources/CLIToolsModel.swift:1705-1716` | Partly: `ManagerDescriptor.lane` is one string per manager (`:1711-1712`). bun → `"bun"`, pnpm → `"pnpm"`, yarn → `"yarn"` fit. npm needs a lane per root → L7. Without it, two prefixes would serialise (harmless) and **Claude Code's npm update could run beside a package update in its prefix** (a race npm has no lock against, `C/NpmActivity.swift:7-8`). |

### Notes, presentation, `duo`

| # | Behaviour | Where | Managed model |
|---|---|---|---|
| N1 | Notes: GitHub releases of `package.json`'s `repository` (many URL forms), versions `pending` (≤10 above installed), follow-ups by tag after a full page, renamed-repo redirect keeps the token | `C/NpmChangelog.swift:48-158`; `C/NpmRegistry.swift:133` | Has: `releaseNotes(for:)` override calls `NpmChangelog.fetch`. Needs `pending` → payload. |
| N2 | Notes cache key per installed version, `npm:<name>@<installed>` (review #949: one copy's notes hid another prefix's older sections) | `C/NpmChangelog.swift:32-34` | **Lacks**: `ManagedCheck.releaseNotesKey` = `managed:<manager>:<key>` for every manager (`M/ManagedCheck.swift:147-149`) — #949 would come back → L4. |
| N3 | Breaking hints: npm rows uncapped today | `App/Sources/CLIToolsModel.swift:911-916` | D10's ≤5 cap applies to managed rows with `item.notes != nil` (:913) → D-P5-9. |
| N4 | Empty notes say "<package>'s release notes have no section…" | `App/Sources/CLIToolsWorkbench.swift:1136-1138` | Lacks: reads `.npm` detail → payload. |
| P1 | Groups: npm split by prefix, each prefix where its first package stood; bun = bun's row + packages; pnpm, yarn one group each, all under "Other tools" | `App/Sources/CLIToolPresentation.swift:123-145` | Has: `groups` by `manager|root` → each prefix its own **top-level level** (D12, `App/Sources/WorkbenchWindowView.swift:963-978`) → D-P5-3/D-P5-8. |
| P2 | Prefix header: label (`nvm`/`fnm`/`mise`/`asdf`, else the path) + "node 24.13.0"; pnpm/Yarn header "pnpm 10.33.2 · node 26.10.0" | `App/Sources/WorkbenchWindowView.swift:1251-1260`; `App/Sources/CLIToolPresentation.swift:158-163`, `:746-770` | Partly: managed header = `headerSummary` (binary version · root, `M/ManagerDescriptor.swift:101-111`). With the node as the root's binary: "node 24.13.0 · ~/.nvm/versions/node/v24.13.0". Wording changes; owner to look (D-P5-3). |
| P3 | Runtime-security mark on the prefix header (node notices once per node, Homebrew keg matched) and its popover's `NodeUpgradeCommand` listing the prefix's packages | `App/Sources/WorkbenchWindowView.swift:1231-1242`; `App/Sources/CLIToolPresentation.swift:417-445`; `C/RuntimeSecurity.swift:669-680` | Lacks: keyed on `Group.prefix` and `.npm` detail → payload, and the managed level header must carry the mark. |
| P4 | Title twins: one package in two prefixes → "openclaw · node 24", else the full node version, else the prefix | `App/Sources/CLIToolPresentation.swift:29-50` | Lacks: managed title = `status.name` → keep the rule over the payload. |
| P5 | Pane facts: Prefix, Node (version · signature), Newer release (gap), Linked to, Registry, Version range, Updated with (pnpm/Yarn copy) | `App/Sources/CLIToolPresentation.swift:632-675` | Partly: `ManagedItem.facts` (`.source`, `.note`, …) could carry them, but the App already words them from `NpmPackage` with translations → payload (L1) keeps them. |
| P6 | openclaw caption "openclaw update also runs openclaw doctor, restarts …" | `App/Sources/CLIToolPresentation.swift:309-310` | Lacks → payload, or an `Effect`. |
| P7 | Icons/tints: `cli-npm` (#CB3837), `cli-bun` (label), `cli-pnpm` (#F69220), `cli-yarn` (#2C8EBB) | `App/Sources/CLIToolsWorkbench.swift:84-87`, `:129`, `:140`, `:152-153` | Has: `ManagerDescriptor.logo/tint`. |
| P8 | Wording: ~14 npm-specific reasons with translations (no own npm, runtime too old with the requirement, standalone pnpm, no Yarn 1 found, bun not Oven's, busy "npm is busy in this prefix", the origin of a reported-only package…) | `C/CLIToolWording.swift:77-78`, `:96-99`, `:140-175`, `:234-253`, `:360-372` | Lacks: managed arms are generic (`:316-347`). Keep the existing strings by matching the payload in the `.managed` arm (no new translations) → D-P5-10. |
| P9 | GitHub pause: bun packages (kind `.bun`) inherit `.ourTokenIfAny`, so they are held while the app's GitHub budget is paused | `C/CLITool.swift:558-563`, `:578-580`, `:593` | Changes: a `bun` descriptor with `updaterSpendsGitHubAPI: nil` stops that. `bun add -g` asks the npm registry, so this looks like an accident today — **not verified**; owner to confirm (D-P5-11). |
| P10 | Process watch/stale banners: none for packages (path is a directory) | `C/CLIToolProcesses.swift:223-249` (`isRegularFile`) | Has: unchanged as long as `path` stays the package directory. |
| P11 | Runtime tag (Rust/Go/Bun build of a package's binary) read off `status.path` | `C/CLIRuntime.swift:454-470`; `CLI/Sources/DuoKit/CLIToolRows.swift:53-57` | Has: `installPath` = package directory. |
| D1 | `duo` rows: `tool` = `npm`/`bun`/`pnpm`/`yarn`, `name` = package, `path` = package dir, `channel` = dist-tag, names = `[name]` | `CLI/Sources/DuoKit/CLIToolRows.swift:114-141`, `:164-171` | Changes: `tool: "managed"`, `manager`, `item`, `root`; names `[key, manager/key, name]` (`duo install npm/cowsay` new; `duo install cowsay` as before; twins across prefixes still refused as ambiguous, `CLI/Sources/DuoKit/Inventory.swift:271`). `channel` lost unless L3. D-P5-6. |
| D2 | `duo check` lists packages by prefix for the node-upgrade advice (`npmPackage`) | `CLI/Sources/DuoKit/Check.swift:93-101`; `C/RuntimeSecurity.swift:669-680` | Lacks → `npmPackage` reads the payload. |
| D3 | Job id and breaking key by `kind:identity` | `CLI/Sources/DuoKit/CLIToolRows.swift:237`, `:263`, `:514` | Has (transient, nothing to migrate). |

### Lacks, collected (P5.0's scope)

- **L1 payload**: `ManagedItem` gains one optional, `Equatable`/`Sendable` payload enum with a single case `.nodePackage(NpmPackage)`. The App's npm presentation (P3–P6, N4, P8), `npmPackage` (D2), busy (B1–B4) and notes (N1) read it. This is the one place the shared model learns a manager's type; the alternative (re-wording everything as `Fact`s and re-deriving the install at each hook) redoes translated work and re-scans per call. D-P5-12.
- **L2 gate**: `ManagedVerdict.hold: (withheld: CLIToolWithheld, note: String, manual: CLIToolCommand?)?` — applied by `ManagedCheck` after the state is decided, only when the row would offer a click: keeps `.updateAvailable`, takes `oneClick`, sets `withheld`/`note`/`manualCommand`. Expresses K10, K13 (non-root gates), K14, and U5's second trust (the adapter's `current` re-derives the hold at the click; a held item → `.failed("not run: …")`). For K10, `latestVersion` = the tag's version (today's).
- **L3 channel**: `ManagedVerdict.channel: String?` → `CLIToolStatus.channel`.
- **L4 notes key + note text**: `ManagerAdapter.releaseNotesKey(_:)` (default today's); npm adapters return `NpmChangelog.releaseNotesKey`. `Blocker.notIndexed` note stays generic unless the adapter passes `.unknownVersionForm`/a new `.reportedOnly(String)` whose note is the reason as written.
- **L5 stdin**: `ManagerAdapter.standardInput: Data?` (default nil) passed to the runner; npm adapters return `Data()`.
- **L6 run hooks**: `ManagerAdapter.prepare(_ item) async -> Prepared?` (read the specifier) and `finish(_ item, prepared, run) async -> CLIToolUpdateOutcome?` (exact-version check, pnpm link-following re-read, specifier restore, `failureMessage` with npm's/openclaw's reason). Defaults keep P1–P4 unchanged.
- **L7 lane**: `ManagerAdapter.lane(of item) -> String` (default `descriptor.lane`); `CLIToolsModel.lane(of:)` asks it through the item. npm returns `"node:" + canonical(root)`, today's spelling, so Claude Code's npm row and the prefix's packages share again.
- **L8 current-row note**: `ManagedVerdict.note: String?` → `CLIToolStatus.note` on a row `ManagedCheck` makes `.upToDate` (K12: the tag's prerelease or deprecated version; today `C/NpmCheck.swift:169`), so the row and `duo`'s `note` stay as they are. Default nil: P1–P4 unchanged.

---

## 15.2 Key migration

### What names these rows today

`CLIToolStatus.identity` defaults to `path` (`C/CLITool.swift:294-301`); the App's key is `CLIToolID.tag` = `"<kind>:<identity>"` (`App/Sources/CLIToolsModel.swift:7-30`).

| Persisted? | Key | Format today | Example (owner's Mac, `defaults export com.duoupdater.app`, 2026-10-27) |
|---|---|---|---|
| **Yes**, UserDefaults `NotifiedCLIToolVersions` (`App/Sources/Preferences.swift:102`, `:280-284`, `:631-634`), dictionary tag → up to 8 versions (`Engine/NotifiedUpdateVersions.swift:68`, `:97`) | npm | `npm:<prefix>/lib/node_modules/<name>` | `npm:/Users/bobby/.nvm/versions/node/v24.13.0/lib/node_modules/agent-browser` → `[0.39.0 … 0.39.4]`; `npm:/Users/bobby/.local/share/fnm/node-versions/v24.12.0/installation/lib/node_modules/pnpm` → `[12.10.1 … 12.15.0]` (5 `npm:` keys of 39) |
| same | bun packages | `bun:<home>/.bun/install/global/node_modules/<name>` (bun's own row `bun:<…>/.bun/bin/bun` keeps its key) | none on this Mac (its `~/.bun/install/global/node_modules` holds only dependencies of a package without `bin`) |
| same | pnpm | `pnpm:<home>/Library/pnpm/global/5/node_modules/<name>`, `pnpm:<home>/Library/pnpm/global/v11/<hash>/node_modules/<name>` | none (no `~/Library/pnpm/global`) |
| same | yarn | `yarn:<home>/.config/yarn/global/node_modules/<name>` | none (no `~/.config/yarn/global`) |
| Yes, `CLIToolNotificationBaselineSeeded` (`Preferences.swift:103`) | — | Bool | stays `true`; no new silent pass |
| No (in memory) | `justUpdated`, red lines, progress, selection, breaking hints, release-notes cache, popover pages | by `CLIToolID` / tag / `releaseNotesKey` | `App/Sources/CLIToolsModel.swift:164-194`, `:259`, `:379`. P5 ships in an app update, i.e. after a relaunch: nothing to carry |
| No | skip / ignore | apps only (`UpdateResult` keys, `CLI/Sources/DuoKit/Visibility.swift:94-148`); `grep -n -i 'ignor\|skip' App/Sources/CLIToolsModel.swift` finds none for tools | — |
| Delivered notifications | `clistale:<tag>` | per install with a process target | none for packages (P10) |
| `@AppStorage` | `workbenchOtherToolsExpanded`, `workbenchHomebrewExpanded` | not keyed by tool | unaffected; managed levels are "remembered only for the window" (§5) |

### New identity

`"<manager>|<root>|<key>"` (`M/ManagedItem.swift:277-288`), tag `managed:<identity>`, the form the 15 `managed:` keys on this Mac already have (`managed:nvm-node|/Users/bobby/.nvm|v24`).

| Manager | root | key | Example tag |
|---|---|---|---|
| `npm` | the prefix as discovered (`/opt/homebrew`, `~/.nvm/versions/node/v24.13.0`, fnm's `…/v24.12.0/installation`, `~/.npm-global`, npmrc's) | install name (`@scope/x` allowed) | `managed:npm|/Users/bobby/.nvm/versions/node/v24.13.0|agent-browser` |
| `bun` | `~/.bun/install/global` | name | `managed:bun|/Users/x/.bun/install/global|cowsay` |
| `pnpm` | pnpm home `~/Library/pnpm` | name (collision rule in §15.5) | `managed:pnpm|/Users/x/Library/pnpm|cowsay` |
| `yarn` | `~/.config/yarn/global` | name | `managed:yarn|/Users/x/.config/yarn/global|cowsay` |

`installPath` = today's package directory, unchanged, so `status.path`, the runtime tag (P11) and duo's `path` keep their meaning.

### The migration: dual keys, no rewrite (recommended, D-P5-4)

The legacy tag is computable from the new row alone: `"<legacy kind>:" + item.installPath`, legacy kind = the manager id (`npm`/`bun`/`pnpm`/`yarn` are today's kind raw values). So:

1. `ManagedItem` (or the payload) carries `aliases: [String]` = `[legacyTag]`, set by the adapter.
2. `UpdateAnnouncementItem` gains `aliases`. `UpdateAnnouncementLedger.pass` asks `wasAnnounced(side, under: [key] + aliases)` — the plural form already exists for the apps' bundle-id → path migration (`Engine/NotifiedUpdateVersions.swift:142-146`, used at `App/Sources/AppListModel.swift:10570-10579`) — records under the key **and** every alias, and counts aliases in `liveKeys`.
3. `notifyNewCLIToolUpdates` (`App/Sources/AppListModel.swift:10601-10613`) passes them.

No one-time step runs, so there is no "migrated" flag to get wrong. It is the same redundancy the apps' ledger keeps for older builds (`lastAnnounced`, `Engine/NotifiedUpdateVersions.swift:99-113`).

Failure modes:

| Case | With dual keys | With a one-shot rewrite instead | With nothing |
|---|---|---|---|
| First launch of P5 | legacy key found → nothing re-announced; new key recorded beside it | nothing re-announced | **one banner listing every npm/bun/pnpm/Yarn package on offer right now** (`pass`: seeded is already true, the new keys are unknown, `UpdateAnnouncements.swift:49-58`); the 5 `npm:` keys are pruned the same pass |
| Downgrade to a pre-P5 build | its `npm:` keys are still there → nothing re-announced; it prunes the `managed:npm|…` keys (not live for it); back on P5 the alias finds the legacy key again → nothing | the pre-P5 build finds no `npm:` keys → one banner; its prune deletes the rewritten keys → P5 then announces once more | one banner each way |
| Two installs on one preference domain (a dev build beside the release, the `lastAnnounced` scenario) | each keeps the other's form alive (P5 records both; the old build prunes only the new form, which P5 restores from the alias) → no ping-pong | ping-pong: one banner per switch | ping-pong |
| Prefix moved / removed (nvm node replaced, `brew` relinks `node` → same `/opt/homebrew` path) | removed prefix: both forms pruned; a new prefix's packages are new rows, announced once if offered — today's behaviour (§3.3, §10 "a moved root") | same | same |
| pnpm 11 → 12 replaced the group (`<hash>` changes, `C/NodePrefixes.swift:239-241`) | new identity is unchanged (root = pnpm home, key = name) but the legacy alias changes → no re-announce, the new form already matches | a rewritten key from the old hash path would map to the same identity → fine | today's behaviour already re-announces once here |
| `notifyOnCLIToolUpdates` off | `pass` records nothing (`UpdateAnnouncements.swift:48`); old keys stay until it is on | the rewrite would still run | — |

Retiring the aliases (D-P5-5): keep them indefinitely — one extra short entry per package; or drop after two releases, accepting one banner on a downgrade across that boundary.

---

## 15.3 Phasing

Never register an adapter beside the provider it replaces: both would list the same package (double counts, double banners) in **different lanes** (`node:<prefix>` vs the manager's), so Update All could run two `npm install -g` into one prefix at once — the race `NpmActivity` exists for (`C/NpmActivity.swift:7-8`). Parity is proven by a test instead, then one commit switches.

**P5.0 — Model extensions, nothing visible.** L1–L8 in `M/`; `ManagedAgreementTests`, new (see P5.2's acceptance), over P1–P4's adapters first; `UpdateAnnouncementItem.aliases` + ledger; `CLIToolsModel.lane(of:)` asks the adapter; `ManagedCheck` applies `hold` and `channel`.
Acceptance: `make test` exit 0 (judged by exit code, project memory); every P1–P4 adapter test unchanged and green (no fixture edited); new `ManagedCheck` table rows, each with its mutation named: a `hold` on an offered row keeps `.updateAvailable` and removes `oneClick` (mutate: apply `hold` as a blocker → the row turns `.unknown`, red); `hold` ignored on `.pinned`/`.upToDate` rows; channel carried. Ledger tests: legacy-only ledger + item with alias → no announce (mutate: drop aliases from `wasAnnounced` → red); record writes both (mutate: record key only → the downgrade test reads the legacy key absent, red); prune keeps aliases (mutate: liveKeys without aliases → red); a simulated pre-P5 pass over the same `persistable` dictionary announces nothing. Runner test: `standardInput` reaches the double. Lane: a fake adapter's per-item lane reaches `CLIRunLaneCopy` (`App/Sources/CLIToolsModel.swift:1617`).

**P5.1 — Adapters, not registered.** `M/Node/Packages/{NodePackages,NpmPackagesAdapter,BunPackagesAdapter,PnpmPackagesAdapter,YarnPackagesAdapter}.swift`, built on the existing scanners, `NpmCheck`, `NpmActivity`/`BunActivity`/`GlobalPackageActivity`, `NpmUpdater`'s restore and reasons (moved, not copied — project rule: no second copy of production logic).
Acceptance: **parity test** over the existing fixtures of `NpmTests`, `BunTests`, `GlobalPackagesTests`, `NpmUpdaterTests`, `BunUpdaterTests`: for every fixture install, old provider's status vs `ManagedProvider(adapter)`'s → identical `(state, installedVersion, latestVersion, channel, oneClick argv, withheld, note, commandToCopy)` except the listed, owner-accepted differences (D-P5-7 copy command, D-P5-11 pause); K12 rows are identical, including `latestVersion` and `note` (L8), each asserted explicitly. Update parity with the runner double: argv, environment keys (`PNPM_HOME`, `PREFIX`, `BUN_INSTALL`; no `npm_config_prefix`), stdin empty, exact-version failure, specifier restore for `^6.0.0`→`^7.0.0`, `7.x` at 8.0.0 → `^8.0.0`, exact kept, Yarn lock key line. Mutations: drop `--engine-strict` → argv assertion red; offer a version whose engines exclude the node → red; run `openclaw update` when an npmrc redirects → red; restore over a user's exact pin → red; pnpm 11 `update -g` instead of `add -g` → red; busy ignored at the click → red. Source test: no `ChildProcess` in any `scan()` (§10).

**P5.2 — The switch (one PR).** Register the four adapters (registry order: after `go`? or first — D-P5-3); remove `NpmProvider`, `GlobalPackagesProvider`, `BunProvider`'s package half (bun's own row stays), the `.npm`/`.pnpm`/`.yarn` kinds and their arms (D-P5-13); App: presentation reads the payload (P2–P6, N4), the managed level header carries P3's mark, wording arms keep today's strings (P8); `duo` names, `npmPackage`, schema (D-P5-6).
Acceptance: `make test` exit 0; `CLIToolsTests.everyKindHasOneProviderInKindOrder` rewritten; `CLIToolPresentationTests` snapshot of `groups` for fixture statuses: one level per prefix, titles and twins as today; `ManagedAgreementTests` run over the four adapters — **it does not exist yet** (§6 proposed it; P1–P4 never wrote it; review round 1 of #1725), so P5.0 builds it: one provider with fixture adapters through both `CLIToolsModel` and `CLIToolRows`, states compared, first over P1–P4's adapters; `duo check --json` row for a fixture package carries `tool`, `manager: "npm"`, `item`, `root`, `channel`, and the chosen `schemaVersion`.

**P5.3 — Mac acceptance (real home, §8.1), then delete dead code.** `make install` + `make cli`. Back up first: `defaults export com.duoupdater.app ~/p5-prefs-before.plist`, and each prefix's packages' versions and the bun/pnpm/Yarn `package.json`/`yarn.lock` (sha256). Fixtures, owner's OK needed (the Mac has no bun packages, no pnpm or Yarn globals today): `npm i -g cowsay@1.5.0` into nvm `v24.22.1`; `bun add -g cowsay@^1.5.0` then pin a second package exactly; `brew install pnpm yarn` (or corepack) with one package each at an old version; the owner's own nvm `v24.13.0` packages and openclaw left as they are, never clicked unless the owner says so.
- Rows: app and `duo check --all --json` agree (state, versions, held-back reason, copy command) on every package; banner: **none** on the first P5 launch; `NotifiedCLIToolVersions` holds each package under both forms (`defaults export … | plutil -extract NotifiedCLIToolVersions json`); then launch the previous release build: no banner, its `npm:` keys intact; back to P5: no banner.
- One-click: cowsay (npm) 1.5.0 → newest, `--engine-strict` in the log; bun cowsay → `^<new>` restored in `~/.bun/install/global/package.json`, only that value changed (`diff`); pnpm and Yarn likewise, Yarn's `yarn.lock` key line extended.
- §13.2: C1 (hold: the P3 pyenv fixture's build in front, as in P3/P4, or a running `npm install` in the prefix for the busy gate); C2 — before the vendor command these adapters read the disk and the process table only (busy, trust, specifier), so as in P2–P4 there is no child to hold; say so with the evidence; C3 (a long `npm install -g` — e.g. a large package — or openclaw if the owner allows its doctor/gateway restart); C4; C5 `duo install npm/cowsay` SIGINT before and during; C6.
- §13.3 D15 table for npm, bun, pnpm, Yarn: SIGINT/SIGTERM at resolve/download, extract (npm's `.<name>-<hash>` staging, `C/NpmInstall.swift:318`), link/`package.json` write; old version runs? next plain run recovers?
- Restore: preferences from the backup only if the owner asks (the run should leave them correct); fixtures removed; `brew uninstall` what was added.
- Then delete what P5.2 left unreachable; `grep -c` each removed type name over `App CLI DuoUpdaterCore` = 0.

---

## 15.4 Decisions for the owner

| # | Decision | Recommendation | Instead of |
|---|---|---|---|
| D-P5-1 (**ruled: yes**, owner 2026-10-27) | Do P5 at all, given the identity gains nothing for these rows (paths do not move) | **Do it only if npm/bun/pnpm/Yarn packages should be managers' levels in the UI and `duo install npm/x` is wanted**; otherwise leave them (they work, and P5.0's L1 teaches the shared model one manager's type) | — |
| D-P5-2 | Managers | **Four (`npm`, `bun`, `pnpm`, `yarn`) over one shared core** — each has its own binary and trust, lane and logo | one `node-packages` manager |
| D-P5-3 | npm root, and where the levels go | **root = the prefix**: one level per prefix, as today's groups, each with its own Update All; registry order after `fnm-node`, so "nvm Node" sits above "npm · nvm v24.22.1" | one npm level, prefix as a fact |
| D-P5-4 | Ledger migration | **Dual keys (aliases), no rewrite** | one-shot rewrite at launch; accept one banner |
| D-P5-5 | Alias lifetime | **Keep indefinitely** | drop after two releases |
| D-P5-6 | `duo` JSON | **`schemaVersion` 3**: the same rows change `tool` from `npm` to `managed` (K12 rows keep their `latestVersion`, see K12), which NDJSON's own rule counts as repurposed (`CLI/Sources/DuoKit/NDJSON.swift:13-22`); D-B's "stays 2" covered new rows only | stay 2 |
| D-P5-7 | An untrusted (ad hoc, unsigned, quarantined) prefix node: the managed rule hands the npm command out to copy | **Keep today's: nothing to copy** for a node that failed the trust rule (the copied command runs that node); adapter opts out | managed rule |
| D-P5-8 | bun's own row stays in "Other tools", its packages move to a "bun global packages" level | **Accept** — the shape of uv / uv tools and mise / mise tools | keep bun's packages under bun's row |
| D-P5-9 | D10's ≤5 breaking-hint documents per pass now covers npm rows | **Accept** — D10 exists for the GitHub budget, which npm notes spend | npm uncapped |
| D-P5-10 | Wording | **Keep every npm string as it is** (matched through the payload): no new translations | generic managed wording |
| D-P5-11 | bun packages stop following the GitHub pause (P9) | **Accept** if the owner agrees today's pause on them is an accident | keep `.ourTokenIfAny` on the bun descriptor |
| D-P5-12 | L1 payload in the shared model | **Accept, one case** | re-word everything as `Fact`s |
| D-P5-13 | Remove `CLIToolKind.npm/.pnpm/.yarn` | **Remove in P5.2**; their raw values live on only as alias prefixes | keep empty kinds |
| D15 | Stopping a started npm/bun/pnpm/Yarn command | ~~(a) `.runToCompletion`~~ **Superseded (owner, 2026-10-27, §13.4 on PR #1722):** stoppable, snapshot and put back; each adapter's `interruption` from its own measured write set, as P1–P4's | — |

---

## 15.5 Could not determine (and what would)

- **pnpm key collisions**: whether one name can sit in two projects at once (`global/5` and a `global/v11/<hash>` after a 10→11 upgrade, or two v11 groups). Not measured; `GlobalPackageHomes.pnpmProjects` comment only says both layouts can exist (`C/NodePrefixes.swift:243-244`). If yes, key = `<name>` for the project the picked pnpm reads and `<name>@<project dir name>` for the other; measure with pnpm 10 then 11 in a scratch home.
- **From-scratch environment for openclaw**: whether `openclaw update` → `doctor` → gateway restart needs variables the inherited environment had. Needs a real run with the owner's OK (it restarts their gateway).
- **`NO_COLOR=1`** (added by `ManagedProvider`) changing npm's or openclaw's failure lines that `npmReason`/`openclawReason` parse. Not measured.
- **Whether bun packages being held by the GitHub pause is intended** (P9): no comment in `C/CLITool.swift:558-563` says so.
- **Who consumes `duo --json` `tool == "npm"`**: no caller in this repo (`grep -rn '"npm"' CLI/Sources` finds only doc comments); outside users unknown — input to D-P5-6.
- **The downgrade and two-install behaviour on a real Mac**: reasoned from `UpdateAnnouncementLedger.pass` and `NotifiedUpdateVersions.prune`, not run.
- **Scan cost**: today's npm scan already computes code signatures per prefix node in `scan()` (`C/NpmInstall.swift:388`); moving it under `ManagedProvider` should not change the cost, but §12 item 16 (scan time) is still owed for P3 and was not measured for this either.
- Nothing was compiled or tested; every "Has" above is from reading signatures and call sites, not from running a fake adapter through them.
