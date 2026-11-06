# Handy distribution-channel verification

Date: 2026-11-06. Read-only upstream checks and VMPal bundle comparison.

## Conclusion

The tested third-party tap, official cask and DuoUpdater GitHub recipe all use
cjpais/Handy's stable releases. The earlier tests demonstrate a non-brew
installation and a stale brew receipt, not a change of distribution channel.
They do not justify prohibiting GitHub updates for official auto_updates casks.

## Definitions and release assets

- Third-party definition: https://github.com/nsheaps/homebrew-devsetup/blob/main/Casks/handy.rb
  Blob SHA: 7bc564afa6c19895042a92c4eaa87c945cb6c33a.
  Version 0.7.12; ARM URL is
  https://github.com/cjpais/Handy/releases/download/v0.7.12/Handy_0.7.12_aarch64.dmg.
  Cask SHA-256 and GitHub release asset digest both equal
  d7acf62e4c8ca91100d0759d1b7fe5bc3d425352c2e2dfe68ca734166675622d.
- Historical official 0.9.8 definition: Homebrew/homebrew-cask commit
  330b7c8d9a5261bdda642b81f6ae762c0298be2d, Casks/h/handy.rb.
  Cask SHA-256 and the corresponding cjpais/Handy ARM DMG digest both equal
  81ac05aaaf4fafa62826bb40c5cf0bc0c813fb6fc8255497480e762620779417.
- Current official definition: https://github.com/Homebrew/homebrew-cask/blob/main/Casks/h/handy.rb
  Blob SHA: c5a8d145a94281b189d297ba54779bb186ba0dac.
  Version 0.10.0; cask SHA-256 and GitHub ARM DMG digest both equal
  bdc41359af0b8b3014f14c44ea3fe85b1e45387bdad261bd4a2cfc92f7f35496.
- GitHub release metadata for v0.7.12, v0.9.8 and v0.10.0 all reports
  prerelease=false.
- DuoUpdater's com-pais-handy.swift recipe selects cjpais/Handy releases,
  Handy_[0-9.]+_aarch64.dmg, with the stable/non-prerelease defaults confirmed
  by its checked-in recipe golden.
- The inspected macOS cask definitions install Handy.app from those DMGs;
  neither introduces a custom build or bundle-patching step.

## Actual VM copies

Compared the preserved 0.10.0 copy previously installed through DuoUpdater's
vendor route with the 0.10.0 copy subsequently installed through Homebrew.
Neither copy was modified during this check.

```text
                         vendor route            brew route
bundle ID                com.pais.handy           com.pais.handy
marketing/build          0.10.0 / 0.10.0          0.10.0 / 0.10.0
TeamIdentifier           UWFLB4GC25               UWFLB4GC25
CDHash                   408c7486399ba6e6ab53c4befd038d529d543b7f (both)
regular files/links      23                       23
different bundle files   0
```

Every regular file was compared by SHA-256 and symlinks by target, keyed by
bundle-relative path. This comparison does not compare filesystem extended
attributes, permissions or timestamps.

## Decision boundary

Recommendation: do not retain the blanket official auto_updates ownership
change on the basis of Handy. Whether to preserve a third-party tap's version
policy is a separate product decision; Handy does not demonstrate a third-party
custom-build or stable/beta channel replacement either.

No source code was changed during the read-only channel verification. Earlier
records' descriptions of a source-ownership failure must be read with this
correction; they establish installer routing and receipt lag only.

The user subsequently requested withdrawal of the official auto_updates changes.
See [the final rollback validation](official-auto-updates-reverted.md).
