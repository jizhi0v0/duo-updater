# DiffusionBee

## 基本信息
- App: DiffusionBee — 本地跑 Stable Diffusion / Flux 出图的 Electron app（Vue 前端 + `Contents/Resources/core` 里的 Python 后端）
- Bundle ID: `com.diffusionbee.diffusionbee`（1.7.4 起）；0.1.0–1.5.2 是 `com.linerai.liner`，见「覆盖清单」
- 仓库: `divamgupta/diffusionbee-stable-diffusion-ui`（默认分支 `master`，最后推送 2024-10-30；`master` 上 `electron_app/package.json` 停在 2.3.0，2.4 起的源码没有推上来，2.x 的行为以真包里的 `app.asar` 为准）
- Team ID: `6QF6Z7X8UW`（1.5.2、1.7.4、2.5.1、2.5.2、2.5.3 五个真包一致，都 `spctl` Notarized Developer ID）
- 观测版本: 2.5.3（`CFBundleVersion` 2.5.3，2024-08-14）；上一正式版 2.5.1；2.5.2 是 GitHub prerelease；观测日期: 2026-10-22
- 自更新机制: **只提示**。2.5.3 `app.asar` 的 `check_for_updates()` 请求 `checkupdates.diffusionbee.com/check_diffusionbee_updates?user_id=…`，取响应里 `版本_构建号` 的构建号和自己比，大就弹 `native_confirm`（「A new version of DiffusionBee is available. Do you want to visit https://diffusionbee.com to update?」），点了只打开官网。不下载、不暂存、不替换。该端点 2026-10-22 应答 `1.7.4_0024`，所以 2.x 副本永远不会被它提示
- 分发: GitHub Releases（Homebrew cask `diffusionbee` 指向 GitHub 的 2.5.3 arm64 dmg，无 `auto_updates`）。官网 `diffusionbee.com/download` 2026-10-22 仍链接 **2.5.1** 的两个 dmg（GitHub 上的同一资产），没有链 2.5.3。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | （cask 存在，非本次） | —   | ✓      | ✗           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 对 2.5.1 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。VendorProbe ✗：厂商自己的检查端点冻结在 1.7.4，读它只会得到错的版本。

## 覆盖清单
- **各版本的 bundle id / Team**（读真包）:
  - 2.5.3、2.5.2、2.5.1、1.7.4: `com.diffusionbee.diffusionbee`，Team `6QF6Z7X8UW`
  - 1.5.2: `com.linerai.liner`，`CFBundleName=DiffusionBee`，Team `6QF6Z7X8UW`
  - 源码佐证（`electron_app/vue.config.js` 的 `appId`，按 tag 读）: 0.1.0、0.2.0、0.3.0、1.0.0、1.3.1、1.4.2、1.4.3、1.5.1、1.5.2 都是 `com.linerai.liner`；提交 `3b5e2744`（2023-04-28「update to 1.5, better logging, build conf json」）改成 `com.diffusionbee.diffusionbee`，1.7.4（2023-04-29）起一直是它
