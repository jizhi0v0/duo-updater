# Electron ZIP blockmap downloads

## 1. Eligibility and integrity

`VendorInstaller.download` tries this after an exact already-downloaded package
and the existing signed patch preference. The target must be a ZIP with a
publisher SHA512 or SHA256 and either installed Electron configuration or an
explicit sibling blockmap from the selected GitHub release. Nested installer
stubs and non-ZIP containers keep their existing routes.

The external gzip JSON v2 map describes original ZIP bytes. It cannot be made
from the installed `.app`. Unknown formats, including binary EBB3, fall back to
the ordinary full archive. The map has compressed/decoded, block-count,
block-size and total-archive bounds. COPY matches checksum plus block length;
DOWNLOAD ranges cross short COPY gaps to avoid tiny requests, and the complete
plan caps both network requests and total I/O iterations before work begins.

A reconstructed target must match every supplied whole-archive digest before
it reaches the existing bundle signature, Team, id, architecture, edition and
OS checks. The block checksums are planning hints, not installation trust.

## 2. Baseline cache and storage

Only a successful install retains its original ZIP/map pair in
`~/Library/Caches/com.duoupdater.installers`, keyed by bundle id plus installed
path. A cold update downloads fully and seeds the next update after the swap.
`DUO_STATE_DIR` redirects this cache together with other Duo state.

The 2 GiB cache counts allocated data and metadata. Old entries are evicted;
claimed readers are preserved and a new optional entry is dropped if they leave
no room. Open regular file handles protect COPY from path replacement; a stored
SHA256 rejects changed cached bytes. Owned `.incoming-UUID` directories left
by a killed writer are reclaimable. A vendor's configured `update.zip` and
`current.blockmap` can also provide a baseline without modifying vendor files.

Settings and `duo storage` show this cache as clearable. Disk-space reclamation
tries it before backups. Cache loss or refusal costs a future full download.

## 3. HTTP, cancellation and accounting

Metadata and ranges use a bounded delegate-driven session with no credential,
cookie or disk URL cache. Ranges require exact 206/Content-Range/size and identity
encoding. Redirects are bounded, strip cross-origin credentials and reject HTTPS
downgrades. Cancellation cancels the active URLSession task and escapes the
fallback path. Failed differential bytes and metadata count toward download
accounting; existing request metrics record their transfers as install traffic.

## 4. Verification

The offline suite covers parsing, moved blocks, request amplification, corrupt
and symlinked baselines, cache budget under parallel installs, orphan cleanup,
range failures, whole-target rejection and byte accounting. Cancellation tests
observe live map/range requests; a direct transport test releases a valid server
body after cancellation so a missing cancellation bridge cannot pass on timeout.

[VM receipts](../../verify/electron-blockmap-20261115/README.md) record a genuine
FlyEnv 4.20.1 → 4.20.2 cold/full then differential install, plus each proposed
DMG→ZIP package comparison and production install/startup result. These are
one-time measurements, not a maintained app inventory or a guarantee about all
future vendor artifacts.
