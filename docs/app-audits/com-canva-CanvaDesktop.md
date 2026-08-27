# Canva

审计 2026-08-27。

## 基本信息

- Bundle ID: `com.canva.CanvaDesktop`
- App 名: `Canva.app`
- URL scheme: `canva`
- 官网 / 下载页: https://www.canva.com/download/
- 观测版本: `1.124.0`（`CFBundleVersion` = `3597652.392500792`）
- Team ID: `5HD2ARTBFS` — Canva Pty Ltd，`spctl` 判定 "Notarized Developer ID"
- 自更新机制: **electron-updater**（Electron 壳，`NSPrincipalClass = AtomApplication`，
  `Contents/Frameworks/` 下有 `Squirrel.framework` + `Electron Framework.framework`）

确实是套壳，这条是实测的不是推的：`Contents/MacOS/` 只有一个可执行 `Canva`，
业务逻辑在 `Resources/app.asar`（`Info.plist` 带 `ElectronAsarIntegrity`），而
`strings app.asar` 里同时有 `https://www.canva.com`、`https://www.canva.com/_online`
和 `BrowserWindow` / `loadURL` / `webContents` —— 即它开一个窗口去加载 canva.com。

不过对更新检测来说，有用的推论只有一条：它走 electron-builder 那套 manifest，
端点不用猜。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | — | ✗ | — | — | ✓ 一键 |

当前生效源：**VendorProbe**。其余四条源为什么都不答：

- **Sparkle** — bundle 里没有 `SUFeedURL`（也没有 `SUEnableAutomaticChecks`）。
- **Homebrew** — cask `canva` 存在，但是 `auto_updates true`，`HomebrewCaskSource`
  按设计直接 `return nil`。而且它确实是滞后的：审计当天 cask 停在 `1.123.1`，
  厂商 feed 已经是 `1.124.0`。
- **MAS** — `itunes.apple.com/lookup?bundleId=com.canva.CanvaDesktop&entity=macSoftware`
  返回 `resultCount: 0`。
- **GitHub** — 没有公开发布仓库。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.canva.CanvaDesktop` | 独立 | — | — | ✓ |
| beta | 无独立 bundle id | — | — | — | ✗ 废弃轨道，未接入 |

**beta 轨道已经废弃，故意不接。** `https://desktop-release.canva.com/beta-mac.yml`
仍然应答 200，但内容是 `1.98.0-beta`、`releaseDate: 2024-11-12`，而 stable 当天是
`1.124.0` / `2026-08-25`。app 侧也没有任何 channel 偏好键或独立 bundle id 能把一台机器
判进 beta。`alpha-mac.yml` / `arm64-mac.yml` / `latest-mac-arm64.yml` 全部 403。

这条废弃轨道是 recipe 里所有 pattern 都以「数字和点」结尾的原因，见下。

## 更新检测

端点不是猜出来的，两处独立佐证：

1. app 自带的 `Contents/Resources/app-update.yml`：

   ```yaml
   provider: generic
   url: https://desktop-release.canva.com
   useMultipleRangeRequest: false
   updaterCacheDirName: canva-updater
   ```

2. Homebrew cask 的 `livecheck` 读同一份 manifest，`strategy :electron_builder`。

recipe 落在 `https://desktop-release.canva.com/latest-mac.yml`：

```yaml
version: 1.124.0
files:
  - url: Canva-1.124.0-universal-mac.zip
    sha512: rf69D6q9…
    size: 220713510
  - url: Canva-1.124.0-universal.dmg
    sha512: XfyF0nxk…
    size: 229528957
  …（dmg 条目厂商重复列了三遍）
path: Canva-1.124.0-universal-mac.zip
sha512: rf69D6q9…
releaseDate: '2026-08-25T02:56:23.561Z'
```

- **版本方案对齐**：feed 的 `version` = `1.124.0` = 装机 `CFBundleShortVersionString`。
  `CFBundleVersion`（`3597652.392500792`）在 feed 里根本不出现，所以**不是**
  `versionIsBuild`。
