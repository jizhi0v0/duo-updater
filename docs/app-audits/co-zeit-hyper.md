# Hyper

## 基本信息
- App: Hyper — Electron 写的终端（vercel/hyper，MIT）
- Bundle ID: `co.zeit.hyper`（stable 与 canary 共用；3.0.2、3.4.0、3.4.1、4.0.0-canary.5 四个真包一致）
- 仓库: `vercel/hyper`（默认分支 `canary`，未归档；最后一个 release 是 2023-07-13 的 v4.0.0-canary.5，最后一个 stable 是 2023-01-08 的 v3.4.1）
- Team ID: `JW6Y669B67`（Developer ID Application: Vercel, Inc）。3.4.1、3.4.0、3.0.2、4.0.0-canary.5 都是这个 Team，`spctl` 都是 `Notarized Developer ID`
- 观测版本: 3.4.1；上一版 3.4.0；观测日期: 2026-10-22
- 自更新机制: Electron 自带的 `autoUpdater`（Squirrel.Mac，bundle 里有 `Squirrel.framework`/`ShipIt`），feed 是 `https://releases.hyper.is/update/darwin_arm64/<version>`（canary 用 `releases-canary.hyper.is`）。settled from source: `app/updater.ts` @ `v3.4.1`。**不是** update.electronjs.org，也不是 electron-builder 的 electron-updater
- 分发: GitHub Releases；Homebrew `hyper`（3.4.1）和 `hyper@canary`（4.0.0-canary.5），两个 cask 都 `auto_updates true`；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | — (auto_updates) | — | ✓ | — |
| **canary**   | —       | — (auto_updates) | — | ○（要改 `ReleaseChannel.detect`，见下） | — |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 对 3.4.0 dmg：`review electronProviderNeedsConstruction`——bundle 里有 electron-builder 生成的 `Contents/Resources/app-update.yml`（`owner: zeit, repo: hyper, provider: github`），但 app 不用它（`updater.ts` 只用 `electron.autoUpdater`），`ElectronManifestSource` 也不构造 github provider，所以不会被 generic 源覆盖，需要这条 rule。

## 覆盖清单
- **bundle id**: `co.zeit.hyper`，唯一的一次改名在 0.8.0 → 0.8.1 之间。0.8.0（2016-10-06）发的是 HyperTerm：`package.json` @ `0.8.0` 的 `build.appId` 是 `co.zeit.hyperterm`，`app/package.json` 的 `productName` 是 `HyperTerm`，资产是 `hyperterm-0.8.0-mac.zip` / `hyperterm-0.8.0.dmg`；0.8.1（2016-10-11）起 `appId` 是 `co.zeit.hyper`、资产是 `hyper-0.8.1-mac.zip`。最老真包 3.0.2（2019，x86_64）已经是 `co.zeit.hyper`。`co.zeit.hyperterm` 的副本没有覆盖，见「已知问题」。
- **发版轨道**: stable 和 canary。canary 的 tag 全部是 `…-canary.N`，GitHub 上 47 个 canary release 都标了 `prerelease: true`。app 里用 `~/.hyper.js` 的 `updateChannel: 'canary'` 切轨，canary 构建的 Info.plist 与 stable 只差版本号（`4.0.0-canary.5`）。见「Channel 详情」。
- **版本范围**: 3.0.2（2019）到 3.4.1 Team 都是 `JW6Y669B67`，安装闸不会拒旧副本。2.x 及更早没有下载核对（只影响 2019 年以前的副本，一键装的是最新 arm64 包，Team 闸比对的是装好的旧副本，如果 Team 不同会拒，不会误装）。
- **我们的主机下限**: DuoUpdater 只出 arm64。3.1.0 起有 arm64 资产；3.0.2 及更早只有 x86_64，这类副本也会被提示 3.4.1、一键装成 arm64（Team 相同）。
- **ad-hoc / digest**: 不适用（Developer ID）。这些 2023 年的资产 GitHub 没有 `digest`，只靠 Team 闸。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `co.zeit.hyper` | 共享 | 版本号纯数字 | `/releases/latest` | ✓ |
| canary  | `co.zeit.hyper` | 共享 | 版本号 `-canary.N`；`ReleaseChannel.detect` **不认** | — | ○，一键被 `OneClickGate` 挡住 |

