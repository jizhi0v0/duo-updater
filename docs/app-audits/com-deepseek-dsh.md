# DeepSeek Harness（官方桌面端）

审计 2026-10-30。

> 不要与 [DSH Desktop / DSH NEXT](ai-deepseek-dsh-desktop.md) 混：那两条是社区
> `anywhere-labs/dsh-desktop` 的 GitHub Releases 构建（bundle id `ai.deepseek.dsh.desktop`
> / `…desktop.next`，Team `UM3Z9G5DNH`）。这份是 DeepSeek 自己的 0.2.x Harness 桌面客户端，
> bundle id、Team、版本线和分发都不同，可以并列安装。

## 基本信息

- Bundle ID: `com.deepseek.dsh`
- App 名: `DeepSeek Harness.app`
- Team ID: `NAN929V4UM` — Developer ID Application: Hangzhou DeepSeek Artificial Intelligence
  Co., Ltd（已公证）
- 观测版本: `0.2.1-rc.3`（short == build），`LSMinimumSystemVersion` 13.0，`lipo -archs` = `arm64`
- 分发: 官网 <https://www.deepseek.com/harness/>；Homebrew cask `deepseek-harness`
  （`auto_updates: true`，2026-10-30 的 cask API 版本 `0.2.1-rc.5`，URL 就是下面 feed 里的同一个 zip）
- 自更新机制: **electron-updater**（`Squirrel.framework` + `Electron Framework.framework`），
  bundle 自带 `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://download.deepseek.com/dsh-desk/feeds/mac-arm64/
  channel: nightly
  updaterCacheDirName: '@deepseek-aidsh-desktop-updater'
  ```

- Sparkle: 没有 `SUFeedURL`（包里是 Squirrel，不是 Sparkle）
- 开源: 上游 DSH 在 <https://github.com/deepseek-ai/deepseek-harness>；但它的 Releases 只有 tag
  （`dsh-v0.2.1-rc.5` 等，全部 prerelease、**没有任何 asset**，2026-10-30 实测；2026-11-03 复测
  `dsh-v0.2.2-alpha.3` 同样无 asset），桌面 app 的二进制只从厂商自己的域名下发——feed 的 zip，
  以及版本化路径上的 DMG（见「一键安装」）。所以 GitHub 规则不是这条的安装来源；GitHub 只贡献
  版本号（atom feed）和正文（Releases API）。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron | Changelog |
|---|---|---|---|---|---|---|---|
| **nightly**（含 `-rc.N` / 转正版） | — | ✗（cask `auto_updates`） | — | ✗（无 asset） | — | ✓ | ✓ |
| **alpha** | — | ✗（cask 只发 feed 那个 zip） | — | ✗（无 asset） | ✓ 一键 | — | ✓ |

当前生效源：stable/`-rc.N` 装机走 **Electron**（`ElectronManifestSource`）检测 + 一键；`-alpha.N`
装机走 **VendorProbe**（读上游 Releases 的 atom feed 拿版本，再用版本拼厂商的版本化 DMG）。
两轨的说明各走各的 `ChangelogRecipe`（`.gitHubReleases`，读上游仓库的 Releases 正文）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| nightly（`-rc.N` / 转正版） | `com.deepseek.dsh` | 共享 bundle id | `app-update.yml` 的 `channel: nightly` | Electron 源读 bundle 自己的配置 | ✓ |
| alpha | `com.deepseek.dsh` | 共享 bundle id 和 Team | 版本串 `-alpha.N` | `ReleaseChannel.detect` 0.999 规则 + probe 的 `channel: .alpha` | ✓ |

**stable/`-rc.N` 轨**：`app-update.yml` 写 `channel: nightly`，读的是 `nightly-mac.yml`；同目录的
`latest-mac.yml` 是 404（2026-10-30；`alpha-` / `beta-` / `canary-` 三个同形状的名字 2026-11-02
复测也是 404；`feeds/alpha/mac-arm64/`、`feeds/mac-arm64-alpha/`、`bin/mac-arm64/alpha-mac.yml`、
`bin/mac-arm64/latest-mac.yml` 四个别的路径形状 2026-11-03 复测同样 404）。**厂商没有第二条 feed。**

