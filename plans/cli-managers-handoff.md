# Managed tools: hand-off (2026-10-27, end of the D15 session)

For the session that takes over: what is open, what is decided, what to start with, and what bit us. The design is `plans/cli-managers-redesign.md`; read its Status line, §13.4 (D15) and §15 (P5) first. Everything below links there rather than repeating it.

## 1. Open pull requests (all by this session)

| PR | Branch | What | State at hand-off |
|---|---|---|---|
| #1719 | `plan/mise-release-age` | Docs: §12 item 5, mise's `minimum_release_age` measured | CI green (one flaky `readsALiveChild` re-run); Auto-fix on; not merged |
| #1722 | `cli-managers-d15` | **D15**: a managed update may be stopped mid-command and is put back (snapshot + session-wide Ctrl-C + restore), all ten managers; §12 item 16 (scan cost) in the plan | Review rounds 1–2 addressed (`c4196960`, `3625bb49`); real-Mac record redone on the session build (plan §13.4, PR body); `make test` green (the WebKit download test `DownloadJobResumeServerTests` times out under load now and then; `make test-app` alone 322/322); Auto-fix on; awaiting review round 3 |
| #1724 | `cli-p4-leftovers` | P4 follow-up: cargo-binstall rows say so; Google-signed `/usr/local/go` runs | `make test` green; real-Mac via `brew unlink go` (relinked); Auto-fix on; branch was cut before main moved — CI will say if it needs a sync |
| (this) | `plan/p5-handoff` | Plan §15 (P5 design, D-P5-1 ruled) and this file | docs only |

The three plan edits (#1719, #1722, this) each touch `plans/cli-managers-redesign.md`; #1719 and this one both append at its end, so whichever merges second needs a trivial rebase.

## 2. Decided by the owner on 2026-10-27

- **D15**: stop like a terminal's Ctrl-C, but only where nothing can be damaged → built as §13.4 (snapshot, stop, put back). Every new adapter needs an `interruption` plan **from measured writes** (§13.4's method: isolated home, the adapter's own argv/env, SIGINT at every stage, byte-for-byte compare) and a `ManagedInterruptionTests` case whose mid-run writes touch every path and rule of the plan.
- **P5: do it.** "Other tools" stays a flat list of what the user installed on its own — no groups in it. Anything a manager keeps (npm/pnpm/Yarn globals, bun's packages) moves to that manager's own level. D-P5-2…13 are still recommendations: **ask the owner before P5.2** (the switch).
- **Go logo**: none for now. An approval request went to trademark@golang.org from jizhiovo@gmail.com (signed "jizhi") on 2026-10-27. If they approve, the asset already in the repo (`App/Resources/Assets.xcassets/FormulaLogos/brew-go.imageset`) can be reused for the go level, in the form the request described (single colour, not cropped).
- **cargo-binstall**: show it (done in #1724).
- **`/usr/local/go`**: trust Google's signature (done in #1724). The owner's Mac now has go.dev's Go in `/usr/local/go` (+ `/etc/paths.d/go`); whether to keep it is the owner's call (uninstall: `sudo rm -rf /usr/local/go /etc/paths.d/go && sudo pkgutil --forget org.golang.go`).

## 3. Still waiting on the owner

- The "decisions taken while writing" of P0, P2, P3, P4 (status log entries; also listed in Chinese in the owner's copy of `owner-decisions.md` from this session). None was answered yet; nothing waits on them.
- D-P5-2 … D-P5-13 (§15.4).

## 4. P5: where to start

1. Read §15 whole, then §13.4. §15 was written before D15 and the owner's principle; §15's own text is otherwise unchanged and its line numbers were read at `03331828` — re-read the code before trusting any `file:line`.
2. **P5.0** (model extensions, nothing visible): §15.1 "Lacks" L1–L7 and the ledger aliases (§15.2). Land green with P1–P4's tests unchanged.
3. Measure the four managers' write sets for D15 *before* writing their adapters: npm's in-place replace of `<prefix>/lib/node_modules/<name>` and its `.<name>-<hash>` staging (`C/NpmInstall.swift`), bun's global install, pnpm's `global/5` and `global/v11/<hash>` projects plus the store, Yarn 1's global dir. Same method as §13.4.
4. Then P5.1 (adapters unregistered, parity test) and P5.2 (the switch, one PR), P5.3 (real Mac, C1–C6, dead code) as §15.3 says. Never register an adapter beside the old provider (two `npm -g` in one prefix at once).
5. Check the principle on the result: after P5.2, the workbench's "Other tools" must hold no group at all.

## 5. Found, not fixed (follow-ups)

- **mise rows can vanish**: a mise tool whose only installed version is in mise's purgatory (`scheduled_for_pruning: true` — after `mise upgrade` and a later `mise uninstall` of the new version) gets no row, because `MiseToolsLs.Entry.isRow` excludes every purgatory entry. The whole "mise tools" level can disappear. Seen on the Mac 2026-10-27; P1 code, on main.
- **Scan cost floor**: §12 item 16 measured the standalone tools' scan at a median of ~2.5 s per popover open (off the main actor); not looked into. mise's managed scan repeats the standalone mise row's 138 MB signature check (~370 ms, in parallel).
- **Other managers' stops in the app**: on the Mac, D15 was exercised in the app for mise and cargo only (duo for cargo too). The other eight are covered by isolated-home measurements and `ManagedInterruptionTests`.

## 6. How the real-Mac runs were done (and what bit)

- **Leases**: `claude-lease acquire duo-app` before `make install` (a hook enforces it), `screen` before driving the UI; release right after.
- **Drive the app in the background only**: `request_access(["DuoUpdater"])` (granted, full tier), then `app_menu` (Window ▸ DuoUpdater to open the workbench; DuoUpdater ▸ Quit), `app_click`/`app_type` on the search field (`app_type` with `mode: replace` is refused in the background: clear with the field's cancel button first). Relaunch with `open -g`. Never raise windows or post global CGEvents — the owner objected when this session did.
- **AX presses** for row buttons: an `ax press <pid> <x> <y>` helper (AXPress on the element whose frame origin matches) and `cancel-when.sh` (wait for a row line, then press the row's "Cancel update"). Row buttons carry the install path in `AXHelp`.
- **Byte-for-byte compare**: a lister printing path, type, mode, size, sha256 (or link target) — inode and mtime excluded; run before and after.
- **duo Ctrl-C**: write `\x03` to duo's pty (a `pty.fork` helper), not `kill -INT`.
- **zsh does not split variables** (`$XY` with "265 238" is one argument): three "identical" trials ran nothing before this was noticed. Put trial loops in `bash` scripts.
- **mise fixture trap**: downgrading with `mise install node@old && mise uninstall node@new` after an upgrade leaves `old` in purgatory → no row (see §5). Clear `~/.local/state/mise/tool-purgatory.json`'s entry, or don't uninstall the new one.
- **Session probe**: to see whether a vendor's descendants stay in the command's session, walk descendants by ppid every 50 ms and read `os.getsid`; a descendant read after it exited gives `ESRCH`, which is not an escape.
- **Fixtures left on the owner's Mac** (per the ledger memory): mise node at 20.20.2 (20.10.0 in purgatory, pruned by mise within 24 h); tokei 15.0.0; gofumpt v0.12.0; `/usr/local/go` installed.