- **canary 不会被当成 stable 的「最新版」**：stable rule 读 `/releases/latest`，GitHub 文档说它只返回最新的非 prerelease、非 draft release；实测 `gh api repos/vercel/hyper/releases/latest -q .tag_name` → `v3.4.1`。另外版本模式是锚定的，`v4.0.0-canary.6` 读不出（见「更新检测」）。
- **但 canary 副本会被当成 stable 副本**（推翻了「不会」的假设）：channel-verify 对 `Hyper-4.0.0-canary.5-mac-arm64.dmg` `--expect canary`：

  ```
  short version   4.0.0-canary.5
  inferred        stable
  detected channel  → stable
  ✗ MISMATCH: expected channel 'canary'
  winning source  GitHub
  latest          3.4.1
  status          up to date
  ```

  `ReleaseChannel.detect` 第 4 步只认 `-beta<N>`、`-beta.<N>`、`-preview.<N>` 以及 dash 分隔的 `nightly`/`snapshot`/`dev`，没有 `-canary.<N>`。后果：
  - 4.0.0-canary.N 比 3.4.1 大，显示 up to date（不会降级）。但 canary.1–4 的副本看不到 canary.5（我按 `VersionComparator` 推断，只实测了 canary.5）。
  - 早于 3.4.1 的 3.x canary（如 `3.4.0-canary.1`、`3.3.0-canary.2`）会被提示 stable 3.4.1。
  - **一键已用 `OneClickGate` 挡住**：`.installedVersion(pattern: ^[0-9]+(?:\.[0-9]+)+$)`，带 `-canary` 后缀的副本不给一键，stable 包不会换掉 canary 副本。正则在样本上的结果：`3.4.0 / 3.4.1 / 3.0.2 / 4.0.0` 放行，`4.0.0-canary.5 / 3.4.0-canary.1 / 3.0.1-canary.4` 不放行。
  - 要正式跟踪 canary，需要在 `ReleaseChannel.detect` 加 `-canary.<N>` 的形态（或给 `co.zeit.hyper` 加一个 bundle-id 限定的分支），再加一条 `usePrereleases` 的 canary rule。这是引擎改动，本 PR 没做。canary 自 2023-07 起没再发版，收益很小。

