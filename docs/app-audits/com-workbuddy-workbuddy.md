# WorkBuddy（国内站）

审计 2026-08-27。WorkBuddy 是**两个 app**，不是一个 app 的两个 channel：本文档是国内站
`com.workbuddy.workbuddy`，国际站 `com.workbuddy.workbuddy-ai` 见
[com-workbuddy-workbuddy-ai.md](com-workbuddy-workbuddy-ai.md)。两站共用的部分（updater 代码、
更新端点与三个陷阱、changelog 页面标记、一键安装的闸、验证方法）只写在这一份里。

## 基本信息

| | 国内站 |
|---|---|
| Bundle ID | `com.workbuddy.workbuddy` |
| App 名 | WorkBuddy.app |
| URL scheme | `workbuddy` |
| 官网 | https://www.workbuddy.cn |
| 观测版本 | 5.3.14 |
| Team ID | `FN2V63AD2J` — Tencent Technology (Shanghai) Company Limited（与国际站同一个） |
| 自更新机制 | 自研（Electron + `electron.net.fetch`，非 electron-updater，无 `app-update.yml`，无 Sparkle） |

两个包的 updater 代码**逐字节相同**；分流完全靠 build 时烤进 product config 的
`endpoint`（`getUpdateBaseUrl()` 就是读它）。因此**唯一**把安装引到自己那条轨道
上的东西是 bundle id —— 而 bundle id 正是 recipe 的查找键，两条轨道天然不可能串。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable（国内站）** | — | — | — | — | ✓ 一键 |

当前生效源：**VendorProbe**（前四条源全部不适用：无 `SUFeedURL`、无 cask、非 MAS、
无公开 GitHub 发布）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.workbuddy.workbuddy` | 独立 | — | — | ✓ |

**没有非 stable channel。** 两个 bundle 里都不存在 `KSChannelID`、`RemotingName`、
可读的 `package.json` channel 字段或任何偏好键；`ReleaseChannel.detect()` 对两者都
判 stable，与实际相符。"国际站 / 国内站"是**发布站点**这条轴，不是质量轨道那条轴，
不应该被建模成 channel —— 建成 channel 反而会给出一个能把一站的包投给另一站安装的
路径，而现在这条路径不存在。

## 更新检测

端点就是 app 自己的 `AbstractUpdateService` 调的那个：

```
<base>/v2/update?platform=workbuddy-{os}-{arch}&version=<已装版本>
```

`<base>` 默认 `https://copilot.tencent.com`（与 `www.workbuddy.cn` 应答一致）。
无鉴权：app 会追加的 `x-user-id` / `x-tenant-id` 是可选的，recipe 两个都不发。

响应（2026-08-27 实测，国际站 arm64）：

```json
{"version":"5.4.2.36857725",
 "url":"https://codebuddy-1328495429.cos.accelerate.myqcloud.com/workbuddy/saas/darwin-arm64/WorkBuddy-darwin-arm64-5.4.2.36857725-d74591c4.zip",
 "productVersion":"5.4.2.36857725",
 "sha256hash":"5d28d2b0…","timestamp":1787580925,
 "hash":"","name":"","supportsFastUpdate":false}
```

### 陷阱一：这是「我该更新吗」而不是「最新是多少」

把你**已经在跑的版本**传进去，端点回 **204 No Content**（实测：国内站传 5.3.14 →
204，国际站传 5.4.2 → 204）。照搬会让探针恰好在"应该说已是最新"的时候变哑。
所以 recipe 的 URL 里**不带 `version` 参数**：不带就回 200 + 最新版，既绕开 204，
也不会钉在升级链的某一跳上。

