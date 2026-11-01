# LosslessCut

## 基本信息
- App: LosslessCut — Electron 视频剪切/合并工具（`mifi/lossless-cut`，MIT，仓库未归档）
- Bundle ID: `no.mifi.losslesscut-mac`
- Team ID: `46F6T3M669`（Developer ID Application: Mikael Finstad）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.70.2（tag `v3.70.2`，资产 `LosslessCut-mac-arm64.dmg`，165792537 字节）；prerelease 3.70.0（tag `v3.70.0`，同名资产，165848325 字节）；观测于 vmpal「macOS VM 1」（macOS 27.2），2026-11-01
- 自更新机制: 包里有 electron-builder 的 `Contents/Resources/app-update.yml`（provider github，`mifi/lossless-cut`，`updaterCacheDirName: lossless-cut-updater`）和 `Squirrel.framework`，但真包的 `app.asar` 里没有 `checkForUpdates` / `setFeedURL` / `electron-updater` 任何调用；Homebrew cask 也不是 `auto_updates`。两份真包都没有自行检查、下载或停放更新的代码路径
- 分发: GitHub Releases（每个 release 有 arm64 / x64 两个 dmg、一个标着 `DONT-USE-THIS-FILE` 的 universal pkg，以及 `latest-mac.yml` / `.blockmap`）；Homebrew cask `losslesscut`（3.70.2，非 auto_updates）；Mac App Store 有同 id 的 LosslessCut 1.14（商店副本由 App Store 自己更新，不走这条 rule）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（非 auto_updates） | —（商店副本） | ✓ 一键 arm64 dmg | — |
| **beta**   | —       | —        | —   | —（prerelease 副本按 stable 毕业，见下） | — |

当前生效源: **GitHub**（`duo check` 实测；`duo verify --only no.mifi.losslesscut-mac` 的 GitHub rule 与 changelog 都 ✓）

## 覆盖清单
- 真包（都读自 dmg）:
  - v3.70.2 arm64: `no.mifi.losslesscut-mac`，Team 46F6T3M669，Notarized，`CFBundleShortVersionString` = `CFBundleVersion` = 3.70.2，`LSMinimumSystemVersion` 12.0
  - v3.70.0（prerelease）arm64: 同 id、同 Team、同版本方案，版本 3.70.0
- 嵌套: `Contents/Frameworks/LosslessCut Helper{, (GPU), (Plugin), (Renderer)}.app`，都是 Electron 自己的子进程；没有 `Contents/Library/LoginItems`、LaunchAgent、root helper、系统扩展
- 其他轨: **prerelease 与正式版同名同形**。最新 100 个 release 里 26 个标了 `prerelease: true`，tag 和正式版一样是 `vX.Y.Z`（v3.70.0、v3.65.0、v3.61.0…），资产名也相同，包里版本号同样是纯数字（3.70.0）
- 版本范围: 每个 prerelease 之后的第一个正式版都更高（3.70.0 → 3.70.1；3.65.0 → 3.66.1；3.17.27 → 3.21.0）。所以装着 prerelease 的副本按 stable 读，拿到的是它的「毕业版」，不会被降级
- 主机下限: 资产只取 `arm64`，与 `App/project.yml` 的 arm64 一致；`LSMinimumSystemVersion` 12.0，低于我们的下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `no.mifi.losslesscut-mac` | — | `CFBundleShortVersionString` 纯数字 | `/releases/latest`（GitHub 排除 prerelease） | ✓ |
| beta    | 同 id | 共享 | 无本地信号 | 没有 beta rule：`/releases/latest` 本来就不含 prerelease，列表按新到旧、同形 tag 无法只挑 prerelease | —（prerelease 副本按 stable 处理，见「已知问题」） |

