# Nightly coverage acceptance

Read this when auditing or implementing a new app, release track, feed change,
or supported legacy copy group. Detection, installation and changelog remain
three separate product results; nightly coverage is an integration acceptance
check alongside them.

For an implementation, include the applicable monitoring entry or explicit gap
in the **same PR** as the app/channel/feed change, after the feed and real
package have been verified. An audit-only task records the current coverage and
hands off missing work; it does not authorize unrelated implementation or a
runner deployment. For an already-integrated app, check monitoring as well as
product behavior before reporting that the integration is complete.

## Choose the actual monitoring route

Inspect the current loader and enumerator in the checkout before editing.
Today the public feed inventory is
`CLI/Sources/DuoKit/AuditedUpdateFeeds.swift`; `InstallVerify.swift` and
`AuditedFeedVerification.swift` consume it. If it has moved to a configuration
file, update that owning file instead of creating another Swift/JSON list.

- Generic Sparkle/Electron: add or update the audited public feed entry. Runtime
  coverage from `SUFeedURL` or `app-update.yml` does not enumerate packages on a
  runner with no installed apps. Keep each distinct product, track and supported
  old/new copy group represented; sharing a Bundle ID or feed does not collapse
  those groups. Preserve stable recipe IDs when only the feed changes.
- Vendor/GitHub: the existing registries are enumerated automatically. Confirm
  the precise recipe IDs are present; installer-byte coverage additionally needs
  `install` / `installAssetPattern`. Detection-only coverage is not a successful
  archive inspection. Do not duplicate these entries in the generic inventory.
- MyGo: check the existing `MyGoFeedCatalog` / `duo verify --mygo` route.
- `ChannelBinding` / `SparkleFeedCatalog` feed checks establish feed health.
  They do not replace generic install-byte coverage: `feed:<id>` and
  `install:sparkle:<id>:<track>` check different things.
- Private, credential-bearing, copy-specific or retired feeds: record the exact
  gap and evidence in the audit and the applicable inventory gap collection.
  Use `uncoveredRows`, `uncoveredTracks` or `unavailablePublicKeys` where they fit;
  a missing public key alone does not exclude otherwise public identity checks.
  Other unsupported mechanisms get an explicit audit limitation. Publish only
  safe public configurations, never credentials or an owner's installed-app list.

Record the observed feed, Bundle ID, track, Electron manifest channel or Sparkle
channel tags, copy-group discriminator, public key when established, and audit
provenance. A manifest channel such as `nightly` is not necessarily the app's
release track. Read the matching real bundle/audit instead of inferring these
fields from a newer sibling product or channel.

## Verify before claiming coverage

1. Keep the existing functional verification. `verify-install` only downloads and
   inspects; it does not replace old-to-new one-click installation evidence.
2. Run the relevant inventory tests (`AuditedUpdateFeedsTests` in the CLI package
   while that implementation exists). Check the expected **set of recipe IDs**
   for this app, including channels and legacy copies. Current index-set tests
   detect missing audit rows; an unchanged row does not prove new tracks are
   covered. Update legitimate fixture counts without weakening those set checks.
3. Use a CLI built from the changed checkout, following the project's build and
   lease rules. For generic packages run `duo verify-install --only <id>` with
   reports in task-owned scratch space. For the other mechanisms, run their
   actual enumerating verifier. Inspect every expected item/status; zero selected
   targets, an unresolved installer, or an OS skip is not a passed byte check.
   Reuse real artifacts/results from the same tested code when sufficient.
4. Keep first-observation evidence distinct from continuity against a previously
   recorded or audited anchor. Preserve existing identity/issue state; do not
   replace keys, reset baselines, lower counters or add an acknowledgement to
   turn a signing or feed failure green. An identity change needs its own evidence
   and review. In delegated work, the parent performs checks the worker cannot
   run and records their actual results before completing the integration.

In the audit/report's **夜扫覆盖** section, name the monitor and exact recipe IDs,
which tracks/copy groups they cover, the verification command/result, and any
remaining feed/key/byte-inspection gap. Distinguish records added from checks
actually run. A missing check stays pending with a concrete handoff; a measured
limitation stays an explicit gap. Report-only work must not silently add code,
close issues or launch scheduled jobs.
