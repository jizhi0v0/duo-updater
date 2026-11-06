# Homebrew rows and queue availability — VMPal verification

Verification date: 2026-11-06. Environment: Apple Silicon macOS VM managed
by VMPal, macOS 27.2 (26B123), Release build 0.5.24-beta.1.
The host installation was not replaced.

This public record intentionally excludes full-desktop screenshots, personal
paths, machine identifiers, unrelated application inventories and raw logs.
Original screenshots remain local. Application names below identify only the
public casks needed to explain the tested behavior.

## Nested official cask and third-party tap

Installed LuLu 4.5.7 and CompressO 4.1.0 into one ordinary subdirectory of
`/Applications`, with Caskroom links pointing to the installed apps.

- Official 0.5.23 showed both the LuLu app row and a redundant `lulu` package row.
- The fixed build showed one LuLu row, while retaining the qualified
  `codeforreal1/tap/compresso` package row. CompressO also remained in Apps.
- Temporarily reinstalled CompressO 4.0.0 from its tap's historical cask,
  restored the current cask definition, then clicked the package row's Update.
- Observed `brew upgrade --cask -- codeforreal1/tap/compresso`.
- Bundle metadata, Homebrew's installed version and the UI all returned 4.1.0.
  The CLI link still resolved into the nested CompressO bundle; the tap
  worktree was clean after restoring its definition.

Executable SHA-256 for the tap upgrade verification:

```text
d891c9338d70d663d889fd32cd0fd9bab2f3efad279d3c49fd41765189a37c3b
```

## Upgrade All and popover

The follow-up build added only the queue-aware batch offer and its tests.
Its executable hash matched between the host build and the installed VM app:

```text
21655035cee7b372a616cc5264648b005240eb16e8ce11bdff905e9574f62404
```

Used two disposable CLI casks in a VM-local test tap, versions 1.0 → 2.0,
with a 90-second preflight to make intermediate states observable.

| State/action | Observed result |
| --- | --- |
| Two outdated targets, neither claimed | Upgrade All visible |
| A running, B unclaimed | Upgrade All remains visible |
| A running, B queued | B says Queued; Upgrade All hidden |
| Cancel B's queued run | B's Update and Upgrade All reappear |
| A finishes; click Upgrade All | Remaining B updates successfully |
| Reset B to 1.0; start its individual update | Single-target Upgrade All hides |
| Individual or batch run in progress | Popover shows progress and cancellation, without Update |
| All runs finish | Popover returns to Up to date |

Background scans can reduce the outdated count during installation; the
popover continues showing the claimed run until it finishes. Both test
executables ultimately returned `2.0`; `brew outdated --cask --json=v2`
returned empty arrays. Removed the two test casks, their temporary trust
entries and the test tap, then stopped the fixture HTTP server.
LuLu and CompressO were unchanged during the queue follow-up.

## Automated checks

- `swift test --package-path DuoUpdaterCore --force-resolved-versions --filter
  'BrewOutdatedCaskTests|BrewUncheckedPackageTests|BrewFormulaServiceTests|BrewAskPassTests'`:
  65 tests passed after the tap changes.
- `swift test --package-path DuoUpdaterCore --force-resolved-versions --filter
  'BrewRowViewTests|CLIRunQueueTests'`: 20 tests in 2 suites passed after the queue change.
- `make test-app`: 328/328 App cases passed; 1253 localization keys agree.
- Release build succeeded; strict signature verification passed in the VM.
- `git diff --check`: passed.

The standalone duo CLI was not exercised in this VM run. It consumes the
same Core cask classification logic; the batch-header change is App UI only.
