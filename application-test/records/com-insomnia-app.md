# Insomnia — channel verification record

Verified 2026-06-06. Stable = installed `/Applications/Insomnia.app`; Beta =
`Insomnia.Core-13.0.0-beta.0.dmg` mounted read-only (not installed). **Shared bundle
id `com.insomnia.app` across channels.** Team `FX44YY62GV` (Kong Inc.).

| Channel | real bundle id | real short ver | detect() | source → verdict |
|---------|----------------|----------------|----------|------------------|
| stable | `com.insomnia.app` | `12.6.0`        | stable ✓ | GitHub `Kong/insomnia` `core@12.6.0` → up to date |
| beta   | `com.insomnia.app` | `13.0.0-beta.0` | **stable ✗** (detect ignores `-beta.N`) | — (channel-gate can't route) |

## Key findings
- **Beta build keeps its suffix**: `CFBundleShortVersionString = 13.0.0-beta.0`
  (NOT stripped, unlike Mozilla) — yet `ReleaseChannel.detect()` returns `.stable`
  because it doesn't parse the version-suffix signal. So a `channel: .beta` rule
  would never pass the gate. Beta/alpha support is **blocked at the detection layer**
  until `detect()` learns the `-beta.N`/`-alpha.N` suffix for this bundle id.
- **Stable cross-channel bug (FIXED)**: Kong publishes `core@13.0.0-beta.0` before
  any `core@13.0.0` stable, so it sorts newest/first. The old unanchored pattern
  `core@([0-9]+\.[0-9]+\.[0-9]+)` captured `13.0.0` from it → pushed beta onto stable
  users as "13.0.0"; the `-beta.0` dmg then failed `installAssetPattern` →
  `vendorInstallerKind` nil → UI showed **"Open"**, not "Update". Fix: `$` anchor →
  `core@([0-9]+\.[0-9]+\.[0-9]+)$`. Offline lock: `insomniaRuleMatchesCoreTagOnly`
  now feeds `["core@13.0.0-beta.0","core@12.6.0",…]` and asserts first match = 12.6.0.

## Live API (2026-06-06)
Newest-first `Kong/insomnia` releases: `core@13.0.0-beta.0`(pre), `core@12.6.0`,
`core@12.6.0-beta.0`(pre), `core@12.5.1-alpha.0`(pre), `core@12.5.0`, … — each with
`Insomnia.Core-<ver>.dmg` + `inso-macos-*` (CLI, excluded by the anchor).
