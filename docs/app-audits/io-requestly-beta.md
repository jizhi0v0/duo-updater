# Requestly

> 稳定版的 bundle id 带 `.beta` 后缀。`ReleaseChannel.detect` 第 2 步原本把每一份 Requestly 都判成 beta，stable rule 不应答（channel-verify 实测 `status unknown (no source answered)`）；现由 `detect` 第 0.997 步按这个 id 判成 stable（`RequestlyChannelTests`）。

## 基本信息
- App: Requestly — HTTP 拦截代理（Electron 42，electron-builder 26，BrowserStack）
- Bundle ID: `io.requestly.beta`（这就是正式版的 id；helper 是 `io.requestly.beta.helper{,.GPU,.Renderer,.Plugin}`，都在 `Contents/Frameworks`）
- 仓库: `requestly/http-interceptor-desktop-app`（原名 `requestly/requestly-desktop-app`，GitHub 重定向；包里的 `app-update.yml` 和 Homebrew cask 的 URL 仍是旧名）
- Team ID: `YQ5FZQ855D`（Browserstack Inc）自 v25.6.27 起；v25.6.25 及更早是 `AFBT5Z9V94`。都 `spctl` Notarized Developer ID
- 观测版本: 26.6.29（tag `v26.6.29`，2026-06-29 发布，资产 `Requestly-26.6.29-arm64.dmg`）；上一版 26.6.26；观测日期: 2026-10-26
- 自更新机制: **electron-updater**（`provider: github`、`releaseType: release`、`updaterCacheDirName: requestly-updater`），Mac 上经 Squirrel.Mac 落地
- 分发: GitHub Releases；Homebrew cask `requestly`（`url` 指 arm64 dmg，无 `auto_updates`）；官网 `get.requestly.com/macOS` 302 到同一个 GitHub 资产；Setapp 版另有 id（见覆盖清单）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | 现有通用 cask 源（仅 brew 装的副本） | — | ✓ | — |

当前生效源（channel-verify 实测）: **GitHub**。`ElectronManifestSource` 接不上：`app-update.yml` 是 `provider: github`，`feed-discover` 结论 `review electronProviderNeedsConstruction`。

