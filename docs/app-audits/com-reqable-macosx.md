# Reqable

## 基本信息
- App: Reqable — HTTP / API 调试代理与测试客户端（Flutter + C++，闭源）
- Bundle ID: `com.reqable.macosx`
- 仓库: `reqable/reqable-app`（README 自述「not an open-source project」，仓库只用来收 issue 和发 release；未归档；默认分支 `main`，只有 README 与配图）
- Team ID: `DXY5A5J7C4`（Developer ID Application: Shanghai Reqable Technology Co., Ltd.）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.3.5（tag `3.3.5`，资产 `reqable-app-macos-arm64.dmg`，build 227）；上一版 3.3.4（build 226）；观测日期: 2026-10-26
- 自更新机制: **Sparkle 2.8.0**（`Contents/Frameworks/Sparkle.framework`），经 Flutter 插件 `auto_updater`（`auto_updater.framework`，`setFeedURL:` / `checkForUpdates` / `setScheduledCheckInterval`）在运行时设 feed；Info.plist 没有 `SUFeedURL`，有 `SUPublicEDKey`。详见「更新检测」
- 分发: GitHub Releases（每版 arm64 / x86_64 两个 dmg，另有 Windows / Linux / Android 资产）；Homebrew cask `reqable`（`auto_updates true`，3.3.5，URL 就是这里的 release 资产）；Mac App Store 搜不到（`mas search Reqable` 无结果，iTunes Search `entity=macSoftware` 0 条）
- 产品终止: 未见。仓库 README 与 release 列表没有 sunset / 停止维护字样，2026-10-23 还在发版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ○（feed 在代码里且要带参数，见下） | —（`auto_updates`，让位） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。`feed-discover` 对 3.3.5 dmg 的结论是 `review noCandidate`：没有 `SUFeedURL`、没有 `app-update.yml`、没有 MyGo feed，所以通用 Sparkle 源读不到；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - 3.3.5 arm64: `com.reqable.macosx`，Team DXY5A5J7C4，Notarized，build 227，`LSMinimumSystemVersion` 11.0
  - 3.3.5 x86_64: 同 id、同 Team、同版本，`archs=x86_64`
  - 3.3.4 arm64: 同 id、同 Team，build 226
  - 2.21.2 arm64: 同 id、同 Team，build 102，`LSMinimumSystemVersion` 10.15
  - 1.1.5 arm64（release 列表里最老的一版，2023-08-01）: 同 id、同 Team，build 29，`LSMinimumSystemVersion` 10.14
  - 没有改名前的旧 bundle id；cask 只有 `reqable` 一个，没有别的 cask 指向这个仓库