## 更新检测
- 源: `vercel/hyper` GitHub Releases，`/releases/latest`
- 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`。tag `v3.4.1` → `3.4.1`，等于 `CFBundleShortVersionString`。
- **「有 tag 读不出」的结论：放宽到 `v?`，全收。** 41 个非 prerelease tag 里，`^v…$` 只读出 13 个（v3.1.0 起）。读不出的 28 个是 `3.0.2, 3.0.0, 2.1.2 … 1.0.0, 0.8.3 … 0.8.0`，全是 2016–2019 年 Hyper 自己的 stable release，那时 tag 不带 `v`；不是别的产品，也不是别的轨道。`v?` 读出 41/41，prerelease 一个都没读出；`v4.0.0`、`v10.0` 读得出，`v4.0.0-canary.6`、`v4.0.0-rc.1`、`4.0.0-beta` 读不出。
  - 对用户可见的行为没有变化：stable rule 的检测和 changelog 都只读 `/releases/latest`（`GitHubReleasesSource.resolve`：「A single-`latest` fetch yields just one entry」）。list 回退时的页大小是 20，最早只到 v3.1.2（2021），碰不到 2019 年以前的 tag。放宽只是让模式对这个仓库的所有 stable tag 都成立。
- `CFBundleVersion`：3.x 与短版本相同；3.0.2 是 `3.0.2.2038`，不参与比较。

## 按架构 / 按 OS 分轨
- 每版有 `mac-arm64` 和 `mac-x64` 两种 dmg/zip，没有 universal。按规则选 arm64 dmg（`^Hyper-[0-9]+(?:\.[0-9]+)+-mac-arm64\.dmg$`）。`lipo` 结果：arm64 包 `archs=arm64`。
- `LSMinimumSystemVersion` 10.13（Electron 20.3.6）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Squirrel.Mac 只下整包 zip | `releases.hyper.is/update/darwin_arm64/3.4.0` 返回 `{"name":"v3.4.1","pub_date":"2023-01-08T00:56:10Z","url":".../Hyper-3.4.1-mac-arm64.zip","notes":…}`，只有一个整包 URL | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（启动 10 s 后检查，之后每 30 min） | 真机实测（2026-10-22）：3.4.0 启动约 23 s 后 ShipIt 已武装（`Detected this as an install request` 12:47:08），停放的是 3.4.1 | 不用：它停放的就是 GitHub 上的 `-mac-arm64.zip`，和我们装的同版本 |
| 证据 | `updater.ts`：`autoUpdater.on('update-downloaded', …)`，`setTimeout(checkForUpdates, 10s)` / `setInterval(…, 30m)`；Squirrel.Mac 停放在 `~/Library/Caches/co.zeit.hyper.ShipIt`（brew cask 的 zap 也列了这个目录），退出时 ShipIt 换包 | — | — |

- Hazel 风格的 feed 只回最新版，对已是最新的版本回 `204`（实测 `…/darwin_arm64/3.4.1` → HTTP 204），所以停放的永远是当时的 latest。服务器响应头 `server: Vercel`；路由形状和 JSON 字段与 Hazel 一致，「是 Hazel」是我的推断，服务器没说。

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，3.4.0 起）: `source structured: 1 entries; newest 3.4.1: 1 items, headings []; first items ["Use stable node-pty in https://github.co"]`
- 3.4.1 正文：标题行 `V3.4.1`、一段说明（「Based on some reports of errors with `node-pty`, reverting it to a stable version.」）、一张下载表格、`## What's Changed` 下一条列表、`**Full Changelog**` 链接。面板只留了那一条列表项（含 PR 链接），说明段被丢掉（`sectionProse` 把列表前的段落当引言），`What's Changed` 这个泛用小标题不保留（`headings []`），表格和 Full Changelog 不进面板。内容没有被压平成一段，但丢了那句说明。通用解析器的取舍，不改。
- 跟随 channel: 只有 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
  - 第一轮（不运行）: 3.4.0 → `duo check` `3.4.0 → 3.4.1 [GitHub, in-place]` → `duo install` `downloading… extracting verifyingCodeSignature installing done installed.` → 3.4.1、可执行文件 inode 变、`TeamIdentifier=JW6Y669B67`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted（Notarized Developer ID）、`diff -r` 与厂商 3.4.1 包相同
  - 第二轮（运行中）: 启动 3.4.0 后立即 `duo install`（12:46:45 → 12:47:17 完成，提示 `Still running the old code: Hyper`）。装的过程中 Squirrel 已停放 3.4.1，ShipIt 12:47:08 武装。`duo restart Hyper`：旧进程退出 → ShipIt 12:47:35 开始安装、12:47:41 把它停放的 3.4.1 换进 `/Applications/Hyper.app`（`Installation completed successfully`）；我们的重启 12:47:35 已拉起新进程，所以 **ShipIt 的换包发生在新进程运行期间**。两边都是 3.4.1（Hyper 的 Squirrel 停放的就是 latest），所以后写的一方无害：磁盘 3.4.1、签名有效，新进程正常运行、退出正常。这条路径上没有任何守卫在判断：`duo restart` 走 `AppRestarter.restart`（退出再拉起），不查 `RestartStandoff`；GUI 的 Restart 只对 Sparkle 暂存才去读（`result.app.hasSparkleUpdater`），Hyper 带的是 `Squirrel.framework`，`staged` 为 nil、`decide` 直接 `.proceed`。停放的若不是同一版本会怎样，这次没有造出来（Hazel feed 只回最新版）