## 覆盖清单
- **bundle id**: 真包 1.4.0（x86_64，release 列表最老一版）、2.0.0、25.4.13、25.5.14、25.5.20、25.5.30、25.6.19、25.6.25、25.6.27、25.10.8、26.3.3、26.6.8、26.6.22、26.6.26、26.6.29 都是 `io.requestly.beta`。没有改名前的旧 id
- **Team**: 二分真包得到边界 —— 25.6.25 `AFBT5Z9V94`，25.6.27 `YQ5FZQ855D`（中间没有别的 release）。`SignatureVerifier.verifyTeamIdentifierMatch` 要求完全相等，所以 ≤25.6.25 的副本一键会被 Team 闸拒（只检测，用户手动更新一次）。厂商自己的 designated requirement（`assets/requirement.rqset`，2025-05-15 #162 加入 `YQ5FZQ855D`）同时接受 `B7SH28MF39` / `AFBT5Z9V94` / `YQ5FZQ855D`：真包 25.6.25 与 26.6.29 的 `codesign -d -r-` 三个 OU 都在，25.5.14 只有前两个
- **其他轨**: 92 个 release 无一 `prerelease`，`-beta` / nightly 资产都没有。`io.requestly.beta` 里的 beta 只是历史命名，不是一条轨
- **同厂商其他产品**: Setapp 版 `io.requestly.beta-setapp`（`electron-builder-setapp.json`，没下到真包）；Requestly API Client `com.requestly.api-client`（官网 `get.requestly.com/mac-api-client` → `assets.requestly.com/.../requestly-api-client-2610.23.2-mac-arm64.dmg`，真包 Team 同为 `YQ5FZQ855D`，electron-updater generic，`feed-discover` = `ADOPT`，`ElectronManifestSource` 已覆盖）。两者 id 不同，本 rule 碰不到
- **版本范围**: 1.4.0–2.0.0 是 semver，25.4.13 起是 `YY.M.D`。`^v([0-9]+(?:\.[0-9]+)+)$` 读得出全部 92 个 release tag。另有 11 个 tag 没有 release（`v2025.04.11`、`v2025.04.13`、`v2025.4.11`、`v25.10.1`、`v25.5.19`、`v25.6.13`、`v25.7.21`、`v1.4.1`、`v1.4.7`、`v1.4.8`、`1.4.6`），`/releases/latest` 不看它们；若哪天给 `v2025.*` 建了 release 会读成 2025 > 26（推断，今天不发生）
- **架构**: 1.5.9 起每版有 `-arm64.dmg`；更早只有 x64。x64 副本（≤1.5.8 或装了不带架构词的包）一键会换成 arm64 包。DuoUpdater 只跑 arm64（`App/project.yml`），不构成问题
- **主机下限**: arm64 dmg `LSMinimumSystemVersion` 26.6.26 起 12.0（之前 10.13），低于 DuoUpdater 自身下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.requestly.beta` | — | `detect` 0.997 按 id 判 stable | `/releases/latest` | ✓ |

## 更新检测
- 源: `requestly/http-interceptor-desktop-app` GitHub Releases，`/releases/latest`
- 版本方案: tag `v26.6.29` → `CFBundleShortVersionString` = `CFBundleVersion` = `26.6.29`（settled from source: `release/app/package.json` on `master`）
- install pattern `^Requestly-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`；同 release 里另有 `-arm64-mac.zip`、x64 的 `.dmg` / `-mac.zip`、`latest-mac.yml`、blockmap、Windows / Linux 包
- **读的是**: 人人可手动下载的 GA（官网下载按钮 302 到同一个 GitHub 资产；app 自己的 electron-updater 也读 `/releases/latest`）
- channel-verify（2026-10-26，加 `detect` 0.997 之前）: 26.6.26 → `inferred beta`、`winning source <none>`、`status unknown (no source answered)`
- channel-verify（2026-10-26，加之后，`--expect stable`）: 26.6.26 → `detected channel → stable`、`winning source GitHub`、`latest 26.6.29`、`status UPDATE → 26.6.29`；26.6.29 → `up to date`；25.6.25（旧 Team）→ `UPDATE → 26.6.29`

## 按架构 / 按 OS 分轨
- 分架构资产，无 universal；arm64 dmg `archs=arm64`。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（blockmap 差分下载） | 有 blockmap | 不需要 |
| 证据 | electron-updater 的 differential download 读 `.blockmap`（库行为，未在本 app 上核） | v26.6.29 发了 `-arm64-mac.zip.blockmap` 等 | 那是下载层的分块复用，不是二进制补丁；我们下整包 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 没查（真机第二轮待主会话） | 能（通用 electron-updater 布局，已接） |
| 证据 | 26.6.29 `app.asar` `dist/main/main.js`：`autoDownload=!0`、`autoInstallOnAppQuit=!0`（库默认值，`src/lib/autoupdate/index.js` 没改）；`cacheDirForPendingUpdate` = `<cacheDir>/pending`、`update-info.json` | — | `SelfUpdaterStash.electronCacheDirectoryName` 读 `app-update.yml` 的 `updaterCacheDirName` |

- 记录文件: `~/Library/Caches/requestly-updater/pending/update-info.json`（下载完成后写，见 `SelfUpdaterStash` 注释）
- 容器: zip（`-arm64-mac.zip`），包根是 `Requestly.app`（推断，按 electron-builder 惯例，未开包核）
- 检查触发: 主进程只注册 IPC `check-for-updates-and-notify`，由远端 web 界面调用；何时调用不在本仓库里，没核

## 代理与根证书（换包会碰到什么）
settled from source（`master`，与 26.6.29 `app.asar` 的 `dist/renderer/renderer.js` 字符串一致）:
- **根证书**: 首次开启 HTTPS 拦截时生成 CA（`CERT_NAME` = `RQProxyCA`）到 `~/Library/Application Support/Requestly/.tmp/certs/ca.pem`，用 `osascript … do shell script "security add-trusted-cert -r trustRoot -k $HOME/Library/Keychains/login.keychain …" with prompt …` 装进**登录钥匙串**（没有 `with administrator privileges`，系统会为信任设置弹自己的授权框）。证书和文件都在 bundle 外，换包不动它们
- **系统代理**: 「System-wide」开关用 `networksetup -setwebproxy / -setsecurewebproxy Wi-Fi 127.0.0.1 <port>` 和 `-setproxybypassdomains`，只改 `Wi-Fi` 这一个网络服务。关掉或正常退出时 `removeProxy` 执行 `-setwebproxystate Wi-Fi off` 等
- **退出路径**: 主窗口 `close` 先 `preventDefault` 并发 `initiate-app-close` 给 web 界面；web 界面回 `quit-app` 后才真正关，`closed` 里 `getReadyToQuitApp` → 后台窗口 `shutdown` → 各 traffic source `deactivateAll()` → 撤系统代理。被强杀（不走这条路）时系统代理会留在 `127.0.0.1:<port>`，该端口没人监听，`Wi-Fi` 上走系统代理的流量会断，直到再开 Requestly 并关掉开关（推断，未真机验证）
- 没有 LoginItems / LaunchAgent / root helper / 系统扩展；`@vscode/sudo-prompt` 只在本地文件同步写受保护路径时按需用
- Firefox 的证书注入用包里的 `static/nss/darwin/certutil`，按需调用，不常驻

## Changelog
- 来源: GitHub release 正文，`GitHubMarkdownParser`
- 结构化（channel-verify，26.6.26 起）: `source structured: 1 entries; newest 26.6.29: 1 items, headings []; first items ["chore(release): proxy 1.5.2 + app versio"]`
- 正文只有自动生成的 `## What's Changed` + PR 标题列表 + `**Full Changelog**`；唯一的标题没出现在 headings 里、也不在条目里（被解析器丢掉，未压平进条目）。条目是 PR 标题，内容稀薄但结构化
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（Team `YQ5FZQ855D` 的副本，即 25.6.27 起）
- 端到端: 待主会话
- 格式: dmg（`hdiutil imageinfo` Format `UDZO`）
- 校验: GitHub 资产 `digest` `sha256:e8eebb6db725b079306973f74a453c2b707924d8a44c641b3a531eac83758bfc`，下载文件 `shasum -a 256` 相同、155160056 字节
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- Team: ≤25.6.25 的副本被 Team 闸拒（`AFBT5Z9V94` ≠ `YQ5FZQ855D`），只检测
- 真机要盯（来自源码，未在真机观察）: 运行中退出要走 web 界面的关闭流程，`duo` 的退出可能被挡；退出后核 `networksetup -getwebproxy Wi-Fi` / `-getsecurewebproxy Wi-Fi` 是否已关；登录钥匙串里的 `RQProxyCA` 应保持不变；URL scheme `requestly`；文件关联 `.har`（Default）、`.rqly`（Owner）

