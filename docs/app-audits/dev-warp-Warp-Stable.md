# Warp

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable 完整（检测+一键）；preview/dev 已检测；beta/canary 轨道已废弃，无配方**

## 基本信息
- Bundle ID: `dev.warp.Warp-Stable`（preview/dev 各自独立：`dev.warp.Warp-Preview` / `dev.warp.Warp-Dev`）
- 自更新机制: Warp 自研更新器

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **preview**  | —       | —        | —   | —      | ✓           |
| **dev**      | —       | —        | —   | —      | ✓           |
| **beta**     | —       | —        | —   | —      | ✗(轨道废弃) |
| **canary**   | —       | —        | —   | —      | ✗(轨道废弃) |

当前生效源: **VendorProbe**（stable 走 `app.warp.dev/download` 页面；preview/dev 走 `releases.warp.dev/channel_versions.json`）

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `dev.warp.Warp-Stable`  | 独立 | bundle id `-Stable` 后缀  | ✓ 检测+一键 |
| preview | `dev.warp.Warp-Preview` | 独立 | bundle id `-Preview` 后缀 | ✓ 仅检测 |
| dev     | `dev.warp.Warp-Dev`     | 独立 | bundle id `-Dev` 后缀     | ✓ 仅检测 |
| beta    | `dev.warp.Warp-Beta`    | 独立 | — | ✗ 轨道冻结于 2024-12，无配方 |
| canary  | `dev.warp.Warp-Canary`  | 独立 | — | ✗ 轨道冻结于 2022-09，无配方 |

Beta/Canary 轨道仍在 `channel_versions.json` 中有键，但版本停更已数月/数年。不加配方，避免永久报"需要更新"（那个"最新"是过时构建）。

## 更新检测
- stable: VendorProbe `app.warp.dev/download?package=dmg` → GET，**不跟随**（302 直接到 320 MB dmg）；version 从小的重定向 body 中提取 `releases.warp.dev/stable/v<ver>.stable`
- preview/dev: VendorProbe `releases.warp.dev/channel_versions.json` → `"version":"v<ver>.<channel>_NN"` 各自 pattern

## Changelog
- stable: ChangelogRecipe ✓（`docs.warp.dev/changelog/2026/`，Starlight 渲染页，年份路径）
- preview/dev: 无独立 changelogURL（WebView 均指向同一 `docs.warp.dev/changelog` 页）
- 缺口: preview 和 dev 的 `changelogURL` 与 stable 共用；VendorProbe 的 changelogURL 字段已设，不是 ChangelogRecipe

## 一键安装
- stable: ✓ dmg（`releases.warp.dev/stable/v<ver>/Warp.dmg`），Team 2BBY89MBSN
- preview/dev: 仅检测

