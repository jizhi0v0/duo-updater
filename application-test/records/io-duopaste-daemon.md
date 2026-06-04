# DuoPaste — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`~/Applications/DuoPaste.app`) via the production `AppScanner.scan()` →
`ChannelBinding.resolve()` path, plus a fetch of the live appcast.

DuoPaste is a textbook **channel-tag** Sparkle app: one appcast whose items carry
`<sparkle:channel>beta</sparkle:channel>`, and an `allowedChannels` delegate driven
by `sparkleIncludePrereleases` (Bool) in its own UserDefaults. The feed is not
overridden — the channel just narrows which items are accepted.

| Channel | real bundle id | real short ver | `sparkleIncludePrereleases` | detect()/binding | appcast head |
|---------|----------------|----------------|------------------------------|------------------|--------------|
| beta    | `io.duopaste.daemon` | `0.1.1251-beta+962a0e1` | **1 (true)** | **beta** ✓ | 0.1.1251-beta = installed, up to date |
| stable  | `io.duopaste.daemon` | `0.1.1251-beta+962a0e1` | 0 (temp) | **stable** ✓ | appcast has only `beta` items today |

## Both channels confirmed on this machine (2026-06-04)
- **beta**: native state (`sparkleIncludePrereleases=1`) → `--scan` → beta ✓.
- **stable**: temporarily set the flag to `false`, `--scan` → stable ✓, then restored to
  `1` (re-scan → beta ✓). DuoPaste was not running; only the stored pref toggled.
  End state == original (`1`).

## Notes
- `sparkleIncludePrereleases = 1` and the installed build is itself `…-beta` → beta is
  correct. The appcast (`raw.githubusercontent.com/jizhi0v0/duo-paste-releases`) lists
  **only** `<sparkle:channel>beta</sparkle:channel>` items right now; head = installed.
- VendorProbe intentionally returns nothing (mechanism is channel-tag Sparkle). The
  harness "VendorProbe → no version" is **expected**.

## Command
```
swift run --package-path application-test channel-verify --scan io.duopaste.daemon --expect beta
```
