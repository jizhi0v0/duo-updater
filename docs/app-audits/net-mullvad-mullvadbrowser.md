# Mullvad Browser

## 基本信息
- App: Mullvad Browser — Mullvad 与 Tor Project 合作的隐私浏览器（Firefox ESR 衍生，和 Tor Browser 同一套
  `tor-browser-build` 构建，但不连 Tor 网络）
- Bundle ID: stable `net.mullvad.mullvadbrowser`；alpha `net.mullvad.mullvadbrowseralpha`（"Mullvad Browser Alpha.app"）
- 仓库: `mullvad/mullvad-browser`（GitHub Releases，每个 release 带 macOS dmg + `.asc` 签名）；下载页
  `https://mullvad.net/en/download/browser/macos`，`/latest` 与 `/latest-alpha` 302 到 `cdn.mullvad.net` 上同名 dmg
- Team ID: `MADPSAYN6T`（The Tor Project, Inc；Developer ID + 公证，`spctl` = `Notarized Developer ID`）
- 观测版本: stable 15.0.25（`CFBundleVersion` `14026.10.11`）、15.0.24（`14026.9.28`）；alpha 16.0a13（`15326.9.30`）；
  最早的 12.0.4（`10223.7.2`）；观测日期: 2026-10-16
- 架构: universal（x86_64 + arm64），`LSMinimumSystemVersion` = `10.15.0`
- 自更新机制: Mozilla 自带更新器（`Contents/MacOS/updater.app`，`org.mozilla.updater`），无 `SUFeedURL`、无
  electron-builder 配置、无 MyGo feed（feed-discover: `—`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（cask `mullvad-browser` 为 `auto_updates`） | — | ✓ | — |
| **alpha**  | —       | —（无 alpha cask） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，两轨都是）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.mullvad.mullvadbrowser` | 独立 | — | `/releases/latest` + `^([0-9]+(?:\.[0-9]+)+)$` | ✓ |
| alpha   | `net.mullvad.mullvadbrowseralpha` | 独立 | 名字里的 "Alpha" 与版本里的 `a<N>`（`inferred alpha`） | 列表 + `^([0-9]+\.[0-9]+(?:\.[0-9]+)?a[0-9]+)$`，`channel: .alpha` | ✓ |

- 两轨是两个 app，可以并存；alpha 的 `CFBundleShortVersionString` 保留 `a<N>`（`16.0a13`，与 tag 一致），
  不像 Firefox/Thunderbird 那样剥掉后缀。
- `application.ini` 的 `RemotingName`: stable `Mullvad Browser`（12.0.4 为 `mullvadbrowser`），alpha
  `Mullvad Browser Alpha`。channel-verify 读到 `<none>`（扫描器只为 `org.mozilla.*` 读它），不影响判轨。
- GitHub 的 `prerelease` 位与 tag 形状一致：116 个 release 里 67 个裸版本 tag 全是 `false`，49 个 `a<N>` tag 全是 `true`。
- 没有 beta / nightly 轨：下载页只给 stable 与 alpha。

## 更新检测
- 源: `mullvad/mullvad-browser` GitHub Releases。stable 读 `/releases/latest`；alpha 读列表、取第一个 `a<N>` tag
  （列表里 alpha 与 stable 交错；最新 100 个 release 里第一个 alpha 在第 1 位、两个 alpha 之间最多隔 6 个，
  `GitHubListPageSizeTests` 记的下限是 7，规则用默认页 20）。
- 版本 = tag，原样等于 `CFBundleShortVersionString`。stable pattern 读得到全部 67 个裸 tag（含两段式 `15.0`、`14.0`、`13.0`），
  不吃 `a<N>`；alpha pattern 读得到全部 49 个 alpha tag，不吃裸 tag。
- app 自己的更新检查: `--with-updater-url=https://cdn.mullvad.net/browser/update_responses/update_1/`（`buildconfig.html`），
  形如 `…/release/macos/<版本>/ALL` 的 Mozilla update XML；其 `detailsURL` / `openURL` 指向本仓库的 release 页。
  同目录还有 `release/download-macos.json` / `alpha/download-macos.json`（`{"binary","version",…}`，与 Tor Browser 的
  `aus1.torproject.org` JSON 同形）。没用它们：GitHub 同时给检测、dmg 资产 digest 与 release notes。