## channel-verify 状态
- ✓ **三 channel 全部已验证 2026-06-04**。stable `dev.warp.Warp-Stable`（本机 `--scan`）/ preview `dev.warp.Warp-Preview` / dev `dev.warp.Warp-Dev`（官方 dmg 只读挂载）各自 VendorProbe 应答=对应版本，无幽灵更新；channel 由连字符后缀直读。beta/canary 死轨已弃、不给 recipe。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan dev.warp.Warp-Stable --expect stable
swift run --package-path application-test channel-verify /tmp/WarpPreview.dmg --expect preview
swift run --package-path application-test channel-verify /tmp/WarpDev.dmg     --expect dev
```

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/dev-warp-Warp-Stable.swift — Preview / Dev VendorProbe（版本里的构建计数器）

转引自 recipe 注释，未复测。整段原文；末句指向的记录文件迁移时已不在当前树里（`4ff9a902` 起不再跟踪），代码里改写了，见下面的更正。这里还有一处不是机器状态的改写：原文末句里那份记录文件的完整路径换成了「[an untracked local record]」——`scripts/check_app_audits.py` 不允许审计文档里出现指向未跟踪记录目录里某个文件的路径，逐字保留会让检查失败。下面的更正换一种写法点名了同一个文件，因为它配了 `git show 19296da7:` 这个任何人都能复现的读法，不再是只有一个人读得到的路径。

Warp — Preview / Dev. One JSON lists every channel's version, each tagged
with the channel name in its suffix (`…preview_01`), so a per-channel
pattern is unambiguous. Channels ship as separate bundle ids
(`dev.warp.Warp-Preview`, …) — the Stable build is the existing
`dev.warp.Warp-Stable` recipe below. Both capture groups matter: the app
reports the feed's `v<stamp>.<channel>_NN` as `<stamp>.NN`, so the
counter is joined back on (see `VendorProbeRecipe.version(of:in:)`).
Confirmed against real bundles on all three tracks in
[an untracked local record] — including dev's
`_00`, which the app does spell out as a trailing `.00`.

更正 2026-09-14：那份记录文件（记录目录 `application-test/records/` 下的 `dev-warp-Warp-Stable.md`）由 `19296da7`（2026-06-04）加入 git，`4ff9a902`（2026-08-14，「chore: stop tracking local working notes」）起不再跟踪，现在由 `.gitignore:40` 排除，所以当前树里循着这个路径找不到它。`git show 19296da7:` 加上那个路径仍能读到：表里 dev 的真实 short version 是 `0.2026.06.04.09.31.00`（stable 与 preview 是 `0.2026.05.27.15.44.01`）。原结论出自提交 `c910576f`（2026-08-10），它的提交说明写着三条轨都对真实 bundle 核对过、包括 dev 的 `.00`。代码里保留这个结论，改成写明记录的加入与取消跟踪的两个提交，并指向本审计的 channel-verify 一节（2026-06-04 的三轨核对）。

### Recipes/dev-warp-Warp-Stable.swift — Preview VendorProbe（一键与 `channel=dev` 的陷阱）

转引自 recipe 注释，未复测。整段原文；代码里把「a 300 MB disk image」换成了「a disk image of a few hundred MB」（原句没写日期，引入它的提交是 `8345c35b`，2026-08-09），并把「(verified 2026-08-09: …)」改成把日期放在末尾的「(…; checked 2026-08-09)」，核对的内容原样。

PREVIEW installs one-click; DEV deliberately does not. `app.warp.dev/
download?package=dmg&channel=preview` really does serve WarpPreview.app
(verified 2026-08-09: dev.warp.Warp-Preview, Team 2BBY89MBSN, notarized,
version matching the JSON). The same URL with `channel=dev` ignores the
parameter and hands back **Warp.app / dev.warp.Warp-Stable** — wiring that
would install Stable over a Dev install, the cross-channel swap the whole
channel gate exists to prevent. Note the Content-Type on both is
`text/html` despite the body being a 300 MB disk image; don'"'"'t trust it.

### Recipes/dev-warp-Warp-Stable.swift — ChangelogRecipe（读 `channel_versions.json` 而不是文档站）

转引自 recipe 注释，未复测。整段原文；「As of mid-2026 … sits behind」迁移时已不成立，代码里改成过去时并注明复测，见下面的复测；其余原样。

Warp — read the machine-readable feed, not the docs site. As of mid-2026
docs.warp.dev sits behind a Vercel "Security Checkpoint" JS bot wall that
returns HTTP 429 + a challenge page to any non-browser fetch, so the old
Starlight-HTML scrape (year-pinned `/changelog/2026/`) went permanently
dark. `releases.warp.dev/channel_versions.json` is the same ungated
endpoint the vendor probe already uses and carries a full per-channel,
per-version `changelogs` map (date + markdown sections) — richer and far
more stable than scraping rendered HTML. One recipe per channel; both
point at the same JSON but the `channel` selects the sub-feed (and gives
each its own cache slot — see `ChangelogService`). The entries are NOT in
newest-first document order in the JSON, so the structured decoder sorts
by the (lexically-chronological) version key — hence not a regex recipe.

复测 2026-09-14（11:40–11:41 UTC，只读 GET，不跟随重定向）：`docs.warp.dev/changelog` 与 `docs.warp.dev/changelog/2026/` 在 Safari UA、`Python-urllib/3.12` UA、`curl/8.7.1` UA 下都回 200（96,473 B / 554,738 B），body 里没有 "Checkpoint"。本机走代理，没有换网络再测。同一说法在 `Sources/ChangelogRecipe.swift` 的 `StructuredFormat.warpChannelVersions` 文档注释里的副本（「which now sits behind a Vercel bot wall」）一并改成了过去时并注明复测。

### Recipes/dev-warp-Warp-Stable.swift — ChangelogRecipe（为什么没有 Dev recipe）

转引自 recipe 注释，未复测。整段原文；代码里只把「(verified 2026-08-09)」改成了「(when checked, 2026-08-09 and 2026-09-14)」。

Stable and Preview only. There is deliberately **no Dev recipe**: Warp
ships a real `dev.warp.Warp-Dev` build and the probe tracks its version
fine, but the vendor publishes no notes for that track. `changelogs.dev`
holds exactly one entry — and it is fixture data, unchanged for years
(verified 2026-08-09):
```
  "v0.2026.08.07.08.31.dev_00": { "date": "2021-11-23T10:07:01-06:00",
    "sections": [ { "title": "dev", "items": ["dev 1", "dev 2"] } ],
    "oz_updates": ["[TEST] Testing Oz recent updates!", …] }
```
The version key tracks the live dev build, but the body is placeholder
text under a 2021 date, and it uses the pre-2022 `sections` shape rather
than the `markdown_sections` every real entry has had since. Surfacing
"dev 1 / dev 2" under the installed dev version would be worse than
nothing, so Warp-Dev carries no recipe and falls back to embedding
docs.warp.dev/changelog — same call, and the same reasoning, as the
VendorProbe declining to probe the abandoned beta/canary tracks.

复测 2026-09-14（11:40 UTC，只读 GET `releases.warp.dev/channel_versions.json`，1,375,485 B）：`changelogs.dev` 仍只有 1 条，key 是 `v0.2026.09.14.08.30.dev_00`，`date` 仍是 `2021-11-23T10:07:01-06:00`，`sections` 仍是 `dev 1` / `dev 2`。

### Recipes/dev-warp-Warp-Stable.swift — stable VendorProbe（`followRedirects: false`）

转引自 recipe 注释，未复测。整段原文；代码里只把「the 320 MB dmg」换成了「the full dmg」。原句没写日期，引入它的提交是 `182717d4`（2026-06-02）。

GET 302s straight to the 320 MB dmg — DON'T follow; read the small
redirect body, whose href carries both the version and the dmg URL.
