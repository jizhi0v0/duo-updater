# FlyEnv

## 基本信息
- App: FlyEnv — 本地开发环境管理器（Electron；nginx / Apache / PHP / MySQL / PostgreSQL 等服务的版本管理与启停），前身 PhpWebStudy
- Bundle ID: `phpstudy.xpfme.com`
- 仓库: `xpf0000/FlyEnv`（默认分支 `master`；旧名 `xpf0000/PhpWebStudy`，GitHub 重定向到这里）
- Team ID: `956BZQ2F2P`（Developer ID Application: pengfei xu）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 4.20.1（tag `v4.20.1`，资产 `FlyEnv-4.20.1-arm64.dmg`）；上一版 4.20.0；观测日期: 2026-10-26
- 自更新机制: **只提示、不自装**。settled from source（`v4.20.1` / `master`）: `src/fork/module/App/index.ts` 的 `checkAppVersionUpdate` 读 `https://raw.githubusercontent.com/xpf0000/FlyEnv/refs/heads/master/latest-mac-arm64.yml`（x64 读 `latest-mac.yml`），版本更高时 `src/render/store/app.ts` 弹框，按钮是「查看更新日志」（打开 releases 页）和「下载新版本」（用浏览器打开 `releases/download/v<v>/FlyEnv-<v>-arm64.dmg`）。包里有 electron-updater 和 `app-update.yml`（`provider: github`、`owner: xpf0000`、`repo: FlyEnv`、`updaterCacheDirName: flyenv-updater`），但 `src/main/core/UpdateManager.ts` 没有任何地方引用（GitHub code search 只命中它自己），4.20.1 的 `app.asar` 里 `autoDownload` 出现 6 次，全在 electron-updater 库自身的源码里，没有 `UpdateManager` 那句 `autoDownload = false` 的编译产物
- 分发: GitHub Releases（每版 arm64 dmg、x64 dmg、两个 mac zip、blockmap、Linux / Windows 包和 `latest*.yml`）；Homebrew cask `flyenv`（`auto_updates`，arm 用 `FlyEnv-<v>-arm64-mac.zip`，intel 用 `FlyEnv-<v>-mac.zip`；2024-11-16 由 `phpwebstudy` 改名而来）；App Store 没有（`itunes.apple.com/lookup?bundleId=phpstudy.xpfme.com` resultCount 0）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`、没有 MyGo feed；`feed-discover` 对 4.20.1 dmg 的结论是 `review electronProviderNeedsConstruction`（`app-update.yml` 是 github provider，通用 `ElectronManifestSource` 不接）；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh` / `codesign` / `spctl`）:
  - v4.20.1: `phpstudy.xpfme.com`，Team 956BZQ2F2P，Notarized，arm64，`FlyEnvHelperProtocolVersion` 48
  - v4.20.0: 同 id、同 Team，Notarized，`FlyEnvHelperProtocolVersion` 47
  - v4.15.2（还带资产的最老一版）: 同 id、同 Team，Notarized；Info.plist 没有 `FlyEnvHelperProtocolVersion`，但 helper 也是同一个 `com.flyenv.helper` LaunchDaemon
  - v4.15.1 及更早的 36 个 release 资产都已被厂商删掉（另一个 0 资产的是还没挂资产的 v4.20.2），读不到真包。改名前的 id 从源码定：`package.json` 在 `v1.0.0` 写 `"appId": "phpstudy.xpfme.com"`、`productName: PhpWebStudy`，`configs/electron-builder.ts` 在 `v4.0.0` 和 `master` 都是同一个 `appId`。所以 PhpWebStudy 时代的副本也是这个 id，不需要 `BundleIDMigration`。它们的 Team 读不到：如果不是 956BZQ2F2P，Team 闸会拒一键（安全失败，用户手动更新一次），检测照常
  - 改名前的副本可能装在 `/Applications/PhpWebStudy.app`。一键在原路径换包，换完 bundle 是 FlyEnv、文件夹名不变（与厂商「拖进去覆盖」的路径不同，那会多出一个 FlyEnv.app；未在真机上看）
