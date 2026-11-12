# Managed-tool fixtures and reference captures

The adapter tests load fixtures by name from their source directory. The files
listed below are **reference-only captures**, not inputs currently read by a
test. They explain vendor behavior the adapters must account for; keeping them
does not mean their exact human-readable wording is an API to parse.

Capture dates and tool versions below come from the corresponding adapter-test
headers and source comments. The observations describe those versions, not a
promise about every future release. Homes were rewritten to `/ZZFixture-home`.

## Reference-only captures

| File | Captured command and provenance | Why it stays |
| --- | --- | --- |
| `mise/offline-outdated.stderr.txt` | `mise outdated --json`, mise 2026.10.7, 2026-10-23, proxy pointed at a closed port | A failed version lookup can still exit 0 and leave `{}` on stdout. Paired with `mise/offline-outdated.json`. |
| `mise/offline-outdated-bump.stderr.txt` | `mise outdated --bump --json`, same mise capture | Backends report different errors, and quiet mode can remove them. Paired with `mise/offline-outdated-bump.json`; stderr text cannot establish that omitted tools are current. |
| `pipx/list-outdated.json` | `pipx list --outdated --output json`, pipx 1.18.4 / Python 3.12.15, 2026-10-27 | Vendor comparison data for pinned cowsay, outdated httpie/ruff and non-index duolocal. The adapter reads metadata and PyPI instead of spawning pipx to check. |
| `pipx/upgrade-cowsay.err.txt` | `pipx upgrade cowsay`, same pipx capture | `pipx pin` prevents an upgrade even when a newer release exists; the command can exit 0 without updating the package. |
| `uv-tool/upgrade-black.stderr.txt` | `uv tool upgrade black`, uv 0.13.4, 2026-10-27, request `>=23,<24` | A range already at its ceiling can print “Nothing to upgrade” and exit 0. |
| `uv-tool/upgrade-ruff.stderr.txt` | `uv tool upgrade ruff`, same uv capture, request `==0.6.0` | An exact pin stays in place; the output suggests `uv tool install ruff@latest` to lift it. |

## Behavior covered by tests

- `MiseToolsAdapterTests.offlineIsNeverCurrent` loads the paired stdout maps and
  makes `mise latest` return no version. Those rows remain unknown rather than
  current. `MiseToolsOutdated` explains why this uses read-back instead of stderr.
- `PipxAdapterTests.theRowsFollowPipxsOwnRules` checks the metadata/PyPI-based
  decisions for a pin, an outdated package and a non-index installation.
- `UvToolAdapterTests` covers exact pins and ranges through the receipt and
  outdated-list fixtures. The upgrade stderr files document why those requests
  must not be treated as unconstrained upgrades.
- `ManagedModelTests.aRunThatMovesNothingIsNotAnUpdate` checks the shared upgrade
  completion rule: a successful exit with the installed version unchanged is
  reported as not updated. `ManagedProvider` rereads the installed version; it
  does not infer success from these human-readable messages.

Two former pipx captures, `upgrade-httpie.err.txt` and
`upgrade-duolocal.err.txt`, contained only “upgrading …” progress lines. They
were removed because neither line recorded the resulting version or proved
whether an upgrade occurred.

When an adapter's decision changes, revisit its matching capture and test.
Retain reference-only files when they explain a distinct decision; remove
captures that no longer support one. Do not add a test that only checks for a
phrase to turn a reference capture into a nominal test input.
