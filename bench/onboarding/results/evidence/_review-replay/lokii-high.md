**Blocking findings: 0**

I listed the groups of installed copies first. Every Lokii copy has one bundle ID, `com.lokii.app`. `scripts/build.sh` at v0.1.0 hardcodes `bundle_id="com.lokii.app"`, and nothing in the repo or the audit mentions a rename. There is one edition and one stable track: the v0.1.0, v0.1.1 and v0.1.2 releases are all `prerelease: false`, and the workflow publishes with `--latest` and no prerelease flag. All three ship the same two per-arch dmg names, every asset has a `sha256:` digest, and every build is ad-hoc. In `build.sh`, `codesign --force --sign -` runs whenever `LOKII_SIGN_IDENTITY` is empty. Lokii has no Sparkle feed in any version. Copies from the author's tap install the same release assets: `Casks/lokii.rb` at 0.1.1 points at the same URLs and its sha256s match the API digests. The one rule, with `.publishedDigestOnly`, covers all of these groups.

I checked these against the GitHub API, each on the vendor's side:
- The release workflow rejects a tag that isn't `v` followed by the crate version, and `build.sh` writes that version into `CFBundleShortVersionString`.
- `AppUpdater.swift` only reads `/releases/latest` and opens the dmg URL.
- Every release body is the placeholder sentence.
- The digests in the audit match the API.
- The tap cask has no `auto_updates`.

`^v([0-9]+(?:\.[0-9]+)+)$` reads every existing tag and a two-part tag like `v1.2`. It rejects an unflagged `-rc` tag, so the worst case there is a missed detection, not a wrong offer. The asset pattern picks `Lokii-arm64.dmg` on arm64. The digest-only test fixtures, the golden file and the index's alphabetical placement all match the recipe.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-lokii-app.swift:17-20`: "a sealed signature that passes `codesign --verify --deep --strict` and the signed identifier `com.lokii.app` (0.1.1 and 0.1.2)". The digest-only identity gate depends on this. If a released bundle's seal or Info.plist bundle id/version doesn't match, one-click installs are refused, though detection still works. v0.1.0 wasn't mounted, but only the newest release is ever installed.
- `docs/app-audits/com-lokii-app.md:5`: v0.1.2's `CFBundleShortVersionString` is `0.1.2`, matching the tag without the `v`. The source confirms the build stamps the crate version, but nobody here inspected the shipped bundle. If it differs, the digest-only version check refuses the install.

**Other unverified external claims**

- `docs/app-audits/com-lokii-app.md:62`: real downloads' `shasum -a 256` "全部一致" (all match) the API digest. The API digests themselves do match the audit's listed hashes.
- `docs/app-audits/com-lokii-app.md:5`: `spctl` rejected, no stapled ticket, `Sealed Resources version=2 files=4`.
- `docs/app-audits/com-lokii-app.md:50`: "官网 `lokii.huangy.top` 只有下载链接" (the official site only has download links).
- `docs/app-audits/com-lokii-app.md:72-73`: the Full Disk Access grant doesn't carry across ad-hoc builds (TN3127).
- `.claude-review/pr.md`: channel-verify results (0.1.2 is up to date; 0.1.1 arm64/x86_64 shows UPDATE → 0.1.2).
