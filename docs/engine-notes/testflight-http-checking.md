# TestFlight HTTP update checking: protocol investigation

Status: design draft, not an implemented or live-verified update source.
Evidence below comes from static inspection of TestFlight 4.3.1 (681.1),
including TestFlightServices arm64 method bodies and application entitlements.
Private interfaces can change independently of DuoUpdater releases.

## Problem and intended behavior

`TestFlightInventory` reads a local catalog. A successful database read does
not establish that the catalog was recently synchronized with the server.
`UpdateChecker` currently compares its cached build with the installed build
and can return `upToDate` when they match. That equality does not prove the
absence of a newer remote build.

The proposed source would query the builds available to the signed-in tester
and compare them with the installed build on the corresponding platform.
Installation would remain managed by TestFlight. This document changes no
runtime behavior and does not claim to solve session acquisition.

## Interfaces found in the client

| Client method / path | Static evidence | Remaining validation |
| --- | --- | --- |
| `TFHallidayService.requestCheckUpdatesForInstalledApps:completionBlock:` | Builds a POST to `/v4/accounts/{accountId}/updatableApps`, sets JSON content type, wraps its argument in `installedApps` | Complete per-item schema, required headers, response semantics and live behavior |
| `TFHallidayService.requestAppListOutlineWithPrefetchCount:lastKnownETag:completionBlock:` | Starts with `/v4/apps`; builds `allDetailsCount` query parameter and passes an ETag | Effective account-scoped URL and response shape |
| `TFHallidayService.requestAppDetailsForBatch:completionBlock:` | Batch details route `/v4/appDetails` | Request and response schema, batch limits |
| `TFAuthenticationManager._authenticateWithHalliday` | Session-authentication request and system store-account integration | Authentication accessible to an independently signed client |

The client contains the server root `https://testflight.apple.com`, with an
override lookup in `TFServerRoot`. Its network layer also contains account
path rewriting for v2/v3/v4 routes. Confirm the final encoded URL rather than
concatenating every discovered path directly to the root.

The following is a protocol outline, **not a runnable request**:

```http
POST /v4/accounts/{testflightAccountId}/updatableApps
Host: testflight.apple.com
Content-Type: application/json
X-Session-Id: <authorized-session>
X-Request-Id: <new-request-uuid>
X-Session-Digest: <computed-digest>

{"installedApps": ["<item schema still to be verified>"]}
```

The string entry above is deliberately a placeholder, not a proposed JSON
item type. Do not implement a decoder or ship a request schema from it.
The endpoint name alone does not establish whether results are filtered by
per-app automatic-update preferences, rollout eligibility, or tester groups.
Those distinctions matter: manual update detection must still find a build
when automatic installation is disabled.

## Authentication is the feasibility gate

`TFAuthSessionInfo.generateURLRequestAuthHeadersWithAccountDSID:` constructs:

- `X-Session-Id` from the TestFlight session ID.
- `X-Request-Id` from a newly generated UUID string.
- `X-Session-Digest` from a hash of session ID, request UUID, Apple account
  DSID, and an embedded protocol constant, in that order.

The helper `TFUtils.createHashStringFromData:` calls `CC_SHA1` and formats
bytes using lowercase `%02x`. This describes the inspected client, not a
live-tested authentication recipe. No embedded constant or account material
is reproduced here. TestFlight account ID and Apple DSID are distinct values.

`TFAuthenticationManager` loads session/account identifiers from the Keychain.
Its query selects the data-protection Keychain. The TestFlight application
has its own Keychain access group and private Apple account/media-services
entitlements. A normal DuoUpdater process must not assume it can read that
session, inherit the entitlements, or obtain a renewable session simply by
loading the bundled framework. Full Disk Access is not evidence of Keychain
authorization.

The authentication implementation references system store-account cookies,
device metadata and `/v1/session/authenticate`. Session acquisition, renewal,
account switching and expiry handling need a legitimate, user-authorized
integration path before a production HTTP source is feasible. This draft
does not read credentials or propose bypassing access controls.

