# WorkBuddy AI（国际站）

审计 2026-08-27。WorkBuddy 是**两个 app**，不是一个 app 的两个 channel：本文档是国际站
`com.workbuddy.workbuddy-ai`；国内站 `com.workbuddy.workbuddy` 见
[com-workbuddy-workbuddy.md](com-workbuddy-workbuddy.md)。两站共用的部分——更新端点、三个陷阱、
changelog 页面标记、一键安装的闸与 host 钉死、验证方法——只写在国内站那份里，这里不重复。

## 基本信息

| | 国际站 |
|---|---|
| Bundle ID | `com.workbuddy.workbuddy-ai` |
| App 名 | WorkBuddy AI.app |
| URL scheme | `workbuddy-ai` |
| 官网 | https://www.workbuddy.ai |
| 观测版本 | 5.4.2 |
| Team ID | `FN2V63AD2J` — Tencent Technology (Shanghai) Company Limited |
| 自更新机制 | 自研（Electron + `electron.net.fetch`，非 electron-updater，无 `app-update.yml`，无 Sparkle） |

国际版另有 `TuringShield.bundle`（腾讯安全 SDK），国内版没有；这属于两站构建差异，
与更新检测无关。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable（国际站）** | — | — | — | — | ✓ 一键 |

当前生效源：**VendorProbe**（前四条源全部不适用：无 `SUFeedURL`、无 cask、非 MAS、
无公开 GitHub 发布）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.workbuddy.workbuddy-ai` | 独立 | — | — | ✓ |

没有非 stable channel，理由（两站相同）见国内站文档的「Channel 详情」。

## Changelog

| | URL | 状态 |
|---|---|---|
| 国际站 | https://www.workbuddy.ai/docs/workbuddy/Changelog | 200，但**落后于自己的轨道**（写作时最新条目 5.2.7，而发布版是 5.4.2） |

解析结果（2026-08-27 实测）：国际站 2 条（最新 5.2.7）。这个 2 是**厂商页面本身**如此，
不是 recipe 坏了 —— 同一条正则在 CN 页跑出 58 条。`duo verify` 会为此报一条 ⚠（最新条目
5.2.7 落后于探测到的 5.4.2），这条警告是真的，且厂商补上笔记后会自动消失。

## 一键安装

- 状态：**支持**（检测 + 一键）
- install 正则钉死的下载 host：`codebuddy-1328495429.cos.accelerate.myqcloud.com`
  （为什么要钉、钉错会怎样，见国内站文档「一键安装」）

## 已知问题

- 国际站 changelog 页滞后于其发布轨道，vendor 侧问题，我们这边无解。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-workbuddy-workbuddy-ai.swift — VendorProbe（两站两个 app 的对照表）

转引自 recipe 注释，未复测。整段原文；（开头一句与表格之间原注释有空行，这里按两段放。）代码里只把表格最后一列的版本号去掉了。原句没写日期，引入它的提交是 `a374e923`（2026-08-27）。

WorkBuddy ships as TWO separate apps, not two channels of one. Tencent
runs an international site and a China site, each with its own bundle
id, its own app name, its own update host and its own release train:

```
  com.workbuddy.workbuddy-ai  "WorkBuddy AI.app"  www.workbuddy.ai  5.4.2
  com.workbuddy.workbuddy     "WorkBuddy.app"     www.workbuddy.cn  5.3.14
