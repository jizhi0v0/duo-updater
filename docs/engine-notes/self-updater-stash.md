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
copy. Hence `isSoleClaimant`, which requires the one bundle claiming the cache
directory to BE the app being installed, and refuses a population it was not
given. It runs after the archive is known to exist — see §7 for why.

⚠️ **Requiring the claimant to be this app is not the same as counting one.**
The first version counted, and that passes when the app under install is ABSENT
from the population — one at a path the scan did not cover, or moved between the
scan and the per-install re-check — while some other bundle claims the same
directory. The gate would then hand that other app's `pending/` over, leaving
only the archive's bundle identifier to object; and two copies of one app, the
case this gate exists for, share that too.

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

1. **A dmg cannot be version-read as cheaply as a zip.** Reading the bundle
   version out of one means attaching it — a device, a mount point — where a
   zip's central directory is at the tail and randomly addressable, which is
   what makes the gate in §5 cost ~2 ms. This originally said "seconds"; that
   was never measured, and it is only true with checksum verification on. With
   `-noverify` it is a fraction of a second — see *Re-measured 2026-10-15* below.
   Both of these carry the version in the *file name*, but trusting a vendor's
   file-name habit is the assumption OpenCode already falsifies.
2. **A `.pkg` is not swapped by this route at all** — `VendorInstaller.download`
   refuses `.pkg` and `PackageInstaller` handles it, so the substitution has
   nowhere to land.
3. **The benefit is unproven for them.** Both parked installers observed were
   stale (§2), so neither would have been used.

`SelfUpdaterStash.archiveKind` still classifies dmg and tar.gz rather than
pretending they do not exist; `resolve` refuses everything but zip, which is what
electron-updater downloads on macOS in any case
(`findFile(files, "zip", ["pkg", "dmg"])`).

### Re-measured 2026-10-15: what reading a dmg's version actually costs

One-time measurement, not a tracked metric. Same two images, same script, on two
machines: the development Mac (macOS 27.2, M3 Max; load average ~27 at the time,
so its numbers are the noisier ones) and the mini (macOS 26.7, M4; load ~3). Each
cell is the median of 5 runs of attach → read the root `.app`'s `Info.plist` →
detach, with `com.apple.diskimages.recentcksum` stripped before every run so the
verified rows really verify. Both images are UDZO, ~176 MB.

| mode | Gemini, 27.2 | Gemini, 26.7 | Qianwen, 27.2 | Qianwen, 26.7 |
|---|---|---|---|---|
| `hdiutil attach -noverify` | 0.56 s | 0.25 s | 0.60 s | 0.18 s |
| `diskutil image attach` | 0.96 s | 0.41 s | 0.78 s | 0.32 s |
| `hdiutil attach` (verifies) | 2.00 s | 3.59 s | 3.40 s | 2.97 s |

Reading the plist itself is 2–10 ms in every row; the rest is attach and detach.

- **There is no OS difference to find.** macOS 26 is no slower, and on the quiet
  machine it is faster. The "seconds" is the UDIF checksum pass over the whole
  image, on either OS (1.5–4.9 s per run across both machines).
- **`-noverify` is only honest with a digest gate behind it.** Skipping the
  checksum is what makes this cheap, so the bytes have to be proven some other
  way, as gate 8 does for zips. Of the shapes seen, Gemini records no digest at
  all, Qianwen records only an MD5 (its `sha256` field is empty), and Cindy (a
  zip) records a SHA-256.
- **A verifying attach writes onto the other updater's file.** It leaves a
  `com.apple.diskimages.recentcksum` xattr on the image, and later verifying
  attaches skip the pass because of it (the uncached ~2.4 s became ~0.3 s). That
  is a write to bytes we do not own, and it is also why a naive re-run looks fast.
- **macOS 27's `DiskImageKit` does not help.** Its public interface (SDK
  `DiskImageKit.swiftinterface`) knows three formats — `asif`, `raw`, `stack` —
  and offers create / open / append-layer / truncate, with no block or file
  read. Opening either UDZO image throws `UnsupportedFormatError` within 16 ms.
  `diskutil image attach`, which the 27 `hdiutil imageinfo` deprecation
  warning points to, is still an attach, and slower than `hdiutil -noverify`.
- **What is inside need not be the app, and the route already knows.** Qianwen's
  image root holds `com.qianwen.inputmethod.desktopime.installer`; the input
  method (`com.qianwen.inputmethod.desktopime` 1.2.35.46) is in
  `Contents/Resources/QianwenIME.zip` inside it — exactly the recipe's
  `nestedArchivePath`. A reader that looks only at the root `.app`, as the zip
  reader does, would refuse it; one that follows the route's own nested path
  would not.

Shapes seen that day, beyond the two above. None was newer than what was
installed, so none would have been used:

| app | parked at | integrity record | parked | installed |
|---|---|---|---|---|
| Gemini | `~/Library/Caches/com.google.GeminiMacOS/Updates/<version>/update.dmg` | none locally | 1.128.7.1072 | 1.128.14.1166 |
| Qianwen IME | `~/Library/Application Support/QianwenIME/updates/<md5>.dmg` + `silent-install-session.json` | MD5 (= file name) | 1.2.35.46 | 1.2.35.46 |
| Cindy | `~/Library/Application Support/CindyGlobal/updates/<name>.zip` + `patch-info.json` | SHA-256 + version | 0.1.99 | 0.1.97, offered 0.1.108 |

What each one is, as far as the evidence went:

- **Gemini** — written by the app's in-app Omaha updater (its log says "Using
  Omaha updater"); a second updater, GoogleUpdater/Keystone, also installs it
  (`Logs/preinstall_*.log`, signal file `update_pending`). The dmg was born
  12:30:58, finished 12:31:29, and the app relaunched as that version at
  12:31:38, so it is the installer of the version just applied, left behind —
  not a download waiting to be applied. Whether this updater ever parks a
  *newer* version there is not observed. The route's own Omaha response carries
  a `hash_sha256` per package, which would be the digest gate if the parked file
  is that same package; not checked, since Omaha only answers for the current
  version.
- **Qianwen IME** — not byte-identical to the vendor's current CDN dmg (176,333,529
  vs 176,309,198 bytes, ETag ≠ its MD5) but carries the same payload version —
  the OpenCode shape again, one release in two containers. Version equal to the
  installed build, so there was nothing to apply.
- **Cindy** — a full `Cindy.app` (`com.xd.cindy` 0.1.99), SHA-256 matching
  `patch-info.json`. It comes from Cindy's own manifest (`app.version` +
  `app.hotfix.file`, applied on relaunch), not from GitHub: v0.1.99 was never
  published as a GitHub release (0.1.97 → 0.1.101), and our route offers GitHub
  versions, so the version gate can only match when the two lines agree.

Warp's parked file that day was a truncated UDIF image, not a different format:
its first chunk inflates to 512 zero bytes, consistent with the start of a UDZO
image, but it
is 105,775,627 bytes against the vendor's 326,470,525 for that version, so the
`koly` trailer never arrived and `hdiutil` reports "image not recognized". It
sat in a random-named directory (`autoupdate/nCFyXHk/`) from 2026-07-16 with no
completion record beside it — an abandoned download.

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

**The version read runs first and the hash last**, and the order was chosen
against the common case rather than the interesting one. A parked installer is
usually stale (§2), so hashing before reading the version would spend ~0.31 s to
learn what ~2 ms already says, on every install of such an app. The cost of that
order, stated because it is not free: `unzip` reads an archive whose integrity
has not yet been established. Acceptable here and only here — the file was
written by an app already installed and running as this user, so it is not a new
trust boundary — and nothing read from it is used until the digest agrees.

The hash is still mandatory before the bytes are adopted: it is the only thing
that proves what is on disk is what the app's own updater recorded, and 0.31 s is
nothing next to the download it replaces.

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
- `RemoteVersion.expectedSHA256` likewise — for OpenCode it is the `digest` GitHub
  publishes for that dmg, not for the zip.
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

## §7 Why a refusal is logged louder than a skip, and why the gate order follows

`resolve` has two log levels. Everything up to "is there a parked archive at all"
is the ordinary answer for nearly every app on the machine; logging it would be a
line per app per install with no reader, so it is `.debug`. Everything after that
point is a refusal to use a download that IS sitting on disk, and it is the only
thing that can answer the report this feature generates — "it fetched the whole
thing again even though the app already had it". Neither `.debug` nor `.info` is
retained for this subsystem, so a reason left at either level is gone by the time
anyone asks; those go out at `.notice`, alongside the hit.

**The gate order is arranged so that split is exactly true rather than nearly
true.** The attribution gate (§3) was originally third, ahead of the check for a
parked record — so two copies of an app sharing a cache directory announced
`attributionAmbiguous` at `.notice` on every install even when `pending/` was
empty, and a reader chasing "why did it download again?" would go hunting for a
file that was never there. It now runs after the archive is known to exist.
`Rejection.refusedAnArchiveOnDisk` is the single definition of which side each
answer falls on, and Swift's exhaustive switch makes adding a case a compile
error rather than a silent default.

`resolve` is a logging wrapper over `evaluate`, which returns WHICH gate
answered. That split is not tidiness: these gates are each other's fallback, so
deleting one usually leaves the next refusing the same input for a different
reason, and a test that only sees nil keeps passing while no longer measuring
anything. Three cases in this suite were vacuous for exactly that reason — two
found by a review, one by the re-review of the fix for the first two.

## §8 End-to-end verification (2026-09-16)

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