**alpha 轨**：alpha 构建的 `app-update.yml` 和 stable 的一字不差（`channel: nightly`，从真包
`0.2.2-alpha.3` 的 DMG 里读出来的），所以 alpha 装机**没有**独立的渠道字段，唯一本地信号是
`CFBundleShortVersionString` 里的 `-alpha.N`。`ReleaseChannel.detect` 因此加了一条 bundle-id
限定的规则（0.999）：装 alpha 的拷贝读作 `.alpha`；stable 和 `-rc.N` 的拷贝继续读 `.stable`，
继续由 Electron 源回答。

⚠️ **没有**把 `alpha` 加进步骤 4 的通用版本词表：那会把所有版本号以 `-alpha.N` 结尾的 app 一起
改判，而其中大多数没有 `.alpha` recipe，会从「有更新」直接掉成 unknown。这条规则是为这个 bundle
id 写的，不是为那个形状写的。

⚠️ `.alpha` 只决定「谁回答」，不改 feed：厂商自己的更新器在 alpha 构建里也只看
`nightly-mac.yml`，而那条 feed 2026-11-03 发的是 `0.2.1-rc.5`（比装着的 alpha 旧），所以 app
自己永远不会把下一个 alpha 推给任何人。下一个 alpha 只以版本化 DMG 的形式出现——这就是 probe
的理由，见「更新检测」。

⚠️ stable/`-rc.N` 拷贝在 duo 里仍读作 `.stable`——`ReleaseChannel.detect` 的通用规则没有
`-rc.N`。它们照旧走 Electron 源；changelog recipe 标 `channel: .nightly` 却要靠查表的最后一步
命中，见下面「Changelog」。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://download.deepseek.com/dsh-desk/feeds/mac-arm64/nightly-mac.yml`（实际请求带
  `noCache` 查询串）
- 版本方案: manifest 的 `version` == 包的 short == build（`0.2.1-rc.5`）
- `releaseDate` 是完整 ISO8601（`2026-10-29T13:55:07.029Z`）
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）；用
  `electron-verify` 看它（见「如何复验」）
- **feed 用 YAML folded block scalar**: `url`、`sha512`、`path` 都写成 `>-` 加一行缩进内容。
  2026-10-30 之前 `ElectronManifest.parse` 把 `>-` 本身当值，地址解析成 `%3E-`、扩展名是空的，
  行于是退化成 detection-only（`duo check` 报 `route: manual`）。现在解析前先由
  `ElectronManifest.logicalLines` 把 block scalar 折回一行，同一份 manifest 报
  `route: in-place`、`canAutoInstall=true`

**alpha 轨的检测**（`VendorProbeRecipe`，`channel: .alpha`）：

- 端点: `https://github.com/deepseek-ai/deepseek-harness/releases.atom`（ATOM，不是 REST API：
  probe 每次检查都跑，不该占 GitHub 的 API 预算，也不需要 token）
- 版本: `<title>v<version></title>`，`selectHighest` 取最高版本。**必须按版本取，不能取第一条**：
  feed 按发布时间排，2026-11-03 的实际顺序是 `0.2.2-alpha.3`、`0.2.1-rc.5`、`0.2.2-alpha.2`…
  （`rc.5` 比 `alpha.2` 晚发布却版本更低）
- 版本集合是整条轨（`-alpha.N` / `-rc.N` / 纯版本号），`VersionComparator` 对三者的排序是
  alpha < rc < 纯版本号、`0.2.2-alpha.3` > `0.2.1-rc.5`，所以转正后的构建就是「更新的版本」
