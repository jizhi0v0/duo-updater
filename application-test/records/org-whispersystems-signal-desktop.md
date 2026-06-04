# Signal — channel verification record

Verified 2026-06-04 with `channel-verify` against the **official zips of both
channels** (extracted, `.app` inspected; not installed). Independent bundle ids
(Pattern A), each with its own electron-builder feed.

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `org.whispersystems.signal-desktop`      | `8.13.0`        | stable ✓ | 8.13.0 = build, up to date |
| beta    | `org.whispersystems.signal-desktop-beta` | `8.14.0-beta.1` | beta ✓   | 8.14.0-beta.1 = build, up to date |

## Notes
- Beta is a separate `Signal Beta.app` with a distinct `-beta` bundle id; detection
  is unambiguous. Both VendorProbe recipes (`latest-mac.yml` / `beta-mac.yml`)
  answered with the build's own version → no phantom update.
- Detection-only (Signal self-updates via electron-updater).

## Commands
```
swift run --package-path application-test channel-verify "/tmp/Signal.app"      --expect stable
swift run --package-path application-test channel-verify "/tmp/Signal Beta.app" --expect beta
```