- 没有 OS 上下限要处理：update XML 的 `minSupportedOSVersion="19.0.0"`（Darwin 19 = macOS 10.15），低于我们的宿主下限。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Mozilla MAR） | 有 | 不能 |
| 证据 | 自带 `updater.app` 应用 MAR 包 | 2026-10-16 `update_responses/update_1/release/macos/15.0.24/ALL` 给 complete MAR（139132772 B）与 partial `mullvad-browser-macos--15.0.24-15.0.25.incremental.mar`（8802786 B） | `DeltaApplier` 只认 Sparkle BinaryDelta 与 MyGo，不认 MAR |

- 格式: Mozilla MAR（厂商自有）
- 阻塞项: 需要 MAR 应用器，不在本次范围

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 15.0.24 运行 30 s 内停放并预先应用成 `Updated.app`（15.0.25，实测） | 不能（MAR 不是 app 包） |
| 证据 | 默认 `app.update.staging.enabled = true`、`app.update.auto = true`（`browser/omni.ja` 默认 prefs）；停放目录没核实 | 2026-10-16 真机：`~/Library/Application Support/MullvadBrowser/UpdateInfo/Applications/Mullvad Browser/updates/0/` 下 `update.mar`（8,802,786 B，partial）、`update.status` = `applied`、`update.version`、`Updated.app`（目录共 395 MB）；`active-update.xml` 的 `appVersion` 15.0.25 | `SelfUpdaterStash` 不读 MAR |

- 记录文件与字段: `updates/0/update.status`（`applied` = 已预先应用、等下次启动换包）、`update.version`；`UpdateInfo/…/active-update.xml`
- 容器: MAR
- 两份副本会不会共用这个目录: 没查

## Changelog
- 来源: GitHub Release body（`GitHubMarkdownParser`）。厂商的 update XML 也把 release 页当 details。
  bundle 里另有 `Contents/Resources/MullvadBrowser/Docs/ChangeLog.txt`，内容相同。
- 结构化（2026-10-16，channel-verify `changelog pane`）:
  - stable 15.0.25: `source structured: 1 entries; newest 15.0.25: 7 items, headings []; first items ["All Platforms", "Updated NoScript to 13.6.36.1984", "Bug 45382: Backport Security Fixes from "]`
  - alpha 16.0a13: `web page https://github.com/mullvad/mullvad-browser/releases/tag/16.0a13, no structure`
    （16.0a13 的 release body 为空，长度 0；之前的 alpha 都有内容，`release history 8 entries`）
- **分节被压平**。用生产解析器直接跑真实 body: 15.0.25 得 7 条，`content` 为空；平台分组行
  （"All Platforms"、"Windows"）作为普通条目出现，`## Build System` 标题被丢掉，它下面的构建条目直接接在浏览器条目后面。
  16.0a12（19 条）同样。原因是 body 用 ` * <平台>` 作为分组、`## Build System` 不是解析器保留的分类标题。
- 跟随 channel: 是（每个 tag 自己的 body）
- Recipe 状态: 没写；要保留分节需要专门的解析，或 `skipSections: ["Build System"]` 至少去掉构建条目（见建议下一步）

## 一键安装
- 状态: **支持**（stable 与 alpha 都接了 install pattern；Team 闸）
- 格式: dmg（ULMO，无 SLA），universal；嵌套 `updater.app`（`LSUIElement`）、`plugin-container.app`、
  `media-plugin-helper.app`（alpha 另有 `gpu-helper.app`），都是浏览器运行时按需拉起的子进程，没有 LoginItems /
  LaunchAgent / 常驻 helper。`updater.app` 按 Mozilla 的设计只在应用 MAR 时由浏览器拉起、应用完退出（推断，未读源码核实），换包后不会继续运行旧代码。
- Pattern: stable `^mullvad-browser-macos-[0-9]+(?:\.[0-9]+)+\.dmg$`；alpha
  `^mullvad-browser-macos-[0-9]+\.[0-9]+(?:\.[0-9]+)?a[0-9]+\.dmg$`。不匹配 `.asc`、Linux/Windows 包。
  12.0.x 与 12.5.x 的旧资产名是 `MullvadBrowser-<v>-macos_ALL.dmg`，pattern 不匹配，那些 release 已不会是最新版。
