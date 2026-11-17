# Setapp ownership regression — issue #2072

## Real-machine result (2026-11-17)

Apple Silicon macOS 27.2 VM, Homebrew 7.0.12. Installed original vendor-signed
AirBuddy 3.0.3 (1034) and Downie 4.13.4 (5284) using pinned historical official
Homebrew casks. Both direct packages contain `setappPublicKey.pem` and Sparkle.
No package resource was removed or modified during this comparison.

- Main `c2615223`: both direct copies incorrectly reported Setapp/up-to-date.
- Fixed production-core CLI: Homebrew correctly offers AirBuddy 3.1 and
  Downie 4.13.5.
- The existing real `com.charliemonroe.Downie-setapp` copy remains Setapp-owned;
  its complete check result is unchanged.
- Both direct package signatures pass `codesign --verify --deep --strict`.
- Test casks were uninstalled afterwards; the original Setapp copy was preserved.

Raw results: `check-main.jsonl`, `check-fixed.jsonl`,
`direct-identities-after.txt`, `cleanup.txt`.

The original defect was also reproduced after restoring the VM's clean-install
snapshot without Homebrew, Setapp or DuoUpdater preferences: the classification
does not depend on a stale installed Setapp client or its cache.

## Regression tests

`swift test --package-path DuoUpdaterCore --filter SetappCatalogSourceTests -j 6`
passes all 34 tests. The new direct-copy test covers both reported bundle IDs
with a catalogue miss and timeout (four cases). All four fail against the old
ownership predicate; the fixed implementation passes. Existing suffixed Setapp
copy tests retain terminal failure protection. Raw red/green output is included.

The only runtime change removes the public-key resource as terminal ownership
proof. It remains a catalogue candidate hint; exact catalogue matching and the
existing version/source/install policies are reused.
