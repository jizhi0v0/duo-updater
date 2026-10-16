# KnockKnock

## 基本信息
- App: KnockKnock — Objective-See 的持久化项扫描器（列出 launch item、登录项、BTM、浏览器扩展等），GPL-3.0 开源
- Bundle ID: `com.objective-see.KnockKnock`
- 仓库: `objective-see/KnockKnock`（默认分支 `main`）；产品页 `https://objective-see.org/products/knockknock.html`
- Team ID: `VBG97UB4TA`（Developer ID Application: Objective-See, LLC；公证）
- 观测版本: 4.1.0（`CFBundleVersion` 同为 `4.1.0`）；观测日期: 2026-10-16
- 自更新机制: 自研，只提示不安装。settled from source: `Update.m` on `main` 读
  `https://objective-see.org/products.json` 里 `KnockKnock.version`，与 `getAppVersion()` 做 `NSNumericSearch`
  比较，新了就弹窗（偏好 `PREF_DISABLE_UPDATE_CHECK` 可关）。它不下载、不替换 bundle
- 分发: GitHub Releases，每个 release 一个 universal `KnockKnock_<ver>.zip`（`release.sh` 产出，签名 + 公证 + staple）。
  `products.json` 的 `zip` 字段与产品页的下载链接都指向同一个 GitHub 资产。Homebrew cask `knockknock`
  （`auto_updates` 未设）；没有 MAS

## 覆盖清单（Coverage checklist）
- **bundle id**: 读了 2.2.0、3.1.0、3.9.8、4.0.3、4.1.0 的 Info.plist，全部 `com.objective-see.KnockKnock`。没有改名、没有别的版本
- **发布轨**: 只有 stable。仓库发过 4 个 GitHub pre-release（`v3.9.5`…`v3.9.8`，2025-12-07 至 12-13，正文写
  「Pre-release for v4.0.0」），之后没有再发。app 里没有 beta 开关（`Update.m` 只读 `products.json` 的一个
  `version`），pre-release 的 bundle 与正式版同 id、版本串不带后缀（3.9.8 的 `CFBundleShortVersionString` = `3.9.8`），
  磁盘上没有能区分它的信号。所以不是用户可选的轨。装着 3.9.8 的副本由 stable 规则服务：channel-verify 实测
  3.9.8 → `UPDATE → 4.1.0`（**实测**）
- **版本范围**: 2.2.0 与 3.9.8 的 Team 都是 `VBG97UB4TA`（**实测**，codesign），与 4.0.3 / 4.1.0 相同，Team 闸不拒旧副本
- **宿主下限**: `LSMinimumSystemVersion` = `10.15`（4.x），低于我们的下限，不需要 `hostRequirement`
- **版本 pattern**: `^v([0-9]+(?:\.[0-9]+)+)$`。全部 15 个非 pre-release tag 都是 `vX.Y.Z`；单测覆盖 8 个代表 tag、
  `v5.0`、`v4.2.0-beta.1` / `v4.2.0b1`（不读）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（brew 装的副本） | — | ✓ | — |
| **beta**   | —       | —        | —   | —（见上：历史 pre-release，无 app 内轨） | — |

