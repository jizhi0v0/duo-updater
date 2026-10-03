# Ducoro

审计 2026-10-04。

## 基本信息

- Bundle ID: `ai.ducoro.desktop`
- App 名: `Ducoro.app`
- Team ID: `6YU2PK44KX` — Developer ID Application: Songtao Xiang（已公证，staple）
- 观测版本: `2026.1002.354`（short == build），`LSMinimumSystemVersion` 15.0，`lipo -archs` = `arm64`
- 分发: 官网 `ducoro.ai/download/`。下载页读 `https://static.ducoro.ai/desktop/release.json`，
  只挑 `Ducoro-<version>-arm64.dmg`（页面标注 "Apple silicon only"）
- 自更新机制: **electron-updater**（generic provider），bundle 自带 `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://static.ducoro.ai/desktop
  updaterCacheDirName: '@ducoroelectron-updater'
  ```

  没有 `channel:` 一行，所以读默认的 `latest-mac.yml`。主进程里调的是
  `autoUpdater.setFeedURL({provider:"generic", url})`，没设 `channel`，`autoInstallOnAppQuit=false`。
- Homebrew: 无 cask（`formulae.brew.sh/api/cask/ducoro.json` → 404，2026-10-04）
- Sparkle: 没有 `SUFeedURL`
- 开源: 不是。`github.com/ducoro` 只公开了 `plugins`（skill 目录）和 `motion-studio`（宣传片源码），
  app 本身不在里面

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** | — | — | — | — | — | ✓ |

当前生效源：**Electron**（`ElectronManifestSource`）。不需要 VendorProbe recipe，也没有 changelog recipe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `ai.ducoro.desktop` | 单一渠道 | — | — | ✓ |

`release.json` 里写着 `"channel": "alpha"`，下载页的解析器只接受 `alpha` / `stable` 两个值。这是
**产品成熟度标签，不是另一条更新轨**：app 自己的 updater 不设 channel，只读 `latest-mac.yml`；
`alpha-mac.yml`、`stable-mac.yml` 都是 404（2026-10-04）。官网前端打包里的
`VITE_DUCORO_RELEASE_CHANNEL` 是 `"stable"`，说的是网页，跟桌面 app 无关。
将来真分出 `stable-mac.yml` 时，bundle 的 `app-update.yml` 会多出 `channel:`，通用源会跟着读。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://static.ducoro.ai/desktop/latest-mac.yml`（实际请求带 `noCache` 查询串；带和不带
  返回同一个版本）。Cloudflare 前置；同目录的 `release.json` 响应头是 `cache-control: no-store`
- 版本方案: 看着是日历版本 `YYYY.MDD.N`。官网 JS 校验的正则是 `^\d{4}\.\d{3,4}\.\d{1,4}$`，
  中段 3–4 位，`1002` 对上发版日 10 月 2 日（不补零的话 9 月就是 3 位的 `9xx`）。按数字逐段比时，
  年内与跨年都单调递增，`VersionComparator` 没问题。只见过 `2026.1002.354` 这一版，规则是推断的。
  manifest 的 `version` == 包的 short == build
- `releaseDate` 是完整 ISO8601（`2026-10-02T04:19:24.787Z`）
- 按 OS 分轨: 没有。manifest 不带 `minimumSystemVersion` / `maximumSystemVersion` 之类的字段；
  OS 下限只在包里（`LSMinimumSystemVersion` 15.0）
- 读的是哪一份: manifest 只有一个版本，没有 `stagingPercentage`，就是 app 自己 updater 读的那份
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 不能 |
| 证据 | 主进程打包了 electron-updater 的 `FileWithEmbeddedBlockMapDifferentialDownloader` | `Ducoro-2026.1002.354-arm64-mac.zip.blockmap`（189,570 字节）和 `.dmg.blockmap`（189,272 字节）都回 200（2026-10-04） | `DeltaApplier` 只吃 Sparkle binary delta；blockmap 差分下载是另一套机制 |

- 格式: electron-builder blockmap（按块差分下载，不是二进制补丁）
- 阻塞项: 没有消费 blockmap 的机制。全量 zip 约 180 MB

## Changelog

- 来源: 无结构化来源
- 官网 `https://ducoro.ai/whats-new/` 是服务端渲染的 HTML，每条 `<article>` 有
  `<time dateTime="2026-10-01">`、一个 `<h2>` 标题和若干 `<h3>`+`<p>` 小节，**但全页没有一个版本号**
  （`2026\.\d{3,4}\.\d+` 匹配 0 次）。`ChangelogRecipe` 的 `entryPattern` 必须捕获 `version`，这一页给不出来
- 也不能拿日期去对版本：`2026.1002.354` 的版本号写的是 10 月 2 日，`releaseDate` 是 UTC 10-02 04:19，
  而最新一条说明标的是 October 1, 2026。两边差一天，换算规则（时区？发版日还是写稿日？）厂商没写，
  猜一个会把说明挂到错的版本上
- manifest 不带 `releaseNotes`
- `channel-verify` 的 `changelog pane` 行: `none — the pane says there are no release notes`
  （注意 channel-verify 的源链里没有 Electron 源，见「已知问题」；Electron 源本身也不带说明，结论相同）
- 跟随 channel: 不适用（单轨）
- Recipe 状态: 不需要。厂商在条目里写上版本号时再加

## 一键安装

- 状态: 由 `ElectronManifestSource` 提供。它从 `files:` 里选出 `Ducoro-2026.1002.354-arm64-mac.zip`
  （带 sha512 + size），走 `VendorInstaller` 的 zip 路线 + Team ID 闸