- 其他轨: 53 个 release 全是 `prerelease: false`，没有 beta / nightly 资产，cask 只有 `flyenv`；源码里没有渠道开关（`checkAppVersionUpdate` 只读 master 上那一个 yml）
- 版本范围: 53 个 release 的 tag 都是 `v<数字>(.<数字>)+`，`versionPattern` 53/53 读得出；仓库还有 `1.0.1`、`V1.0.3` 等早期 tag，但没有对应 release，`/releases` 不返回它们
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；FlyEnv `LSMinimumSystemVersion` 12.0，不需要 `hostRequirement`
- 同一 id 的两种构建: arm64 dmg 与 x64 dmg（`FlyEnv-<v>.dmg`）只差架构（4.20.1 的 `latest-mac.yml` 同时列出两者），不是两个产品；install pattern 只取 `-arm64.dmg`。Apple silicon 上跑 x64 副本的用户会被换成 arm64 版，与厂商自己的检查在 arm64 机器上给出的链接一致

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `phpstudy.xpfme.com` | — | — | GitHub `/releases/latest`（没有 mac 资产时退回列表） | ✓ |

只有一个轨。

## 更新检测
- 源: `xpf0000/FlyEnv` GitHub Releases，`/releases/latest`
- 版本方案: tag `v4.20.1` → `CFBundleShortVersionString` `4.20.1`、`CFBundleVersion` `4.20.1`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定）
- install pattern `^FlyEnv-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`。同一 release 里另外的 mac 安装包 `FlyEnv-4.20.1.dmg`（x64）、`FlyEnv-4.20.1-arm64-mac.zip`、`FlyEnv-4.20.1-mac.zip` 不匹配
- **先发 release、后传资产**: 2026-10-26 `/releases/latest` 是 v4.20.2（2026-10-24 发布，正文只有 "v4.20.2: Fix Issues"，0 个资产）。macOS 构建 workflow 在 v4.20.2 tag 上 2026-10-24 跑成功，但产物还没挂到 release；master 上的 `latest-mac-arm64.yml` / `latest-mac.yml` / `latest.yml` 仍是 4.20.1，所以厂商自己的检查此时也只给 4.20.1。`GitHubReleasesSource` 在 `/releases/latest` 没有匹配资产时退回列表、跳过它，给出 v4.20.1（channel-verify 实测）；资产挂上后自然变成 4.20.2

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（arm64 dmg / x64 dmg），本 rule 只取 arm64；`LSMinimumSystemVersion`: 12.0（4.15.2、4.20.0、4.20.1 都是）。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无（未启用） | 有 blockmap | 不能 |
| 证据 | electron-updater 打进了 `app.asar` 但没被调用（见基本信息）；厂商自己的检查只给整包链接 | 每版有 `*.dmg.blockmap` / `*-mac.zip.blockmap`（electron-builder 差分下载用） | 引擎没有 blockmap 差分；整包下载 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（真机第二轮待主会话） | 不需要 |
| 证据 | 厂商检查只用浏览器打开 dmg 链接，下载由浏览器完成，落在用户的下载目录，不是 app 的缓存。electron-updater 没被调用，`~/Library/Caches/flyenv-updater/pending` 不会有东西（`SelfUpdaterStash` 读这个 electron-updater 通用布局，有也能用） | — | — |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 4.20.0 起）: `source structured: 1 entries; newest 4.20.1: 1 items, headings ["**📦 Build & Transparency**"]; first items ["**Global Build History:** [GitHub Action"]`
- **结论: 不合格（有损）**。厂商每版的格式是 `## **🚀 New Features**` / `## **🛠️ Improvements & Bug Fixes**` 下面一条条 `### **1. 标题**`，标题下面是段落，有时再跟 `- **要点**: …` 列表，最后是固定的 `## **📦 Build & Transparency**`（一条指向 GitHub Actions 的列表项）。解析器只取列表项：
  - 4.20.1、4.19.1、4.17.0 这类只有段落的版本，唯一的列表项是 Build & Transparency 那条，面板只显示它（上面实测）
  - 带列表的版本（4.20.0 实测 16 条）拿到的是各功能下的要点，但 `### **1. Added Windows UAC Authorization Mode**` 这类编号标题含数字，被 `isVersionLikeHeading` 当成版本号丢掉，要点失去所属功能；末尾仍带 Build & Transparency 那条