- **旧 id `com.linerai.liner` 的副本（0.1.0–1.5.2）: 缺口，有意不接。** 同一开发者的另一个产品 Liner.ai（`linerai/releases`，ML 训练工具）也用 `com.linerai.liner`：真包 `Liner-0.2.0.0004-arm64.dmg` 读出 `CFBundleIdentifier=com.linerai.liner`、`CFBundleName=Liner`、`CFBundleShortVersionString=0.2.0`、Team `6QF6Z7X8UW`，自带 electron-updater（`divamgupta/liner-electron-app`）。版本还重叠（两边都有 0.1.0、0.2.0）。`BundleIDMigration` 只按 id + Team + 版本上界认副本，加一条 `com.linerai.liner → com.diffusionbee.diffusionbee` 会把 Liner 的副本当成旧 DiffusionBee，给它推 DiffusionBee、一键还会用 DiffusionBee 替换 Liner（Team 相同，闸拦不住）。能区分两者的只有 `CFBundleName`，现有机制都不读它，所以记成缺口
- **其他轨**: 只有 stable。2.5.2、2.3.0 在 GitHub 上标了 prerelease，和正式版同 id、同资产命名，版本号是普通的 `X.Y.Z`；2.2.1 的 release 名写「( Beta )」但没标 prerelease。三者都已被更高的正式版超过，副本被判成 stable 后推 2.5.3 是对的（2.5.2 实测，见「如何复验」）。仓库里没有 nightly 构建
- **`weights` tag**: 2022-09-08 发布，资产是 `clip_tokenizer.zip`（546842 B）和 `clip_transformer.zip`（341284588 B），是模型权重，不是 app。版本模式不读它，有意如此
- **1.5.2 / 1.5.1 / 1.4.3（以及 1.4.2）没有匹配资产**: 这些 release 的资产名是旧格式（`DiffusionBee-1.5.2-arm64_MPS_SD1.5_FP16.dmg`、`…arm64_TF_SD1.4_FP32.dmg`、`…intel_MPS_SD1.5_FP16.dmg`），不是「没有 mac 包」。它们都属于 `com.linerai.liner` 时期，规则读 `/releases/latest`，碰不到它们
- **版本范围、主机下限**: `LSMinimumSystemVersion` 2.5.x 是 12.4.0、1.7.4 是 11.0.0；cask 写 `depends_on macos >= 13`（2.5.3 说明里 Flux 要 macOS 13+）。都低于 DuoUpdater 的 15.0（`App/project.yml`），不需要 OS 门控
- **架构**: 每个 2.x release 有 `DiffusionBee_MPS_arm64-<v>.dmg` 和 `DiffusionBee_MPS_Intel-<v>.dmg`（2.3.0 只有 arm64）。DuoUpdater 只出 arm64（`ARCHS: arm64`），规则只装 arm64 那个，Intel 包不需要门控

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.diffusionbee.diffusionbee` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `divamgupta/diffusionbee-stable-diffusion-ui` GitHub Releases，`/releases/latest`（2026-10-22 指向 2.5.3）
- 版本: tag `2.5.3` → `^([0-9]+(?:\.[0-9]+)+)$` → `2.5.3`，等于 `CFBundleShortVersionString`。22 个 app tag 全部读出，`weights` 不读；`3.0.0`、`3.0` 读出，`2.6.0-beta`、`2.6.0-rc.1` 不读。厂商从没用过 `v` 前缀，`v2.6.0` 不读
- 注意: 官网下载页落后于 GitHub（停在 2.5.1）。GitHub 把 2.5.3 标为 Latest、非 prerelease，cask 也装 2.5.3，所以以 GitHub 为准

## 按架构 / 按 OS 分轨
- 分架构资产（arm64 / Intel 两个 dmg），规则用资产名选 arm64；2.5.1、2.5.2、2.5.3 的主程序都只有 arm64（`check-bundle.sh` 的 `archs=arm64`）
- `LSMinimumSystemVersion` 12.4.0（2.5.1–2.5.3）；release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `app.asar` 里没有 `autoUpdater` / `electron-updater`（`grep -c` 都是 0），bundle 里没有 `app-update.yml` | 每个 release 只有两个整包 dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 2.5.1 约 50 s，没有停放任何东西） | 不需要 |
| 证据 | `check_for_updates()` 只弹框、打开官网，不下载（见「基本信息」） | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 2.5.1 起）: `source structured: 1 entries; newest 2.5.3: 6 items, headings []; first items ["Support for Flux.1 image generation mode", "To use flux, scroll down to the bottom i", "Support for external textual inversion e"]`
- 厂商正文没有小标题，`headings []` 不是被压平。2.5.3 正文里「To use flux, scroll down…」是 Flux 那一条下面缩进的子项，面板把它当成并列的第 2 条显示
- `release history 1 entries`：从 2.5.1 到 2.5.3 之间只有 2.5.2 一个 release，它是 prerelease，不计入
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
  - 第一轮（不运行）: 2.5.1 → `duo check` `2.5.1 → 2.5.3 [GitHub, in-place]` → `duo install` `downloading… extracting verifyingCodeSignature installing done installed.` → 2.5.3、可执行文件 inode 变、`TeamIdentifier=6QF6Z7X8UW`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted（Notarized Developer ID）、`diff -r` 与厂商 2.5.3 包相同
  - 第二轮（运行中）: 启动 2.5.1（主进程 + 4 个 helper + `core/diffusionbee_backend`），`duo install` 后提示 `Still running the old code`；`duo restart DiffusionBee` 后旧后端（pid 56423）退出，只剩新版主进程和新后端（13:01:30 / 13:01:33 启动），磁盘 2.5.3、签名有效
- 格式: dmg（`hdiutil imageinfo` `Format: UDZO`，2.5.1 / 2.5.3 相同），根目录 `DiffusionBee.app` + `Applications` 软链。Pattern `^DiffusionBee_MPS_arm64-[0-9]+(?:\.[0-9]+)+\.dmg$`，kind `.dmg`
- 嵌套（2.5.3）: 只有 Electron 自带的四个 `Contents/Frameworks/DiffusionBee Helper*.app`（`LSUIElement=true`，随主进程起落）；没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent。`app.asar` 里 `setLoginItemSettings` / `openAtLogin` / `LaunchAgents` 都是 0 次
- 签名: 2.5.1、2.5.2、2.5.3 都是 `TeamIdentifier=6QF6Z7X8UW`，`codesign --verify` 通过，`spctl` Notarized Developer ID。上一版和最新版 Team 相同，旧副本不会被 Team 闸拒
- 校验: 资产没有 GitHub `digest`（2024 年上传，早于 GitHub 2025-06 开始给资产算 digest），只靠 Team-ID 闸
- **读的是**: 人人可手动下载的 GA（GitHub Releases 页的 Latest，cask 也装它）
- 阻塞: 无

## 已知问题
- **首次使用会下载很大的模型。** 默认模型 `SDB_0.1.tdict` 从 `huggingface.co/divamgupta/stable_diffusion_mps` 下载，2026-10-22 `content-length` 2440763520 B（约 2.4 GB），存进 `~/.diffusionbee`；回退地址 `models.diffusionbee.com`。从 `app.asar` 静态读没找到首启自动触发下载的调用点（真机核对：启动、运行中换包、重启，全程没碰界面，`~/.diffusionbee` 只有 8 KB，没有触发下载）
- **启动时把自己设成 `diffusionbee://` 的默认处理者**（`app.setAsDefaultProtocolClient("diffusionbee")`，`app.asar`），用来处理 `huggingface_sd_model/…` 深链
- **数据目录在 `~/.diffusionbee`**（导入的模型 `imported_models/`、图片 `inp_images/`），cask 的 `zap` 也列了它和 `~/Library/Application Support/DiffusionBee`
- **运行中替换时的 Python 后端**: 主进程用 `Contents/Resources/core` 里的后端起子进程，`window-all-closed` 时 `kill` 它（`app.asar`）。真机核对：`duo restart` 时旧后端随主进程一起退出，没有残留
- 旧 id `com.linerai.liner` 的副本不检测，见「覆盖清单」

