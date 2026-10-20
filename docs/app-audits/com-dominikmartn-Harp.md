# Harp

## 基本信息
- App: Harp — 开源终端 Warp 的非官方分支，把标签栏换成给 Claude Code / Codex 长任务用的侧栏；AGPL-3.0
- Bundle ID: `com.dominikmartn.Harp`（可执行文件 `warp-oss`；与 Warp 的 `dev.warp.Warp-Stable` 不同，可并存）
- 仓库: `dominikmartn/harp`（默认分支 `main`）
- Team ID: `423S87ZC86`（Developer ID Application: Renderei Martin GmbH；dmg 公证、stapled）
- 观测版本: 0.1.1（`CFBundleVersion` 20261020.133345）；上一版 0.1.0（20261020.110615）；观测日期: 2026-10-20
- 自更新机制: **无**。settled from source: `app/src/autoupdate/mod.rs` on `main`，`fetch_version` 对 `Channel::Oss` 直接 `bail!("… open-source channel binaries don't support autoupdate")`；`script/release_macos` 用 `script/macos/bundle --channel oss` 出包
- 分发: 只有 GitHub Releases（每版一个 `Harp-<version>.dmg`）。没有 Homebrew cask（`brew search --cask harp` 无），没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 对 0.1.0 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.dominikmartn.Harp` | — | 默认 | `/releases/latest` | ✓ |

- 单轨。两个 release（v0.1.0、v0.1.1）都不是 prerelease；仓库没有 beta / nightly 的发版脚本或 tag。上游 Warp 的 Preview / Dev 轨是 Warp 自己的服务器发的，Harp 的 `oss` 构建不读它们。
- 覆盖清单：
  - bundle id：只有 `com.dominikmartn.Harp` 一个（README 写明、两版真包一致），没有改名前的旧 id。
  - 版本范围：两版 Team 相同、都没有 `LSMinimumSystemVersion`。
  - 架构：dmg 只有 arm64（`lipo -archs` = `arm64`，两版相同）。DuoUpdater 本身只出 arm64（`App/project.yml` `ARCHS: arm64`），不需要架构门控。

## 更新检测
- 源: `dominikmartn/harp` GitHub Releases，`/releases/latest`
- 版本: tag `v0.1.1` → `^v([0-9]+(?:\.[0-9]+)+)$` → `0.1.1`，等于 `CFBundleShortVersionString`（`release_macos` 用 Info.plist 的 `CFBundleShortVersionString` 给 dmg 命名）。锚定：`v0.2.0-rc.1`、`v0.2.0-beta` 不匹配，`v1.0`、`v2.0.0` 匹配
- `CFBundleVersion` 是构建时间戳（`20261020.133345`），不参与比较

## 按架构 / 按 OS 分轨
- 一个 arm64 dmg；Info.plist 无 `LSMinimumSystemVersion`，release 也不声明 OS 范围

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `oss` 渠道的自更新整体关闭（上面的 `fetch_version`） | release 资产只有一个 dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | 不需要 |
| 证据 | 自更新关闭，不下载 | 第二轮启动 0.1.0 后按 T0 diff `~/Library/{Caches,Application Support,Containers}` 下 >8 MB 的新文件：没有属于本 app 的 | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-20，channel-verify `changelog pane`，从 0.1.0 起）: `source structured: 1 entries; newest 0.1.1: 2 items, headings []; first items ["Signed and notarized DMG for Apple Silic", "Open it and drag Harp into Applications."]`
- **面板丢了真正的改动说明。** 0.1.1 正文是一段说明（「Harp now opens straight into the terminal…」）加两条安装说明的列表；解析器把列表前的段落当作列表的引言、只留列表（`GitHubMarkdownParser.sectionProse` 的设计），所以面板只显示两条安装说明。这是通用解析器的取舍，不是这条 rule 的问题；厂商以后若把改动写成列表项就会显示
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg（APFS UDZO），根目录 `Harp.app` + `Applications` 软链。Pattern `^Harp-[0-9.]+\.dmg$`，kind `.dmg`
- 嵌套: 只有 `Contents/PlugIns/WarpDockTilePlugin.docktileplugin`（Dock 加载的图标插件），没有 LoginItems / Helpers / LaunchAgent。登录项是 app 自己：见「已知问题」
- 签名: 0.1.0、0.1.1 都是 `TeamIdentifier=423S87ZC86`，`spctl` `accepted / Notarized Developer ID`，hardened runtime
- 校验: GitHub 资产 `digest`。v0.1.1 资产 `sha256:b3c2e1eb95c5834a649fadfa39a02b04aa9e8448cd8bd37475d556e16526a900`，`gh release download` 取到的 dmg `shasum -a 256` 相同，161529669 字节等于资产大小。按代码（`VendorInstaller` 对 `.developerID` 且带 `expectedSHA256` 的下载先跑 `verifySHA256`），duo 的下载会比对这个 digest；比对成功不打日志，本次没有单独取证
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，README 的安装说明就指向它）
- 端到端（2026-10-20，`make cli` 后的 `duo`）:
  - 第一轮（不运行）: 0.1.0 `ditto` 进 `/Applications` → `duo check` `0.1.0 → 0.1.1 [GitHub, in-place]` → `duo install --yes --json` → `outcome: installed`、`route: vendor`、`bytesDownloaded: 161529669`，23 s → 0.1.1（20261020.133345），inode 变，`codesign --verify --deep --strict` 通过，`spctl` Notarized Developer ID，Team `423S87ZC86`，`diff -r` 与厂商 0.1.1 dmg 里的 bundle 完全相同。当时「保留备份」偏好是关的（`KeepBackups` = 0），所以 `duo backups` 里没有 0.1.0——按偏好跳过，不是失败
  - 第二轮（运行中）: 再放 0.1.0 并启动 → `duo install --yes --json` → `installed`，54 s → `duo restart Harp` 3 s 报 restarted，新进程启动时间在安装之后，之后 10 s 磁盘一直是 0.1.1；退出后 `diff -r` 仍与厂商包相同，`duo check` up to date
- 阻塞: 无

## 已知问题
- **首次启动把自己注册成登录项。** 继承自 Warp：`general.login_item`（`add_app_as_login_item`）默认 `true`，`app/src/login_item/macos.rs` 在 release bundle 首启时调 `SMAppService.mainAppService` `register`，并在偏好里记 `AppAddedAsLoginItem = true`，之后不再重注册（用户在系统设置里删掉不会被加回）。2026-10-20 实测：首启后 `sfltool dumpbtm` 有 `Name: Harp`、`Type: app (0x2)`、`Identifier: 2.com.dominikmartn.Harp`、`URL: /Applications/Harp.app`、`Disposition: [enabled, allowed, notified]`；`System Events` 的 login items 里有 `Harp`。登录项按路径指向 `/Applications/Harp.app`：0.1.0 首启时注册，之后 duo 原地换成 0.1.1，换完的 `dumpbtm` 里这条仍在、仍 enabled、URL 不变；下次登录时会不会拉起新版没测。卸载时要另外移除它（系统设置 › 通用 › 登录项，或 `osascript -e 'tell application "System Events" to delete login item "Harp"'`，删后 `dumpbtm` 不再有这条）。首版审计写成「启动前后 `dumpbtm` 无本 app 条目」是错的：那次启动后的 `dumpbtm` 输出为空文件，grep 出的 0 不是证据
- 除登录项外，首次启动只写自己的地方：`~/.harp/`、`~/Library/Application Support/com.dominikmartn.Harp`、`~/Library/Preferences/com.dominikmartn.Harp.plist`、`~/Library/Logs/harp.log`。`~/.claude/settings.json`、`~/.claude/skills`、`~/.claude/plugins` 启动前后不变，Harp 进程没有打开 `~/.claude` / `~/.codex` 下的文件（`lsof`）
- changelog 面板只显示安装说明，见上

## 建议下一步
1. 下一个正式版出来后复查 `/releases/latest` 指向它、版本模式读得出、资产名仍是 `Harp-<version>.dmg`。

## 如何复验
```
gh release view v0.1.1 -R dominikmartn/harp --json assets -q '.assets[]|.name+" "+.digest'
swift run --package-path application-test feed-discover Harp-0.1.0.dmg     # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify Harp-0.1.0.dmg    # → stable，winning source GitHub，UPDATE → 0.1.1
swift run --package-path application-test channel-verify Harp-0.1.1.dmg    # → up to date
codesign -dvv /Volumes/Harp/Harp.app 2>&1 | grep TeamIdentifier           # → 423S87ZC86
lipo -archs /Volumes/Harp/Harp.app/Contents/MacOS/warp-oss                # → arm64
```