- 其他轨: 没有。全部 160 个 release 都是 `prerelease: false`、`draft: false`；tag 除 `test` 外都是纯数字点分。`test`（2026-08-11）只带一个 `reqable-app-macos-arm64.dmg`，真包是 `com.reqable.macosx` 3.2.23（build 221），即普通的 3.2.23 构建，不是另一条轨；装了它的副本读作 3.2.23，照常看到 3.3.5。smart-appcast 端点要求的参数（见下）里没有 channel
- 版本范围: `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$` 读得出全部 159 个数字 tag，`test` 不匹配；锚定，`3.3.6-beta` 这类不会被读成 `3.3.6`；下一个大版本 `4.0.0` 也匹配
- 没有 macOS 资产的 release: 3.2.22、3.2.21、3.2.20、3.2.12、2.16.1、2.10.2、2.8.1、2.2.1（只发了别的平台）。最长连续 3 个（3.2.20–3.2.22），在 `maxReleasesWithoutMacOSAsset`（5）以内：`/releases/latest` 恰好是这种 release 时引擎改读列表往回走到最近一个有 arm64 dmg 的版本
- 许可状态: Community 免费、Premium 付费，同一个二进制，更新不按许可分发（smart-appcast 不带账号参数）
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Reqable 3.3.x `LSMinimumSystemVersion` 11.0，在下限之下，不需要 `hostRequirement`。install pattern 只锚 `-arm64`：DuoUpdater 只跑在 arm64 上；用 Rosetta 跑 x86_64 版的副本会被一键换成 arm64 版（同 id、同 Team，原生构建）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.reqable.macosx` | — | — | GitHub `/releases/latest` | ✓ |

## 更新检测
- 源: `reqable/reqable-app` GitHub Releases，`/releases/latest`
- 版本方案: tag `3.3.5` → `CFBundleShortVersionString` `3.3.5`、`CFBundleVersion` `227`（比 short 版本，`versionIsBuild` 不需要）
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^reqable-app-macos-arm64\.dmg$`；同一 release 里的 `reqable-app-macos-x86_64.dmg` 和其他平台资产不匹配
- **App 自己的更新器（Sparkle，feed 在代码里）**:
  - `App.framework/App`（Dart AOT）里有 `/version/smart-appcast?version=`；2.21.2 与 1.1.5 里是 `/version/appcast?platform=`。可执行文件里没有出现完整的主机名
  - 我们按服务端的报错补齐了参数（**主机和参数是推出来的，没有抓 app 自己的请求**）: `https://app.reqable.com/version/smart-appcast` 依次报缺 `platform`、`arch`、`ext`、`locale`；`version` 要整数（传 `3.3.4` 报 `For input string`，即 build 号）；`locale` 接受 `en-US` / `zh-CN`，不接受 `en`、`en_US`
  - 2026-10-26 `?version=220&platform=macos&arch=arm64&ext=dmg&locale=en-US` 返回 200、一个 `<item>`：`sparkle:version="227"`、`sparkle:shortVersionString="3.3.5"`、`length="36564683"`、`sparkle:edSignature`，`url` 就是 `https://github.com/reqable/reqable-app/releases/download/3.3.5/reqable-app-macos-arm64.dmg`（长度与 GitHub 资产相同）；`<description>` 是从 3.2.23 到 3.3.5 的累计 HTML 说明。`arch=x86_64&version=226` 返回同一版本、x86_64 资产。没有 `<sparkle:channel>`、没有 `minimumSystemVersion` / `maximumSystemVersion`、没有 `<sparkle:deltas>`
  - 旧路径 `app.reqable.com/version/appcast?platform=macos` 还在，报缺 `arch`（旧副本自己的更新器仍有端点可问）
  - 结论: 厂商 feed 发的就是 GitHub 上的同一个文件，GitHub 规则读到的版本与它一致。通用 Sparkle 源用不上：地址不在 Info.plist 里，而且要带安装副本的 build 号、arch、locale；`SparkleFeedCatalog` 是固定地址，表达不了这种按副本拼参数的 feed（没有改引擎去支持，见「建议下一步」）
- 注意事项: 无 WAF、无 rollout 迹象（同一时刻不同 build / locale / arch 都答 3.3.5）

## 按架构 / 按 OS 分轨
- 架构: 分架构资产 `reqable-app-macos-arm64.dmg` / `reqable-app-macos-x86_64.dmg`（`lipo` 层面各自单架构）；规则只装 arm64
- `LSMinimumSystemVersion`: 3.3.x 11.0；2.21.2 10.15；1.1.5 10.14。release 与 feed 都不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2.8.0 自带 BinaryDelta） | 无 | — |
| 证据 | `Sparkle.framework` 2.8.0（`Resources/Info.plist`） | 2026-10-26 smart-appcast（arm64 build 220、x86_64 build 226）响应里没有 `<sparkle:deltas>` | 服务端不发，不需要 |

- 格式: Sparkle binary delta（若将来发）
- 阻塞项: 无

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（Sparkle 的标准行为，我的推断，未在本包上实测） | 真机（2026-10-26）：3.3.4 运行 15 s 内没有出现 Sparkle 缓存，也没有停放的更新 | ○ |
| 证据 | Sparkle 2 用户选了自动下载 / 下载后「安装并重启」之外的「退出时安装」时，会把更新包放在 app 的缓存目录里等退出。Info.plist 没有 `SUAutomaticallyUpdate`；`App.framework` 里没有 `automaticallyDownloadsUpdates` 字符串，默认是弹窗问用户 | — | `SelfUpdaterStash` 现在只读 electron-updater 和 Cindy 两种布局，不读 Sparkle 的 |

