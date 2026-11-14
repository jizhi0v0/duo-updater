# Kuvo Box / Kuvo Code integration — 2026-11-15

Two products, two bundle IDs. This fixes DuoUpdater's source selection without authorizing cross-product replacement. Official repositories: [Box](https://github.com/serhatandic/box), [Code](https://github.com/serhatandic/kuvo).

## Build and environment

- Product source commit: `25798276a8a61dd9d3a481bf59febed1c3ddc7f7`, base `8475f6389b141e45603e43c30f31df391c0ce25b`.
- Signed Release app and CLI built with Xcode; Sparkle helper signing, strict signature verification, all 11 localizations and macOS 15 Swift back-deployment checks passed. Both binaries signed by DuoUpdater Team `RS59HDH7Y3`.
- CLI source digest: `f5da0a8f058a1a55d07b04a8d53c453f92e8a2e4e3138473ccb04f62c0dede42`.
- Dedicated Apple Silicon VM `Duo Kuvo integration`, macOS 27.2 (`26B123`), 4 CPUs / 8 GB. Host date 2026-11-15; guest clock displayed Nov 14. No host Kuvo app or preferences changed.
- `make test`: exit 0, scripts / App / Core all passed (162 seconds). Targeted Box, Code, catalog and binding tests: 25 passed. Recipe goldens: 7 passed.

## Detection and upgrades

| Product / state | Input | Result and receipt |
|---|---|---|
| Box baseline, old CLI | 0.1.2 / `run.kuvo.app` | Incorrectly offers Code 0.7.2: [baseline](vm/baseline-box-check.json) |
| Box fixed source | Same installed bundle | Offers Box 0.1.3 from `serhatandic/box`, with relocated enclosure: [check](vm/fixed-box-check-before.json), [full chain](vm/box-channel-before.txt) |
| Box stopped | 0.1.2 → 0.1.3 | `installed`, `applied:true`, Sparkle, 3,659,402 bytes: [receipt](vm/box-install-stopped.json) |
| Box running | 0.1.2 → 0.1.3 | [Installed](vm/box-install-running.json), [`duo restart` succeeded](vm/box-restart.txt), [five polls over 10 seconds remain 0.1.3](vm/box-post-restart-versions.txt) |
| Code stable, stopped | 0.7.1 → 0.7.2 | `installed`, `applied:true`, Sparkle, 29,022,193 bytes: [receipt](vm/code-install-stopped.json) |
| Code stable, updater ready | 0.7.1, Sparkle downloaded 0.7.2 | [`install` defers](vm/code-install-running.json); [`restart` hands off to updater](vm/code-restart.txt); [0.7.2 persists](vm/code-post-restart-versions.txt) |
| Code beta, running | 0.7.2 → 0.8.0-beta.1 | UI toggle writes true, [check selects beta](vm/code-beta-ui-on-check.json); [installed](vm/code-beta-install-running.json), 31,862,955 bytes; [restart](vm/code-beta-restart.txt) and [10-second polls](vm/code-beta-post-restart-versions.txt) pass |
| Code beta turned off | 0.8.0-beta.1, explicit false | [Stable feed selected, `hasUpdate:false`](vm/code-beta-ui-off-check.json); [install has no plan items](vm/code-beta-ui-off-install.json), no downgrade |

Both stable installs passed strict deep signature and Gatekeeper checks with the correct product ID and Team `C8Y523R7T5`: [Box](vm/box-installed-signature.txt), [Code](vm/code-installed-signature.txt). The beta also [passed strict deep signature verification](vm/code-beta-signature.txt). Stopped installs were compared recursively with the official mounted DMGs: no differing files; macOS `diff -r` reported directory-loop warnings for Sparkle framework aliases. Both stable bundles subsequently [report up to date](vm/both-up-to-date.json).

`KeepBackups=0` was inherited and preserved, so the installs intentionally produced no new Kuvo rollback copies. [Settings](vm/duo-backup-settings.txt). Previous baseline backups in the VM were left untouched.

## Native changelog and channel UI

- Box: `source structured: 1 entries; newest 0.1.3: 10 items`, headings `What's new` / `Fixes`. [Workbench screenshot](box-native-changelog.jpg).
- Code stable: `source structured: 1 entries; newest 0.7.2: 8 items`; beta: `2 entries; newest 0.8.0-beta.1: 25 items`. Vendor bullets have no section headings to preserve. [Stable feed in the workbench after beta opt-out](code-native-stable-wait.jpg); [beta harness](vm/code-beta-channel.txt).
- Code's real Settings → General → Get beta updates switch was turned on at 0.7.2 and off at 0.8.0-beta.1. [Off state screenshot](code-beta-off-settings.jpg), [true](vm/code-beta-ui-on-pref.txt), [false](vm/code-beta-ui-off-pref.txt). The workbench has no Update action for the older stable release.

## Updater staging and limits

Code's own updater was allowed to download the legitimate stable update. It left a 29,022,193-byte DMG at `~/Library/Caches/run.kuvo.code/org.sparkle-project.Sparkle/Installation/<random>/<UUID>.dmg`, and its UI said Ready to Install. [Files before handoff](vm/code-staging-ready.txt); [no staged files remain afterwards](vm/code-staging-after.txt). `duo restart` waited for the updater to apply it and reopen the app.

The Box app itself still declares the old feed. Its own update prompt offered Code 0.7.2; this change corrects DuoUpdater's path, not the vendor's signed bundle. We did not let Box download that wrong product. No older staged-version collision was constructed for either product; the Code staging test covers a same-target handoff. Box Docker workloads / nested virtualization and Code coding sessions / accounts were not validated.

## Local adversarial review — 25798276 (2026-11-15)

Reviewer: separate `gpt-6-astra` adversary. No findings, 0 blocking. Reviewed all shipping changes, including final source commit.

- **trust**: Box and Code share signing Team and Sparkle key. Retained exact product ID checks and did not introduce a Bundle ID migration; regression test confirms no cross-product acceptance.
- **untrusted-input**: relocation is bound to the catalog's bundle ID and exact feed. Only HTTPS GitHub release paths from the old repository move; tags, file names, lengths and signature metadata remain intact. Other origins, apps and feeds are unchanged.
- **data-loss**: inspected full/delta URL paths and beta opt-out behavior for product replacement or downgrade; no blocking defect found. VM receipts above supply installation and restart evidence.
- **secrets**: the added CFPreferences read is scoped to the non-secret `run.kuvo.code` / `updates.betas` Bool. It reads no account credential or token and has no new logging or network disclosure path.

Shipping-only binary diff SHA-256 against base: `37aaf5724873b838c847fd77688a6573548fc4bae24b4dd9a076bc6ffeae997e`.

## Retained state

Both test products were quit. Dedicated validation VM is suspended, retaining Box 0.1.3, Code 0.8.0-beta.1 with beta updates off, packages and evidence. Temporarily suspended `Duo recipe seven 27.2` was resumed from its saved session. Host app installation and existing local changes were left in place.
