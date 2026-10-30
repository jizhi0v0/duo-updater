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

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **nightly** | — | ✗（cask `auto_updates`） | — | ✗（无 asset） | — | ✓ |

当前生效源：**Electron**（`ElectronManifestSource`）。没有 recipe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| nightly | `com.deepseek.dsh` | 单一渠道 | — | bundle 自己的 `app-update.yml` | ✓ |

`app-update.yml` 写 `channel: nightly`，读的是 `nightly-mac.yml`；同目录的 `latest-mac.yml`
是 404（2026-10-30），没有第二条轨。

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

- 未接。feed 不带 `releaseNotes`；上游 GitHub Releases 只有 tag、正文为空，没有可结构的发布说明。

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
```

## 建议下一步

- 跑一次真机端到端（`0.2.1-rc.3` → `0.2.1-rc.5`，`electron-verify com.deepseek.dsh --install`），
  顺带覆盖副本正在运行时的退出/重启路径。