Apple's public [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
uses organization API keys and JWTs to manage that organization's apps and
beta builds. It can serve an owner-controlled build catalog; it is not a
replacement for the tester session needed to check unrelated developers'
apps enrolled in TestFlight.

## Proposed integration boundary

1. Keep local scanning for installed versions, platform and TestFlight
   provenance. Treat cached remote builds as observations, not fresh verdicts.
2. Acquire a session through a verified, explicit authorization flow. Keep
   this behind a separate session-provider boundary.
3. Perform a batched, read-only remote check. Preserve tester-account and
   platform boundaries; do not compare an iOS build with a native macOS app
   even if they share a bundle identifier.
4. Normalize and validate the response before comparing build versions.
   Account-visible and device-compatible must both hold. Include expiry and
   distribution-group semantics once the response schema is verified.
5. Publish a fresh result only after a successful authoritative check.
   Retain the TestFlight-managed install action.

The source should distinguish at least:

| Outcome | Intended treatment |
| --- | --- |
| Successful authoritative response, newer eligible build | Update available |
| Successful complete response, no newer eligible build | Checked, no update |
| Cached catalog only | Freshness unknown; never manufacture a fresh no-update result |
| Missing/expired session | Authentication required; no silent login loop |
| Incomplete, malformed or unexpected response | Check unavailable; do not interpret omissions as no update |
| Network/server failure or rate limit | Bounded retry/backoff; preserve freshness uncertainty |

HTTP 304 is meaningful only with the matching previously validated response
and validator, scoped to the same account, request and platform. An empty
list must not mean "up to date" until the endpoint's completeness semantics
have been established.

## Read-only PoC acceptance criteria

Before integrating the source, verify all of the following:

- An independently signed client can obtain and renew an authorized session
  without Apple-only entitlements, process injection or exported credentials.
- A direct HTTP response detects a newer build while the local catalog has
  not refreshed; the check does not launch or install an app.
- The complete `installedApps` item and response schemas are understood.
- Detection works with per-app automatic updates both enabled and disabled.
- Native macOS and iOS-on-Mac builds stay separate, including shared bundle IDs.
- Expired, withdrawn, incompatible and inaccessible builds are not offered.
- Account switching invalidates prior observations and validators.
- Authentication failure, throttling, malformed responses and partial results
  never become a successful no-update verdict.
- Synthetic fixtures exercise the parser and comparison behavior. No real
  account payloads enter the repository or CI.

Do not use the extension's combined check-and-install entry point merely to
refresh metadata: `reloadAppsFromServerWithReply:` can lead to
`_checkAndInstallUpdatesWithRefreshType:cleanupProfiles:pushMessages:reply:`.
That is a different side-effect boundary from HTTP update detection.

## Privacy requirements

Keep credentials and raw account responses out of request logs, diagnostics,
crash attachments and fixtures. Redact session/digest/cookie headers and
account identifiers embedded in URL paths. Do not include signed download
URLs, installed-app inventories, tester names, local paths, device identifiers,
or machine-specific timelines in PRs.

Use synthetic examples such as `com.example.beta`, and keep any authorized
session handling local to the user's client. Do not add a server that collects
users' Apple account credentials as a shortcut around session acquisition.

## Evidence and limits

Reproducible static inspection targets (addresses are image-relative for the
inspected framework and are not stable API identifiers):

| Method | Address |
| --- | --- |
| `requestCheckUpdatesForInstalledApps:completionBlock:` | `0x756c0` |
| `generateURLRequestAuthHeadersWithAccountDSID:` | `0x4c38c` |
| `createHashStringFromData:` | `0xbe758` |
| `TFServerRoot` | `0x77ed8` |

No authenticated HTTP request was executed as part of this investigation.
The protocol outline is supported by static code inspection; a deployable
session provider, wire schemas, server acceptance, and end-to-end behavior
remain unverified. This document is a handoff for that PoC, not completion of
the real-time TestFlight detection feature.