- 记录文件与字段: Sparkle 自己的暂存布局，未在本包上核
- 容器: dmg（与 GitHub 资产同一文件）
- 两份副本会不会共用这个目录: 按 bundle id 的缓存目录，会（推断）

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 3.3.4 起）: `source structured: 1 entries; newest 3.3.5: 6 items, headings []; first items ["💪 [OPT] Support importing intermediate C", "💪 [OPT] Imported intermediate CA certifi", "💪 [OPT] All UI text related to root cert"]`
- 正文的 `###` 标题是**平台范围**，不是分类：`### windows-macos-linux-android-ios`、`### windows-macos-linux`、`### android-ios`、`### windows`、`### linux`、`### macos` 等（最近 60 个 release 逐个列过）。3.3.5 只有一个标题，解析器对少于 2 个标题的正文不保留标题（`GitHubMarkdownParser` 的 qualifying-headings 规则，读代码得出），所以 `headings []`；6 条都在 `windows-macos-linux-android-ios` 下，全适用于 macOS，没有被压成条目
- 有 2 个以上标题的版本（如 3.3.2、3.3.0）标题会保留为 `.heading`，`### android-ios`、`### windows`、`### linux` 下的条目会和 macOS 条目一起显示在标题下，读者能看出平台。这一点按解析器代码推断，没有用 channel-verify 在那几版上实测（channel-verify 只打印最新一条）
- smart-appcast 的 `<description>` 是厂商为 macOS 生成的累计说明（`<h2>v3.3.5</h2><h3>Release Date…</h3><ul>…`），我们不读它
- 跟随 channel: 只有 stable
- Recipe 状态: 不需要（结构化、按版本分条）

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-26，本分支 `make cli` 的 duo）**（Developer ID、Team DXY5A5J7C4、Notarized、dmg）
- 端到端（2026-10-26，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 3.3.4 → `duo install` → 3.3.5、`TeamIdentifier=DXY5A5J7C4`、`codesign` 退出 0、`spctl` Notarized Developer ID
  - 第二轮（运行中）: 3.3.4 从 19:14:36 起运行，15 s 内没有 Sparkle 缓存、没有停放的更新；`duo install` 就地装好，提示 `Still running the old code`；`duo restart Reqable` → `restarted`，19:15:08 起的新进程是 3.3.5，`codesign` 0
  - proxy helper 与根证书没装（没有回答任何管理员提示），`/Library/Application Support/Reqable` 不存在，所以「换包前后 `proxy-helper` 是否被动过」这次没法比。终态: 3.3.5，未运行
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `Reqable.app` + `Applications` 软链 + 背景图
- 签名: 1.1.5、2.21.2、3.3.4、3.3.5（arm64 / x86_64）都是 Team DXY5A5J7C4、Notarized，Team 没换过，Team 闸不会拒旧副本
- 校验: GitHub 资产 `digest`。3.3.5 arm64 `sha256:650e4650506f8baf73e91dee01fa0533bdf4b2585bd52bc5d5146c866d44b057`、3.3.4 arm64 `sha256:d81c2d20f8aae2f42721671537e8bd582ada53d458cfd964551aabad1430cb81`，都与下载文件的 `shasum -a 256` 相同；3.3.5 的值也与 cask 的 arm `sha256` 相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；厂商 smart-appcast 发的也是同一个文件）
- 包里的非主程序组件（真包核对，3.3.5 / 3.3.4 / 2.21.2 / 1.1.5）:
  - 没有 `Contents/Library`（无 LoginItems、LaunchAgents、SystemExtensions）、没有嵌套 `.app`；主程序没有 entitlements 输出（`codesign -d --entitlements -` 为空），没有 Network Extension
  - `Contents/Resources/proxy-helper`: universal、同 Team 签名的一次性命令行工具（strings 里只有读写系统代理 `Proxies` / `http` / `https` / `socks`、`save` / `restore`、`system_proxy_backup.plist`、`version` 1.0.0）。`install_helper.sh` 用 `sudo` 把它拷到 `/Library/Application Support/Reqable/proxy-helper` 并 `chown root:admin`、`chmod +s`（setuid root）；`uninstall_helper.sh` 删它。它**不常驻**，每次设系统代理时被调用一次。3.3.5、3.3.4、2.21.2 包里的 `proxy-helper` 字节相同（SHA-256 前缀 `6c4f9e8ed26fb5eb`，`install_helper.sh` 也相同）；1.1.5 没有它。换包不动 `/Library` 里那份——厂商自己的 Sparkle 换包也一样不动它，所以一键不比厂商更新多出风险；若将来某版改了 helper，两条路都会留下旧 helper，由 app 自己决定是否重装（`App.framework` 里有 `/proxy-helper-tool` 和 helper 路径字符串，`proxy-helper` 自己带 `version` 1.0.0；app 是否比对版本未验证）
  - `Contents/Helpers/mcp-server`: 同 Team 签名的 arm64 可执行文件（2.21.2、1.1.5 包里没有，3.3.4 起有；每版字节不同），是 stdio MCP 服务器。MCP 客户端若配置成从 bundle 路径启动它，换包后已在跑的那个进程继续跑旧代码，直到客户端重启它——与 Sparkle 换包相同，不加闸（来自 reqable-mcp-server README 的 stdio 说明；app 内配置路径未核）
  - CA 证书: 用户在 app 里安装的「Reqable Proxy」根证书在钥匙串里（cask 的 `uninstall_postflight` 删的就是它），与 bundle 无关，换包不受影响