- 试过只用 recipe 修: `ChangelogRecipe`（`.gitHubReleases`，`skipSections: ["**📦 Build & Transparency**"]`）对 4.20.1 正文解析出 nil（变得更差），4.20.0 去掉了那条、剩 15 条，标题问题不变；且 recipe 读列表时最新一条是没有 mac 包的 4.20.2。没有提交。要保留 `### **N. 标题**` 需要改解析器（引擎），本次范围外，见「建议下一步」
- 跟随 channel: 只有一个轨
- Recipe 状态: 不加（见上）

## 一键安装
- 状态: **支持**（Team 956BZQ2F2P 的副本）
- 端到端: 待主会话（真机从 4.20.0 装到 4.20.1）
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `FlyEnv.app` + `Applications` 软链
- 嵌套: `Contents/Frameworks/FlyEnv Helper*.app` 四个是 Electron 自己的 GPU / Plugin / Renderer 子进程（`phpstudy.xpfme.com.helper*`，`LSUIElement=true`），随主进程退出，不常驻
- 签名: 4.15.2、4.20.0、4.20.1 都是 Team `956BZQ2F2P`、Notarized Developer ID，Team 没换过
- 校验: GitHub 资产 `digest`。v4.20.1 arm64 dmg `sha256:d6ae9cce1ae7155e0324859e1df6bfe6d3e2bbebc60b22b033a5ae50e414f17a`，v4.20.0 arm64 dmg `sha256:342bb7c10ea6bba20f51439c2d28540c330691c25e234603aa2df1f66e7f5afc`，下载文件的 `shasum -a 256` 都相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，没有 mac 资产时退回列表里最新带 arm64 dmg 的 release；与厂商自己的检查给出的 dmg 是同一个）
- **root helper（不在 bundle 里，换包后继续跑旧版）**:
  - 是什么（4.20.1 真包 + 源码）: `Resources/plist/com.flyenv.helper.plist` 是 LaunchDaemon，`ProgramArguments` = `/Library/Application Support/FlyEnv/Helper/flyenv-helper`，`RunAtLoad` + `KeepAlive`，`AssociatedBundleIdentifiers` = `phpstudy.xpfme.com`。用户在 app 里确认后，`src/main/core/AppHelper.ts` 用 `sudo`（管理员密码框）跑 `Resources/helper/flyenv-helper-init.sh`：先 `codesign -R` 校验 app（identifier `phpstudy.xpfme.com`、Team 956BZQ2F2P）、核对 Info.plist 的 `FlyEnvHelperProtocolVersion`，再把二进制拷到上面的路径、plist 拷到 `/Library/LaunchDaemons/com.flyenv.helper.plist`，`launchctl bootstrap system`。以 root 常驻，退出 app 后仍在
  - 换包后: helper 的可执行文件在 bundle 外，换包不碰它，它继续跑旧版。helper 的 Go 源码（`src/helper-go/main.go`、`darwin.go`、`darwin_policy.go` @ `v4.20.1`）不引用 `/Applications` 或 bundle 内路径。新 app 每次需要提权操作时 `AppHelperCheck` 比对 helper 报告的版本与自己的 `HelperVersion`（4.20.1 源码: 48），不等就抛 `helper_version_mismatch`、发 `needInstall`，由界面请用户确认后重装（管理员密码框）。4.20.0→4.20.1 正好跨了一次（47→48，两个真包的 Info.plist）
  - 为什么不加闸: 厂商唯一的 macOS 更新路径就是下载 dmg 拖进去覆盖（上面「自更新机制」），换完的状态和我们一键完全一样，厂商为它设计了上面的版本比对和重装。换包不毁掉任何东西：旧 helper 被新 app 拒用，直到用户在 FlyEnv 里同意重装。与 SwitchHosts（SMAppService LaunchDaemon、换包后按协议版本重检）同一处理
  - 我们不替用户重装 helper，也不 `bootout` 它：那需要 root，且应由 FlyEnv 自己用它校验过的字节来装
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 启动旧版（4.20.0）会自动检查更新并弹「有新版本」对话框（取消 / 查看更新日志 / 下载新版本），点哪个都只是开浏览器
  - 第一次做需要提权的操作时（hosts 等，`AppHelper.ensureReady` → `needInstall`）FlyEnv 会请求安装 helper 并弹管理员密码框——这超出一键的预授权，第二轮不要触发它；若机器上本来就装着 helper，换包后新 app 会提示重装，同样不要代为确认
  - 退出时 FlyEnv 先停它管理的服务（`Application.ts` 的 quit 序列: service-drain、fork-drain、services-stop、hosts 清理），退出会比普通 Electron app 慢；`duo install` 运行中一轮要看退出是否在超时内完成
  - 有托盘窗口，关窗不等于退出；设置里有开机自启（`setLoginItemSettings`，主 app 自己作为登录项，不是独立 helper）
  - 首启写 `~/Library/FlyEnv`、`~/Library/Application Support/FlyEnv`、`~/Library/Logs/FlyEnv`（cask `zap` 列表）；`Resources/helper/flyenv.sh` 是给 zsh 的 `chpwd` 钩子，是否被写进 shell 配置没核
  - Info.plist 没有 URL scheme、没有文档类型
  - 有许可证功能（`api.one-env.com` 激活码），与更新无关

