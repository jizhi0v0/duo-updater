# Managed tools in the CLI tab: a shared model for "manager → many items"

Design for jizhi0v0/duo-updater, branch `runtime-composition-detail`, HEAD `cbc6bcc1`. Repo paths: `C/` = `DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/`. Evidence IDs refer to the twelve research files; review verdicts override reports (corrections are applied inline and marked "corrected"). Anything not in that set is in §12.

**Status (2026-10-24): §0 done, P0 green on CI; P1 (mise tools) green on CI and through the Mac acceptance; owed: §12 items 2 and 5, the owner's answer on P1's decisions.** The owner took every recommended option (§11). §0's survey is `plans/cli-managers-int-on-main.md` (committed beside this file); P0's code is on `plan/cli-managers-redesign` (PR #1613) — see the status log at the end of this file for what is in and what is not. Before P1, read §13 (cancel, which every adapter must measure for real).

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

- **Workbench CLI tab**: one `cliToolHeader(group)` per managed group (title = `descriptor.displayName`; summary = manager version · root via `headerSummary` reading `.managed(ManagerContext)`), then `CLIToolSidebarRow` per item exactly as now (icon via descriptor logo/tint; title = `status.name`; caption = `versionCaption` → "20.10.0 → 20.20.2", pinned wording from `CLIToolWording.pinned` generalised to the request; trailing = Update / copy glyph / nothing by the existing rules, CLIToolsWorkbench.swift:276-297). Each manager's items are a **top-level level of their own** beside Homebrew and "Other tools" (D12, revised 2026-10-24): a `HomebrewGroupHeader` titled with the group ("mise tools") and its own Update All, a counts row (manager version · root), then the rows. Open by default; a closed one is remembered only for the window. "Other tools" keeps the standalone tools alone.
- **Rows represent**: mise — one row per (tool, request) in the user's config (two requests of node = two rows, MISE-51); uv tool/pipx/cargo/go — one row per package/binary; version lines — **one row per line (major for Node, minor for Python/Ruby)** showing the newest installed patch, older patches as an "Also installed" fact (D1). A mise node version also appears as an npm prefix header ("mise · node 20") — different thing (the packages in it), kept.
- **States and words**: `updateAvailable` → tinted `a → b` + Update; `pinned` → "Pinned to `1.6` in mise's config, so it doesn't follow new releases" + copy glyph for `mise upgrade --bump jq`; range held → caption shows installed, pane fact "26.12.1 available beyond `20` — `mise upgrade --bump node`"; `unknown` → existing reasons; busy → "mise is already changing its tools" (manager-specific wording via `reason(_:of status:)`). `rowWarning` (orange caption, already exists) carries `.dropsSpecifier` and `.packagesNotCarried` before the click (D7).
- **Detail pane** (`CLIToolDetailPane`): header name + install path (unchanged); facts from `ManagedItem.facts`/`effects` (Source config, Request, Backend, Also installed, Default alias, Python, Target, Known by, What the update does: "keeps the old version for 24 h" / "rebuilds from source" / "leaves `default` on 22.21.1"); release notes view unchanged.
- **Popover tool groups (2026-10-24, owner's pick after real-Mac trials)**: Homebrew stays its own row. "Other tools" gets a sideways chevron (› closed, ‹ open) between its title and its line, shown while at least one group has work. It slides in a page — `ToolsPage` — over the app list, at the list's height, with a "‹ Other tools" header: one row per group with work (named by the group: "Claude Code", "npm · nvm", "mise tools"), each with its own Update (`CLIToolsModel.updateAll(in:)`, the group's `CLIRowSnapshot.scoped`) and Cancel (`cancelRow(in:)`); the parent row keeps Update All. A row's name opens the workbench on that group's first copy with work, selected and scrolled to (`requestedWorkbenchCLITool`). The search field stays in place and searches the groups while the page is open. The page keeps the rows it opened with until it closes, so a group whose update ended does not leave from under the pointer; the page and the list are one strip moved by offset, so quick toggles leave no copies behind. Not remembered across popover opens.
- **Popover `CommandLineRow` lines**: managed rows are tool statuses, so "N updates", "held back", "Updating mise tools" (uses `kind.displayName`; for `.managed` the head line should name the manager: one `if` in `toolsHalf` reading the first claimed status's descriptor, MenuContentView.swift:897-899). Banner/badge: `offered.count` and `UpdateAnnouncementItem(key: tag, name: item name)` unchanged (AppListModel.swift:9429-9442).
- **New UI, only one**: none strictly; the "Also installed" fact and the effects facts are new *rows* in the existing facts table, not new controls.

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

**P1 — mise tools.** `C/Managed/Mise/{MiseToolsAdapter,MiseToolsLs,MiseToolsOutdated}.swift`, registry line, strings. Acceptance: unit fixtures from `r-mise-asdf/out-cur-ls.json`, `out-cur-outdated2.json`, `out-cur-outdated-bump.json`, `out-old-ls.json`, `out-old-outdated-bump.json`, the 2024.12.6 empty-stdout case; mutation checks (§9). Real machine, isolated: `HOME=<iso>` populated like the researchers did (`MISE_DATA_DIR` et al. point into `<iso>` because the adapter sets `HOME=<iso>` for the child), `<iso>/.local/bin/mise` a symlink to the real signed binary, tools `jq="1.6"`, `node="20"`, `npm:prettier="2.0.0"` installed at old versions; run the provider via a test executable with `home: <iso>`: expect rows node (`updateAvailable` 20.10.0→20.20.2), jq (`pinned`, copy `mise upgrade --bump jq`), prettier (`pinned`); one-click on node → `.updated("20.20.2")`, config byte-identical, purgatory entry present, `alsoInstalled` shows 20.10.0; `duo check --json`/`duo install mise/node` on the same iso home agree with the app's statuses; before/after `stat` of `~/.local/share/mise`, `~/.config/mise`, `~/Library/Caches/mise` identical (the researchers' `before.txt/after.txt` method); UI: duoshot of the workbench group header, a pinned row with the copy glyph, an updating row, the popover "Updating mise tools"; `make install` + real popover open shows the group without the user's real mise config being written (owner's OK needed only if the real home is used — it is not).

**P2 — uv tool, pipx.** Adapters + `PyPIProject` fetcher + `ProjectURLRepo` rule. Fixtures: `r-uv-pipx/pipx-list-*.json`, the `uv tool list --outdated` log text (with `- ` lines), receipts from `iso/uv-tools/*/uv-receipt.toml`, 0.5.0 receipt shape (UV-28). Real machine: iso `UV_TOOL_DIR` under `<iso>/.local/share/uv/tools` with ruff `==0.6.0` (pinned), black `>=23,<24` (reported, D9), cowsay unpinned (update); `pipx` venvs under `<iso>/Library/Application Support/pipx` with one `pipx pin`. Expect states as §3.2; uv one-click on cowsay → `Updated` on stderr parsed, settle by dist-info; pipx rows show copy command (until D5).

**P3 — lines: uv python, nvm Node, fnm Node, pyenv, rbenv.** `NodeDistIndex` + `NodeChangelog` parser; definitions readers; nvm bash runner. Fixtures: trimmed `index.json` (first 40 entries incl. a `security` one and the first Jod), `r-pyenv-rbenv` definition name lists (`ls share/python-build`), `rbenv versions --bare` unsorted sample. Real machine: `<iso>/.nvm` with v22.21.1 and the real `nvm.sh` copied (NVM-05 recipe) → one-click `nvm install 22 --reinstall-packages-from=22.21.1` yields v22.23.4 beside it, `default` unchanged, globals carried; fnm with `--fnm-dir <iso root>`; pyenv/rbenv one real build each (~2–3 min, as the reviewer did) only after D5; uv python 3.12.5 → upgrade → 3.12.15 with old dir kept.

**P4 — cargo, go.** Fixtures: `r-cargo-go` `.crates.toml`/`.crates2.json` samples, `api-tokei.json`, a sparse-index file in publish order (rand's tail `0.8.7, 0.9.5, 0.8.8, 0.10.3`), `go version -m` text samples (tagged, pseudo, devel, dirty). Real machine: `CARGO_HOME=<iso>/ch` with tokei 14.0.0 `--features yaml` → row `updateAvailable` 14.0.0→15.0.0 → one-click → 15.0.0 **with yaml kept** (D8); hexyl git row reported; `GOBIN=<iso>/go/bin` with gofumpt v0.9.1 → `go list` latest v0.12.0 → one-click → v0.12.0; `GOTOOLCHAIN=local` case reported.

Every phase P1–P4 also passes §13.2 (C1–C6) for each adapter it adds and delivers that adapter's §13.3 measurements. A phase is not done without them.

Every real-machine step: isolated roots only, never the user's `~/.local/share/mise`, `~/.nvm`, `~/.cargo`, `~/go`; before/after `stat` proof attached to the PR (project rule: paste commands and raw output).

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
| D12 | Managed groups **after the standalone kinds, in registry order**. **Revised 2026-10-24 (owner):** each manager is a top-level level of its own after "Other tools", not a group inside it; the popover reaches them through "Other tools"' tool groups page (§5) | interleaved after each manager's own row |
| D13 | go latest: **`go list -m -json <mod>@latest`** (honours GOPROXY/GOPRIVATE, skips retracted) | direct proxy HTTP |
| D14 | asdf: **not onboarded** | onboard |
| D-A | A newly scanned manager's current offers are **announced once** | silent first pass |
| D-B | duo JSON: **schema stays 2**, `tool: "managed"` + new `manager` key | schema 3 |
| D-C | bub's uv-tool/pipx venvs **fold into the managed rows in P2**; `BubProvider` keeps only bub's own installer method | keep `BubProvider` as is |

Open, to be decided from §13's measurements: **D15**, whether any manager's command may be stopped once it has started.

## 12. Needs verification before implementation

Each: the check to run, in an isolated home.
1. **mise from a GUI cwd `$HOME` with an untrusted config**: `env -i HOME=$ISO PATH=/usr/bin:/bin $ISO/.local/bin/mise ls --json` and `outdated --json` with an untrusted `$ISO/mise.toml` — does it prompt, skip, or fail? (MISE could-not-verify #7.) Decides D3.
   **Done 2026-10-23** (mise 2026.10.7 linux-x64, isolated home, stdin `/dev/null`): a `~/mise.toml` with only `[tools]` is read with no trust asked; one with `[env]` makes `ls --json` from `$HOME` fail — `mise ERROR Config files in ~/mise.toml are not trusted.`, exit 1, nothing on stdout. **`mise install -y` / `upgrade -y` run from `$HOME` trust it**: they wrote `~/.local/state/mise/trusted-configs/<home>` and installed its request. From `/`: only the global config is read (not `~/mise.toml`, not `~/.tool-versions`), and `install -y` / `upgrade -y jq` wrote no trusted-configs. → D3's fallback, cwd `/`.
2. **mise token retry string on backend installs**: with the anonymous budget spent, `mise upgrade -y jq` (aqua) and `github:BurntSushi/ripgrep` — is "No GitHub token was found" printed as for self-update (INT-80)? Decides whether `ManagedTokenRetry` applies.
3. **mise `upgrade -y` and PATH needs**: `env -i HOME=$ISO PATH=$ISO/.local/share/mise/shims:$ISO/.local/bin:/usr/bin:/bin mise upgrade -y npm:prettier` and `pipx:ruff` (MISE-76): do npm/pipx backends find node/uv? Record the exact PATH prefix needed.
   **npm done 2026-10-23**: with `"npm:prettier" = "2"`, `PATH=/usr/bin:/bin` alone (no node anywhere on it) upgraded 2.0.0 → 2.8.8 — 2026.10.7 runs its own node. The shims and `~/.local/bin` still lead `PATH` (§4.1). pipx not measured.
4. **Timing**: wall time of `mise ls --json`, `outdated --json`, `outdated --bump --json` warm and cold (**mise done 2026-10-23**: 15 ms; 520 ms cold / 15 ms warm; 194 ms / 17 ms, three tools); `uv tool list --outdated` with 10 tools; `go list -m -json X@latest` per module — all must fit the 15 s rule.
5. **mise default `minimum_release_age` in `outdated`**: observe on a release <24 h old (MISE-30 narrow measured only 400d).
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

These run per adapter, in an isolated home (same rules as §8.1), against `make install`'s app and the installed `duo`. Paste every command and its raw output into the PR, with a before/after `stat` of the manager's root.

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

**Decisions taken while writing (owner to confirm or reverse):**

- D3's fallback (cwd `/`), on §12 item 1's measurement. A request in `~/mise.toml`, `~/.tool-versions` or a project is not a row.
- Notes: none for `core:node` (P3's `CHANGELOG_V<major>.md` parser), `pipx:` (P2's PyPI rule) and `asdf:` — an asdf id names the plugin's repository, not the tool's (the design listed it with github/ubi).
- Two requests of one tool: the one `mise outdated` names is answered; the other is `.unknown` with the reason. Both carry a note that one click moves every request of the tool.
- Offline (review rounds 3–4): mise prints `{}` to both reads and exits 0, and what it warns depends on the backend (`core:node` "Error getting latest version for node", aqua's jq only "Remote versions cannot be fetched for jqlang/jq") and on `quiet` (nothing). So a row the two maps leave out is current only once `mise latest <tool>@<request>` printed a version, and a pin is held only once `--bump` or `mise latest <tool>` named what lies beyond it; otherwise `.unknown`. Online `mise latest` answered in 14–400 ms; offline it printed nothing for every backend tried. A `mise latest` that hits the 15 s deadline stops the rest of that check.
- `CLIToolsModel.summary` (a log line) still says "Managed tools ×N".

**Not done (owed before P1 is accepted):**

- `make test` on a Mac (CI).
- §8.1's real-machine acceptance and §13.2 C1–C6 with `make install`'s app and `duo` on a Mac: the vendor's behaviour above was measured on Linux with the real mise binary, never DuoUpdater running it. Signature and quarantine of the macOS binary were not re-read.
- §12 item 2 (the token-retry marker on a backend install) and item 5 (`minimum_release_age`).

### 2026-10-24 — P1 on the Mac, and the managers' own levels

**Mac acceptance** (`make install`'s app and `make cli`'s `duo`, in the owner's real home — `duo` and the app read `homeDirectoryForCurrentUser`, not `$HOME`, so an isolated home was not possible): rows, signature, one-click node, `duo` agreeing with the app, offline, C1–C6 all passed; results and raw output are in PR #1613's description. Not seen: the popover line "node updated to 20.20.2" (it shows only when nothing else under "Other tools" is outdated).

**UI, from trials on the Mac** (§5, D12 revised):

- Workbench: one top-level level per manager (`managerLevels`), with its own Update All (`OtherToolsUpdateAllButton(scope:)`) and counts; `SidebarSelection.cliOrder(managers:)` walks them last.
- Core: `CLIRowSnapshot.scoped(to:updateAllOffered:updateAllStartable:)` — a group's own snapshot, running only while Update All holds one of its copies.
- `CLIToolsModel`: `updateAll(in:)` (while another Update All runs, a group's click queues its copies one by one), `rowSnapshot(in:)`, `cancelRow(in:)`.
- Popover: the tool groups page (§5); a row opens the workbench on its tool; the empty list's placeholder icons share one 41 pt box (the magnifier drew 34 pt beside the seal's 39); "N updated" when more than one copy was just updated, where it used to name the first ("jq updated to 1.8.2" after three).

**Still owed:** §12 item 2 (the token-retry marker on a backend install) and item 5 (`minimum_release_age`); the owner's answer on the four decisions in the P1 entry above.