当前生效源: **GitHub**（channel-verify 实测）。brew 装的副本由 `HomebrewCaskSource` 先答（cask 不是 `auto_updates`）。
`feed-discover` 给出 `no Sparkle, no electron-builder update config and no MyGo feed`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.objective-see.KnockKnock` | — | — | `/releases/latest`（排除 pre-release） | ✓ |

## 更新检测
- 源: `objective-see/KnockKnock` GitHub Releases，`/releases/latest`
- 版本: tag 去 `v`，与 `CFBundleShortVersionString`、`CFBundleVersion` 相同（5 个真包核对）
- 与 app 自己的检查一致: `products.json` 的 `KnockKnock.version` 观测为 `4.1.0`，与 `/releases/latest` 相同

## 按架构 / 按 OS 分轨
- 单个 universal zip（`lipo` = `x86_64 arm64`，4.0.3 / 4.1.0）
- release 不声明 OS 上下限；`LSMinimumSystemVersion` = `10.15`

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `Update.m` 只比较版本号、不下载 | 每个 release 只有一个完整 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（运行中一轮待主会话执行） | — |
| 证据 | `Update.m` 不下载任何东西（源码） | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-16，channel-verify `changelog pane`，4.1.0）: `source structured: 1 entries; newest 4.1.0: 7 items,
  headings []; first items ["Root: new "always run as root" preferenc", "Fix Full Disk Access detection on macOS ",
  "Hardening: uncaught-exception handler, p"]`
- 生产解析器跑全部 19 个 release 正文（2026-10-16）:
  - 4.1.0: 7 条，正是正文的 7 个 `-` 条目；赞助行、`Version 4.1.0: …` 引言、`🔐 … SHA-256` 尾注都没进条目
  - 4.0.1–4.0.3（`☑️` 行，不是 Markdown 列表，走 prose 分支）: 条目里多出赞助行
    `You can now sponsor **KnockKnock**/…` 与 `🔐 KnockKnock_<ver>.zip`。LuLu 同一种正文已有单测，现状如此
  - 4.0.0: 0 条——prose 行数超过 `proseItemCap`（12），解析器按设计放弃，面板退回整段正文
  - 2.x / 3.x: 1–5 条，都是厂商的 emoji 行，干净
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要（最新版正文干净；`☑️` 风格的尾巴是解析器通用行为，见已知问题）

## 一键安装
- 状态: **支持**（按 Team 闸）
- 端到端: 真机端到端：待主会话执行
- 格式: zip（universal，公证、staple）；bundle 内没有嵌套 app、XPC、LoginItems 或 LaunchAgents
- Pattern: `^KnockKnock_[0-9]+(?:\.[0-9]+)+\.zip$`, kind `.zip`
- 解包: 4.1.0 的 zip 把 AppleDouble 文件（`Contents/Resources/._*.png`）当普通条目存着。`unzip` 解出来
  `codesign --verify --deep --strict` 报 `file added: …/._*.png`、`spctl` 报 `a sealed resource is missing or invalid`；
  生产的 `ArchiveExtractor` 用 `ditto -x -k`，它把这些合回扩展属性，解出 0 个 `._*` 文件，
  `codesign` valid、`spctl` accepted（Notarized Developer ID）。**实测**，两种解法都跑过。4.0.3 的 zip 两种解法都干净
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: 4.1.0 = `98eae6cd…941a3f9e`、4.0.3 = `1e1371ff…52663c69`，
  与各自 `digest` 相同；4.1.0 也与正文写的 SHA-256 相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；产品页和 `products.json` 链接的就是这个 zip）
- 登录项与 root:
  - 4.0 起的 “Start at Login” 用 `LSSharedFileListInsertItemURL` 把 **app 自己的 bundle URL** 加进登录项
    （`utilities.m` `toggleLoginItem`），原地换 bundle 后路径不变，不需要处理
  - 4.1.0 的 “always run as root” 偏好: 启动时经管理员授权以 root 重新拉起自身（`relaunchAsRoot`，`-relaunched` 参数）。
    这样跑着的是一个 root 进程（**我的推测，未验证**: 用户态的退出/重启可能动不了它，`duo restart` 可能留下旧进程）
- 阻塞: 无

## 已知问题
- `☑️` 风格正文（4.0.x 及更早的 LuLu 同款）在 changelog 面板里多出赞助行和 `🔐 <zip>` 行；4.0.0 那样的长正文按设计不转结构化
- 以 root 运行的实例（4.1.0 偏好）在一键安装时的退出/重启行为未验证

## 建议下一步
1. 主会话: 装 4.0.3，`duo install --yes`（不运行；运行中 + `duo restart`），补进本文件
2. 有人报 root 实例的问题再看 `AppRestarter` 对 root 进程的处理

## 如何复验
```
swift run --package-path application-test feed-discover <KnockKnock.app>      # → no Sparkle, no electron-builder update config and no MyGo feed
swift run --package-path application-test channel-verify <4.0.3 KnockKnock.app> --expect stable
#   → detected stable，winning source GitHub，latest 4.1.0，status UPDATE → 4.1.0
swift run --package-path application-test channel-verify <4.1.0 KnockKnock.app（ditto -x -k 解出）> --expect stable
#   → detected stable，winning source GitHub，latest 4.1.0，status up to date
swift run --package-path application-test channel-verify <3.9.8 KnockKnock.app>
#   → detected stable，status UPDATE → 4.1.0
codesign -dv <KnockKnock.app>        # → TeamIdentifier=VBG97UB4TA（2.2.0、3.9.8、4.0.3、4.1.0）
spctl -a -vv <KnockKnock.app>        # → accepted, source=Notarized Developer ID
```
