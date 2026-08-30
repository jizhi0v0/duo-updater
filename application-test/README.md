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

## 判据必须借用引擎，不能重实现

`channel-verify` 曾经两处自己推导，两处都错，而且错得会让一个 ✓ 变得毫无意义
（2026-08-21 由豆包输入法的验证逼出来）：

1. 直接读 `CFBundleVersion`，于是对一个生产按 `90602` 比较的 app 打印 `build version 1`。
2. 把引擎判据重实现成「有 shortVersion 就比它，否则比 build」。每条 `versionIsBuild`
   recipe 两者都带——build 用来比，marketing 串用来显示——而 `UpdateChecker.evaluate()`
   优先比 build，那份重实现优先比 marketing。结果 90601 那份被读成"已是最新"。

两处都已改成镜像 `AppScanner.buildVersionIsOverridden` + 直接调 `UpdateChecker.evaluate`。

**规矩**：这个 harness 里任何"是否有更新"的判断都必须调用 `UpdateChecker.evaluate`，
不得另写一份。同一形状的错误在 2026-08-30 又犯过一次——当时用 `VersionComparator.hasReached`
（那是**重启落地**检测的入口，只服务于自带更新器的 app）去判"有没有更新"，于是把两条
本来正常的 recipe 误报成 bug。入口选错和重实现是同一类错。
