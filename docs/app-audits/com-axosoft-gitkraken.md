# GitKraken Desktop

Axosoft 的 Git 客户端，Electron 套壳，用 Electron 自带的 `autoUpdater`（Squirrel.Mac）自更新。

## 基本信息
- Bundle ID: `com.axosoft.gitkraken`
- Team ID: `T7QVVUTZQ8`（Developer ID Application: Axosoft, LLC）
- 观测版本: short `12.6.0`，无 `CFBundleVersion`（2026-10-16）
- 自更新机制: Electron `autoUpdater`（Squirrel.Mac，`Contents/Frameworks/Squirrel.framework`）
- 版本：`LSMinimumSystemVersion` `10.10.0`；arm64 与 x64 各一个 zip，没有 universal

## 覆盖组（Coverage checklist）

| 组 | 结论 | 依据 |
|---|---|---|
| 旧 / 改名的 bundle id | 无：10.8.0、11.0.0、11.5.0、12.0.0、12.5.0、12.6.0 都是 `com.axosoft.gitkraken` | 实测，range 读各版 zip 里的 Info.plist |
| 其他 edition | **On-Premise Serverless（STANDALONE）共用同一 bundle id、app 名、Info.plist 和 Team** → 见「已知问题」；自托管 Enterprise edition 没有公开下载，未核 | Standalone 实测；Enterprise 只见于代码（`CLIENT_TYPE.ENTERPRISE`），未验证 |
| 其他 release track | 无：updater URL 不带 channel，`darwin-arm64-beta/RELEASES` 404，app 里没有渠道开关 | 实测（asar + 端点） |
| 版本区间 / Team 变化 | 10.8.0 → 12.6.0 都是 Team `T7QVVUTZQ8` | 实测（主可执行文件里的签名证书主题） |
| 架构 | 端点按架构分路径；我们只跑 arm64（`App/project.yml`），所以只问 `darwin-arm64`。Rosetta 下跑的 x64 副本也会被一键换成 arm64 版（同 id 同 Team） | 实测端点；x64 副本行为是推断 |
| 版本格式 | 历史版本都是三段数字（12.x 页面 13 个版本全部 `X.Y.Z`），pattern 也收两段和下一个大版本，拒 `-beta` 后缀 | 实测 + 单测 |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | — (`auto_updates true`，按设计让出) | — | — | ✓ 检测 + 一键 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.axosoft.gitkraken` | — | — | — | ✓ |

## 更新检测
- 源: `VendorProbeRecipe`
- 端点: `https://release.gitkraken.com/darwin-arm64/RELEASES`
  - app 自己拼的 URL（`app.asar` 里的 `919.main.bundle.js` 与渲染进程入口）：base `https://release.gitkraken.com`
    （`global.mode === 'staging'` 时是 `stagingrelease`），路径 `darwin` + arm64 时 `-arm64` + `/RELEASES`，
    query `?v=<当前版本>&darwin=<os.release()>`，交给 `autoUpdater.setFeedURL`。
  - 应答 `{"name":"12.6.0","url":"https://api.gitkraken.dev/releases/production/darwin/arm64/12.6.0/GitKraken-v12.6.0.zip"}`；
    带上已是最新的 `v=12.6.0` 时回 204。
  - recipe 不带 query：裸路径、`v=0.0.0`、`v=12.5.0`、`darwin=19.0.0/25.0.0/999` 答的都是同一份 JSON，
    带 `channel=beta` 也一样。去掉 query 可以避开 204，也不会把版本号写进 URL。
- `name` 是 marketing 版本，等于 `CFBundleShortVersionString`；包里没有 `CFBundleVersion`，所以不是 `versionIsBuild`。
- 读的是**人人可手动下载的 GA**：请求里没有任何设备标识，cask 和官网下载的也是这一个 zip（12.6.0 的 SHA-256 与 cask 一致）。
- 按 OS 分轨：应答里没有系统版本字段，`darwin=19.0.0` 与 `25.0.0` 答案相同；包内 floor `10.10.0` 低于我们的 deployment target。
- 只有 `NORMAL` edition 会去检查更新：`clientType === STANDALONE` 时 updater 直接返回 null（代码，未在 Standalone 包上运行验证）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Squirrel.Mac 只下整包 zip | 应答只有 `name` + 整包 `url` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（Squirrel.Mac 的 ShipIt） | 没查 | ○ |
| 证据 | cask `zap` 列了 `~/Library/Caches/com.axosoft.gitkraken.ShipIt` | 未跑第二轮（运行中 + 自更新器武装），待主会话真机执行 | `SelfUpdaterStash` 目前只读 electron-updater 与 Cindy 两种布局，没有 Squirrel ShipIt |

- 记录文件与字段: 未读（ShipIt 的 `ShipItState.plist`），待真机第二轮看实际目录
- 容器: zip，包根是 `GitKraken.app`
- 两份副本会不会共用这个目录: 会（缓存目录按 bundle id 命名），未验证

## Changelog
- 来源: recipe，读 `https://help.gitkraken.com/gitkraken-desktop/current/`（WordPress 服务端渲染，新版在前）
- 结构化: `recipe changelog:com.axosoft.gitkraken:-: 13 entries; newest 12.6.0: 24 items, headings ["New ✨", "Improvements 🙌", "Bug Fixes 🐛"]; first items ["Multiple terminal tabs: Open, switch bet", "Agent status plugin controls: The Agents", "Stacked pull requests on GitHub.com: Whe"]`
- 每版 `<h2>Version X.Y.Z</h2>`，可选 `<p><kbd>日期</kbd></p>`（最新一版 12.6.0 还没有日期），`<h3>` 分类标题，`<hr />` 分隔。
  嵌套列表（加粗引导语下面再挂 `<ul>`）拆成引导语一行 + 子项各一行。