- 端到端: 未跑。没有更早的版本可装：manifest 和 `release.json` 都只列最新一版
- 格式: zip，顶层只有 `Ducoro.app`
- **读的是**: 人人都能下载的 GA 版。manifest 里只有一个版本，app 自己的 updater 读的就是它，
  官网下载页给的也是同一构建（dmg 的 sha256 与 `release.json` 一致）
- 嵌套 app: 只有 Electron 自带的四个 `Ducoro Helper*.app`（都在 `Contents/Frameworks`，`LSUIElement=true`），
  没有 `LoginItems`
- **常驻 daemon，要知道但不阻塞**: 包里有 `Contents/Resources/bin/ducoro-cli`（143 MB，Bun 打包的 agent
  运行时），以 `ducoro-cli daemon run` 常驻。两种托管方式：
  - app 开着时由 Electron 托管：启动时 `launchctl bootout gui/<uid>/ai.ducoro.daemon`，再从**本 bundle**
    spawn 子进程（`DUCORO_DAEMON_TAKEOVER=1`）；退出时杀掉子进程，再 `launchctl bootstrap` 还原托管服务
  - app 没开时由 launchd 托管：`~/Library/LaunchAgents/ai.ducoro.daemon.plist`，`KeepAlive=true`，
    `ProgramArguments` 是**执行 `daemon install` 的那个 `ducoro-cli` 的路径**（可能在 bundle 里，也可能是
    `install.sh` 装的独立 CLI）

  `AppRestarter` 不管这个 daemon。swap 时如果 launchd 托管的那份指向 bundle 内，它会继续跑旧代码，直到下次
  打开 app 时被 bootout 换新。这和厂商自己的 electron-updater（Squirrel.Mac，同样是退出后替换 bundle）
  行为一致，不是我们引入的新风险；app 在运行时一键安装会被重启，重启即换新。所以允许一键
- 上一版 Team: 没查（拿不到上一版的包）

## 已知问题

- `application-test` 的 `channel-verify` 手搭的源链（`MacAppStoreSource` … `VendorProbeSource`）**漏了
  `ElectronManifestSource`**，对 Ducoro 这类纯 Electron 覆盖的 app 会打印 `winning source <none>` /
  `status unknown`，和生产 `SourceStack.make` 的结论不一样。生产链末尾是有 Electron 源的；
  下面「如何复验」用 `feed-discover`（它跑的是生产 `ElectronManifestSource`）代替
- 版本号的中段看着是日期（`MDD`），补不补零按数字比都一样；厂商换成别的方案时要重看比较

## 如何复验

```bash
# 1. manifest（带 noCache 与不带应是同一版本）
curl -sS "https://static.ducoro.ai/desktop/latest-mac.yml?noCache=$RANDOM"
curl -sS https://static.ducoro.ai/desktop/release.json

# 2. 生产 ElectronManifestSource 对真包的判定（dmg 只读挂载，不安装）
swift run --package-path application-test feed-discover Ducoro-<version>-arm64.dmg

# 3. 一键装的那个 zip：sha512 与 manifest 一致、Team 与已装的一致
openssl dgst -sha512 -binary Ducoro-<version>-arm64-mac.zip | base64
ditto -x -k Ducoro-<version>-arm64-mac.zip out && codesign -dv out/Ducoro.app 2>&1 | grep TeamIdentifier
```

## 建议下一步

1. 无代码改动。检测与一键都由通用 Electron 源覆盖
2. changelog: 等 What's New 条目带上版本号再加 `ChangelogRecipe`
3. （另一件事）给 `channel-verify` 的源链补上 `ElectronManifestSource`，让它和 `SourceStack.make` 一致

## 接入时的实测（2026-10-04）

没有 recipe 文件，所以这里不用 `## 历史与实测`（那个标题要和 recipe 里的 `// History:` 指针成对出现）。

**包身份。** `release.json` 列出的 `Ducoro-2026.1002.354-arm64.dmg`：180,492,608 字节，sha256
`14f26bf6…aefb20e` 与 `release.json` 一致。挂载后是 `Ducoro.app`：`ai.ducoro.desktop`，
`2026.1002.354` / `2026.1002.354`，`spctl` accepted（Notarized Developer ID，Songtao Xiang (6YU2PK44KX)）。

**feed-discover。** `ADOPT https://static.ducoro.ai/desktop/latest-mac.yml`（electron-builder manifest）。

**生产源。** 用一次性程序对挂载的 bundle 调 `AppScanner().scan(bundlesAt:)` +
`ElectronManifestSource().latestVersion(for:)`：

```
scan: ai.ducoro.desktop 2026.1002.354 channel=stable
electronUpdate: provider generic manifest https://static.ducoro.ai/desktop/latest-mac.yml
resolved: short 2026.1002.354 kind zip size 180103149
downloadURL: https://static.ducoro.ai/desktop/Ducoro-2026.1002.354-arm64-mac.zip
sha512: 5lgOJLXT…S1NUwg== publishedAt 2026-10-02 04:19:24 +0000
evaluate: upToDate
```

**一键装的 zip。** 下载 `Ducoro-2026.1002.354-arm64-mac.zip`：HTTP 200，180,103,149 字节，sha512 与
manifest 一致；解出的 `Ducoro.app` 是 `2026.1002.354`，Team `6YU2PK44KX`，
`codesign --verify --deep --strict` 通过，`spctl` accepted，`lipo -archs` = `arm64`。
