# WorkBuddy (Tencent)

审计 2026-08-27。一份文档覆盖两个 bundle id —— WorkBuddy 是**两个 app**，不是一个
app 的两个 channel。

## 基本信息

| | 国际站 | 国内站 |
|---|---|---|
| Bundle ID | `com.workbuddy.workbuddy-ai` | `com.workbuddy.workbuddy` |
| App 名 | WorkBuddy AI.app | WorkBuddy.app |
| URL scheme | `workbuddy-ai` | `workbuddy` |
| 官网 | https://www.workbuddy.ai | https://www.workbuddy.cn |
| 观测版本 | 5.4.2 | 5.3.14 |
| Team ID | `FN2V63AD2J` — Tencent Technology (Shanghai) Company Limited | 同左 |
| 自更新机制 | 自研（Electron + `electron.net.fetch`，非 electron-updater，无 `app-update.yml`，无 Sparkle） | 同左 |

两个包的 updater 代码**逐字节相同**；分流完全靠 build 时烤进 product config 的
`endpoint`（`getUpdateBaseUrl()` 就是读它）。因此**唯一**把安装引到自己那条轨道
上的东西是 bundle id —— 而 bundle id 正是 recipe 的查找键，两条轨道天然不可能串。

国际版另有 `TuringShield.bundle`（腾讯安全 SDK），国内版没有；这属于两站构建差异，
与更新检测无关。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable（国际站）** | — | — | — | — | ✓ 一键 |
| **stable（国内站）** | — | — | — | — | ✓ 一键 |

当前生效源：**VendorProbe**（前四条源全部不适用：无 `SUFeedURL`、无 cask、非 MAS、
无公开 GitHub 发布）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.workbuddy.workbuddy-ai` | 独立 | — | — | ✓ |
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
所以 recipe 的 URL 里把 `version=0.0.0` 钉死，才把它变成一个 latest 查询。

### 陷阱二：版本方案（幻影更新）

端点报四段 `5.4.2.36857725`，最后一段是 build 计数器，**在已装 bundle 里哪儿都
没有** —— `CFBundleShortVersionString` 和 `CFBundleVersion` 都是光秃秃的 `5.4.2`。
直接比原值等于 `36857725 > (无)`，是那种永远清不掉的幻影更新。

`versionIsBuild` 在这里是**错的解**：那个计数器也不是 app 的 `CFBundleVersion`。
正解是正则只捕前三段、第四段匹配后丢弃。代价要明说：**vendor 只动 build 计数器的
重新出包，我们看不见。** 第四段写成可选，是为了 vendor 哪天退回三段式时不会静默失配。

### 陷阱三：架构

端点两个架构都服务，且目前对两者回同一个版本 —— 但它给回的 `url` 是分架构的
（`/darwin-arm64/…` vs `/darwin-x64/…`）。一条读 arm64 端点的 recipe 会给 Intel Mac
递一个跑不了的 zip。所以每站注册**两条 recipe**，用 `hostRequirement` 分流
（Raycast v1/v2 的形状），任一台 Mac 上恰好一条合格；install 正则再各自钉死自己的
`darwin-<arch>` 路径，这样即便端点哪天开始无视 `platform` 参数，也解析不出另一架构
的产物。

## Changelog

| | URL | 状态 |
|---|---|---|
| 国际站 | https://www.workbuddy.ai/docs/workbuddy/Changelog | 200，但**落后于自己的轨道**（写作时最新条目 5.2.7，而发布版是 5.4.2） |
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

解析结果（2026-08-27 实测）：CN 站 58 条（最新 5.3.14，14 个条目），
国际站 2 条（最新 5.2.7）。国际站那个 2 是**厂商页面本身**如此，不是 recipe 坏了 ——
同一条正则在 CN 页跑出 58 条。`duo verify` 会为此报一条 ⚠（最新条目 5.2.7 落后于
探测到的 5.4.2），这条警告是真的，且厂商补上笔记后会自动消失。

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
- 国际站 changelog 页滞后于其发布轨道，vendor 侧问题，我们这边无解。
- x64 那两条 recipe 的产物没有下载挂载验证过，只验证了「存在 + 分架构命名」；
  跨架构不误取由单测守着（证据见下文「如何复验」。）。

## 验证

```sh
swift run --package-path application-test channel-verify <WorkBuddy DMG>   # 两站真实 bundle 均 ✓
duo verify --only workbuddy                                                # 4 vendor probes ✓ 4 ⚠ 0 ✗ 0
```

实证记录证据见下文「如何复验」。；
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