- **版本不等于能下**：厂商会给没打包的构建写正文（`0.2.2-alpha.2`、`0.2.1-alpha.5` 有正文、
  DMG 404），所以这条 recipe 开了 `selectsHighestPublishedBuild`：从最高版本往下 HEAD
  （`publishedWalkLimit` = 3 个候选），用第一个真正能下的。走查的三种回答分开处理：
  - `ok` → 就用这个版本；
  - `gone`（4xx）→ 说明「这个构建没打包」，往下一级走；
  - `transient`（5xx/429/连不上）→ 说明「厂商现在出问题」，**停下**：保留读到的版本、关掉一键、
    升 `installURLTransient`。不越过它是因为越过会 (a) 悄悄报一个更旧的构建，(b) 让后面某个 404
    把它改写成 `installURLNotFound`——一次故障被记成「厂商删了产物」。

  三个候选都是 `gone` 时同样保留版本、关掉一键，升 `installURLNotFound`——一行「没有 Update
  按钮」是缺按钮的 bug，一行 Update 点了 404 是我们的 bug
- 代价：这条 recipe 每次检查多 1 个 HEAD（最高版本已发布时）。没有做成默认行为，因为普通检查
  不该按 app 付这个请求（见 `ProbeWarning.installURLNotFound` 的注释）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 支持 blockmap） | 无 | 不适用 |
| 证据 | electron-updater | `nightly-mac.yml` 没有 `blockMapSize` / `differential` 字段（2026-10-30） | `DeltaApplier` 只吃 Sparkle binary delta |

## Changelog

- 源: `ChangelogRecipe`（`structuredFormat: .gitHubReleases`），读
  `api.github.com/repos/deepseek-ai/deepseek-harness/releases?per_page=40`
- 为什么不读 feed：`nightly-mac.yml` 没有 `releaseNotes`；上游 Releases 的正文就是厂商写的
  发布说明（中文在前、英文在后）
- 轨: 两条 recipe，一条一轨，靠 `channel` 精确分流：
  - `channel: .nightly` 收 `-rc.N` 和转正后的纯版本号（feed 那条轨；`nightly-mac.yml` 现在是
    `0.2.1-rc.5`）。stable/`-rc.N` 拷贝读作 `.stable`（见上），所以 `recipe(forBundleID:channel:)`
    走查表的最后一步 —— 它必须留在文件里**第一位**，否则 `.stable` 会先拿到 alpha 那条。
  - `channel: .alpha` 收整条 alpha 轨（`-alpha.N`、`-rc.N`、纯版本号），只有读作 `.alpha` 的
    拷贝按精确匹配拿到它。收整条而不是只收 alpha，是因为厂商同编号转正
    （`0.2.2-alpha.3` → `0.2.2-rc.N` → `0.2.2`）：只收 alpha 会让 alpha 装机的面板在转正那天
    冻在最后一个 alpha 上，而 feed 那条又被 probe 挡在后面。
- 渠道: `.nightly` 那条——`.gitHubReleases` 的 stable 过滤只收 `prerelease: false`，而这个仓库
  每条都是 prerelease；`.alpha` 那条则是 `.gitHubReleases` 的 prerelease 读取
- 加第二条 recipe 不会盖过第一条：两条的 `channel` 不同，选择器先做精确匹配
- 转正: rc 是同编号转正的（`0.2.1-rc.5` → `0.2.1`），`includesPromotedStable` 让 GitHub
  不再标 prerelease 的那条继续出现
- 双语: 同一条变更会出现两次（中文、英文各一次）。厂商没有按语言拆开的正文，
  `GitHubMarkdownParser.firstLanguage` 只认 `<!-- lang:xx -->` 标记，这些正文没有
- 日期: 取 `published_at`，按本地日（`isoDay`）
- `duo verify --only deepseek` 读的是生产链（API 走 `gh auth token`）。注意它没有
  `:nightly` 的版本可对，所以滞后检查在这条上不跑——抓取和解析仍然会被检查