```

### Recipes/com-workbuddy-workbuddy-ai.swift — VendorProbe（传已装版本会得到 204）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论和日期（传你已经在跑的版本会得到 204，measured 2026-08-27 on both hosts），当天两站各传的版本搬到这里。

TRAP, and the reason `version=0.0.0` is pinned into the URL: this is a
"should I update?" service, not a "what is the latest?" one. Passing the
version you already run returns **204 No Content** (measured 2026-08-27:
5.3.14 → 204 on the CN host, 5.4.2 → 204 on the intl host), which would
make the probe go dark precisely when it should say "up to date". An
impossibly old version is what turns it into a latest-version query.

### Recipes/com-workbuddy-workbuddy-ai.swift — VendorProbe（按架构分两条 recipe）

转引自 recipe 注释，未复测。整段原文；「currently」一句按复测加了日期；「offer an Intel Mac a zip it cannot run」迁移时已不成立，代码里改写了，见下面的更正。

Architecture: the endpoint serves both Macs and currently answers the
same version to each, but the `url` it hands back is arch-specific
(`/darwin-arm64/…` vs `/darwin-x64/…`). One recipe reading the arm64
endpoint would therefore offer an Intel Mac a zip it cannot run. Hence
one recipe per architecture, split by `hostRequirement` rather than by
channel (the Raycast v1/v2 shape) so exactly one is eligible on any
given Mac, and the install pattern is additionally pinned to its own
`darwin-<arch>` path so a recipe cannot resolve the other arch's
artifact even if the endpoint were to start ignoring the query.

更正 2026-09-14：DuoUpdater 只跑在 arm64 上（`App/project.yml:23` `ARCHS: arm64`），没有 Intel 宿主。`VendorProbeSource` 在合并多端点之前按 `HostArch.current` 丢掉宿主跑不了的 recipe（`Sources/VendorProbeSource.swift:266-268` 调 `VendorProbeRecipe.runs(onOS:arch:)`，`Sources/VendorProbeRecipe.swift:1038-1040`；`VendorHostRequirement.isSatisfied` 是不带 Rosetta 例外的成员判断，:187-188），所以 x86_64 那条 recipe 在任何 DuoUpdater 宿主上都不会被用到。代码里去掉了 Intel Mac 的说法，改成说明这件事；同一说法在 [com-workbuddy-workbuddy.md](com-workbuddy-workbuddy.md) 的「陷阱三」里的副本一并改了。

复测 2026-09-14（11:03 UTC，只读 GET）：`www.workbuddy.ai/v2/update?platform=workbuddy-darwin-arm64&version=0.0.0` 与 `…-x64…` 都回 `productVersion` `5.5.2.37849279`，`url` 分别在 `/darwin-arm64/` 与 `/darwin-x64/` 下；国内站两个架构都回 `5.3.14.36279234`。

### Recipes/com-workbuddy-workbuddy-ai.swift — VendorProbe（一键：两站 DMG 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（`sha256hash` 接不上 `checksumPattern`，由 Team FN2V63AD2J 闸兜底），2026-08-27 对两站 DMG 的字节数与签名核对搬到这里。

One-click: the JSON's `url` is a plain, unsigned object on Tencent COS
(intl: `codebuddy-1328495429.cos.accelerate.myqcloud.com`; CN:
`download.codebuddy.cn`). The `sha256hash` field alongside it is a
SHA-256 hex digest, which `checksumPattern` (SHA-512, base64) cannot
consume, so it is left unused and Team FN2V63AD2J gates the swap.
Verified 2026-08-27 against both vendor DMGs at the same paths: the
`.dmg` sibling of each `.zip` matches the published installer byte
count, and both bundles are Developer ID signed under FN2V63AD2J.

### Recipes/com-workbuddy-workbuddy-ai.swift — VendorProbe（Changelog：国际站页面落后）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（国际站页面落后于自己的轨道，这正是国际站 ChangelogRecipe 带 `acknowledgedStaleEntry` 的原因），写作当时的 5.2.7 / 5.4.2 搬到这里。复测见 [com-workbuddy-workbuddy.md](com-workbuddy-workbuddy.md) 的「历史与实测」。

Changelog: each site's page is the one the app itself links (the build
branches on `isOverseas()`); the intl page ran behind its own train at
the time of writing (newest entry 5.2.7 against a 5.4.2 release) while
the CN page was current.

### Recipes/com-workbuddy-workbuddy-ai.swift — VendorProbe（`version=0.0.0` 会钉在升级链的第一跳；#737 / #738）

2026-09-18 实测，起因是 `duo verify` 连报两轮 `installURLNotFound` + version 倒退。

`/v2/update` 不是「最新是什么」，也不只是「要不要更新」——它回的是**升级链上的下一跳**。同一天同一个端点，只改 `version` 参数：

| 请求 | `productVersion` |
|---|---|
| `?platform=workbuddy-darwin-arm64`（不带 version） | `5.5.2.37849279` |
| `…&version=5.3.14` | `5.5.2.37849279` |
| `…&version=5.5.0` | `5.5.2.37849279` |
| `…&version=5.0.0` | `5.3.14.36279234` |
| `…&version=1.0.0` | `5.3.14.36279234` |
| `…&version=0.0.0` | `5.3.14.36279234` |

即：比所有发布都旧的版本拿到的是中间跳 `5.3.14.36279234`，不是最新版。

**为什么以前是对的、后来静默错了。** `version=0.0.0` 是当初为绕开 204 钉进去的，钉的时候这条链的第一跳恰好就是最新版。本审计 2026-09-14 那次复测还记着国际站回 `5.5.2.37849279`——那时链只有一跳。厂商后来在上面加了发布，四条 recipe（两站 × 两架构）全部冻在第一跳上。

**只有国际站两条被发现，而且不是因为版本错。** 国际站那一跳的产物后来被 CDN 删了，`duo verify` 才看见 HTTP 404 + version 倒退（#737、#738）。国内站两条的那一跳产物还在，于是一路绿着停在 `5.3.14`，而同一个 app 的 changelog recipe 在同一份 `verify/baseline.json` 里、隔几行，`lastGoodVersion` 写着 `5.5.6`。

这里**有**一条 probe↔changelog 的交叉检查，`Verify.changelogLagComplaint`，而且这两个数字当时就在它手上（两行的 `lastGoodAt` 同为 `2026-09-17T20:25:48Z`，同一轮扫描）。它没响是因为它**单向**：只在 changelog **落后于** probe 时报。这里是 changelog 5.5.6 **领先于** probe 5.3.14——而「changelog 跑在 probe 前面」正是探针冻住的样子，那个方向没人看。见 #743。

**改法**：URL 里不带 `version` 参数。四个 host×arch 组合当天实测都回 200（不是 204）：国际站两架构 `5.5.2.37849279`，国内站两架构 `5.5.6.38337834`，与 Homebrew cask `workbuddy-ai`（`5.5.2.37849279-910352f0`）一致；cask 的 livecheck 打的也正是这个不带 `version` 的 URL。产物存在性也核了：`…-5.3.14.36279234-825709d4.zip` 为 404，`…-5.5.2.37849279-910352f0.{zip,dmg}` 均为 200。

顺带核过的同形写法：`app-chatwise.swift` 的 `releases?version=0.0.0&platform=osx` 不受影响——带不带 `version`、传 `0.8.0`，都回同一个 `26.9.0`，与 brew 一致，没有链式行为。`com-lemon-lvoverseas.swift` 钉的是 `9.99`（比所有发布都**高**），方向相反，钉不到跳上。