- **pattern 末尾的 `\s*$` 是承重的**：万一 `-beta` 版本被推进 stable feed，
  `(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$` 会**一个都不匹配** → 降级 unknown，
  而不是截出 `1.98.0` 把预发当正式版报（那还会相对已装的 `1.124.0` 读成降级并永久卡住）。
- **`releaseDate`** 走 `publishedAtPattern`，单引号 ISO8601 带毫秒，`ReleaseDate` 能解析，
  于是 Release Log 能给 Canva 打精确时间而不是 `≈` 窗口。

生产验证（`duo verify --only canva`，2026-08-27）：

```
vendor probe  ✓ 1  ⚠ 0  ✗ 0  ~ 0  - 0
```

report 里 `"version": "1.124.0"`、`"warnings": []` —— 空 warnings 同时说明
`installURLUnresolved` 和 `checksumPatternNoMatch` 都没触发，即一键的 URL 和 sha512
都在生产路径上解出来了。

`duo check` 全链（真实已装副本）：

```
source: Vendor   installedVersion: 1.124.0   latestVersion: 1.124.0   status: up-to-date
```

## Changelog

**没有接。** Canva 不发布桌面端的 release notes：

- canva.dev 上那几份 changelog 是 Apps SDK / Connect API / Print Partnerships 的，
  是另一个产品，指过去等于给用户看错东西。
- www.canva.com 各路 `/help/whats-new/`、`/newsroom/` 对非浏览器一律 403，浏览器访问
  落到 Cloudflare 交互式验证页，无法确认背后是不是一份 notes 页。

所以 `changelogURL` 留空（UI 显示 "no release notes"），`downloadURL` 指向
`https://www.canva.com/download/`（curl 200，未被 challenge 拦）。

## 一键安装

- 状态: **已启用**，`kind: .dmg`。
- 产物: `Canva-1.124.0-universal.dmg`，由 feed 里的文件名相对
  `https://desktop-release.canva.com/` 解析而来 —— 与版本读自同一台主机、同一份响应。
- **为什么 `.dmg` 而不是 `.pkg`**：挂载真实 dmg 后里面只有 `Canva.app` 和
  `Applications` 软链，没有 pkg、没有 `LaunchDaemons` / `LaunchAgents` /
  `PrivilegedHelperTools` / 系统扩展，`Contents/MacOS/` 只有一个可执行。
  唯一值得怀疑的是 cask `zap` 里列的
  `~/Library/LaunchAgents/com.canva.availability-check-agent.plist` —— 它既不在 dmg 里，
  也不在这台跑过 Canva 的机器上，所以无论是谁写的，反正安装器不写它。换句话说
  「换 bundle」就是完整的更新。
- **checksum 闸已武装**：feed 公布的 base64 sha512 与实际下发的 dmg 字节**完全一致**
  （本机 `shasum -a 512` 后 base64 == feed 值）。这点和 Signal 相反 —— Signal 的
  feed hash 早于自家 stapling，对不上，所以那条 recipe 故意不设 checksum。
- 强制闸（`VendorInstaller`）：Developer ID 签名 + Team `5HD2ARTBFS` + bundle id 一致。

## 已知问题

- feed 把 dmg 条目重复列了三遍（内容完全相同）。first-match 取第一条，无歧义，但
  如果厂商哪天让这三条不再相同，就得改成 entry-scoped 解析。
- mac zip（`Canva-1.124.0-universal-mac.zip`）在 feed 里排在 dmg **前面**，且它的
  sha512 还在文档末尾又出现一次。artifact 与 checksum 两个 pattern 都必须锚到
  `.dmg` 那条，否则会拿 zip 的摘要去校验 dmg 字节，每次安装都会中止。
- Canva 是 Squirrel 自更新 app，所以 `UpdatePolicy.defersToSelfUpdater` 在
  `vendorInstallPolicy == .deferWhenRunning` 且进程在跑时会让位给它自己的更新器。
  这是既有行为，与本 recipe 无关。

## 建议下一步

1. 若 Canva 之后启用 beta 轨道（独立 bundle id 或 app 内 channel 开关），按
   `ChannelProofRegistry` 的要求补 proof 再加 recipe，不要照抄 stable 这条。
2. 若哪天出现可核实的桌面端 release notes 页，补 `changelogURL`。