## 一键安装

- 状态: **支持**。`ElectronManifestSource` 从 `files:` 里选 arm64 zip（带 sha512 + size），走
  `VendorInstaller` 的 zip 路线 + Team ID 闸
- 产物: `deepseek-harness-0.2.1-rc.5-mac-arm64.zip`，347,767,892 B；zip 顶层只有一个
  `DeepSeek Harness.app`，没有安装器壳
- 包验（2026-10-30，`0.2.1-rc.5` 解包）: `com.deepseek.dsh` / `0.2.1-rc.5`（short == build），
  Team `NAN929V4UM`（与观测的 `0.2.1-rc.3` 相同），`spctl accepted / Notarized Developer ID`，
  `lipo -archs` = `arm64`，`LSMinimumSystemVersion` 13.0；sha512（base64）与 manifest 逐字一致
- **读的是**: 公开 feed；Homebrew cask 的 URL 指向同一个 zip，而 cask 是 `auto_updates`，
  `HomebrewCaskSource` 本来也不会应答它 —— 装的正是厂商自己更新器会装的那个构建
- **alpha 轨**: `VendorProbeRecipe`（`channel: .alpha`）读上游 Releases 的 ATOM feed
  （`…/releases.atom`，不是 REST API——probe 每次检查都要跑，不该花 GitHub 的 API 预算），用
  `<title>v<version></title>` 取版本、`selectHighest` 挑最高版本（feed 按**发布时间**排，不是按
  版本排：2026-11-03 的顺序是 `alpha.3`、`rc.5`、`alpha.2`），再用 `.versionTemplate` 拼
  `…/bin/mac-arm64/deepseek-harness-<version>-mac-arm64.dmg`。实测 `0.2.2-alpha.3` 的 DMG
  200 / 268,883,910 B，和本机 Downloads 里那个同尺寸；`0.2.1-rc.5`、`rc.4`、`rc.3` 的 DMG
  也都在（200）。
- **alpha 的一键与「没打包的构建」**: 见「更新检测」最后两条。probe 不会把没打包的版本报成可更新；
  三个候选都没打包时这一轮是 detection-only（有版本、没有 Update 按钮），并在 `duo verify` 里
  留下 `installURLNotFound`。
- 端到端: 未跑。`electron-verify com.deepseek.dsh` 走生产代码给出
  `resolved 0.2.1-rc.5 → UPDATE`、`artifact … kind=zip sha512=yes`、`canAutoInstall=true
  route=vendor`、`no findings`；`duo install --dry-run` 把它列进 `[vendor]`。真实的
  `--install` 会替换正在使用的副本，留给下一轮单独跑

## 已知问题

- feed 是厂商自己的 emitter（folded block scalar），不是 electron-builder 原始的平铺 YAML。
  以后再改格式，先看 `ElectronManifest.logicalLines` 够不够，不要直接把 `>-` 当成值。
- 只有 `mac-arm64` feed，没有 Intel 构建。DuoUpdater 自身 arm64-only，所以不构成缺口。
- 包很大：zip 约 332 MiB，解包约 990 MB。下载和备份都慢，`InstallBatchOrdering` 会让它在
  Update All 里排到小更新后面。
- 上游 GitHub Releases 没有 asset —— 不要为省事加一条 `GitHubReleaseRule`，那条规则只会
  检到版本、拿不到可安装的包。
- cask 是 `auto_updates: true`，brew 装的副本同样由 Electron 源应答，不是 Homebrew 源。
- changelog 的 `tagPattern` 收的是 `-rc.N` 和纯版本号：厂商把夜间轨换成别的后缀（`-nightly.N`、
  `-beta.N`）时它会一条都收不到。`duo verify` 会以"no entries"报出来，不会静默——那时要改 pattern。
  alpha 正文现在由第二条 recipe 承担，不要再把它塞回这条。
