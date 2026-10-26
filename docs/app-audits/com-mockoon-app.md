# Mockoon

## 基本信息
- App: Mockoon — 开源的 API mock 桌面工具（Electron），MIT
- Bundle ID: `com.mockoon.app`
- 仓库: `mockoon/mockoon`（monorepo，默认分支 `main`，未归档）。桌面 app 在 `packages/app`（早期叫 `packages/desktop`）；同仓库还有 npm 库（commons、commons-server、cloud、serverless、CLI）和 web app
- Team ID: `8443RQQKK6`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 9.9.0（tag `v9.9.0`，资产 `mockoon.setup.9.9.0.universal.dmg`）；上一版 9.8.0；观测日期: 2026-10-26
- 自更新机制: **自研，只通知**。settled from source: `packages/app/src/main/libs/update.ts` 与 `packages/app/src/shared/shared-config.ts` on `main`：读 `https://api.mockoon.com/releases/desktop/stable.json`（2026-10-26 返回 `{"tag":"9.9.0","digest":"sha256:d417a921…"}`，`digest` 是 Windows `mockoon.setup.9.9.0.exe` 的），`semver.gt` 比本机版本；macOS 上只发 `APP_UPDATE_AVAILABLE` 给界面，用户点了后 `shell.openExternal('https://mockoon.com/download')`。只有 Windows 安装版会把 `.exe` 下到 `userData` 再运行。v1.23.0 的 `packages/desktop/src/main/libs/update.ts` 在 macOS 上也是同样只开下载页
- 包里的 `Contents/Resources/app-update.yml`（`provider: github`、`owner/repo: mockoon`）是 electron-builder 按 publish 配置写的，app 不用：`app.asar` 里 `electron-updater`、`autoUpdater` 各 0 处（`grep -c -a`），`releases/desktop/stable.json` 有。`Squirrel.framework` 是 Electron 自带，没人调。feed-discover 的 `review electronProviderNeedsConstruction` 就是读到了这份没人用的 yml；release 里也没有 `latest-mac.yml`
- 分发: GitHub Releases（每版 universal / arm64 / x64 三个 dmg，外加 Windows、Linux 包和 SBOM、`web-app-dist-v<版本>.zip`）；Homebrew cask `mockoon`（`auto_updates true`，9.9.0，按架构取 arm64 / x64 dmg，livecheck 读的就是上面的 `stable.json`）；官网 mockoon.com/download；Mac App Store 没有（`itunes.apple.com/lookup?bundleId=com.mockoon.app` resultCount 0）
- 产品终止: 没有。9.9.0 的发布说明只宣布 `@mockoon/serverless` 库弃用，桌面 app 照常发布

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | —（`stable.json` 只有版本号，GitHub 已够） |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`、没有可用的 electron-updater 配置、没有 MyGo feed；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v9.9.0: `com.mockoon.app`，Team 8443RQQKK6，Notarized，`LSMinimumSystemVersion` 13.0
  - v9.8.0: 同 id、同 Team，Notarized，`LSMinimumSystemVersion` 12.0
  - v9.5.0（GitHub 上还有资产的最老一版）: 同 id、同 Team，Notarized，`LSMinimumSystemVersion` 12.0
  - v9.4.0 及更早（55 个 release）: release 还在，资产全被删了（`v9.4.0/mockoon.setup.9.4.0.universal.dmg` 2026-10-26 返回 404），读不到真包。bundle id 从源码核：`package.json` `build.appId` at `v1.0.0`、`packages/desktop/build-configs/electron-builder.common.js` at `v1.23.0`、`packages/app/build-configs/electron-builder.common.js` at `main` 都是 `com.mockoon.app`，没有改名前的旧 id。这些副本的 Team 没法核（**未验证**）：最坏情况是 Team 不同，一键被 Team 闸拒、仍能看到更新、手动更新一次
- 其他轨: 没有。release 列表 61 个 release 全是 `v<数字>.<数字>.<数字>`，`prerelease` 全为 false；git tag 102 个，除这 61 个外是 `libs-v*`（30 个，含两个 `libs-v2023-0x`）、`cli-v*`（6 个，最新 `cli-v2.2.1`）、`web-v*`（3 个）、`cloud-v*`（2 个），都只是 tag、没有 GitHub release；没有 `@mockoon/cli@x` 这类 tag。cask 只有 `mockoon`，没有 `@beta`
- monorepo 与 `/releases/latest`: 2026-10-26 `/releases/latest` = `v9.9.0`（桌面 app）。`libs-v*` / `web-v*` 由 `release-libs.yml` / `release-web-app.yml` 处理，前者发 npm 和 CLI 的 Docker 镜像，后者只上传 workflow artifact，都不建 GitHub release（`cli-v*` / `cloud-v*` 是旧的单独 tag，同样没有 release）（`.github/ISSUE_TEMPLATE/Release_checklist.md`: web app 的产物是「Copy the artefact from the workflow to the release」，即塞进桌面 release，这就是 `web-app-dist-v9.9.0.zip`）。所以 `/releases/latest` 只会指向桌面 release，不需要改读 release 列表
- 发布流程（同一 checklist）: 先以 **pre-release** 发 `v*.*.*`，CI 构建，再把二进制挂上去、最后改成正式版。改成正式版之前 `/releases/latest` 跳过它，不会出现「latest 是一个还没挂 dmg 的 release」；`stable.json` 在那之后才更新，所以 GitHub 比 app 自己的提示早
- 版本范围: 61 个 tag 都能被 `versionPattern` 读出；v9.1.0–v9.4.0 等没有资产的 release 不会被 `/releases/latest` 读到（它们不是最新），出现时按「无 macOS 包」处理
- 主机下限: DuoUpdater 自身 macOS 15.0、arm64（`App/project.yml`）；Mockoon 9.9.0 `LSMinimumSystemVersion` 13.0、universal，都在下限之下，不需要 `hostRequirement`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.mockoon.app` | 独立 | — | GitHub `/releases/latest` | ✓ |

