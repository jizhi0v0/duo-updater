# Codiff

## 基本信息
- Bundle ID: `dev.nkzw-tech.codiff`
- Team ID: `G397874544`（Nakazawa Tech KK）
- 观测版本: 0.1.0、1.19.1、1.20.0；2026-11-16
- 自更新机制: Electron Forge / Squirrel.Mac；非 electron-builder，无 `app-update.yml` 或 `SUFeedURL`。
- 官方源码与下载：[nkzw-tech/codiff](https://github.com/nkzw-tech/codiff)、[codiff.dev](https://codiff.dev)。未见终止维护公告。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | — | ✓ 官方第三方 tap | — | ✓ | — |

当前生效源：直接解压的 ZIP 由 **GitHub** 回答；由 `nkzw-tech/tap/codiff` 管理的副本优先交给现有 ThirdPartyCaskSource。自定义规则不抢占 Homebrew 所有权。

## 覆盖清单
- 最早公开包 0.1.0、上一版 1.19.1、最新版 1.20.0 真包均为上述 Bundle ID / Team，营销版本与 build 相同。`forge.config.cjs` 在最早 tag 与 main 使用相同 `appBundleId`。
- 55 个公开 release、65 个 git tag；公开 release 全部 `prerelease=false`。`v0.5.0-2`、`v0.9.0-2`、`v0.10.0-5`、`v1.0.1-1` 的数字后缀 release 使用无后缀 ZIP 名。另有历史异常：`v0.11.0-2` 资产名为 `Codiff-darwin-arm64-0.10.0.zip`，不能从这个旧 tag 推断包内版本；它不在当前 latest 或 20 条回退窗口中。旧副本仍按 Bundle ID 查当前 1.20.0，无需借旧 tag 确定安装版本。所有 65 个 tag 的数字格式均可读；当前 latest 的 tag、资产与真包版本已核对相等。
- 没有独立 beta/nightly 资产或源码中的发布轨切换。命名预发布后缀不匹配 stable 规则。
- 各历史 tag 无 release 的副本仍按相同 Bundle ID 检测最新 stable；未逐个下载的中间版本若签名不同，现有安装 Team 闸会安全拒绝。
- 无许可/订阅门控，无其他 Mac 产品或旧 Bundle ID 证据。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `dev.nkzw-tech.codiff` | 独立 | 常规正式版版本号 | 锚定 tag 与 arm64 ZIP 资产名 | ✓ |

## 更新检测
- `GitHubReleaseRule`：`nkzw-tech/codiff`，`^v([0-9]+(?:\.[0-9]+)+)(?:-[0-9]+)?$`。
- 端点：[GitHub latest release](https://api.github.com/repos/nkzw-tech/codiff/releases/latest)。与厂商 `electron/update-check.cjs` 的 `LATEST_RELEASE_URL` 一致。
- 复用 SourceStack / GitHubReleasesSource；无新增请求、缓存、后台任务或权限。
- 官方 [tap cask](https://github.com/nkzw-tech/homebrew-tap/blob/main/Casks/codiff.rb) 为 `auto_updates true`，独立安装来源仍服从现有所有权规则。

## 按架构 / 按 OS 分轨
- Mac ZIP 仅 arm64。0.1.0 的 `LSMinimumSystemVersion=12.0`；1.19.1、1.20.0 为 `13.0`，均低于 DuoUpdater 的 macOS 15 下限。
- 没有按设备分配或按 OS 分桶；读取的是人人可从 Releases 手动下载的公开 GA。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | Squirrel.Mac 更新 | 本次仅完整 ZIP | 现有 GitHub ZIP 安装路线 |
| 证据 | `electron/updater.cjs` 的 `applySquirrelUpdate` | 2026-11-16 `update.electronjs.org/nkzw-tech/codiff/darwin-arm64/1.19.1` 返回 1.20.0 ZIP URL；release 无 delta/blockmap 资产 | 无需增加增量机制 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 用户点更新后交 Squirrel；启动检查只记通知状态 | 启动检查仅留下版本通知状态，无暂存整包 | 无需为启动检查新增 stash 规则 |
| 证据 | `performCheck` 写 `~/.codiff/update-state.json`；只有 `applySquirrelUpdate` 才调用 `autoUpdater.checkForUpdates()` | 真包 1.19.1 启动后 `~/.codiff/update-state.json` 记录 `compatible=true`、`latestVersion=1.20.0`；对应缓存/用户数据目录未见大于 8 MiB 的完整安装包 | 记录文件不声明已下载包或摘要，不能当作完成记录 |

两份副本共用 `~/.codiff/update-state.json`；此文件只有版本、检查时间、兼容状态等，非安装容器。手动点更新触发的 Squirrel 下载竞争未以人为构造的旧暂存包验证。

## Changelog
- 来源：GitHub release body，经 GitHubReleasesSource 的现有 Markdown 解析器结构化，无独立 ChangelogRecipe。
- pane 实测：`source structured: 1 entries; newest 1.20.0: 5 items, headings []`。厂商本条 release 是平铺 bullet，无分节标题；5 条功能/修复条目保留，贡献致谢与安装命令未混入。
- 跟随 stable，与安装资产来自同一 release。

## 一键安装
- 格式：`^Codiff-darwin-arm64-[0-9]+(?:\.[0-9]+)+\.zip$`，根目录为 `Codiff.app`，无 LoginItems 或 Helpers 下的常驻子 app。
- 校验：现有 SHA-256、Developer ID / Team、bundle identity、架构与系统版本安装闸。
- 1.20.0 ZIP：262837986 bytes，SHA-256 `e7de5307d1231ab495ca0e6822f0275256f60459ae5c24018e2aa525c3f1b358`，与 GitHub asset digest、官方 cask 一致。
- 1.19.1 ZIP：275299243 bytes，SHA-256 `6fccf1f825b6f1e0542d0d1ae351dff631704b530cdf983437fd68b6c631cebe`，与 GitHub asset digest 一致。
- **读的是**：人人可手动下载的 GA；和厂商自身检查相同，不提前绕过设备分配。
- 端到端（macOS 27.2 / arm64 VM，2026-11-16）：
  - 未运行：真实 1.19.1 → `duo check Codiff --json` 返回 GitHub / 1.20.0 / in-place；`duo install Codiff --yes --json` 返回 `outcome=installed`、`applied=true`、`bytesDownloaded=262837986`。目录 inode 4978645 → 5001057，营销/build 均为 1.20.0。
  - 与厂商 ZIP 解压结果逐项比较文件 SHA-256、权限、目录和 symlink target：10506 / 10506 项、0 差异。BSD `diff -rq` 对厂商 framework 符号链接打印 directory-loop 警告，另以不跟随链接的清单比较确认一致。
  - 运行中：重新放入真实 1.19.1 并启动；默认更新检查写出 1.20.0 可用状态后，再次安装返回 `installed / applied=true`、下载 262837986 bytes。`duo restart Codiff` 返回 `restarted`，之后每秒读取一次磁盘版本，10 次均为 1.20.0，未被自更新器回退。
  - 两轮都通过 `codesign --verify --deep --strict` 与 `spctl -a -vv`（Notarized Developer ID）；签名团队保持 G397874544。Keep Backups 关闭时未新增 Codiff 备份。
  - 验证结束保留最新版 Codiff，关闭其进程；验证用 CLI 已还原。

## 夜扫覆盖
- 现有 Vendor/GitHub registry 自动枚举，精确 recipe ID：`github:nkzw-tech/codiff:stable`；installer finding ID：`install:github:nkzw-tech/codiff:stable`。
- 覆盖同一 Bundle ID 下的历史 stable 副本与数字后缀重打包；不重复加入 AuditedUpdateFeeds。
- 实测：当前 checkout 的签名 CLI：`duo verify --only nkzw-tech/codiff` 选择 1 条规则，`ok`、版本 1.20.0、warnings 为空；`duo verify-install --only nkzw-tech/codiff` 选择 1 个安装包，`ok 1 / warn 0 / failed 0 / unresolved 0 / skipped 0`，262837986 bytes、97 秒，包身份与上述 Bundle ID / Team / arm64 / macOS 13.0 一致。
- 首次包身份观测与既有 identity baseline 连续性不同；本次不修改共享 baseline。

## 已知问题
- 无预发布轨证据；未来出现其他轨需要独立核对真实 bundle 信号。
- 手动触发 Squirrel 下载后与外部安装的竞争未验证，保留为明确的实测限制。

## 如何复验
1. 从 GitHub Releases 下载 0.1.0、1.19.1、1.20.0 arm64 ZIP，解压并读 Info.plist 与 `codesign -dvv`。
2. `swift run --package-path application-test feed-discover <Codiff.app>`。
3. `swift run --package-path application-test channel-verify <Codiff.app> --expect stable`。
4. 使用本次 checkout 经 `make cli` 构建的 CLI，在 VM 安装真实 1.19.1，运行 `duo check Codiff --json`、`duo install Codiff --yes --json`；分别验证未运行与运行状态，再用 `duo restart Codiff` 检查磁盘版本。
5. `duo verify --only nkzw-tech/codiff --report <scratch>/verify.json`；`duo verify-install --only nkzw-tech/codiff --report <scratch>/install.json`。

## 验证结果
- 配方/index/golden 回归：102 项通过；`make test-scripts` 通过；所有 55 个公开 release tag 与 65 个 git tag 都能提取营销版本。
- feed-discover：`no Sparkle, no electron-builder update config and no MyGo feed`。
- 真实 0.1.0 与 1.19.1 的 channel-verify 均判 stable，完整 SourceStack 均由 GitHub 返回 1.20.0；pane 同上。

## 建议下一步
1. 发布后由既有夜扫自动观测该 registry entry；不需要新 runner 或定时任务。
