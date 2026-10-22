# Sentinel

## 基本信息
- App: Sentinel — Gatekeeper 的图形前端：开关 Gatekeeper、拖入 app 去掉隔离属性（`xattr -rd com.apple.quarantine`）、拖入 app 重签名（ad-hoc 或开发者证书）；带一个 Finder 右键扩展。与 Pearcleaner 同一作者
- Bundle ID: `com.alienator88.Sentinel`（1.5 起）；1.0–1.4 是 `com.alienator88.sentinel`（小写 s，见覆盖清单）
- 仓库: `alienator88/Sentinel`（默认分支 `main`，Xcode 工程，依赖 `alienator88/AlinFoundation`，`Package.resolved` 钉在 `main` 的 `f61241c`）
- Team ID: `BK8443AXLU`（Developer ID Application: Marius Lupascu），1.5–3.1.4 每一版相同（逐版实测）；1.0–1.4 ad-hoc，无 Team
- 观测版本: 3.1.4（`CFBundleVersion` 19）；上一版 3.1.3（18）；观测日期: 2026-10-22
- 自更新机制: **自研**，AlinFoundation 的 `Updater`（读 GitHub Releases，不是 Sparkle）。只在用户点 Update 时下载，下完立刻换包，不停放，详见下文
- 分发: GitHub Releases；Homebrew cask `alienator88-sentinel`（`auto_updates true`，url 是同一个 `Sentinel.zip`）；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，cask 源让路） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，3.1.3 / 2.1 / 1.4 / 3.1.4 都是 `winning source GitHub`）。`feed-discover` 对 3.1.3 zip: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（逐版解 `Sentinel.zip` 读真包，2026-10-22）:
  - 1.0、1.1、1.2、1.3、1.4: `com.alienator88.sentinel`，`TeamIdentifier=not set`（ad-hoc）
  - 1.5–3.1.4（14 个 release，每个都解开读了）: `com.alienator88.Sentinel`，Team `BK8443AXLU`，`spctl` 全部 `Notarized Developer ID`
  - 小写 id 的副本：`GitHubReleasesSource` 按 bundle id 精确查表（大小写敏感），所以给它单独一条**只检测**的 rule。不能走 `BundleIDMigration`：它要求两个 id 由同一个 Team 签，1.0–1.4 没有 Team。一键也不行：安装闸要 Team 匹配和 bundle id 一致，两样都不满足。`.publishedDigestOnly` 是给「新包本身 ad-hoc」的，这里新包是 Developer ID，不适用。用户手动更新一次后就落到主 rule 上