没有 beta / nightly / prerelease 轨（见覆盖清单）。

## 更新检测
- 源: `mockoon/mockoon` GitHub Releases，`/releases/latest`
- 版本方案: tag `v9.9.0` → `CFBundleShortVersionString` `9.9.0`、`CFBundleVersion` `9.9.0`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`libs-v9.9.0`、`cli-v2.2.1`、`web-v9.9.0`、`v10.0.0-rc.1` 不匹配；`v10.0.0` 匹配）
- install pattern `^mockoon\.setup\.[0-9]+(?:\.[0-9]+)+\.universal\.dmg$`；同一 release 里的 `mockoon.setup.<v>.arm64.dmg`、`.x64.dmg`、`web-app-dist-v<v>.zip`、Windows / Linux 包、SBOM 都不匹配。选 universal 是因为它在每个有资产的 release 里都有，且 Intel 副本也能用；arm64 dmg（139.9 MB）比 universal（241.2 MB）小，是可以换的取舍
- 厂商自己的版本端点 `api.mockoon.com/releases/desktop/stable.json` 与 GitHub 在 2026-10-26 都是 9.9.0；不需要 VendorProbe

## 按架构 / 按 OS 分轨
- universal dmg（`archs=x86_64 arm64`），另有 arm64、x64 单架构 dmg，同 id 同 Team。`LSMinimumSystemVersion` 9.9.0 为 13.0（9.8.0、9.5.0 为 12.0）；cask `depends_on macos: :ventura`。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `update.ts`：macOS 上不下载任何东西；Windows 下整个 `.exe` | 2026-10-26 `stable.json` 只有 `tag` 和 `digest` 两个字段；release 无 `latest-mac.yml` / blockmap | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会（macOS） | 没查（真机第二轮待主会话） | 不需要 |
| 证据 | `update.ts`：只有 `process.platform === 'win32'` 且非 portable 时才把 `mockoon.setup.<v>.exe` 下到 `userData`；macOS 分支只通知 | — | — |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 9.8.0 起）: `source structured: 1 entries; newest 9.9.0: 1 items, headings []; first items ["[Full changelog](https://mockoon.com/rel"]`
- **不算结构化**: 每个 release 正文只有一行 `[Full changelog](https://mockoon.com/releases/<版本>/)`（v9.9.0、v9.8.0、v9.5.0、v9.4.0 都核过），所以 pane 里只有这一条链接，没有任何改动条目
- 厂商有逐版的 Markdown: app 自己的更新说明弹窗读 `https://mockoon.com/desktop-changelogs-markdown/<版本>.md`（`shared-config.ts` 的 `changelogMarkdownURL`；`changelog-modal.component.ts`）。2026-10-26 `9.9.0.md` 返回 200，front matter 带 `date: '2026-09-16'`，正文 `## Improvements` / `## Fixes` / `## Chores` 下是列表，另有几个纯段落的专题节和一个「Support us!」赞助节（HTML 表格）
- 跟随 channel: 只有 stable
- Recipe 状态: **需要**（`ChangelogRecipe` 读上面的逐版 Markdown），本次没做，见「建议下一步」

