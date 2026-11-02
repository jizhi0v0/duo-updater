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
  （`dsh-v0.2.1-rc.5` 等，全部 prerelease、**没有任何 asset**，2026-10-30 实测），桌面 app 的二进制
  只从厂商 feed 下发。所以 GitHub 规则不是这条的安装来源。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron | Changelog |
|---|---|---|---|---|---|---|---|
| **nightly** | — | ✗（cask `auto_updates`） | — | ✗（无 asset） | — | ✓ | ✓ |

当前生效源：**Electron**（`ElectronManifestSource`）检测 + 一键；说明走 `ChangelogRecipe`
（`.gitHubReleases`，读上游仓库的 Releases 正文）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| nightly | `com.deepseek.dsh` | 单一渠道 | — | bundle 自己的 `app-update.yml` | ✓ |

`app-update.yml` 写 `channel: nightly`，读的是 `nightly-mac.yml`；同目录的 `latest-mac.yml`
是 404（2026-10-30；`alpha-` / `beta-` / `canary-` 三个同形状的名字 2026-11-02 复测也是 404），
没有第二条轨。

⚠️ 这是**厂商 feed 的渠道名**，不是 `ReleaseChannel.detect` 的判定：bundle 的
`0.2.1-rc.5` 不匹配任何版本规则，名字/文件名的规则也都不命中，所以这份拷贝在 duo 里读作
`.stable`。装着的就是 nightly 轨的构建这一点没变——Electron 源本来就读 bundle 自己的
`app-update.yml`。changelog recipe 因此标 `channel: .nightly` 却要靠查表的最后一步命中，
见下面「Changelog」。

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
- 轨: feed 只发 `-rc.N`（`nightly-mac.yml` 现在是 `0.2.1-rc.5`）。同一份 Releases 里并排跑着
  `-alpha.N`（`0.2.2-alpha.2` 比 feed 的版本还新，但桌面端拿不到），所以 `tagPattern` 只收
  `-rc.N` 和转正后的纯版本号
- 渠道: recipe 标 `channel: .nightly`——`.gitHubReleases` 的 stable 过滤只收
  `prerelease: false`，而这个仓库每条都是 prerelease。这份拷贝读作 `.stable`（见上），
  所以 `recipe(forBundleID:channel:)` 走到最后一步；**再给这个 bundle id 加第二条 recipe 会盖过它**
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
  `-beta.N`）时它会一条都收不到。`duo verify` 会以"no entries"报出来，不会静默——那时要改 pattern，
  不要删掉过滤去收全部 prerelease，那会把装机拿不到的 alpha 轨放进面板。
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

# 4. changelog（生产链；API 用 gh 的 token）
make cli && duo verify --only com.deepseek.dsh
```

## 建议下一步

- 跑一次真机端到端（`0.2.1-rc.3` → `0.2.1-rc.5`，`electron-verify com.deepseek.dsh --install`），
  顺带覆盖副本正在运行时的退出/重启路径。

## 历史与实测

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
