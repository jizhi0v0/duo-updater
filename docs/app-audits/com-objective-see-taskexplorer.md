# TaskExplorer

## 基本信息
- App: TaskExplorer — Objective-See 的进程浏览器（进程、签名、dylib、文件、网络连接，3.x 内置 AI 助手），开源
- Bundle ID: `com.objective-see.taskexplorer`（3.x）；2.x 是 `com.objective-see.TaskExplorer`（见「旧 bundle id」）
- 仓库: `objective-see/TaskExplorer`（默认分支 `main`）；产品页 `https://objective-see.com/products/taskexplorer.html`
- Team ID: `VBG97UB4TA`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID（2.1.0、3.0.0、3.1.0 三个真包）
- 观测版本: 3.1.0（tag `v3.1.0`，资产 `TaskExplorer_3.1.0.zip`）；观测日期: 2026-10-20
- 自更新机制: 自研，只提示不安装。settled from source: `App/Update.m` on `main` 读
  `https://objective-see.com/products.json` 的 `TaskExplorer.version`，与 `getAppVersion()` 做 `NSNumericSearch` 比较；
  只在菜单「Check for Updates…」手动触发（`AppDelegate.check4Update`），有新版就弹窗、点 Update 打开产品页。不下载、不替换 bundle
- 分发: GitHub Releases，每个 release 一个 universal `TaskExplorer_<ver>.zip`（`release.sh` 产出，签名 + 公证 + staple）。
  `products.json` 的 `zip` 指向同一个 GitHub 资产（观测: `version` `3.1.0`）。Homebrew cask `taskexplorer`
  （`auto_updates` 未设，`depends_on macos >= 14`）；MAS 搜不到

## 覆盖清单（Coverage checklist）
- **bundle id**: 读了全部 3 个 release 的 Info.plist。2.1.0 = `com.objective-see.TaskExplorer`，3.0.0 / 3.1.0 =
  `com.objective-see.taskexplorer`，只差大小写。规则按 bundle id 精确匹配（`GitHubReleasesSource` 用
  `Dictionary(grouping:by: \.bundleID)`），所以 2.x 副本要 `BundleIDMigration` 才能找到规则，已加（Picard 同款大小写改名）
- **发布轨**: 只有 stable。3 个 release 都不是 pre-release；app 里没有 beta 开关（`Update.m` 只读一个 `version`）
- **版本范围**: 2.1.0 / 3.0.0 / 3.1.0 的 Team 都是 `VBG97UB4TA`（**实测**，`check-bundle.sh`），Team 闸不拒旧副本
- **宿主下限**: 3.x `LSMinimumSystemVersion` = `14.0`，2.1.0 = `11.5`，都低于我们的下限（`App/project.yml` macOS 15.0），不需要 `hostRequirement`
- **版本 pattern**: `^v([0-9]+(?:\.[0-9]+)+)$`。3 个 tag 都是 `vX.Y.Z`；单测覆盖 3 个 tag、`v4.0`、`v3.2.0-beta.1`（不读）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（brew 装的副本） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测）。brew 装的副本由 `HomebrewCaskSource` 先答（cask 不是 `auto_updates`）。
`feed-discover` 给出 `no Sparkle, no electron-builder update config and no MyGo feed`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.objective-see.taskexplorer` | — | — | `/releases/latest` | ✓ |

## 更新检测
- 源: `objective-see/TaskExplorer` GitHub Releases，`/releases/latest`
- 版本方案: tag 去 `v`，与 `CFBundleShortVersionString`、`CFBundleVersion` 相同（3 个真包核对）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^TaskExplorer_[0-9]+(?:\.[0-9]+)+\.zip$`
- 与 app 自己的检查一致: `products.json` 的 `TaskExplorer.version` 观测为 `3.1.0`，与 `/releases/latest` 相同

## 旧 bundle id
- 2.1.0 的 zip 是 `com.objective-see.TaskExplorer`（2025-04-30），3.0.0 起是 `com.objective-see.taskexplorer`，同 Team，
  中间没有别的 release。`BundleIDMigration(from: com.objective-see.TaskExplorer, to: com.objective-see.taskexplorer,
  lastFromVersion: 2.1.0, firstToVersion: 3.0.0)`
- 不标 `isRewrite`: 2.1.0 自己的 `Update.m`（tag `v2.1.0`）读同一个 `products.json` 键，现在答 3.1.0，厂商把 3.x 当普通更新推给 2.x。
  3.0.0 的 release 正文说是 "a near complete rewrite"（Endpoint Security 系统扩展取代 2.x 的 XPC helper），
  首次启动会走欢迎窗口、要批准系统扩展和完全磁盘访问
- channel-verify 实测 2.1.0 副本: bundle id `com.objective-see.TaskExplorer`，winning source GitHub，`UPDATE → 3.1.0`