## 一键安装
- 状态: 支持
- 端到端: 待主会话
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Mockoon.app` + `Applications` 软链
- 嵌套 / 常驻组件: `Contents/Frameworks/Mockoon Helper.app`、`Helper (GPU)`、`Helper (Plugin)`、`Helper (Renderer)`（`LSUIElement=true`），是 Electron 的子进程，随主进程退出，不常驻。没有 LoginItems / LaunchAgent / Helpers；`app.asar` 里没有 `setLoginItemSettings`、`LaunchAgents`、`.claude/`、`.agents/` 字符串
- 签名: 9.5.0、9.8.0、9.9.0 都是 Team `8443RQQKK6`、Notarized Developer ID；9.4.0 及更早读不到包（见覆盖清单）
- 校验: GitHub 资产 `digest`。v9.9.0 universal dmg `sha256:984a167e9b31e6725f2decabd575189fb4e61f185660b392f8856876e68632f1`，下载文件 `shasum -a 256` 相同、241247016 字节；v9.8.0 universal dmg `sha256:aa00ed3e5cbec89077fa674d0eab338a0342bc5ddca35ae28adbbe3e560bcc10` 同样相符。`stable.json` 的 `digest` 是 Windows exe 的，不能用
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；官网下载页和 cask 指向同一批 GitHub 资产）
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 从 9.8.0 启动会检查 `stable.json`，界面上出现更新提示；点它只会打开浏览器到 mockoon.com/download，不会换包，和我们不抢
  - 换到新版后再启动，会因版本变高弹出更新说明窗口（读 `desktop-changelogs-markdown/<版本>.md`）
  - 注册 URL scheme `mockoon`（`setAsDefaultProtocolClient("mockoon")`，Info.plist `CFBundleURLTypes`）
  - 数据在 `~/Library/Application Support/mockoon`（cask `zap` 列的路径）

## 已知问题
- changelog 只有一条「Full changelog」链接，见 Changelog 节
- v9.4.0 及更早的副本 Team 没法从真包核（资产已删），bundle id 从源码核过

## 如何复验
```bash
gh api repos/mockoon/mockoon/releases/latest -q .tag_name                       # v9.9.0
gh release download v9.9.0 -R mockoon/mockoon -p 'mockoon.setup.9.9.0.universal.dmg'
gh release download v9.8.0 -R mockoon/mockoon -p 'mockoon.setup.9.8.0.universal.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh mockoon.setup.9.8.0.universal.dmg   # Team 8443RQQKK6, Notarized
swift run --package-path application-test feed-discover mockoon.setup.9.9.0.universal.dmg     # review electronProviderNeedsConstruction（yml 没人用）
swift run --package-path application-test channel-verify mockoon.setup.9.8.0.universal.dmg --expect stable   # GitHub, UPDATE → 9.9.0
swift run --package-path application-test channel-verify mockoon.setup.9.9.0.universal.dmg --expect stable   # up to date
curl -sS https://api.mockoon.com/releases/desktop/stable.json
```

channel-verify 原始输出（2026-10-26）:
```
9.8.0 dmg: detected channel → stable; winning source GitHub; latest 9.9.0;
  download https://github.com/mockoon/mockoon/releases/download/v9.9.0/mockoon.setup.9.9.0.universal.dmg;
  changelog pane source structured: 1 entries; newest 9.9.0: 1 items, headings []; first items ["[Full changelog](https://mockoon.com/rel"];
  status UPDATE → 9.9.0
9.9.0 dmg: detected channel → stable; winning source GitHub; latest 9.9.0; status up to date
```

## 建议下一步
1. 主会话真机两轮（上一版 9.8.0 → 9.9.0），结果写回「一键安装」并把 README 行改成 ✓
2. changelog: `/fragile-recipe Mockoon`（ChangelogRecipe，source `https://mockoon.com/desktop-changelogs-markdown/<版本>.md`，按 `## ` 分节，`date` 取 front matter；「Support us!」节要丢掉）