- Team: 12.0.4、13.0、15.0.24、15.0.25、16.0a13 全是 `MADPSAYN6T`，没换过 Team；bundle id 自 12.0.4 起没变。
- 校验: GitHub 资产 `digest`（sha256）。`shasum -a 256` 与 digest 一致：15.0.25 `bb5b6559…683a7151`、
  15.0.24 `2c2352c3…6466dfa7`、16.0a13 `27d9b3b0…7aa1b343`（15.0.25 下自 cdn.mullvad.net、15.0.24 下自
  archive.torproject.org，与 GitHub 资产是同一份字节）
- alpha 渠道证明: `githubChannelProofs` 断言 URL 为 `/download/<v>a<N>/mullvad-browser-macos-<v>a<N>.dmg`
- **读的是**: 人人可手动下载的 GA（stable: `/releases/latest`，下载页 `/latest` 302 到同一 dmg；alpha: 下载页
  `/latest-alpha` 链接的同一版本）。app 自己的 update XML 请求只带版本与平台、不带设备标识，没看到按设备灰度。
- 真机端到端（2026-10-16，集成分支 `make cli`）：15.0.24 → 15.0.25（含 `verifyingSignature`），`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 阻塞: 无

## 已知问题
- 运行中更新与自带更新器会碰撞，但无害（运行中一轮实测）: 浏览器已停放 15.0.24→15.0.25 时 duo 先换成 15.0.25，`duo restart` 拉起的新进程发现停放，
  启动 `updater.app/Contents/MacOS/org.mozilla.updater` 把它的 `Updated.app` 整个换进来（主程序 inode 变成它那份）再重启自己；结果仍是 15.0.25、签名完好，停放目录清空。
  不是对新文件再打 MAR，而是换入预先应用好的整包。`duo check` 对这种停放显示 `[GitHub, in-place]`，不提示已停放
- alpha 最新 release 偶尔没有 notes（16.0a13），此时 changelog 落到网页。

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：15.0.24 运行中、已停放 15.0.25，`duo install --yes` → `installed.` 并提示 `Still running the old code: Mullvad Browser`；`duo restart` → `restarted`，随后 Mozilla 更新器换入它的 `Updated.app` 并重启（见已知问题）。Team `MADPSAYN6T`、`codesign --strict` 0、Notarized。新增 `~/Library/{Application Support/MullvadBrowser, Caches/MullvadBrowser, Preferences/net.mullvad.mullvadbrowser.plist}`，登录项前后无差异
2. 可选：给 GitHub 结构化日志加 `skipSections: ["Build System"]` 或专门的 Tor 系 ChangeLog 解析，保留平台分组。

## 如何复验
```
swift run --package-path application-test channel-verify mullvad-browser-macos-15.0.24.dmg --expect stable
#   → detected stable，winning source GitHub，latest 15.0.25，UPDATE → 15.0.25
swift run --package-path application-test channel-verify mullvad-browser-macos-15.0.25.dmg --expect stable
#   → detected stable，winning source GitHub，latest 15.0.25，up to date
swift run --package-path application-test channel-verify mullvad-browser-macos-16.0a13.dmg --expect alpha
#   → bundle id net.mullvad.mullvadbrowseralpha，inferred alpha，winning source GitHub，latest 16.0a13，up to date
swift run --package-path application-test channel-verify MullvadBrowser-12.0.4-macos_ALL.dmg --expect stable
#   → detected stable，UPDATE → 15.0.25
codesign -dvv <Mullvad Browser.app>   # → TeamIdentifier=MADPSAYN6T
spctl -a -vv -t exec <Mullvad Browser.app>   # → source=Notarized Developer ID
```

## 历史与实测
- 2026-10-16 接入。triage 记的「GitHub release asset: False」不对：`mullvad/mullvad-browser` 每个 release 都带 macOS dmg，
  下载页的 "Download from GitHub" 链接就是它（triage 只看了 cask 的 CDN 地址）。
- 2026-10-16 release 列表: 116 个 release，67 stable / 49 alpha；无 macOS 资产的: stable `14.0.8`，alpha `14.0a1`、`13.5a3`、
  `13.0a2`、`13.0a1`、`12.5a7`；旧资产名 `MullvadBrowser-<v>-macos_ALL.dmg` 用到 12.5.6。
- 2026-10-16 `cdn.mullvad.net/browser/update_responses/update_1/alpha/download-macos.json` 报 `16.0a13`，而
  `dist.torproject.org/mullvadbrowser/` 已有 `16.0a14` 目录、GitHub 尚无 16.0a14 release。
