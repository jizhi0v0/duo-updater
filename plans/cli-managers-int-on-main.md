# INT on main: what §3 of `cli-managers-redesign.md` meets on `origin/main`

Written 2026-10-23 against `origin/main` = `cbbe8a1` ("verify: update recipe baseline (#1612)"), which is also the base of `plan/cli-managers-redesign`. This is §0's acceptance: each internal claim the design rests on, and whether it still holds, moved, or was replaced. Line numbers are main's. `C/` = `DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/`, `A/` = `App/Sources/`, `K/` = `CLI/Sources/DuoKit/`.

Files touching CLI tools that the design did not know (added between `8c2a5933` and main), and whether the managed model touches them:

| File | What it is | Managed model |
|---|---|---|
| `C/CLIRunReducer.swift`, `C/CLIRunQueue.swift`, `C/CLIRunOffer.swift` | run state as a pure reducer keyed by `Key` (= `CLIToolID` in the app) and provider *index*; the queue of clicks | **not touched**: every event is keyed by `CLIToolID`, which P0 makes identity-based, and by provider index, which is per `ManagedProvider`. Nothing in them switches on kind. |
| `C/CLIRowView.swift` (+ `BrewRowView.swift`) | the popover row and workbench header drawn from `CLIRowSnapshot.Tool` | one arm: `Tool.kind` names "Updating <kind>" (`:318`); for `.managed` the head reads "Updating Managed tools". Left as is in P0 (no manager is visible); P1 adds a display name to `Tool` if the owner wants the manager named (§5 of the design). |
| `C/CLIToolProcessOrigin.swift` | who started a tool's process | not touched: reads by executable path. |
| `C/RuntimeSecurity.swift`, `C/RuntimeSecurityFeeds.swift` | node/php security notices for npm prefix headers | not touched: keyed by `NodePrefix`; managed Node lines (P3) may later feed it. |
| `C/Obelus*.swift`, `C/Biome*.swift` | two more kinds (28 non-managed kinds now, 30 providers) | not touched; `.managed` goes after `.biome`. |
| `K/SignalGate.swift` | duo's Ctrl-C handling | not touched; `CLIToolRows.apply` already counts tools kept from starting as cancelled. |
| `A/InstallTable.swift`, `A/BrewRowRuns.swift`, `A/QuitCoordinator.swift`, `A/EarlierInstallBackupNote.swift` | app rows and brew runs | not touched. |

## §3.1 Types and the provider

| Claim | On main |
|---|---|
| `CLIToolKind` is a `String` enum, `CaseIterable`, order = group order | **holds** (`C/CLITool.swift:11`). `.managed` is appended last so `CLITools.inKindOrder` puts the managed groups after every standalone kind (D12). |
| `CLIToolStatus` identity is `(kind, path)` | **holds** (`:143`, doc comment). P0 adds `identity` (default `path`). |
| `MiseUpdater.failureMessage` at `C/MiseUpdater.swift:189-204` | **moved** to `:197-213`; same shape (first `mise ERROR` line, else the last meaningful line, exit code). `ManagedProvider` uses `CLIToolCommandRunner.failureMessage` plus the exit status; a manager that prints a marker line does what mise does, in its adapter. |
| mise token handoff at `C/MiseUpdater.swift:122-141` | **moved** to `:138-157` (`foundNoToken` at `:187`), unchanged in substance: a second run with `MISE_GITHUB_TOKEN` only after "No GitHub token was found", and `InstallJobs.noteRefusedCommit` when a Cancel cut the token lookup short. Generalised as `ManagedTokenRetry` (adapter opts in). |
| `CLIToolCommandRunner.run`/`path(prefix:)` | **holds** (`C/CLIToolCommandRunner.swift:28`, `:70`); `run` goes through `InstallCommit.run` with `.runToCompletion` — the commit point §13.1 describes. |
| `environmentWithSystemProxy` (INT-74) | **holds** (`Support/SystemProxyEnvironment.swift:129`); `SystemProxyEnvironment.applied(to: [:])` gives the proxy variables alone, which is what "built from scratch plus the proxy" needs. |
| `DenoChangelog.gitHubReleases`, `NpmChangelog` as note fetchers | **hold** (not used in P0). |

