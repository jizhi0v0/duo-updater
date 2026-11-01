# Super Productivity

## 基本信息
- App: Super Productivity — Electron 时间记录 / 待办应用（`super-productivity/super-productivity`，MIT）
- Bundle ID: `com.super-productivity.app`
- Team ID: `363FAFK383`（Developer ID Application: Johannes Millan）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 19.3.1（tag `v19.3.1`，资产 `superProductivity-arm64.dmg`，147832257 字节）；prerelease 18.0.0-rc.0（tag `v18.0.0-rc.0`，同资产名，123334055 字节）；观测于 vmpal「macOS VM 1」（macOS 27.2），2026-11-01
- 自更新机制: `Contents/Resources/app-update.yml` = `provider: github` / 本仓库 / `updaterCacheDirName: superproductivity-updater`；应用代码里有 `autoUpdater.quitAndInstall()`，并读 `api.github.com/repos/super-productivity/super-productivity/releases/latest`；Homebrew cask 是 `auto_updates true`，所以它自己会下载并在退出时装
- 分发: GitHub Releases（arm64 / x64 两个 dmg + blockmap）；Homebrew cask `super-productivity`（auto_updates）；Mac App Store 有同 id 的 Super Productivity 19.3.1（商店副本由 App Store 更新）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（auto_updates，让位） | —（商店副本） | ✓ 一键 arm64 dmg | — |
| **beta**   | —       | —        | —   | —（见「Channel 详情」） | — |

当前生效源: **GitHub**（`duo check` 实测；`duo verify --only com.super-productivity.app` 的 rule 与 changelog 都 ✓）

## 覆盖清单
- 真包（都读自 dmg）:
  - v19.3.1 arm64: `com.super-productivity.app`，Team 363FAFK383，Notarized，两个版本键都是 19.3.1，`LSMinimumSystemVersion` 13.0
  - v18.0.0-rc.0 arm64: 同 id、同 Team，两个版本键都保留后缀 `18.0.0-rc.0`，`LSMinimumSystemVersion` 11.0
- 嵌套: `Contents/Frameworks/Super Productivity Helper{, (GPU), (Plugin), (Renderer)}.app`，都是 Electron 子进程；没有 LoginItems、LaunchAgent、root helper
- 其他轨: prerelease tag 都带后缀（`v18.0.0-rc.0`、`v17.0.0-RC.13`、`v15.1.3-rc.0`），包内版本也保留后缀；最新 100 个 release 里 7 个 prerelease，全部早于当前 stable
- 主机下限: 只取 arm64 资产（我们的 app 是 arm64）；`LSMinimumSystemVersion` 13.0 / 11.0，均低于我们的下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.super-productivity.app` | — | 版本纯数字 | `/releases/latest`（GitHub 排除 prerelease） | ✓ |
| beta    | 同 id | 共享 | 版本带 `-rc.N` / `-RC.N`（`ReleaseChannel.detect` 第 4 步不认这个形状，副本读成 stable） | 没有 beta rule：tag 形状本来就不同，stable 的整串锚定 pattern 不会匹配 | —（`-rc` 副本按 stable 毕业，安全） |

## 更新检测
- 源: `super-productivity/super-productivity` GitHub Releases，`/releases/latest`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$` — **必须整串锚定**：默认的 `v?(\d+(\.\d+)+)` 会从 `v18.0.0-rc.0` 里读出一个 18.0.0，把两年前的候选当成「最新」
- `installAssetPattern` `^superProductivity-arm64\.dmg$`；同 release 的 `-x64.dmg`、`.blockmap`、`latest-mac.yml` 都不匹配
- `duo check`（2026-11-01，vmpal）: 18.0.0-rc.0 → `update 19.3.1`，route `in-place`，source `GitHub`；19.3.1 副本 up-to-date

## 按架构 / 按 OS 分轨
- arm64 / x64 各一个 dmg；rule 只装 arm64。`LSMinimumSystemVersion` 13.0（19.x）/ 11.0（18.x）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-builder `.blockmap`） | 有 | 不需要 |
| 证据 | 每个 dmg 旁有 `.blockmap`，`app-update.yml` 是 electron-builder 的格式 | v19.3.1 资产列表 | 我们整包下载 dmg，用 GitHub `digest` 校验 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（auto_updates） | 2026-11-01 运行轮里，启动后的 19.3.1 副本自身没有可下载的更新；18.0.0-rc.0 副本启动后由 duo 抢先装完，没有观察到它自己的 `pending/` 暂存 | `SelfUpdaterStash` 认 `superproductivity-updater`；这次没有暂存可拿 |
| 证据 | `app-update.yml` 的 `updaterCacheDirName`；cask `auto_updates true` | vmpal 两轮 | — |

## Changelog
- 来源: GitHub release 正文（`GitHubMarkdownParser`，`.gitHubReleases`）
- 结构化: 19.3.1 的正文是 `### Improvements`（3 条）/ `### Fixes`（6 条）/ `### Desktop fixes`（2 条），加 `### Contributors`；面板 11 条，标题保留，`Contributors` 由 `skipSections` 丢掉，`**Full Changelog**` 比较链接由 parser 丢掉
- 跟随 channel: 只有 stable
- Recipe 状态: 已有（skipSections: ["Contributors"]）

## 一键安装
- 状态: 支持（arm64 dmg，Team 闸 + GitHub digest）
- 端到端（2026-11-01，vmpal「macOS VM 1」，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 18.0.0-rc.0 → `duo install "Super Productivity" --yes` → `outcome installed`，`bytesDownloaded 147832257`；盘上 19.3.1，Team 363FAFK383，codesign / spctl 通过
  - 第二轮（运行中）: 18.0.0-rc.0 从 GUI 启动（pid 90562）→ `duo install` 装成 19.3.1 → `duo restart "Super Productivity"` 成功（pid 90562 → 90712，输出 "Super Productivity restarted"），新版本在跑
  - 终态: 19.3.1，`duo check` 报 up-to-date
- 校验: 资产 `sha256:ccbddcf82dabd677a0daa8d2fee73d7a004d01057e3eb585229de93842924707`

## 已知问题
- **`-rc.N` 副本被读成 stable**（`ReleaseChannel.detect` 第 4 步不认 `-rc`）：它们会被当作正式版，拿到 19.3.1 毕业；在正式版之前看不到更新的 rc。方向安全，不降级、不跨轨
- 运行中的 `duo restart` 要求副本是从 GUI 会话启动的：同一份 app 若是在 agent 的 shell 里 `open` 的，它没有窗口，退出确认永远等不到，restart 会卡住。VM 里的两轮最终都用 Finder 启动的副本跑通
- App Store 副本与 GitHub 副本同 id（商店版 19.3.1）；商店副本由 App Store 更新

## 如何复验
```bash
curl -L -o /tmp/sp.dmg https://github.com/super-productivity/super-productivity/releases/download/v19.3.1/superProductivity-arm64.dmg
hdiutil attach -readonly /tmp/sp.dmg && codesign -dv --verbose=4 "/Volumes/Super Productivity/Super Productivity.app"
duo verify --only com.super-productivity.app
duo check --all --json | grep super-productivity
duo install "Super Productivity" --yes --json
```
