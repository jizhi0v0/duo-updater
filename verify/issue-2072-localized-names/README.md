# Localized display names — issue #2072

The scanner previously ignored `InfoPlist.strings` intentionally. This exposed
VidHub's internal `MediaCenter` project name and Baidu Netdisk's raw
`BaiduNetdisk_mac` name instead of the names supplied for the user's language.

The existing App Store matching reader is now shared with scanning. A localized
display-name key overrides its raw value; an untranslated raw display-name key
still precedes the shorter localized bundle-name key. Blank/bidi-only values
fall through. Channel detection continues to use the raw metadata name, and App
Store button matching retains that raw name as a separate matching needle. The
scanned model also retains `metadataName` so existing CLI name prefixes remain
valid, using the same ambiguity refusal and deduplication as localized names.
No product-specific aliases, network requests, language-setting changes or
package modifications are introduced.

## Real-machine result (2026-11-17)

Local Apple Silicon Mac (OS build in `host.txt`), original installed packages:

- Official Mac App Store VidHub 3.0.4 (2026111101), `com.mac.utility.media.hub`,
  `/Applications/MediaCenter.app`, receipt present. Raw name is `MediaCenter`;
  all 19 localized name resources say `VidHub`.
- Vendor Baidu Netdisk 8.10.3, `com.baidu.BaiduNetdisk-mac`,
  `/Applications/BaiduNetdisk_mac.app`. Raw name is `BaiduNetdisk_mac`;
  English resource says `BaiduNetdisk`, legacy `zh_CN` says `百度网盘`.

`AppNameProbe.swift` was built locally as a temporary SwiftPM executable linking
this checkout's production DuoUpdaterCore and DuoKit. It invokes the real AppScanner on the
two installed bundles with an empty TestFlight inventory and explicit language
preferences, without account prompts, network access or changing system settings.

- English: **VidHub**, **BaiduNetdisk**.
- Simplified Chinese: **VidHub**, **百度网盘**.
- Both remain stable and retain their bundle IDs, paths and versions. The real
  CLI selector also resolves the old `MediaCenter` and `BaiduNetdisk` prefixes
  to those same paths under both language preferences.

Raw before/after and selected bundle metadata are included. This verifies the
production scanner, not an interactive App Store update or a GUI screenshot.

## Tests

92 scoped Swift Testing tests and 15 XCTest tests pass (raw output: `tests.log`),
covering localization, legacy Chinese mapping, blank/missing resources, raw-name
precedence, wrapped iOS apps, translation/channel separation, scanner/AX guards,
TestFlight metadata retention and interrupted-install recovery identity.

52 CLI selection/tool/recovery tests pass (`cli-tests.log`), including old/new
aliases, collisions, deduplication, missing/damaged app recovery, and existing
interrupted-install command behavior.

The install journal keeps the original name in its existing `appName` field, so
older readers keep their previous selectors. An optional `displayName` carries
the new presentation. New readers carry both names through recovery; old records
without the optional field still decode. A scratch-journal regression exercises
production begin/write/read and legacy decoding. Recovery tests cover both an
absent app and a scanned damaged same-path copy, without modifying real apps.