- 格式: dmg（`hdiutil imageinfo`：UDZO），根目录 `Hyper.app` + `Applications` 软链。kind `.dmg`
- 嵌套: `Contents/Frameworks` 下 4 个 Electron helper（`Hyper Helper{, (GPU), (Plugin), (Renderer)}.app`，`LSUIElement`，随主进程起停）；没有 `Contents/Library/LoginItems`、LaunchAgent、XPC helper
- 签名: 3.4.0、3.4.1 都是 `TeamIdentifier=JW6Y669B67`，`codesign --verify` 通过，`spctl` Notarized Developer ID，hardened runtime
- 校验: 资产没有 GitHub `digest`，只靠 Team 闸
- 一键门控: canary 副本被 `OneClickGate` 挡住（见上）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）

### 启动副作用（读源码 `v3.4.1`，2026-10-22 真机核对）
- **把自己设成 `ssh://` 的默认处理程序**：`app/index.ts` 启动时 `config.defaultSSHApp && !app.isDefaultProtocolClient('ssh')` → `app.setAsDefaultProtocolClient('ssh')`，默认配置 `defaultSSHApp: true`（`app/config/config-default.js`）。真机核对：启动后 `NSWorkspace.urlForApplication(toOpen: ssh://…)` 指向 Hyper；LSHandlers 里仍没有 ssh 条目（是 Info.plist 声明的 scheme 生效，不是写入用户偏好）。把 app 移走并 `lsregister -u` 后回到系统默认 Terminal。另一种撤销：在 `~/.hyper.js` 里设 `defaultSSHApp: false` 再启动一次（源码走 `removeAsDefaultProtocolClient('ssh')`），或真机前先写好这个配置。
- **写配置和插件目录**：macOS 上配置目录是 home（`app/config/paths.ts`），首启生成 `~/.hyper.js`、`~/.hyper_plugins/`（插件用自带 yarn 联网安装）。另有 `~/Library/Application Support/Hyper`、`~/Library/Logs/Hyper` 等（brew zap 清单）。真机核对：首启即生成 `~/.hyper.js`、`~/.hyper_plugins/`、`~/Library/Application Support/Hyper`、`~/Library/Preferences/co.zeit.hyper.plist`、`~/Library/Caches/co.zeit.hyper`；`~/Library/Logs/Hyper` 没出现。
- **CLI 软链**：每次启动 `installCLI(false)` 静默尝试 `ln -s …/bin/hyper /usr/local/bin/hyper`。本机 `/usr/local/bin` 是 `root:wheel 755`，会 EACCES；`silent=true` 时不弹框、不发通知（`cli-install.ts`），只写日志。
- **自更新器会停放并在退出时换包**：启动 10 s 后 Squirrel 检查 `releases.hyper.is`，3.4.0 会下载 3.4.1 zip 到 `~/Library/Caches/co.zeit.hyper.ShipIt`，app 退出时 ShipIt 自己把 `/Applications/Hyper.app` 换成 3.4.1。这会和 duo install 抢同一个 bundle，第二轮要注意（见下）。
- 没有登录项、LaunchAgent、root helper、首启向导；不碰 `~/.claude`、`~/.agents`（源码里没有这些路径，未实测）。Electron 20 在 macOS 27 上能否正常启动未验证。