更正 2026-09-18（#737、#738）：这一节原来写的是「把 `version=0.0.0` 钉死，才把它
变成一个 latest 查询」。**钉 `0.0.0` 是错的**，而且国内站这两条 recipe 就是因此静默
错了两个发布。`/v2/update` 回的不是最新版，是**升级链上的下一跳**：比所有发布都旧的
版本（`0.0.0` / `1.0.0` / `5.0.0`）拿到的是中间跳，不是链尾。钉的时候第一跳恰好就是
最新版，所以当初读对了；厂商在上面加了发布之后，两站 × 两架构四条 recipe 全部冻在
第一跳上。国内站两条那一跳的产物还在 CDN 上，于是一路绿着停在 `5.3.14`，而同一个
app 的 changelog recipe 在同一份 `verify/baseline.json` 里、隔几行写着 `5.5.6`
—— 闸看的是「这次和上次比」，没有任何东西去比对这两行。国际站两条被发现，只是因为
那一跳的产物后来被删了、报出 404，**不是因为版本错**。完整的实测表（六个 `version`
取值 × `productVersion`）见 [com-workbuddy-workbuddy-ai.md](com-workbuddy-workbuddy-ai.md)
的「历史与实测」，两站 recipe 同一个工厂出的，那一条对国内站同样成立：不带 `version`
时国内站两架构当天都回 `5.5.6.38337834`（200，非 204）。

### 陷阱二：版本方案（幻影更新）

端点报四段 `5.4.2.36857725`，最后一段是 build 计数器，**在已装 bundle 里哪儿都
没有** —— `CFBundleShortVersionString` 和 `CFBundleVersion` 都是光秃秃的 `5.4.2`。
直接比原值等于 `36857725 > (无)`，是那种永远清不掉的幻影更新。

`versionIsBuild` 在这里是**错的解**：那个计数器也不是 app 的 `CFBundleVersion`。
正解是正则只捕前三段、第四段匹配后丢弃。代价要明说：**vendor 只动 build 计数器的
重新出包，我们看不见。** 第四段写成可选，是为了 vendor 哪天退回三段式时不会静默失配。

### 陷阱三：架构

端点两个架构都服务，且目前对两者回同一个版本 —— 但它给回的 `url` 是分架构的
（`/darwin-arm64/…` vs `/darwin-x64/…`）。所以每站注册**两条 recipe**，用 `hostRequirement` 分流
（Raycast v1/v2 的形状），任一台 Mac 上恰好一条合格；install 正则再各自钉死自己的
`darwin-<arch>` 路径，这样即便端点哪天开始无视 `platform` 参数，也解析不出另一架构
的产物。

更正 2026-09-14：这一节原来在分两条 recipe 之前还有一句「一条读 arm64 端点的 recipe 会给 Intel Mac 递一个跑不了的 zip」。DuoUpdater 只跑在 arm64 上（`App/project.yml` 的 `ARCHS: arm64`），`VendorProbeSource` 按 `HostArch.current` 丢掉宿主跑不了的 recipe，所以 x86_64 那条在任何 DuoUpdater 宿主上都不会被用到，那句删了。「目前对两者回同一个版本」2026-09-14 复测两站仍成立。recipe 注释的同一处更正见 [com-workbuddy-workbuddy-ai.md](com-workbuddy-workbuddy-ai.md) 的「历史与实测」。

## Changelog

| | URL | 状态 |
|---|---|---|
| 国内站 | https://www.codebuddy.cn/docs/workbuddy/Changelog | 200，与 5.3.14 同步 |

两个 URL 都是 app 自己链的（构建按 `isOverseas()` 分支）。**已做成原生结构化条目**
（`ChangelogRecipe`，两站各一条，共用同一个 `entryPattern`，2026-08-27）。

页面是 VitePress **服务端渲染**，条目形状：

```html
<h2 id="_5-3-14-…">5.3.14 版本发布 🚀（2026-08-17） <a class="header-anchor"…></a></h2>
<ul><li>新增 …</li><li>优化 …</li></ul>
```

两个坑写在 recipe 注释里，这里只点名：

1. **日期外面的括号是全角（）**，中英文两页都是。浏览器里看跟半角几乎没区别，
   用 `\(` 写的正则**两站都匹配不上**。