## 已知问题
- Changelog 有损（见 Changelog 节）
- 厂商先发 release 后传资产，发布与挂资产之间有一段时间 `/releases/latest` 没有 mac 包，这期间给的是上一版（正确，非幻影更新）
- 4.15.1 及更早的资产已删，这些版本的 Team 无法实测

## 如何复验
```bash
gh release view v4.20.1 -R xpf0000/FlyEnv --json assets -q '.assets[]|select(.name|test("dmg$"))|.name+" "+.digest'
curl -sSLO https://github.com/xpf0000/FlyEnv/releases/download/v4.20.1/FlyEnv-4.20.1-arm64.dmg
curl -sSLO https://github.com/xpf0000/FlyEnv/releases/download/v4.20.0/FlyEnv-4.20.0-arm64.dmg
.claude/skills/coverage-discovery/scripts/check-bundle.sh FlyEnv-4.20.0-arm64.dmg   # Team 956BZQ2F2P, Notarized, updater electron-updater (unused)
swift run --package-path application-test feed-discover FlyEnv-4.20.1-arm64.dmg     # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify FlyEnv-4.20.0-arm64.dmg --expect stable   # GitHub, UPDATE → 4.20.1
swift run --package-path application-test channel-verify FlyEnv-4.20.1-arm64.dmg --expect stable   # up to date
curl -sL https://raw.githubusercontent.com/xpf0000/FlyEnv/refs/heads/master/latest-mac-arm64.yml | head -1   # 厂商自己的检查读的版本
```

channel-verify 原始输出（2026-10-26）:
```
4.20.0 dmg: detected channel → stable; winning source GitHub; latest 4.20.1;
  download https://github.com/xpf0000/FlyEnv/releases/download/v4.20.1/FlyEnv-4.20.1-arm64.dmg;
  changelog pane source structured: 1 entries; newest 4.20.1: 1 items, headings ["**📦 Build & Transparency**"]; first items ["**Global Build History:** [GitHub Action"];
  status UPDATE → 4.20.1
4.20.1 dmg: detected channel → stable; winning source GitHub; latest 4.20.1; status up to date
4.15.2 dmg: detected channel → stable; winning source GitHub; latest 4.20.1; status UPDATE → 4.20.1
```

## 建议下一步
1. 主会话真机两轮（上一版 4.20.0 → 4.20.1，或 v4.20.2 资产挂上后的新版），结果写回「一键安装」并把 README 行改成 ✓。不要触发 helper 安装
2. Changelog: `GitHubMarkdownParser` 需要把 `### **N. 标题**` 这种编号功能标题当作条目（或分节标题）保留，并在没有列表时取段落；这是引擎改动，需要单独决定
