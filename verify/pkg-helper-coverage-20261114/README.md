# PKG helper VM coverage — 2026-11-14

This is a package-helper validation record, not a full distribution/channel audit.

## Result and scope

The final change enables 19 app identities: the existing 18 pins plus AdGuard.
All 19 completed a real signed XPC client → root helper → `/usr/sbin/installer`
installation and strict post-install signature validation in macOS VM 1
(Apple Silicon, macOS 27.2 build 26B123). Most were same-version reinstalls.
Tailscale completed a genuine 1.104.6 → 1.104.7 upgrade.

Covered identities: Shottr; AdGuard; TimeMachineEditor; Tailscale; UU Remote;
WeChat DevTools; Open Screen Sharing; XQuartz; Microsoft Excel, Word,
PowerPoint, Outlook, OneNote, OneDrive, Teams, Microsoft 365 Copilot, Edge,
Edge Beta and Edge Dev. Exact versions, package SHA-256 digests, installer
teams, source URLs without query parameters, and per-app receipts are in
[receipts/packages.json](receipts/packages.json).

AdGuard stable 2.20.3 (2633), beta 2.20.3 RC 1 (2634) and nightly
2.21 Nightly 2 (2635) each completed helper installation. These were deliberate
VM track switches for validation; production uses the installed bundle's feed.
Microsoft stable was tested, with Edge Beta/Dev as separate identities. Other
Office Insider/preview package groups, Shottr historical builds and WeChat
RC/nightly were not installed in this batch. Their absence is not an all-channel
certification; prior channel evidence in the per-app audits remains separate.

The first batch used a prototype with additional ToDesk/AweSun pins; later
batches used the WeChat alias fix. Healthy-app admission and protected-package
checks were identical for the final 19 identities. AweSun's experimental success
is retained as evidence but does not approve it. Final-build verification is
recorded below; the full large-package batch was not repeated after changing
pre-execution refusal handling.

## Explicit holds

- **ToDesk (`com.youqu.todesk.mac`)**: official old 5.1.0.0 installs successfully,
  but the installed copy fails strict resource-signature validation (OSStatus
  -67054). The prototype helper refused it before installation, leaving the
  version unchanged. Current 5.3.1.0's PKG is signed/notarized by KM56KD59W4,
  but that alone does not make the installed copy eligible. No pin added.
  The script creates writable resources inside the bundle; no exploit is claimed.
- **AweSun (`com.oray.sunlogin.macclient`)**: CN 16.6.0 helper reinstall worked;
  old 16.5.0 starts and mutates signed resources, failing strict validation.
  More seriously, official global and CN 16.6.0/32198 share bundle ID,
  ZBNMDRTU32 team and `/Applications/AweSun.app` destination. The fully extracted
  global app passes strict validation. CN/global preinstall scripts select
  `CURRENT_OVERSEAS=0/1`; crossing editions with a logged-in console user deletes
  that user's `Library/Application Support/AweSun` without backup. No deletion
  test was executed. The current production recipe is CN-only, so the new pin
  is withheld until reliable edition routing exists. The endpoints currently
  publish the same version: this does not demonstrate an update offered today.
- **ChatGPT Classic (`com.openai.chat`)**: current signed/notarized update PKG
  deposits `ChatGPT Classic.app.zip` under `/Library/Application Support/OpenAI/`
  and declares no installed app bundle. It does not satisfy the helper's exact
  app-destination contract. Detection-only behavior retained; no root install.

## WeChat identity and refusal controls

The actual 2.02 app reports `com.github.Electron` / `36.6.0`; sealed
`package.json` identifies WeChat 2.02.2609250. Before the fix, the canonical
`com.tencent.wechatdevtools` request was refused. The same real package and copy
succeeded after the scoped alias fix. Unit tests also cover the older
`com.tencent.webplusdevtools` identity, wrong product, wrong team and unknown ID.
The older generation was not installed by this batch.

Changing a sealed JSON resource without changing the product marker caused a
real helper refusal; restoring its exact bytes restored strict validation.
Automatic requests for running Tailscale, AweSun and UU Remote deferred without
installing; explicit manual requests then completed. No resource checks were
relaxed. Final code maps only *pre-install installed-copy* refusals to status 77
(interactive handoff for manual work, deferral for automatic work). Protected-PKG,
installer and post-install failures remain errors and do not replay installation.

## Final-build verification

The final signed 19-pin app/helper was deployed in place to the VM; the registered
helper bundle path was preserved. Native DuoUpdater's AdGuard row showed
2.19.0.2258 → 2.20.3, then Installing → Installed, without Installer UI or a
password prompt. On-disk build 2633, release channel and strict signature were
confirmed ([receipt](receipts/native-adguard-final.json)).

The final helper refused both manual and automatic signed-client requests for
a deliberately modified WeChat resource before installer execution. Both replies
required macOS Installer; no installer progress was emitted. Exact bytes were
restored and strict validation passed. These low-level client controls establish
pre-execution refusal; manual GUI handoff and scheduler deferral follow the
existing PackageInstaller error handlers and were not replayed as UI tests here.

The app was quit and the VM's original AutomaticUpdates=true preference restored.
AdGuard remains on stable 2.20.3. ToDesk 5.1.0.0 and AweSun 16.5.0 test seeds
remain installed, with current packages retained for the manual route.

## Validation

- Final App suite: 364/364 declared cases executed, passed.
- Final Core suite: 7,455 tests / 658 suites passed, one known issue, excluding
  `installPipelineDryRun`. Its earlier full `make test` run failed on the unrelated
  live Kuvo download changing bundle ID from `run.kuvo.app` to `run.kuvo.code`;
  identity validation correctly refused it. This is not an all-green `make test`.
- CLI: 699 tests passed; script checks passed; application-test built successfully
  earlier in this task. Final focused policy check (three unapproved app IDs) and
  final Developer ID signed app/helper build passed.
- Local adversarial review: GPT-6 Astra, separate from implementation model;
  privilege, trust, data loss, untrusted input and post-execution replay attacked,
  no findings after withholding AweSun/ToDesk/Classic. See [review.json](review.json)
  for exact source hashes. The review did not execute VM commands.

VM packages, installed apps, original DuoUpdater backup and full raw logs remain
under `/Users/bobby/duo-verify/pkg-coverage-20261114`. Repository receipts omit
package binaries and URL query parameters; text logs strip trailing whitespace. No host DuoUpdater installation or
release publication was performed.