### 推荐真机步骤
1. 第一轮（不运行）: `ditto` 3.4.0 dmg 里的 `Hyper.app` 到 `/Applications` → `duo check` 应为 `3.4.0 → 3.4.1 [GitHub]` → `duo install` → 核对 3.4.1、inode 变、`codesign --verify --deep --strict`、Team `JW6Y669B67`、与厂商 3.4.1 包 `diff -r` 相同。不启动 app，就没有上面的副作用。
2. 第二轮（运行中）: 再放 3.4.0 并启动，**10 s 内**（Squirrel 首次检查前）做 `duo install`，然后 `duo restart Hyper`；之后确认 `~/Library/Caches/co.zeit.hyper.ShipIt` 是否出现，退出后磁盘仍是 3.4.1。想测「停放了一个比 latest 旧的版本」：Hazel feed 只回最新版，造不出来；最接近的是启动 3.4.0 等 Squirrel 停放 3.4.1（等于 latest）再 `duo install`，看 ShipIt 退出时会不会再换一次（同版本，应无害，未验证）。
3. 收尾：删 `~/.hyper.js`、`~/.hyper_plugins`、`~/Library/{Application Support,Logs,Caches}/…Hyper/co.zeit.hyper*`、`~/Library/Caches/co.zeit.hyper.ShipIt`；撤销 ssh 处理程序（见上）。

## 已知问题
- canary 副本被识别成 stable（见「Channel 详情」）；一键已挡，检测会对 3.x canary 提示 stable 3.4.1、对 4.0.0-canary.1–4 显示 up to date。
- changelog 丢了 3.4.1 的说明段。
- 厂商 2023 年后没有发版。
- `co.zeit.hyperterm`（HyperTerm 0.8.0 及更早的 0.x，2016，Electron 1.4，x86_64）的副本没有覆盖：唯一的 rule 绑 `bundleID: "co.zeit.hyper"`，`BundleIDMigration` 里也没有 `hyperterm`；Homebrew 源丢掉 `auto_updates` 的 cask（`HomebrewCaskSource`），所以这类副本的行不显示更新。不加 migration 的原因：`BundleIDMigration` 只能在同一个 Team 内迁移（`teamID` 字段，装机时 Team 闸先跑），而 0.8.0 的 Team 没核实：没有下载 0.8.0 的 zip 看签名，`.travis.yml` @ `0.8.0` 里也没有签名/证书步骤（`grep -ciE "csc|sign|cert"` 为 0，仅此一项，不能推出它没签名），Team 是否等于 `JW6Y669B67` 未验证。2016 年的包，影响面极小。它自带的更新器也已经指不到东西：`app/auto-updater.js` @ `0.8.0` 的 `FEED_URL` 是 `https://hyperterm-updates.now.sh/update/<platform>`，2026-10-22 请求 `…/update/osx/0.8.0` 先 308 到 `hyperterm-updates.vercel.app`，再回 404，所以这类副本自己也升不到 `co.zeit.hyper`。recipe 里「`3.0.2 … 0.8.0` 都是同一个 app 的 stable」按 bundle id 说不准确，对用户可见的行为没有影响（检测和 changelog 只读 `/releases/latest`）。

## 建议下一步
1. 如果 Hyper 再发 canary，再考虑 `ReleaseChannel.detect` 认 `-canary.<N>` + canary rule。

## 如何复验
```
gh api repos/vercel/hyper/releases/latest -q .tag_name                       # → v3.4.1
gh api 'repos/vercel/hyper/releases?per_page=100' --paginate -q '.[]|[.tag_name,.prerelease]|@tsv'
swift run --package-path application-test feed-discover Hyper-3.4.0-mac-arm64.dmg      # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Hyper-3.4.0-mac-arm64.dmg --expect stable   # → GitHub, UPDATE → 3.4.1
swift run --package-path application-test channel-verify Hyper-3.4.1-mac-arm64.dmg --expect stable   # → up to date
swift run --package-path application-test channel-verify Hyper-4.0.0-canary.5-mac-arm64.dmg --expect canary  # → MISMATCH (stable), up to date
curl -s https://releases.hyper.is/update/darwin_arm64/3.4.0                  # → v3.4.1 arm64 zip
```