- alpha 的一键依赖厂商继续在版本化路径发 DMG。哪天连续三个版本都不发了，这一行会退成
  detection-only（`duo verify` 报 `installURLNotFound`），不会静默换包，也不会点下去 404。
- alpha 装机从此由 probe 回答（probe 排在 Electron 源前面）。probe 挂了（atom feed 变了、GitHub
  不通）那台机器的这一行是 unknown，**不会**回落到 feed——这是 channel 分流的代价，写在这里。
- 面板里同一条变更会出现两次（中文一次、英文一次）。这是厂商正文的形状，不是解析错误。

## 如何复验

```bash
# 1. manifest（折叠标量的原始形状也能一眼看出来）
curl -sS "https://download.deepseek.com/dsh-desk/feeds/mac-arm64/nightly-mac.yml?noCache=$RANDOM"

# 2. 生产链的判定：检测 + 产物 + 策略，不安装
duo check "DeepSeek Harness" --json          # route: in-place
swift run --package-path application-test electron-verify com.deepseek.dsh

# 3. 一键装的那个 zip：sha512 与 manifest 一致、Team 与已装的一致
openssl dgst -sha512 -binary deepseek-harness-<version>-mac-arm64.zip | base64
ditto -x -k deepseek-harness-<version>-mac-arm64.zip out
codesign -dv out/DeepSeek\ Harness.app 2>&1 | grep TeamIdentifier
spctl -a -vvv out/DeepSeek\ Harness.app

# 4. alpha 轨：atom feed 的最高版本 + 版本化 DMG
curl -sS https://github.com/deepseek-ai/deepseek-harness/releases.atom | grep -o '<title>v[^<]*' | head -3
curl -sSI https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-<version>-mac-arm64.dmg | head -3

# 5. changelog（生产链；API 用 gh 的 token）
make cli && duo verify --only com.deepseek.dsh
```

## 建议下一步

- 跑一次真机端到端（`0.2.1-rc.3` → `0.2.1-rc.5`，`electron-verify com.deepseek.dsh --install`），
  顺带覆盖副本正在运行时的退出/重启路径。

## 历史与实测

### 本地对抗审查后的修正（2026-11-03，codex review）

- 审查找到两条，都成立：
  1. **major**：probe 会报「有正文、没打包」的版本——按当时的设计，`0.2.2-alpha.2` 那种情况会
     解析出一个下载 404 的 URL，而 `duo verify` 的 HEAD 只在夜间扫描里跑，普通检查没有栅栏。
     修法：`VendorProbeRecipe.selectsHighestPublishedBuild`，从最高版本往下 HEAD（上限 3 个），
     取第一个能下的；都下不了就关掉一键并升 `installURLNotFound`。新增
     `VendorProbeRecipe.versions(in:pattern:)`（去重、按版本降序）与 `publishedWalkLimit`。
     第二轮审查又指出这一版把 `.transient` 当成 `.gone` 越过、并用后一个 404 覆盖前一个 503：
     已改成「`.ok` 选、`.gone` 继续、`.transient` 停下并保留版本 + 升 `installURLTransient`」，
     并用两个 stub 用例把「503 之后不再看更旧构建」「故障不被 404 改写」钉住。
  2. **minor**：channel proof 原来只认 `-alpha.N` 的产物，而 recipe 故意接受整条轨（转正后
     `-rc.N` / 纯版本号），所以转正那天 `duo verify` 会拿一个它自己支持的更新去判失败。修法：
     改成 `.recipeAnchor(#"deepseek-harness"#, in: ["url", "install"])`——渠道身份在
     「本仓库的 releases feed + 厂商自己的 `deepseek-harness…` 产物路径」，不在版本后缀里；
     版本后缀这条路在转正轨里无法既非空又不误伤稳定版。
- 修完的重跑：`swift test` 全绿（含新增 5 条 stub 驱动的走查用例：最高版未打包→降一级、
  最高版已打包→直取、全都没打包→detection-only + 警告、走查上限、versions 去重降序）。