## §3.2 State rules

No internal claim; the rules live in the new `ManagedCheck`. `CLIToolStatus.commandToCopy` (`C/CLITools.swift:95-104`) already hands out `manualCommand` for `.pinned` and for `.updateAvailable` under `.autoUpdateOff/.unsupportedInstaller/.unverified`, so a managed row whose binary is untrusted gets its copy command through the existing rule (D5.2) — `ManagedCheck` sets `withheld = .unverified`, not `.wrongSigner`, when there is a command to copy, because `.wrongSigner` hands nothing out.

## §3.3 Identity and persisted keys

| Claim | On main |
|---|---|
| `CLIToolStatus.toolID` at `A/CLIToolsModel.swift:16-18` | **holds** (`:16-18`); P0 builds it from `identity`. `CLIToolSighting.toolID` at `:35-37` likewise. |
| `CLIToolID.tag` "no colon in the kind" | **holds** (`:13`). The managed tag is `managed:<manager>|<root>|<key>`. |
| scan/check comparison `Set(found) != Set(checkedSightings)` at `:382` | **moved** to `:469` (`onOpen`) and `:512` (`onFocus`); same rule. `CLIToolSighting` gains `identity` and `name`; `CLIToolReport`'s default sightings keep `name: nil` so an existing provider's scan and report still compare equal. |
| `NotifiedCLIToolVersions` key from `toolID.tag`, `AppListModel.swift:9431` | **moved** to `A/AppListModel.swift:10524-10536` (`notifyNewCLIToolUpdates`); still `toolID.tag`, with `liveKeys` pruning. No migration: existing kinds' identity is their path. |
| `UpdateAnnouncements.swift:44-58` baseline/first announcement | **moved**: the ledger is `UpdateAnnouncementLedger` in `A/Preferences.swift:281` and `pass(enabled:offered:liveKeys:)`; the rule (a new key is announced once) holds (D-A). |
| hand-spelled `kind.rawValue + ":" + path` at `K/CLIToolRows.swift:189,214` | **hold** at the same lines; switched to `identity`. The jobID `"cli-tool:<kind>:<path>"` at `:455` and `A/CLIToolsModel.swift:1228` likewise take the identity (the app's already does, through `id.path`). |
| `CLIToolProcesses.target(of:)` uses `status.path` | **holds** (`C/CLIToolProcesses.swift:223-229`). |

## §3.4 Provider identity, lanes, pauses

| Claim | On main |
|---|---|
| "three lookups by kind": `provider(of:)` `:839-841`, `releaseNotes` `:1058`, `CLIToolRows.breakingVersions/apply/after` | **moved**: `A/CLIToolsModel.swift:1092-1094` (`provider(of:)`), `:962` (`offerAtTurn`'s `firstIndex`), `:1661` (`releaseNotes`); `K/CLIToolRows.swift:204` and `:438`. Two more kind-keyed places the design missed: `apply` keys `contexts` by kind (`:658`) and tells the reducer which tools a check answered by kind (`:665`, `answered.contains(id.kind)`); `runLane` collects a tool's statuses by kind after a re-check (`:1604`). All switch to the provider id (`CLIToolID.providerID`), and managed contexts go in `managedContexts: [ManagerID: ManagerContext]`. |
| `update`/`updateAll` to be re-mapped onto `CLIRunEvent`/`CLIRunBatch` | **done by the above**: `CLIRunLaneCopy.tool` is a provider index and `lane` a string from `lane(of:)`; `toolRechecked(Int, now:)` takes the provider index. Nothing in the reducer needs a change. |
| `CLITools.inKindOrder` keeps same-kind providers in given order (`C/CLITools.swift:26-32`) | **holds** (`:28-34`). |
| `lane(of:)` at `:1030-1040`, now `nonisolated static` at `:1633` | **holds** at `:1633-1643`; one arm added: `.managed(item)` → `item.descriptor.lane`. The bub→uv rule stays. |
| `CLIToolKind.updaterSpendsGitHubAPI` `C/CLITool.swift:477-483` | **moved** to `:489-499`; `applyingGitHubPause` (`:512`) and `K/CLIToolRows.check` (`:237`) read it by kind. P0 adds `CLIToolStatus.updaterSpendsGitHubAPI` (descriptor for `.managed`) and both read that. |
| `readsGitHubAPI` default false | **holds** (`:469`). |

## §3.5 One-time switch arms

| Site | On main |
|---|---|
| `CLIToolKind.displayName` `C/CLITool.swift:70` | `:75`; arm added ("Managed tools"). |
| `CLIToolWording.vendor(of:)` `:24` | `C/CLIToolWording.swift:23-40`; arm added (nil); `reason(_:of status:)` (`:120`) gains the managed arms; `pinned(status)` (`:43`) generalised to a managed exact request. |
| `Detail`/`Context` cases `:228`, `:310` | `:236` and `:320`; `.managed(ManagedItem)` / `.managed(ManagerContext)`. |
| `CLIToolsWorkbench.logo/tint` `:76`, `:118` | `A/CLIToolsWorkbench.swift:77-108` and `:111-150`; `CLIToolIcon` takes an optional descriptor, read for `.managed`. |
| `cliToolHeaderSummary` `WorkbenchWindowView.swift:1144` | `:1135-1161`; `.managed` arm reads `managedContexts`. The group title at `:1107` is `group.kind.displayName` → the group's `title` (descriptor's for managed). |
| `CLIToolPresentation.facts(of:)` `:255` | `A/CLIToolPresentation.swift:277-290`; `.managed` arm. `groups` (`:103`) keys managed by `manager|root`; `Group` gains `manager`, `root`, `title`. |
| the two test switches `App/Tests/CLIToolsModelTests.swift:72,113` | `:37-80` and `:89-120`; arms added. |
| `CLIToolsTests.everyKindHasOneProviderInKindOrder` | `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/CLIToolsTests.swift:26`; rewritten: non-managed kinds once each in order, then the registry's providers. |
| `CLIToolGitHubAPITests:22` provider list | `:17-25`; compares against `allCases` minus `.managed` plus the registry. |
| `CLIToolPresentation.groups` key | see above. |

Not in the design, found on main: `A/MenuContentView.swift:1007` words "Updating \(kind.displayName)" from `CLIPopoverRow.Line.updating(CLIToolKind?)`; `A/CLIToolsModel.summary` (`:1740`) counts copies per kind. Both read "Managed tools" for a managed row; P1 decides whether to name the manager (§5 says it should; it needs a display name on `CLIRowSnapshot.Tool`).

## §3.6 Check granularity

`checkedAt[index]` per provider (`A/CLIToolsModel.swift:326`), an update re-checks its own provider only (`runLane` → `check(ready)`, `:1601`): **holds**. Per manager = per `ManagedProvider`.

## The breaking-hint pass (D10)

`loadBreaking`/`readBreaking` at `A/CLIToolsModel.swift:862-902`: unchanged in shape on main; the cap goes there in P1 (no managed row exists before then). `CLIToolChangelog.readsForBreaking` (`C/CLIToolBreaking.swift:33`) reads shared fields only, so managed rows are eligible with no change.

## What this leaves for P1

- `ManagedProvider` is exercised only by fixtures: no adapter is registered (`ManagerRegistry.adapters == []`), so the app and `duo` show nothing new.
- Naming the manager in the popover's "Updating …" head and in `summary`.
- D10's cap in `readBreaking`.
- `make test` could not be run where P0 was written (a Linux cloud session has no Swift toolchain for a macOS-only package); the first macOS run of `make test` is part of P0's acceptance.