## 建议下一步
1. 若要覆盖 `com.linerai.liner` 时期的 DiffusionBee，需要一种能按 `CFBundleName`（`DiffusionBee` vs `Liner`）区分的迁移条件；现有 `BundleIDMigration` 做不到，属于引擎改动，先不做。
2. 厂商下一个版本出来后复查 tag 仍是裸 `X.Y.Z`、资产名仍是 `DiffusionBee_MPS_arm64-<v>.dmg`。

## 如何复验
```
gh release list -R divamgupta/diffusionbee-stable-diffusion-ui --limit 30
gh release view weights -R divamgupta/diffusionbee-stable-diffusion-ui --json assets -q '.assets[].name'   # → clip_tokenizer.zip, clip_transformer.zip
curl -sIL <资产 URL> | grep -i content-length                                   # 2.5.3 arm64: 291305301；2.5.1 arm64: 263986706
.claude/skills/coverage-discovery/scripts/check-bundle.sh DiffusionBee_MPS_arm64-2.5.3.dmg   # → com.diffusionbee.diffusionbee, 6QF6Z7X8UW, Notarized
.claude/skills/coverage-discovery/scripts/check-bundle.sh DiffusionBee-1.5.2-arm64_MPS_SD1.5_FP16.dmg   # → com.linerai.liner
.claude/skills/coverage-discovery/scripts/check-bundle.sh Liner-0.2.0.0004-arm64.dmg               # → com.linerai.liner, CFBundleName=Liner
swift run --package-path application-test feed-discover DiffusionBee_MPS_arm64-2.5.1.dmg               # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify DiffusionBee_MPS_arm64-2.5.1.dmg --expect stable   # → GitHub，UPDATE → 2.5.3
swift run --package-path application-test channel-verify DiffusionBee_MPS_arm64-2.5.2.dmg --expect stable   # → stable，UPDATE → 2.5.3
swift run --package-path application-test channel-verify DiffusionBee_MPS_arm64-2.5.3.dmg --expect stable   # → up to date
curl -s 'https://checkupdates.diffusionbee.com/check_diffusionbee_updates?user_id='                    # → 1.7.4_0024
```
