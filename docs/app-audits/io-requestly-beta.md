# Requestly

## 基本信息
- App: Requestly — Electron 的 HTTP 抓包/改包客户端（桌面版），闭源；官方把它归在 dev tools
- Bundle ID: `io.requestly.beta`（helper 是 `io.requestly.beta.helper{,.GPU,.Plugin,.Renderer}`，都在 `Contents/Frameworks`）
- 仓库: **`requestly/http-interceptor-desktop-app`**。它改过名：旧 slug `requestly-desktop-app` 仍被 GitHub 302 到新名（repo id `500468552` 不变）。app 自己的 `app-update.yml` 里写的还是旧 slug
- Team ID: `YQ5FZQ855D`（Developer ID Application: Browserstack Inc）；spctl: Notarized Developer ID
- 观测版本: 26.6.29（tag `v26.6.29`，资产 `Requestly-26.6.29-arm64.dmg`，`CFBundleVersion` 与 marketing 版本同串）；上一版 26.6.26；观测于 vmpal「macOS VM 1」（macOS 27.2）
- 自更新机制: **electron-updater**。`Contents/Resources/app-update.yml` 为 `provider: github`、`releaseType: release`、`repo: requestly-desktop-app`（旧名）、`updaterCacheDirName: requestly-updater`
- 分发: GitHub Releases；Homebrew cask `requestly`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|        | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------|---------|----------|-----|--------|-------------|
| stable | —       | —        | —   | ✓      | —           |

`ElectronManifestSource` 接不上：`provider` 是 `github`，配置只给 owner/repo，不给可读地址；构造出来的地址一旦应答，可能是别人的 bundle。故走 `GitHubReleaseRule`。

## 覆盖清单
- **bundle id**：只有 `io.requestly.beta` 一个 id（26.6.26 与 26.6.29 一致），没有改名前的旧 id
- **Team**：两个真包都是 `YQ5FZQ855D`，未换过
- **通道**：**id 里的 `.beta` 不是通道。** 厂商只有一条正式轨：`releaseType: release`、所有 GitHub release `prerelease: false`、没有任何 beta 产物，`CFBundleName`/`CFBundleDisplayName` 都是 "Requestly"。`ReleaseChannel.detect` 的 step 2（bundle id 后缀）会把它读成 `.beta`，所以加了 step 0.997 例外把它判回 `.stable`。没有这个例外时两边都不可服务：stable rule 拒绝 beta 副本（`duo check` 报 `unknown`），`.beta` rule 又欠一份它的单一产物给不出的 channel proof
- **资产**：每个 release 有 `Requestly-<v>-arm64.dmg`、`Requestly-<v>-arm64-mac.zip`（electron-updater 自己下的那份）、`latest-mac.yml`，以及 x64/windows/linux 包；rule 钉 arm64 dmg
- **无 Sparkle**：Info.plist 没有 `SUFeedURL`

## 更新检测
`GitHubReleaseRule`（`io-requestly-beta` family）读 `/releases/latest`，`versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`，`installAssetPattern` 钉 `-arm64.dmg`。

**repo slug 必须用新名**：指向旧 slug 时 `duo verify` 报 `staleSlug`——ride redirect 会让请求丢掉 Authorization 头，且重定向不是永久的。

## 一键安装
`installerKind: .dmg`，装的是 `Requestly-<v>-arm64.dmg`（Team 闸 = 已装副本的 `YQ5FZQ855D`）。

## Changelog
release 正文就是变更说明：厂商用 conventional commits 走 GitHub 自己的 release generator，正文是自动生成的 `## What's Changed` + `* <commit> by @author in <PR url>` + 末尾 `**Full Changelog**` 比较链接。

`GitHubMarkdownParser` 正是为这个形状写的（它就是 GitHub 自动生成格式的解析器）：去掉 `by @author in URL` 后缀、丢掉 contributor 噪音段落，所以 `.gitHubReleases` 不需要 `entryPattern`/`itemPatterns`。多数 release 只带版本号自己那一条 commit（两三行），那是厂商写的，不是解析失败。

## 已知问题
- 厂商 `app-update.yml` 里仍是旧 repo slug；厂商哪天把旧名复用，GitHub 的重定向就会断。我们的 rule 已不依赖它，但 app 自己的 electron-updater 仍依赖
- 没有 changelog recipe：release 正文是模板句，官网有逐版说明，未接

## 实测（2026-10-30，vmpal「macOS VM 1」）
- `duo verify --only requestly` → 1 条 rule ✓
- 未运行一轮：26.6.26 → **26.6.29** ✓
- 运行中一轮：三个 app 同时在前台，`duo install` 换包成功，旧 pid 保持（stale）；`duo restart` 后 Requestly 换了新 pid
- 影响面：全程 `scutil --proxy` 与基线逐字相同，`/etc/hosts` 的 sha1 不变（`9feb94ca…`），没有新增 LaunchAgent/LaunchDaemon。启动时只有标准 Electron 助手进程（GPU/Plugin/Renderer + crashpad）

## 如何复验
```sh
duo verify --only io.requestly.beta
# VM 里：装上一版 dmg，duo check 应报 26.6.26 → 26.6.29，duo install 后核对
# 版本 + TeamIdentifier=YQ5FZQ855D + scutil --proxy / /etc/hosts 未变
```
