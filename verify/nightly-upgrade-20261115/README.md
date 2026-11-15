# Nightly verification upgrade — 2026-11-15

The history review separated recipe failures from vendor rollout lag and monitoring defects. It did not accept new signing identities, bump acknowledgements, or close issues based on titles.

- [#155](https://github.com/jizhi0v0/duo-updater/issues/155): an installed-copy Sparkle smoke test can check zero pending updates and still succeed. It is useful installation evidence, but cannot enumerate general feed coverage.
- [#1030](https://github.com/jizhi0v0/duo-updater/issues/1030): installer identity changed while endpoint-only checks stayed healthy. Hosted `verify-install` already inspected vendor/GitHub bytes; audited generic Electron/Sparkle feeds were the remaining inventory gap.
- [#1463](https://github.com/jizhi0v0/duo-updater/issues/1463), [#1464](https://github.com/jizhi0v0/duo-updater/pull/1464): no-Team Sparkle copies require an update-key check. A valid archive signature can satisfy that route; a missing Team alone is not proof of a broken update.
- [#1799](https://github.com/jizhi0v0/duo-updater/pull/1799), [#1812](https://github.com/jizhi0v0/duo-updater/pull/1812), [#1972](https://github.com/jizhi0v0/duo-updater/pull/1972): first adoption of a key and replacement of an existing key require different interpretation. The nightly identity store continues to preserve changed anchors for explicit review.
- [#2021](https://github.com/jizhi0v0/duo-updater/issues/2021): Kuvo Box already returns native structured notes through Sparkle. Absence of a separate `ChangelogRecipe` does not establish a native-notes gap.
- [#2022](https://github.com/jizhi0v0/duo-updater/issues/2022): the retired Box feed now serves Kuvo Code. Comparing those products' versions cannot decide whether Box's replacement feed is justified.

Vendor rollout/API lag and absent artifacts remain separate work: [WeChat #1867](https://github.com/jizhi0v0/duo-updater/issues/1867), [#1429](https://github.com/jizhi0v0/duo-updater/issues/1429), [WorkBuddy #1291](https://github.com/jizhi0v0/duo-updater/issues/1291), [Goose #2010](https://github.com/jizhi0v0/duo-updater/issues/2010). [Shottr #1929](https://github.com/jizhi0v0/duo-updater/issues/1929) needs its own installed-updater/artifact investigation. These were not silenced by this monitoring change.

## Coverage and state

`AuditedUpdateFeeds` enumerates 12 Electron and 59 Sparkle configurations from the audit index, independent of installed or outdated apps on a runner. Distinct tracks and observed copy groups keep distinct IDs. Tests compare sets of linked audit documents, not just totals. Two indexed rows and nine tracks have explicit exclusions; 24 Sparkle bundle identities have no established public key in the permitted audit/bundle sources. The inventory lists those limitations instead of claiming complete signing continuity.

Every selected feed resolves on every run. Changed version/URL, previous failures, or an open issue trigger archive inspection; unchanged clean entries retain the existing incremental skip, and a full pass is owed after seven days. Missing installer/parse/404 failures on generic feeds are actionable here because no other registry files them; transient failures retain infrastructure status.

Sparkle archives are checked against the previously recorded key, falling back to an audited key only when none was recorded. A first archive that fails its audited anchor cannot seed a replacement anchor. Installation gates are unchanged. Disappearing inventory IDs produce warnings and preserve identity/issue history rather than being silently pruned.

## Native verification

A newly built CLI on Apple Silicon macOS inspected actual archives without installing applications. The initial four-target run downloaded 251.7 MB in 23 seconds:

```text
ok electron:ai.thinkany.douchat:stable:legacy-root 0.1.28 ai.thinkany.douchat JU9K7W6T6W
ok electron:ai.thinkany.douchat:stable:thinkany    0.1.29 ai.thinkany.douchat 8PL52G56V9
ok sparkle:com.knollsoft.Rectangle:stable        2.0.4  com.knollsoft.Rectangle XSYZ3E4B7D
ok sparkle:run.kuvo.app:stable                    0.1.3  run.kuvo.app C8Y523R7T5
```

These are representative live-byte results, not a claim that every inventoried archive was downloaded locally. The new hosted inventory establishes and monitors the remaining package identities through its normal persisted state.

The final source head was `817b2a1519db95222aeae669fbc045f67ac2fa4c`. Its newly built CLI also produced these results:

- [HandBrake and Vivaldi](redirect-and-tar.json): both `ok`; HandBrake's redirect resolved to a 47,978,117-byte DMG and its full archive verified against the audited key. Vivaldi's 234,511,456-byte tar.xz unpacked and its code identity passed. Vivaldi's missing audited key remains an explicit continuity limitation in the report.
- [Kuvo native coverage](kuvo-coverage.json) and [feed health](kuvo-feed.json): `coverage:run.kuvo.app` and `feed:run.kuvo.app` both `ok`, without an acknowledgement or a cross-product version comparison.
- [Incremental replay](incremental.json): Rectangle and Kuvo Box were both skipped with **0 downloaded bytes**. Only local temporary state was seeded with a recent full-pass timestamp to exercise that branch; production state was untouched.
- [Signing drift](identity-drift.json): a local baseline fixture retained Douchat's old Team `JU9K7W6T6W`. Inspecting the actual current archive returned exit 1 and warned about `JU9K7W6T6W → 8PL52G56V9`; the stored old Team was preserved.

Validation: full `make test` passed all three parts in 163 s; after the final CLI identity fix and merge of report-persistence changes, the complete CLI suite passed **730 tests in 84 suites**, and the 13 report-validator/workflow tests passed. Core source/diagnostic tests were included in the full run. Independent GPT-6 Astra review closed with no remaining findings at the source head above. It found and verified fixes for failed-anchor first-sighting adoption, archive format/redirect classification, and incomplete no-Team payload identity checks.

The companion [PR #2029](https://github.com/jizhi0v0/duo-updater/pull/2029) requires fresh reports and durable issue/state receipts. The Mac mini wrapper was deployed separately with a backup: it deletes prior generated reports, preserves producer exit status, and requires the fresh-report validator before reconciliation. Six local wrapper simulations passed (fresh exit 0/1 accepted; crash, missing, stale and malformed reports blocked), and remote zsh syntax validation passed. Deployment did not run or restart the entire scheduled scan; its next normal checkout update picks up the repository validator.
