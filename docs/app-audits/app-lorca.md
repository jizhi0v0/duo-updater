# Lorca

## 基本信息
- App: Lorca — egoist 的单人 + agent 端到端加密聊天客户端；Mac app 内带一份 `lorca` CLI（`Contents/Resources/bin/lorca`），由 app 自己起 `lorca serve --port 4862`
- Bundle ID: `app.lorca`（debug 构建 `app.lorca.dev`，不发布）
- 仓库: `egoist/lorca`（开源，GPL-3.0）
- Team ID: `GJE9R5VE87`，Developer ID + 公证（1.0.10 / 1.0.11 真包 `spctl` = Notarized Developer ID）
- 观测版本: 1.0.11（2026-10-09）
- 自更新机制: Sparkle 2（`SUFeedURL` = `https://mac-releases.lorca.app/appcast.xml`，`SUEnableAutomaticChecks` = true，未设 `SUAutomaticallyUpdate`）
- 分发: 只有官网 dmg（`mac-releases.lorca.app/Lorca-<ver>.dmg`，R2）。无 Homebrew cask、无 MAS
- 另有独立分发的命令行版 `lorca`（`lorca.app/install-cli.sh` → `~/.local/bin/lorca`）：不是这个 bundle，见 `CLITools/Lorca*.swift`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | —        | —   | —      | —           |

当前生效源: **Sparkle**（`feed-discover` = `declared`；`channel-verify` winning source = Sparkle）。

## Channel 详情
单轨。settled from source: `scripts/release-mac.ts`（main）只生成一个 appcast，无 `<sparkle:channel>`；feed 3 个 item 全部无标签。

## 更新检测
- 源: `SparkleAppcastSource`，读 bundle 自带的 `SUFeedURL`，无需 recipe
- 版本方案: short == build（1.0.10 / 1.0.11），`release-mac.ts` 要求 `^\d+\.\d+\.\d+$`
- OS 下限: 每个 item 带 `sparkle:minimumSystemVersion` 14.0，与 bundle 的 `LSMinimumSystemVersion` 14.0 一致；无上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能 |
| 证据 | Sparkle 2 framework | 2026-10-09 appcast：1.0.11 item 带 5 个 `<sparkle:deltas>`（自 1.0.6–1.0.10） | 真机 `duo install` 1.0.10→1.0.11 下载 7,901,142 字节 = `Lorca1.0.11-1.0.10.delta` 的 length |

## Changelog
- 来源: appcast 无 inline notes，只有 `<sparkle:releaseNotesLink>` → `Lorca-<ver>.md`（`text/markdown`，由 `release-mac.ts` 从仓库 `CHANGELOG.md` 抽出该版本一节）
- 没有 recipe 时 pane 走 `web page … no structure`，Markdown 原样显示（`- `、反引号都是字面）
- 现在: `ChangelogRecipe`（`Recipes/app-lorca.swift`），`sourceTemplate` = `Lorca-{version}.md`、`versionFromTemplate`
- 结构化（2026-10-09，channel-verify `changelog pane`）: `recipe changelog:app.lorca:-: 1 entries; newest 1.0.11: 1 items, headings []`；装好的 app 里 Release Notes 显示「1.0.11」标题 + 一条列表项，反引号已去
- 只有 1.0.11 有 `.md`（1.0.10、1.0.9 → 404）；不用仓库 `CHANGELOG.md` 是因为 1.0.11 以下各节标的是 `[0.1.10]`、`[0.1.9]`，与 app 版本对不上
- 跟随 channel: 不适用（单轨）

## 一键安装
- 状态: **支持**（Sparkle 路线，增量包）
- 读的是: 人人可手动下载的 GA（官网 dmg 与 appcast 是同一个版本）
- 端到端（2026-10-09）:
  - 不运行: 1.0.10 → `duo check` `[Sparkle, in-place]` → `duo install --yes --json` `installed`（6 s，7,901,142 字节）→ 1.0.11、inode 变、`codesign --verify --deep --strict` 通过、Notarized、Team 不变；与厂商 `Lorca-1.0.11.zip` 逐文件 sha256 一致（64 个文件）；`duo backups` 有 1.0.10 备份
  - 运行中: 重装 1.0.10 并启动；它的 Sparkle 启动即检查并弹出更新窗口，未自行下载（未设自动更新，暂存目录为空）→ `duo install` `installed`（5 s）→ `duo restart Lorca` → app 与它带起的 `lorca serve` 都换成新进程，之后 10 s 磁盘版本保持 1.0.11
  - 未覆盖: 「暂存旧于目标版本」那种撞车，要厂商 feed 里有比目标更旧的可暂存版本才能造出来
- 嵌套: `Contents/Resources/bin/lorca`（app 自己的 CLI，随 app 重启而重启）、Sparkle 的 `Updater.app`

## 已知问题
- app 运行时它的 `lorca serve` 占着 4862，而命令行版 `lorca update` 默认把更新交给 4862 上的 serve；app 那份会拒绝（`Error: Lorca on This Device updates with the app that installed it.`，exit 1，2026-10-09 实测）。命令行版的一键因此在检测到 app 的 serve 时改用 `--port <空闲端口>`（`LorcaActivity.appServe`），绕开它直接替换自己的文件
- app 与命令行版共用 `~/.lorca`（含 `settings.json` 的 `auto_update`）

## 如何复验
```
swift run --package-path application-test feed-discover Lorca-1.0.11.dmg            # → declared
swift run --package-path application-test channel-verify Lorca.app                 # 1.0.10 → UPDATE → 1.0.11，changelog pane = recipe
```