## 更新检测
- 源: `mifi/lossless-cut` GitHub Releases，`/releases/latest`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（整串锚定，`v3.70.0` 与 `v3.70.2` 都读得出）
- `installAssetPattern` `^LosslessCut-mac-arm64\.dmg$`；同 release 的 `-x64.dmg`、`…DONT-USE-THIS-FILE.pkg`、`.blockmap`、`latest-mac.yml` 都不匹配
- `duo check`（2026-11-01，vmpal）: 3.70.0 → `update 3.70.2`，route `in-place`，source `GitHub`；装在盘上的 3.70.2 副本读 up-to-date
- 最新 release 若没有 arm64 dmg，rules 会退到列表并最多走过 5 个无资产的 release；仍找不到就报 miss（不会把更老的版本当成「最新」）

## 按架构 / 按 OS 分轨
- arm64 与 x64 各一个 dmg；rule 只装 arm64（我们的 app 本身 arm64）。`LSMinimumSystemVersion` 12.0

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-builder 的 `.blockmap`） | 有（每个 dmg 旁有 `.blockmap`） | 不需要 |
| 证据 | 产物里有 `*.dmg.blockmap` / `latest-mac.yml`，但 `app.asar` 不调用任何 updater API | v3.70.2 资产列表 | blockmap 只是 electron-updater 的分块下载优化；我们整包下载 dmg，用 GitHub `digest` 校验 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | — |
| 证据 | `app.asar` 没有 updater 调用；cask 非 auto_updates；两轮真机验证里没有出现暂存文件 | 2026-11-01 vmpal 两轮 | 没有可拿的 |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`（`.gitHubReleases`，`tagPattern` 同 stable）
- 结构化: 3.70.2 的正文是 5 条 `- …`（无标题），最后一行 "See [3.70.0] … for the full list of changes."；面板显示 5 条、`headings []`
- 跟随 channel: 只有 stable；`.gitHubReleases` 的 stable 频道按 GitHub 的 `prerelease` 位过滤，所以 prerelease 的正文不会出现在面板里（它们的 tag 形状与 stable 相同，只能靠这个位区分）

## 一键安装
- 状态: 支持（arm64 dmg，Team 闸 + GitHub digest）
- 端到端（2026-11-01，vmpal「macOS VM 1」，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 3.70.0 → `duo install LosslessCut --yes` → `outcome installed`，`bytesDownloaded 165792537`；盘上 3.70.2，Team 46F6T3M669，`codesign --verify --deep --strict` 通过，spctl Notarized Developer ID
  - 第二轮（运行中）: 3.70.0 在跑（pid 85258 等），`duo install` 装成 3.70.2，输出 "Still running the old code"；`duo restart LosslessCut` 换 pid（85258 → 85619），版本 3.70.2
  - 终态: 3.70.2，`duo check` 报 up-to-date
- 校验: 资产 `sha256:3c0e2b3ec25fec66cf0cef343450d9a333e4bba5d64456c34cd18e891a3f5947`，与下载文件大小一致

## 已知问题
- **prerelease 副本没有本地标记**：tag 同形、版本纯数字，`installedTagPrefix` 这类「按精确 tag 证轨道」的机制也无法区分（同形 tag 的 prerelease 只有 GitHub 的 `prerelease` 位知道）。所以装着 prerelease 的副本被当作 stable，只能等毕业；在下一版正式补丁之前看不到更新的 prerelease。方向是安全的：不会被推旧版，也不会被跨轨覆盖
- App Store 副本与 GitHub 副本同 id（商店版 1.14）；商店副本由 App Store 更新，不走这条 rule

## 如何复验
```bash
# 真包
curl -L -o /tmp/lc.dmg https://github.com/mifi/lossless-cut/releases/download/v3.70.2/LosslessCut-mac-arm64.dmg
hdiutil attach -readonly /tmp/lc.dmg && codesign -dv --verbose=4 /Volumes/LosslessCut*/LosslessCut.app
# 规则
duo verify --only no.mifi.losslesscut-mac
# 一键（装一个旧版后）
duo check --all --json | grep losslesscut
duo install LosslessCut --yes --json
```