2. **版本与列表之间必须用 tempered dot**，不能用 `.*?`。惰性间隔在第一个 `</h2>`
   后面没跟列表时**仍会回溯**过去、绑到下一条 release 的列表上——于是一个
   "coming soon" 空标题会吞掉最新版的条目**连同它的标题**，笔记挂到错版本上、
   真条目直接消失。真实页面上实测：朴素正则把 `[5.3.14, 5.3.13]` 变成
   `[9.9.9, 5.3.13]`。

解析结果（2026-08-27 实测）：CN 站 58 条（最新 5.3.14，14 个条目）。国际站页面只有 2 条，
见[国际站文档](com-workbuddy-workbuddy-ai.md)的 Changelog 一节。

## 一键安装

- 状态：**支持**（检测 + 一键，两站均是）
- 格式：`.zip`（端点 JSON 的 `url` 字段；同路径下有同名 `.dmg`，但那是推断出来的，
  端点没声明，所以不用）
- 签名闸：Team `FN2V63AD2J`，两站同一个，与已装包一致 → `VendorInstaller` 放行
- **install 正则钉死各自的下载 host**（intl `codebuddy-1328495429.cos.accelerate.myqcloud.com`，
  CN `download.codebuddy.cn`）：两站的产物**路径完全相同**（`/workbuddy/saas/darwin-<arch>/`），
  host 是解析结果里唯一能说明"这包来自哪一站"的东西。不钉的话，一次改错 host 的编辑、
  或 vendor 把一站的 `/v2/update` 指到另一站 CDN，就会让一键把国际版悄悄换成国内版 ——
  而且下游一个都拦不住：同厂商、同 Team、真正的公证包，签名闸看不出来，
  `ChannelProofRegistry` 又只管非 stable。钉死之后同样的情况变成**响亮失败**
  （`installURLUnresolved`，夜扫 `duo verify` 会报）。守卫见 `noRecipeResolvesTheOtherSitesArtifact`
- `sha256hash` **故意不用**：那是 SHA-256 hex，而 `checksumPattern` 吃的是 base64
  SHA-512，接不上；由签名闸兜底

## 已知问题

- 只动 build 计数器的重新出包检测不到（见陷阱二）——已知代价，不是缺陷。
- x64 那两条 recipe 的产物没有下载挂载验证过，只验证了「存在 + 分架构命名」；
  跨架构不误取由单测守着（复验方法见下文「如何复验」）。

## 验证

```sh
swift run --package-path application-test channel-verify <WorkBuddy DMG>   # 两站真实 bundle 均 ✓
duo verify --only workbuddy                                                # 4 vendor probes ✓ 4 ⚠ 0 ✗ 0
```

实证记录见下文「如何复验」；
回归测试见 `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/WorkBuddyProbeRecipeTests.swift`
（从 registry 推导，12 条）。

## 建议下一步

无。两站的检测与一键都已接入并验证。若将来 vendor 的 changelog 页值得原生条目化，
再走 `/fragile-recipe WorkBuddy`（Changelog 路径）。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-08-27。

```sh
swift run --package-path application-test channel-verify <WorkBuddy DMG>
duo verify --only workbuddy      # 4 vendor probes ✓ 4  ⚠ 0  ✗ 0
```

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-workbuddy-workbuddy.swift — 国内站 ChangelogRecipe（没有日期的旧条目）

转引自 recipe 注释，未复测。整段原文；代码里只把「19 of」换成了「some of」。原句没写日期，引入它的提交是 `577ce43d`（2026-08-27）。