- 阻塞: 无

## 已知问题
- 厂商 smart-appcast 的主机（`app.reqable.com`）与参数是按服务端报错拼出来的，没有抓 app 的真实请求；结论（发的是 GitHub 同一文件）只依赖响应内容，不依赖参数是否和 app 完全一致
- 自更新器竞争: Reqable 运行时 Sparkle 会定期检查（`setScheduledCheckInterval`），用户点了它的「安装」或它已在缓存里暂存了包时，可能和我们的换包撞上（Sparkle 应用的一般情形）
- release 正文的平台标题（`### android-ios` 等）不过滤：多标题版本里，非 macOS 的条目会在各自标题下一起显示

## 如何复验
```bash
gh release download 3.3.5 --repo reqable/reqable-app --pattern 'reqable-app-macos-arm64.dmg' --dir new
gh release download 3.3.4 --repo reqable/reqable-app --pattern 'reqable-app-macos-arm64.dmg' --dir prev
.claude/skills/coverage-discovery/scripts/check-bundle.sh new/reqable-app-macos-arm64.dmg    # Team DXY5A5J7C4, Notarized, sparkle-framework, SUFeedURL <none>
swift run --package-path application-test feed-discover new/reqable-app-macos-arm64.dmg      # review noCandidate
swift run --package-path application-test channel-verify prev/reqable-app-macos-arm64.dmg --expect stable   # GitHub, UPDATE → 3.3.5
swift run --package-path application-test channel-verify new/reqable-app-macos-arm64.dmg --expect stable    # up to date
curl -sS 'https://app.reqable.com/version/smart-appcast?version=220&platform=macos&arch=arm64&ext=dmg&locale=en-US'   # 一个 item，url 指向 GitHub 资产
```

channel-verify 原始输出（2026-10-26）:
```
3.3.4 dmg:
  detected channel  → stable
  ✓ detection matches --expect stable
    SUFeedURL       <none>
    winning source  GitHub
    latest          3.3.5
    download        https://github.com/reqable/reqable-app/releases/download/3.3.5/reqable-app-macos-arm64.dmg
    release notes   0 chars inline, changelogURL https://github.com/reqable/reqable-app/releases/tag/3.3.5
    changelog pane  source structured: 1 entries; newest 3.3.5: 6 items, headings []; first items ["💪 [OPT] Support importing intermediate C", "💪 [OPT] Imported intermediate CA certifi", "💪 [OPT] All UI text related to root cert"]
    release history 1 entries
    deltas          0
    status          UPDATE → 3.3.5
3.3.5 dmg:
  detected channel  → stable
  ✓ detection matches --expect stable
    winning source  GitHub
    latest          3.3.5
    changelog pane  source structured: 1 entries; newest 3.3.5: 6 items, headings []; …
    status          up to date
```

## 建议下一步
1. 若要用厂商 feed 的累计 macOS 说明或让通用 Sparkle 源接管：需要引擎支持按已装副本的 build 号 / arch / locale 拼 feed 参数（`SparkleFeedCatalog` 现在是固定地址），本次不做