- 其他轨: 无。19 个 release 全部 `prerelease: false`，tag 全是纯数字（`1.0`…`2.2` 两段、`3.0.0`…`3.1.4` 三段），仓库没有 beta / nightly 的 workflow（`.github/workflows` 只有 `issues.yml`）
- 版本范围: `^([0-9]+(?:\.[0-9]+)+)$` 读得出全部 19 个 tag；`3.2.0-beta`、`v3.2.0` 这类不匹配（锚定、无 `v`）。下一个大版本 `4.0.0` 匹配
- 主机下限: `LSMinimumSystemVersion` 1.0 为 13.0，1.5–2.1 为 12.0，2.2–3.1.4 为 13.0（1.1–1.4 没读）；都低于 DuoUpdater 自己的下限，不需要 `hostRequirement`
- 架构: `Sentinel.zip` 是 universal（`lipo -archs` = `x86_64 arm64`；1.0、2.1、2.2、3.0.0–3.1.4 实测）；3.1.3 起另有 `Sentinel-arm.zip`（arm64）和 `Sentinel-intel.zip`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.alienator88.Sentinel` | — | 默认 | `/releases/latest` | ✓（一键 zip） |
| stable（1.0–1.4 旧 id） | `com.alienator88.sentinel` | — | 默认 | `/releases/latest` | ✓ 只检测 |

## 更新检测
- 源: `alienator88/Sentinel` GitHub Releases，`/releases/latest`
- 版本: tag `3.1.4` 原样等于 `CFBundleShortVersionString`（19 个 release 的 zip 逐个解开核对，全部一致）。`CFBundleVersion` 是递增整数（3.1.4 = 19），不参与比较
- 分诊草稿说「1.9 / 2.0 / 2.1 没有能匹配的资产」：那是草稿选了 `Sentinel.dmg`，而 dmg 从 2.2 才有。改用 `Sentinel.zip` 后 19 个 release 每个都有。规则只读 `/releases/latest`，旧 release 的资产本来也不影响一键

## 按架构 / 按 OS 分轨
- 见覆盖清单；release 不声明 OS 范围

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | AlinFoundation `UpdaterService.downloadUpdate` 只下整包 zip | 每个 release 只有整包 zip / dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（未做真机第二轮） | 不需要 |
| 证据 | 源码（AlinFoundation `f61241c`，`Sources/AlinFoundation/UpdaterService.swift`）：`downloadUpdate` 把资产写到 `~/Library/Application Support/Sentinel/<资产名>`，紧接着 `unzipAndReplace` 做 `rm -rf <bundle>` + `ditto -xk <zip> <app 目录>` + `rm -f <zip>`，失败时用 `osascript … with administrator privileges` 重做同样三步。zip 只在下载到换包之间存在 | — | — |

- 触发: 启动时 `Updater.checkAndUpdateIfNeeded`（默认频率 daily = 每次启动）只请求 `api.github.com/repos/alienator88/Sentinel/releases` 和 `contents/announcements.json`，置 `updateAvailable` 显示角标，`sheet: false`，不弹窗、不下载。下载只发生在用户点更新面板的 Update（`UpdateView.swift` 的 `updateButtons`）
- 选包: `selectAppropriateAsset` 先找 `Sentinel-arm.zip` / `Sentinel-intel.zip`，再找 `Sentinel.zip`。所以 Apple 芯片上厂商更新器装的是 arm64-only 包，我们装 universal 包；bundle id 与 Team 相同，两者互换不影响
- 与我们的冲突: 只有用户在 Sentinel 里点 Update 的同时 duo 也在换包才会撞（两边都是整目录替换）。没有暂存，所以不存在「暂存了旧版、下次启动装回去」的回退
- 3.1.4 可执行文件里有这几段源码字符串（`needs permission to complete the update`、`" && ditto -xk "`、`alinfoundation.updater.nextUpdateDate`、`/contents/announcements.json`），与上面读的源码对得上

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 3.1.3 起）: `source structured: 1 entries; newest 3.1.4: 1 items, headings []; first items ["[x] Enable drag/drop of application bund"]`
- 标题: 2.0–3.1.4 的正文都是唯一一个 `## What's New` 加列表。单个小标题低于解析器的两小标题门槛，按设计不显示（`qualifyingHeadings` 注释里 Shotbase 的同类情形），**没有被压平进条目**
- 条目文字保留了厂商写的任务列表标记 `[x] `（正文是 `- [x] Enable drag/drop…`）。解析器不剥这个前缀，所以面板每条前面多一个 `[x]`。通用解析器的问题，本次不改
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（规则已接，真机端到端未跑）**
- 格式: zip，根目录 `Sentinel.app`（3.1.4 的 zip 另带 `__MACOSX/`，`ContentsPayload` 会忽略）。Pattern `^Sentinel\.zip$`，kind `.zip`
- 嵌套: `Contents/PlugIns/FinderOpen.appex`（Finder Sync 扩展，右键「Sentinel Unquarantine」）。没有 `Contents/Library/LoginItems`、`LaunchDaemons`、`Helpers`，没有嵌套 app。可执行文件链接 ServiceManagement，但那是 AlinFoundation 的 `HelperToolManager`，Sentinel 源码不调用它（`main` 分支全部 17 个 `.swift` 里 `HelperToolManager` / `SMAppService` 零命中）
- 签名: 3.1.3、3.1.4 都是 `TeamIdentifier=BK8443AXLU`，`codesign --verify --deep --strict` 退出 0，`spctl` `Notarized Developer ID`
- 校验: GitHub 资产 `digest`。3.1.4 `Sentinel.zip` `sha256:fd329451f8d747b4af065036219d75893e6a98c6f3c33b48e3e766a0caa762eb`，2918208 字节；3.0.0 起的资产都有 digest，2.2 及更早没有（在 GitHub 加 digest 之前上传）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；cask 的 url 也是它）
- 端到端: **未跑**，本次只做到 channel-verify。真机由主会话做
- 真机注意事项（从源码读的，未在真机上验证）:
  - 不要往 Sentinel 窗口或 Dock 图标拖任何东西，不要用 Sentinel 打开 `.app`，不要访问 `sentinel://…?path=` 链接：这些都会对目标跑 `xattr -rd com.apple.quarantine`，「自动启动」偏好默认开，随后还会启动那个 app（`DeepLink.swift`、`CmdDrops.swift`）
  - 不要碰 Gatekeeper 开关：它走 `AuthorizationExecuteWithPrivileges` 弹管理员框跑 `spctl --global-enable/--global-disable`（`Gatekeeper.swift`）
  - 启动本身不要管理员权限、不装 helper / 登录项 / LaunchAgent。启动时会跑 `security find-identity -p codesigning -v`（列签名证书给设置页用）和 `spctl --status`，以及上面两个匿名 GitHub API 请求（与 duo 共享同一 IP 的匿名限额）
  - Finder 扩展要用户在设置里开（开关调 `FIFinderSyncController.showExtensionManagementInterface()` 打开系统界面）；首启是否默认开着未验证。若真机上它是开着的，换包后 Finder 里正在跑的扩展进程仍是旧代码，直到 Finder 重新拉起它；未验证
  - 写的地方: `~/Library/Application Support/Sentinel/`（AlinFoundation 启动时建），偏好 `com.alienator88.Sentinel`，app group `group.com.alienator88.Sentinel`
- 阻塞: 无

## 已知问题
- changelog 条目带 `[x] ` 前缀，见上
- 1.0–1.4（小写 id、ad-hoc）只检测，不能一键

## 如何复验
```
gh release view 3.1.4 -R alienator88/Sentinel --json assets -q '.assets[]|.name+" "+(.size|tostring)+" "+.digest'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Sentinel.zip      # 3.1.4: universal, BK8443AXLU, Notarized
swift run --package-path application-test feed-discover Sentinel-3.1.3.zip   # → no Sparkle / electron / MyGo
ditto -x -k Sentinel-3.1.3.zip out313
swift run --package-path application-test channel-verify out313/Sentinel.app --expect stable   # → GitHub, UPDATE → 3.1.4
ditto -x -k Sentinel-3.1.4.zip out314
swift run --package-path application-test channel-verify out314/Sentinel.app --expect stable   # → up to date
ditto -x -k Sentinel-1.4.zip out14
swift run --package-path application-test channel-verify out14/Sentinel.app --expect stable    # → 小写 id，UPDATE → 3.1.4，download 是 releases 页
```

## 建议下一步
1. 主会话真机两轮（不运行 / 运行中 + `duo restart`），结果补进「一键安装」。
2. 下一个正式版出来后复查 tag 仍是纯数字、`Sentinel.zip` 仍在。