## 已知问题
- `io.requestly.beta` 的 `.beta` 后缀靠 `detect` 0.997 的按 id 分支处理；Setapp 版 `io.requestly.beta-setapp` 没有真包、未测（后缀 `-setapp` 不是渠道词，通用规则读成 stable，本 rule 不碰它）
- 仓库在 2026-06-29 后没有新 release（`master` 最后提交同日，`pushed_at` 2026-08-21）。官网下载页同时给出另一个产品 Requestly API Client。没找到厂商宣布停止维护的页面

## 如何复验
```bash
gh release download v26.6.29 -R requestly/http-interceptor-desktop-app -p 'Requestly-26.6.29-arm64.dmg'
gh release download v26.6.26 -R requestly/http-interceptor-desktop-app -p 'Requestly-26.6.26-arm64.dmg'
gh release download v25.6.25 -R requestly/http-interceptor-desktop-app -p 'Requestly-25.6.25-arm64.dmg'   # 最后一个 AFBT5Z9V94
gh release download v25.6.27 -R requestly/http-interceptor-desktop-app -p 'Requestly-25.6.27-arm64.dmg'   # 第一个 YQ5FZQ855D
.claude/skills/coverage-discovery/scripts/check-bundle.sh Requestly-26.6.29-arm64.dmg
swift run --package-path application-test feed-discover Requestly-26.6.29-arm64.dmg   # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Requestly-26.6.26-arm64.dmg --expect stable   # GitHub, UPDATE → 26.6.29
swift run --package-path application-test channel-verify Requestly-26.6.29-arm64.dmg --expect stable   # up to date
swift test --package-path DuoUpdaterCore --filter RequestlyChannelTests
```

## 建议下一步
1. 主会话真机两轮（26.6.26 → 26.6.29），并按「真机要盯」核系统代理与钥匙串