- goldens 变动 141 个文件，每个 +1 行 `selectsHighestPublishedBuild = false`——新字段出现在
  每条 probe 的 dump 里，属于机械变动，不是行为变化。

### Recipes/com-deepseek-dsh.swift — alpha 轨（2026-11-03）

- 触发：本机装着 `0.2.2-alpha.3`（从厂商版本化路径的 DMG 装的，Team `NAN929V4UM`、已公证），
  而这个版本比 feed 的 `0.2.1-rc.5` 新——原来的实现把它当 `.stable`，只给它看 feed 那条轨的说明
  「你没有更新」，alpha 本身在面板里根本不存在。
- 三条事实决定了接法，逐条实测：
  1. alpha 构建的 `app-update.yml` 和 stable 一样是 `channel: nightly`（挂 DMG 读的），
     所以装机侧只有版本号能区分——`ReleaseChannel.detect` 加了 0.999 的 bundle-id 限定规则。
  2. `alpha-mac.yml` 及另外四种路径形状都是 404（2026-11-03），厂商没有 alpha feed，
     所以版本只能从上游 Releases 读；ATOM 比 REST 便宜且不需 token。
  3. 版本化 DMG 存在：`0.2.2-alpha.3` 200 / 268,883,910 B；`0.2.1-rc.5`/`rc.4`/`rc.3` 也 200；
     但 `0.2.2-alpha.2` 和 `0.2.1-alpha.5` 是 404——**alpha 不是每个 tag 都发二进制**。
- 落地：`probes:` 加一条 `channel: .alpha` 的 `VendorProbeRecipe`（atom + `selectHighest` +
  `.versionTemplate` DMG）、`changelogs:` 加一条 `channel: .alpha` 的 `ChangelogRecipe`（整条轨），
  并把 channel proof 注册成 `.artifact`（解析出的 URL 必须带 `-alpha.N`，否则 proof 失败）。
- 没有做的事：没有把 `alpha` 加进 `versionTailChannelWords`（影响面是整个注册表）；没有给
  stable 那条 recipe 加 alpha 正文（channel 分流后它不需要）。
- 未跑：`make install` 之后面板里的观感；alpha 装机的真机一键（本机没有下一个 alpha 可升）。

### Recipes/com-deepseek-dsh.swift — changelog（2026-11-02）

- 2026-10-30 的审计写的是「无 changelog：feed 不带 notes，上游 GitHub Releases 无 asset」。前半句
  仍成立（`nightly-mac.yml` 依旧没有 `releaseNotes`）；后半句把「没有 asset」读成了「没有正文」，
  是错的：`releases?per_page=100` 返回 35 条发布，全部 `prerelease: true`，每条都有正文
  （`0.2.1-rc.5` 418 B，`0.2.2-alpha.2` 24,804 B），中文在前、英文在后。
- 两条轨并行：`0.2.2-alpha.2`（2026-10-28）排在 `0.2.1-rc.5`（2026-10-30）之上，而 feed 只发后者；
  `alpha-` / `beta-` / `canary-` / `latest-` 四个同目录 feed 名字都是 404（2026-11-02 复测），
  所以桌面端只有一条轨。
- 按 recipe 解码（`tagPattern` = `-rc.N` 或纯版本号、`channel: .nightly`、
  `includesPromotedStable: true`）：16 条，`0.2.1-rc.5` → `0.1.0-rc.7`，共 866 条 item（中英各半）；
  `0.2.1-rc.5` 2 条、`0.2.1-rc.3` 6 条、`0.2.1-rc.1` 约 200 条。
- 现成的列表里没有纯版本号的发布，「转正后仍收」用构造的数组钉在
  `DeepSeekHarnessKeepsAGraduatedRelease` 上，不是厂商字节。
- 未跑：`make install` 之后在面板里的观感；`duo verify` 见「如何复验」第 4 步。
