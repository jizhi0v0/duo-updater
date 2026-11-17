# Stable 0.5.25 hotfix validation

Prepared 2026-11-18 from released stable `v0.5.24` (`10536b6494c66f86fd1ff980718e3d971c07adb1`).
Only three existing fixes are backported:

- #2026: Douchat's signed authorization for its forward signing-team migration.
- #2074: direct-download apps with Setapp resources no longer become terminal Setapp owners.
- #2079: WorkBuddy AI downloads the ZIP paired with the current published digest.

The shipping implementation diff is exactly three files: `SignatureVerifier.swift`,
`SetappCatalogSource.swift`, and the international WorkBuddy recipe. All three match
main `431197b8` byte for byte. All other shipping implementations retain the 0.5.24 baseline.
Version metadata is 0.5.25 / build 153, stable channel. English and ten translations retain
all published note history, including the previously published 0.5.25-beta.1 section.

The full feature source is released separately as Beta 0.5.26-beta.1 / build 154.
Both items are to enter the shared appcast together; the higher Beta build prevents
Beta clients being replaced by the smaller stable hotfix feature set.

## Scoped tests

A fresh build of the backported Core passed **73 tests in seven suites** covering
Douchat migration, installation authenticity and staged substitution, Setapp ownership,
WorkBuddy recipe resolution and all recipe goldens. [Log](core-tests.log).
The production CLI built successfully from this worktree; no code was compiled in the VM.

## Real-machine result (2026-11-18)

Apple Silicon macOS 27.2 VM, production Core + DuoKit through that CLI. Test apps lived
under an owned temporary applications folder, with isolated Duo state.

- Actual original AirBuddy 3.0.3 (1034) retains its Setapp public-key resource and valid
  strict deep signature. Its result is now **Sparkle / update 3.1 (1055)**.
- Actual original Downie 4.13.4 (5284) likewise retains the resource and valid signature.
  Its result is **Sparkle / update 4.13.5 (5290)**.
- Genuine `com.charliemonroe.Downie-setapp` remains **Setapp / up to date**,
  4.13.5 (5290). It was queried with `--include-hidden` because its existing ignore
  preference was retained; no preference was changed.
- Real WorkBuddy AI 5.9.4 upgraded to **5.11.4**, `applied:true`, `outcome:installed`,
  **475,192,215 bytes** downloaded. The installed app passes strict deep signature verification.
- The owned test apps were removed; the existing genuine Setapp app and historical
  test archives/copies were preserved. [Raw receipts](vm/).

No AirBuddy/Downie installation or Douchat reinstall is claimed for this combined run.
Douchat's production implementation is identical to the original reviewed fix; the original
real 0.1.28 → 0.1.29 result remains in its [audit](../../docs/app-audits/ai-thinkany-douchat.md),
and the backported signing/staging paths were exercised by the 73 tests above.

The final signed release archive, helper versions, notarization and paired appcast
are checked separately before public delivery. This record does not claim those
publication steps were completed during the CLI verification.
