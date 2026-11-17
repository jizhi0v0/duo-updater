# Localized display names — issue #2072

The scanner previously ignored `InfoPlist.strings` intentionally. This exposed
VidHub's internal `MediaCenter` project name and Baidu Netdisk's raw
`BaiduNetdisk_mac` name instead of the names supplied for the user's language.

The existing App Store matching reader is now shared with scanning. A localized
display-name key overrides its raw value; an untranslated raw display-name key
still precedes the shorter localized bundle-name key. Blank/bidi-only values
fall through. Channel detection continues to use the raw metadata name, and App
Store button matching retains that raw name as a separate matching needle.
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
this checkout's production DuoUpdaterCore. It invokes the real AppScanner on the
two installed bundles with an empty TestFlight inventory and explicit language
preferences, without account prompts, network access or changing system settings.

- English: **VidHub**, **BaiduNetdisk**.
- Simplified Chinese: **VidHub**, **百度网盘**.
- Both remain stable and retain their bundle IDs, paths and versions.

Raw before/after and selected bundle metadata are included. This verifies the
production scanner, not an interactive App Store update or a GUI screenshot.

## Tests

85 scoped tests pass (raw output: `tests.log`), covering localized names,
legacy Chinese localization mapping, blank/missing resources, raw display-name
precedence, wrapped iOS bundles, channel words hidden or introduced by a
translation, scanner behavior and existing App Store offer-button guards.

The new fixtures deliberately use a generic bundle ID, so correctness cannot
come from a VidHub/Baidu alias. Beta/Canary/Preview remain derived from raw
metadata even when the translated row name omits or introduces a channel word.
