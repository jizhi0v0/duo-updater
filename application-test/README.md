# application-test — strict on-machine channel verification

A claim like "a Daily install is detected as `.nightly` and its recipe fires" is
worthless until it's run against a **real bundle on this machine**. This package
makes that one command, exercising the *production* `ReleaseChannel.detect()` and
`VendorProbeSource` (linked from `../DuoUpdaterCore` — never a re-implementation).

This exists because trusting a vendor's *version feed* instead of a *real bundle*
silently shipped two broken Thunderbird recipes (see `records/`). The feed carried
`…esr`/`…b3` suffixes the installed app strips, and used bundle ids the real
builds don't. Only mounting the actual DMGs surfaced it.

## Run

```bash
# Installed app:
swift run --package-path application-test channel-verify "/Applications/Thunderbird.app" --expect stable

# A downloaded DMG — mounted read-only, inspected, auto-detached (NO install):
swift run --package-path application-test channel-verify "/tmp/tb-daily.dmg" --expect nightly
```

`--expect <channel>` is optional; when given, exit code is non-zero on a mismatch
(or a probe miss), so it doubles as a check in a script. Output prints the real
identity fields, the detected channel, and the live probe's from→to verdict.

## What counts as "strictly verified"

A (bundleID, channel) recipe is **verified** only when the harness has been run
against a real bundle of that channel and shows all three:

1. the **real** `bundleID` + `CFBundleShortVersionString` (from Info.plist),
2. `detected channel` == the channel the recipe targets,
3. the probe **answers** for that channel with a sane from→to (no phantom update).

Until then the channel is **needs-verify**, not ✓ — record it as such in the audit
doc and `docs/app-audits/README.md`.

## Getting a channel's installer without installing it

- Homebrew records the per-channel cask + URL: `brew cat --cask <name>@<channel>`.
- Mozilla redirector: `https://download.mozilla.org/?product=<slug>-latest-ssl&os=osx&lang=en-US`
  (HEAD it to read the resolved filename/version before downloading).
- Mount read-only and let the harness inspect: it takes the `.dmg` directly.

## records/

One file per app: the evidence table from the last verification run (date, real
bundle id, real version, RemotingName/channel marker, detected channel, probe
result, verdict). This is the proof behind a ✓ in the audit docs.

> Build artifacts (`.build/`) are git-ignored.