The heading text between version and date varies by era — "版本发布 🚀",
"Lanched 🚀" (the vendor's own typo), or nothing at all on the oldest
entries — so the pattern skips anything that is not a tag or a paren
rather than trying to enumerate the variants. The date group is optional
for the same reason: 19 of the CN page's older entries have no date.

### Recipes/com-workbuddy-workbuddy.swift — 国内站 ChangelogRecipe（`</h2>\s*<ul>` 相邻的代价）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（最旧的一批国内站条目用另一种标记所以解析不到，但 `maxEntries` 是 40、能解析的远不止 40，所以不花钱），「17 oldest」「newest 58」和 2026-08-27 对两页的核对搬到这里。

`</h2>\s*<ul>` adjacency is deliberate: it is what keeps a heading whose
notes are laid out some other way from swallowing the NEXT release's
list. It costs the 17 oldest CN entries (4.5.0–4.7.5, which use a
different markup), and that is free — `maxEntries` stops at 40 and the
newest 58 all parse. Verified against both live pages 2026-08-27: CN 58
entries, newest 5.3.14 with 14 items; intl 2 entries, newest 5.2.7.

复测 2026-09-14：见本节最后一组。

### Recipes/com-workbuddy-workbuddy.swift — 国内站 ChangelogRecipe（国际站页面本来就只有两条）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（国际站页面停在 5.2.7——`acknowledgedStaleEntry` 点名的就是它——而它自己的端点已经发了更新的版本，when checked 2026-08-27、2026-08-28、2026-09-14；国内站同一正则解出几十条），国际站的条数 2、端点版本 5.4.2 和国内站条数 58 搬到这里。

The intl page IS that short: it carries two entries and stops at 5.2.7
(2026-07-17) while its own endpoint ships 5.4.2. A future reader finding
"only 2 entries" has found the vendor's page, not a broken recipe — the
CN page, parsed by the identical pattern, returns 58.

### Recipes/com-workbuddy-workbuddy.swift — 国内站 ChangelogRecipe（国际站的 `acknowledgedStaleEntry`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（`duo verify` 拿 5.2.7 比更新的探测版本、判「recipe degraded」且永远清不掉；确认项点名 5.2.7 而不是关掉检查），5.4.2 和 2026-08-28 的复查搬到这里。

That is also why the intl recipe carries `acknowledgedStaleEntry`
(issue #88). `duo verify` reads 5.2.7 against a detected 5.4.2, calls it
a whole release behind, and files "recipe degraded" — a complaint that
can never clear, because there is nothing on our side to fix. Re-checked
live 2026-08-28: intl still 2 entries topping out at 5.2.7, CN still
parsing, newest 5.3.14 (2026-08-17). The acknowledgement names 5.2.7
rather than switching the check off, so the day the pattern slips to an
older section — or the vendor finally publishes — the sweep speaks up
again.

复测 2026-09-14（11:03 UTC，只读 GET，按 `ChangelogRecipeRegistry.workBuddyEntryPattern` 在 Python 里用 DOTALL 复算）：`www.workbuddy.cn/docs/workbuddy/Changelog` 164,156 B，89 个版本标题，其中 19 个没有括号日期，解析出 72 条，最新 5.5.6（2026-09-10），最旧解析到 4.8.0；`www.workbuddy.ai/docs/workbuddy/Changelog` 33,162 B，解析出 2 条，最新 5.2.7（2026-07-17），另一条 5.2.3。同时 `/v2/update?platform=workbuddy-darwin-{arm64,x64}&version=0.0.0`：国际站两个架构都回 `5.5.2.37849279`，国内站两个架构都回 `5.3.14.36279234`。

## 为什么国内站这一对没人发现（2026-09-18）

机制和改法见上面「陷阱一」的更正块。这里只补一条**给下次用的**观察。

证据本来就摆在这份文件里：上面 2026-09-14 那次复测，同一段话里同时记下了
「国内站 changelog 最新 5.5.6」和「国内站 `/v2/update?…&version=0.0.0` 回 5.3.14」
两个数字，没有人把它们放在一起看。`verify/baseline.json` 里也一样——
`changelog:com.workbuddy.workbuddy:-` 的 `lastGoodVersion` 是 `5.5.6`，
`vendor:com.workbuddy.workbuddy:stable:{arm64,x64}` 是 `5.3.14`，相隔几行。

**教训（比这个 app 本身更值得记）**：`duo verify` 的历史检查全都是「这一轮和上一轮比」，
没有任何一条是「同一个 app 的 probe 行和 changelog 行互相比」。一条 recipe 只要**稳定地**
读错，就不会触发任何闸——这次是靠厂商删了个文件才撞出来的。