## 按架构 / 按 OS 分轨
- 架构: `x86_64 arm64`（单个 universal zip）；`LSMinimumSystemVersion`: 14.0（3.x）
- release 不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `Update.m` 只比较版本号、不下载；bundle 里没有 `Frameworks/`（3.1.0） | 每个 release 只有一个完整 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（运行中一轮未跑） | — |
| 证据 | `Update.m` 不下载任何东西（源码） | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-20，channel-verify `changelog pane`，3.1.0）: `source structured: 1 entries; newest 3.1.0: 5 items,
  headings []; first items ["You can now sponsor **TaskExplorer**/**O", "🦙 Native Ollama support: the AI assistan",
  "🧹 Exited processes are no longer shown: "]`
- 赞助行进了条目（第 1 条）；`## TaskExplorer v3.1.0` 没留成小标题。正文是 KnockKnock / LuLu 同款 emoji 行，
  解析器通用行为。后两条是什么没看到（channel-verify 只打印前 3 条）
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（按 Team 闸）
- 端到端: ✓ 3.0.0 → 3.1.0，app 不运行（2026-10-20）。`duo install` 依次走 `verifyingSignature` → `extracting` →
  `verifyingCodeSignature` → `installed`；装后 `com.objective-see.taskexplorer` 3.1.0、Team `VBG97UB4TA`、
  `codesign --verify --deep --strict` 为 0、`spctl` Notarized Developer ID，`duo check` 报 up to date。运行中一轮未跑
- 格式: zip（universal，公证、staple）。zip 里有 AppleDouble 条目（`._*`，3.1.0 有 63 个），生产的 `ditto -x -k`
  解出后 `codesign --verify --deep --strict` 为 0（3.0.0、3.1.0 实测）
- 嵌套: 3.x 含 Endpoint Security **系统扩展** `Contents/Library/SystemExtensions/com.objective-see.taskexplorer.extension.systemextension`
  （扩展 `CFBundleVersion` 跟 app 走：3.0.0 / 3.1.0）。没有 LoginItems、XPC、LaunchAgents。2.1.0 只有 `Contents/XPCServices/remoteTaskService.xpc`
  - app 每次启动都提交激活请求，`actionForReplacingExtension` 恒返回 replace（`App/Extension.m`），所以换包后下次启动会把扩展换成新版
  - Apple 文档：用户删除 app 时系统自动卸载它的系统扩展（[Installing System Extensions and Drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers)）。
    一键换包算不算「删除」**仍未验证**：真机一轮里 app 从未启动、扩展从未激活，换包前后 `systemextensionsctl list`
    都没有 objective-see 条目。要验证得启动 app 并批准扩展（会弹系统授权框），再换包看扩展的去留
  - app 要求在 `/Applications` 下运行（否则弹窗要求移动），真机一轮装在那里即可
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: 3.1.0 = `536bda55…9ca8705`、3.0.0 = `4a97769c…ca961a02`，
  与各自 `digest` 相同；也与正文写的 SHA-256 相同。2.1.0 资产没有 `digest`（早于 GitHub 加 digest）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；产品页和 `products.json` 链接的就是这个 zip）
- 阻塞: 无（系统扩展一项待真机）

## 已知问题
- 换包对已激活系统扩展的影响未验证（见一键安装）
- changelog 面板多出赞助行

## 建议下一步
1. 真机一键：3.0.0 → 3.1.0，不运行 + 运行中两轮；两轮都在前后记 `systemextensionsctl list`，运行中一轮 `duo restart` 后看扩展是否换成 3.1.0 且仍 activated enabled
2. 2.1.0 → 3.1.0 跨改名一轮（`BundleIDMigration` 放行 bundle id 闸）

## 如何复验
```bash
.claude/skills/coverage-discovery/scripts/check-bundle.sh TaskExplorer_3.1.0.zip   # 也跑 3.0.0、2.1.0
swift run --package-path application-test feed-discover <3.1.0 TaskExplorer.app>   # → no Sparkle, no electron-builder update config and no MyGo feed
# channel-verify 不收 zip，先 ditto -x -k 解出 .app
swift run --package-path application-test channel-verify <3.0.0 TaskExplorer.app> --expect stable
#   → detected stable，winning source GitHub，latest 3.1.0，status UPDATE → 3.1.0
swift run --package-path application-test channel-verify <3.1.0 TaskExplorer.app> --expect stable
#   → detected stable，winning source GitHub，latest 3.1.0，status up to date
swift run --package-path application-test channel-verify <2.1.0 TaskExplorer.app> --expect stable
#   → bundle id com.objective-see.TaskExplorer，winning source GitHub，status UPDATE → 3.1.0
```