- 跟随 channel: 只有一个 channel
- Recipe 状态: 已有
- `current` 页只列当前大版本（现在是 12.0.0–12.6.0）。13.0 发布后这个 URL 是否换成 13.x 的页面，未验证。

## 一键安装
- 状态: 支持（`.versionTemplate` → arm64 zip）
- 端到端: 真机端到端：待主会话执行
- 格式: zip（stored，包根 `GitKraken.app`）
- 校验: 应答不发摘要（只有 `name` 和 `url`），只靠签名 + Team 闸
- **读的是**: 人人可手动下载的 GA
- 上一版（12.5.0）和最新版（12.6.0）都是 Team `T7QVVUTZQ8`，`spctl` 都是 `Notarized Developer ID`，`codesign` 验证通过，只有 arm64
- 嵌套 app：`Contents/Frameworks/GitKraken Helper{,(GPU),(Plugin),(Renderer)}.app`，`LSUIElement=true`，是 Electron 标准子进程，
  由主进程拉起、随主进程退出。zip 里没有 LoginItems、LaunchAgent 或 daemon。`Contents/Resources/bin/gitkraken.sh` 是命令行启动脚本，不常驻
- 下载：`api.gitkraken.dev/releases/production/darwin/arm64/<v>/GitKraken-v<v>.zip` 302 到 `release.gitkraken.dev/gkd/production/normal/…`，
  UA `DuoUpdater/0.1` 拿到 200，Range 请求拿到 206

## 已知问题
- **On-Premise Serverless edition 会被换成普通 edition。** Standalone 包（cask `gitkraken-on-premise-serverless`，
  `api.gitkraken.dev/releases/standalone/production/…`）与普通版 bundle id、app 名、Info.plist、Team 全都一样，只有
  `app.asar` 里的 `src/main/static/clientType.js` 写的是 `'STANDALONE'`（普通版是 `'NORMAL'`）。我们的扫描读不到这个值，
  所以 Standalone 副本也会拿到这条 recipe：检测到的版本号大体对（两条线版本号同步，`standalone/…/12.6.0` 也存在），
  但一键会装上**普通版**的 zip，签名闸拦不住（同 id、同 Team）。实测：Standalone 12.5.0 与 12.6.0 都是
  `com.axosoft.gitkraken` / `T7QVVUTZQ8`，12.5.0 的 `clientType.js` 是 `'STANDALONE'`。
- 自托管 Enterprise edition（`CLIENT_TYPE.ENTERPRISE`，从客户自己的服务器 `…/release` 更新）没有公开包可核，推测也是同一 bundle id，
  问题同上。

## 建议下一步
1. 给扫描加一个 edition 信号：从 `app.asar` 读 `src/main/static/clientType.js`，不是 `'NORMAL'` 的副本不走这条 recipe
   （至少不提供一键）。`BundleFacts` 已经有不解包读 asar 的代码。
2. 真机第二轮（运行中 + 自更新器武装）时记录 ShipIt 停放的内容，评估要不要给 `SelfUpdaterStash` 加 Squirrel 布局。
3. 13.0 发布后确认 `current` 页是否跟着换成 13.x，不跟就改用 `sourceTemplate`。

## 如何复验

```bash
# 1. 端点
curl -sS "https://release.gitkraken.com/darwin-arm64/RELEASES"
curl -sS -o /dev/null -w "%{http_code}\n" "https://release.gitkraken.com/darwin-arm64/RELEASES?v=12.6.0&darwin=25.0.0"   # 当前最新时 204

# 2. 生产检测 + changelog（解开的 zip）
swift run --package-path application-test channel-verify "<12.5.0>/GitKraken.app" --expect stable
swift run --package-path application-test channel-verify "<12.6.0>/GitKraken.app" --expect stable

# 3. edition 标记
#    app.asar → src/main/static/clientType.js：普通版 'NORMAL'，On-Premise Serverless 'STANDALONE'
```

2026-10-16 实测:
- `channel-verify`（12.5.0 arm64 zip 解包）: `detected channel → stable`、`VendorProbe ✓`、`verdict UPDATE 12.5.0 → 12.6.0`、
  `winning source Vendor`、`status UPDATE → 12.6.0`。
- `channel-verify`（12.6.0 arm64 zip 解包）: `verdict up to date`、`winning source Vendor`、`status up to date`。
- 两次的 `changelog pane` 都是上面 Changelog 一节那行。

## 历史与实测

### 2026-10-16 · 接入
- 包：12.6.0 arm64 zip 217,689,863 bytes，SHA-256 `4c3a0485823d8c84fc7f66099d8abfac6a241f0bd2a3c86ca974063f9e265c45`（= cask）；
  12.5.0 arm64 zip 218,710,327 bytes，SHA-256 `406e38d8b1937a58ccc461f7b65e69e2a4a7da4653105bb5c5183e94d40d8bc6`。
- 端点来源：`app.asar` 的 `src/main/static/919.main.bundle.js`（`setUpdateUrlBase` 拼 `RELEASES?v=…&darwin=…` 后交给
  `setFeedURL`）与 `src/render/static/entryPoints/main/index.js`（`clientType === NORMAL` 时发 `update-url-changed`，
  base 为 `https://release.gitkraken.com`）。
- 早期版本 Info.plist 用 HTTP Range 读 zip 中央目录取得，没有下载整包；`10.0.0`、`10.0.2`、`9.13.0`、`9.0.0`、`8.0.0`
  在 `releases/production/darwin/arm64/` 下 404。
- changelog 页 2026-10-16：13 个版本（12.0.0–12.6.0），每版 3–42 条，0 条空项。
