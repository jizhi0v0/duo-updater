# Installing from what the app's own updater already downloaded

Explains `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/SelfUpdaterStash.swift`
and the substitution it feeds in `VendorInstaller.download` / `applyVerified` —
why the gates are shaped the way they are, and what was measured to decide it.

Every number below is a **one-time measurement taken 2026-09-16** on the
development machine (macOS 27, Apple silicon), not a tracked metric. Where an
observation is about a particular copy of an app, it says so: another machine's
copy of the same app can be in a different state, and several of these were.

## §1 What the shape is

An app whose own updater has finished downloading an update, but has not applied
it, leaves the installer sitting in a cache directory. For the electron-builder
family the layout belongs to the library, not to the vendor — from
`electron-updater` 6.8.9, read out of a shipped `app.asar`:

```js
// AppUpdater.getOrCreateDownloadHelper()
const cacheDir = path.join(this.app.baseCachePath, dirName || this.app.name)
// DownloadedUpdateHelper
get cacheDirForPendingUpdate() { return path.join(this.cacheDir, "pending") }
getUpdateInfoFile()            { return path.join(…, "update-info.json") }
```

`baseCachePath` is `getAppCacheDir()` — `~/Library/Caches` on macOS — and
`dirName` is `updaterCacheDirName` from the bundle's own
`Contents/Resources/app-update.yml`. `update-info.json` is written when a
download completes (`setDownloadedFile`) and is what the app reads on its next
launch to decide it already holds the file.

**It records no version.** `setDownloadedFile` writes exactly `fileName`,
`sha512` and `isAdminRightsRequired`, and the file name need not carry one
either — OpenCode's is `opencode-desktop-mac-arm64.zip`. That is why the version
has to be read out of the archive.

### How to re-run the survey

Nothing here is a tracked number; to see the current state on any machine, walk
the roots `AppScanner.defaultLocations` uses, read `updaterCacheDirName` out of
each bundle's `Contents/Resources/app-update.yml`, and list
`~/Library/Caches/<that name>/pending/`. For the non-electron shapes in §4, sweep
`~/Library/Caches` and `~/Library/Application Support` for archives over ~8 MB
and discard the package-manager caches (Homebrew, npm, Playwright, JetBrains)
and this project's own `duo-updater/release-archives`.

## §2 Why every gate is load-bearing

**The default state of this shape is stale debris, not a live offer.** Of the
copies carrying a parked installer on the development machine that day, only
OpenCode's was the release we were about to install. The others, each stated as
what that copy held at that moment:

| copy | parked installer | that copy's installed bundle |
|---|---|---|
| OpenCode | 1.18.31 (zip) | 1.18.26 — the release we were offering |
| ChatWise | 26.3.36 (zip, dated 2026-04-01) | 26.8.0 |
| Warp | `v0.2026.07.08.17.54.stable_02` (dmg) | 0.2026.09.02.08.27.01 |
| UURemote | 4.35.0 (pkg) | 4.40.0, already current |

An implementation that reused whatever it found would have performed three
silent downgrades to save one download. The version gate is not a safety belt
around the feature; it is most of the feature.

## §3 Attribution: the gate with no substitute

Two installed copies of one app share a cache directory, and the two checks that
would otherwise settle ownership both come up empty there.

Observed on that machine: `T3 Code (Alpha)` and `T3 Code (Nightly)` (both under
`~/Applications`) report the **same** `CFBundleIdentifier`
`com.t3tools.t3code` and the **same** `updaterCacheDirName` `t3code-updater`,
differing only in the `channel` their `app-update.yml` asks for — one absent,
one `nightly`. So:

- the directory name cannot say whose download it is, because it is what they share;
- the bundle identifier inside the archive cannot either, for the same reason.

What is left is the version comparison, and leaning on it means betting
correctness on a vendor's version-string habits — these two happen to be
distinguishable only because the nightly carries a `-nightly.<date>.<n>` suffix.
The loser of that bet is an install of the wrong channel's bytes over the other
copy. Hence `attributionIsUnique`, which refuses a cache directory that more
than one scanned bundle claims, and refuses a population it was not given.

**The shape is not new.** `SelfUpdaterStaging.sparkleStagedBundle` documents the
same collision for Sparkle's cache, whose key is the bundle identifier alone,
and records it as a known limitation. The difference is what it costs: there it
can mislabel a row, here it would write the wrong bundle to disk. Note also that
Squirrel's own `ShipItState.plist` does NOT have this problem — it names its
`targetBundleURL`, and `SelfUpdaterStaging.staged` already compares it against
the app's path.

Duplicate bundle identifiers are not exotic on a machine that tests update
paths: this project's verification workflow deliberately keeps an older copy of
an app in `~/Applications`, which is how the duplicate copies above came to
exist.

## §4 Shapes deliberately left unimplemented

Two more apps park installers in vendor-specific layouts. Neither is
implemented, and the reasons are worth keeping so the next person does not
re-derive them:

- **Warp** — `~/Library/Application Support/dev.warp.Warp-Stable/autoupdate/<random>/v<version>.Warp.dmg`.
  Its own updater; neither Sparkle nor Squirrel is embedded.
- **UURemote** — `~/Library/Application Support/com.netease.uuremote.updater/download/uuyc_<version>_nochannel.pkg`.
  Also its own updater.

Against implementing them, in order of weight:

1. **A dmg cannot be version-read cheaply.** Reading the bundle version out of
   one means `hdiutil attach` — seconds, a mount point, and possibly UI. A zip's
   central directory is at the tail and randomly addressable, which is what makes
   the gate in §5 affordable. Both of these carry the version in the *file name*,
   but trusting a vendor's file-name habit is the assumption OpenCode already
   falsifies.
2. **A `.pkg` is not swapped by this route at all** — `VendorInstaller.download`
   refuses `.pkg` and `PackageInstaller` handles it, so the substitution has
   nowhere to land.
3. **The benefit is unproven for them.** Both parked installers observed were
   stale (§2), so neither would have been used.

`SelfUpdaterStash.archiveKind` still classifies dmg and tar.gz rather than
pretending they do not exist; `resolve` refuses everything but zip, which is what
electron-updater downloads on macOS in any case
(`findFile(files, "zip", ["pkg", "dmg"])`).

## §5 Why reading the version is affordable

Measured on the two archives that existed that day, using the same
central-directory read the code performs:

| archive | size | entries | open dir | pick entry | inflate it | parse plist | total |
|---|---|---|---|---|---|---|---|
| `opencode-desktop-mac-arm64.zip` | 149.6 MB | 630 | 1.81 ms | 0.03 ms | 0.06 ms | 4.10 ms | **6.00 ms** |
| `ChatWise-26.3.36-arm64.zip` | 113.0 MB | 651 | 1.56 ms | 0.03 ms | 0.29 ms | 0.14 ms | **2.03 ms** |

(The 4.10 ms is first-call warm-up in the measuring harness, not a property of
the archive.) The cost tracks the number of ENTRIES, not the number of bytes:
roughly 4 KB is read out of an archive of any size. For contrast, on the same
file and the same machine: SHA-512 over the whole file 0.31 s, full extraction
of its 409 MB of contents 0.56 s. All reads were page-cache warm.

This is why gate 6 (`digestMatches`) hashes the file but the version read does
not: 0.31 s at install time is nothing next to the download it replaces, and it
is the only thing that proves the bytes on disk are the ones the app's updater
recorded.

The entry is anchored to the archive root. Electron bundles carry nested helper
`.app`s with their own `Info.plist`s — `…/Contents/Frameworks/OpenCode Helper (GPU).app/…`
and siblings — and an unanchored match reaches one of those first, with a
different version in it.

## §6 What the substitution switches off, and what it must not

The bytes taken are not the artifact our route resolved. OpenCode's
`GitHubReleaseRule` selects `opencode-desktop-mac-arm64.dmg`; electron-updater
only ever downloads the zip. Same release, same Team, both notarized — a
different container. So anything the route publishes that describes *its*
artifact stops applying, and `applyVerified` drops it:

- `RemoteVersion.expectedSHA512` digests the dmg. Run against the zip it cannot
  pass, and it would fail as `checksumMismatch` — "may be corrupt or tampered" —
  for a file that is neither.
- `RemoteVersion.nestedArchivePath` describes where a payload sits inside one
  particular stub installer. A zip of the app is not that stub.

What does not change is everything downstream of the container: `ArchiveExtractor`
dispatches on the suffix, and `SignatureVerifier.verifyInstallArtifact` — bundle-id
pin, Team-ID match against the installed copy, notarization — runs on the
extracted bundle exactly as it does for a downloaded one. That is the gate that
makes the substitution safe, and it is deliberately the same code path rather
than a parallel one.

The file is copied into our scratch directory, never used in place and never
deleted: it belongs to the other updater, which is free to clear `pending/` or
overwrite it mid-install, and our caller removes the scratch directory wholesale.

## §7 End-to-end verification (2026-09-16)

Against the live OpenCode state described in §2, with `make cli` freshly built:

```
$ duo install OpenCode --yes
→ OpenCode
   downloading… / extracting / verifyingCodeSignature / installing / done
1 installed, 0 failed.
real 3.5s
```

```
13:10:52.072  install start: OpenCode [ai.opencode.desktop] 1.18.26 → 1.18.31 via vendor
13:10:52.365  local stash hit: OpenCode 1.18.31 already downloaded by its own updater — 149629372 B not fetched
13:10:53.225  install returned: OpenCode [ai.opencode.desktop] applied=true bytes=0 staged=false
```

Afterwards: the bundle reported `CFBundleShortVersionString` and
`CFBundleVersion` 1.18.31 and `TeamIdentifier=5NZ4Q7NXJ4`; the app's own
`pending/` directory was byte-for-byte unchanged; our scratch directory was gone.
`bytes=0` is the traffic ledger's own statement that nothing was fetched.
