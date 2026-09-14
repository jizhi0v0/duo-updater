# macFUSE

> 首次审计 2026-08-29；**2026-09-14 复核**：下载真实 dmg、`pkgutil --expand-full` 解开安装包
> 逐个读 bundle（**没有安装**），重查 GitHub Releases 和生产代码。复核推翻了首次审计的一条事实
> （"没有任何 `.app`"），但结论不变，理由见下。

## 基本信息
- 主页: https://macfuse.github.io/
- GitHub: `github.com/macfuse/macfuse`（GitHub Releases，持续发布，5.x 线活跃）
- Homebrew cask: `macfuse`，version `5.3.3`，**`auto_updates: true`**
- Team ID: `3T5GSNBU6W`（安装包里四个 bundle 都是这个 Team）
- 自更新机制: 无 Sparkle（下面四个 bundle 都没有 `SUFeedURL`）；用户靠重新运行安装包升级。
- 证据来源：官方 dmg 解包后的安装包载荷，没有取自任何已安装副本。

## 安装包里实际有什么（2026-09-14，`macfuse-5.3.3.dmg` 解包实测）

dmg 顶层是 `Install macFUSE.pkg` 和 `Extras/macFUSE 5.3.3.pkg`（cask 装的是后者）。
后者的 `Distribution` 有两个组件，`hostArchitectures="arm64,x86_64"`：

| 组件 | 落地路径 | bundle id | 版本 (short / build) |
|---|---|---|---|
| `io.macfuse.installer.components.preferencepane` | `/Library/PreferencePanes/macFUSE.prefPane` | `io.macfuse.preferencepanes.macfuse` | `5.3.3` / `5.3.3` |
| `io.macfuse.installer.components.core` | `/Library/Filesystems/macfuse.fs` | `io.macfuse.filesystems.fs.macfuse` | `5.3.3` / `5.3.3` |
| ↳ 嵌在 `.fs` 里 | `macfuse.fs/Contents/Resources/macfuse.app` | `io.macfuse.app` | **`1.0` / `1`** |
| ↳ 嵌在 `.fs` 里 | `macfuse.fs/Contents/Resources/uninstall_macfuse.app` | `io.macfuse.uninstaller` | `1.1` / （无 `CFBundleVersion`） |

另外：`macfuse.fs/Contents/Extensions/{12,14,26}/macfuse.kext`（按系统版本分的内核扩展），
`macfuse.app/Contents/Extensions/` 下有两个 FSKit 模块 `io.macfuse.app.fsmodule.macfuse.appex`、
`io.macfuse.app.fsmodule.macfuse-local.appex`。cask 的 `uninstall` 还会卸 launchd 服务
`io.macfuse.app.launchservice.broker` / `.daemon`。

首次审计从 cask `zap` 里的缓存目录名反推 bundle id 是 `io.macfuse.preferencepanes.macfuse`，
标为"推测"——这次在真实 prefPane 上读到了，**已坐实**。

## 结论：扫描模型接不到它，不是缺 recipe —— 当前架构下决定不做

首次审计写的是"**没有任何 `.app` 落到 `/Applications` 或其他任何位置**"。这句是错的：
上表里有两个 `.app`。但它们嵌在 `/Library/Filesystems/macfuse.fs/Contents/Resources/` 里，
结论依然成立：

- `AppScanner.defaultLocations` 只有 `/Applications`、`/Applications/Utilities`、`~/Applications`、
  `/Library/Input Methods`、`~/Library/Input Methods`（加用户自定义 `extraLocations`）——不含
  `/Library/PreferencePanes`，也不含 `/Library/Filesystems`（2026-09-14 读 `AppScanner.swift` 核对）。
- 扫描对条目的过滤是 `entry.pathExtension == "app"`，`.prefPane` / `.fs` 直接跳过。
- **就算把 `/Library/Filesystems` 加进扫描目录，扫到的也是错的东西**：唯一带产品版本
  `5.3.3` 的是 `.prefPane` 和 `.fs`；嵌套的 `macfuse.app` 自报 `1.0`。拿它去跟 GitHub 的
  `5.3.3` 比，会永远报"有更新"。
- 2026-09-14 在 `DuoUpdaterCore/Sources`、`App/Sources`、`CLI/Sources` 里 grep
  `prefpane|PreferencePanes|kext|SystemExtension`：只命中 Little Snitch recipe 里的一段注释和
  PermissionFlow 里一个"系统设置"面板 id，**没有任何代码把这类软件建模成已安装条目**。
  （首次审计写的是"全文 grep 零命中"，现在不是零，但性质相同。）

**结果**：即使往 `GitHubReleaseRule` 注册表里加一条 macFUSE 规则（GitHub 侧本身可行，见下一节），
`UpdateChecker` 也永远不会评估它——`AppScanner` 不会为 macFUSE 产出能用的 `InstalledApp`。
这样的 recipe 是死代码，而且会让人以为"已覆盖"。

## 如果只看 GitHub 侧（假设扫描模型问题被解决之后）

留给将来万一决定扩展扫描范围时参考，**不是现在要接入的东西**：

- Releases API（2026-09-14，`gh api repos/macfuse/macfuse/releases`）：tag 形如 `macfuse-5.3.3`，
  `prerelease` 标记正确：
  ```
  macfuse-5.4.0  prerelease=true   published=2026-09-07
  macfuse-5.3.3  prerelease=false  published=2026-07-04
  macfuse-5.3.2  prerelease=true   published=2026-06-17
  macfuse-5.3.1  prerelease=true   published=2026-06-13
  macfuse-5.3.0  prerelease=true   published=2026-06-07
  macfuse-5.2.0  prerelease=false  published=2026-04-09
  ```
  `/releases/latest` 返回 `macfuse-5.3.3`，跳过了之后的 `5.4.0` 预发布，`usePrereleases: false` 可用。
- 每个 release 稳定带 `macfuse-<version>.dmg`、`.sha256`、`.sha256.sig`、`-debug.tbz` 四个资产。
- 版本方案：GitHub tag、cask `version`、dmg 文件名、`Distribution` 的 `pkg-ref version`、
  prefPane 与 `.fs` 的 `CFBundleShortVersionString` 六处都是 `5.3.3`（2026-09-14 实测）。
  **例外是嵌套的 `macfuse.app`（`1.0`）**——将来若接入，比较对象必须是 prefPane 或 `.fs`，不能是它。

## 覆盖矩阵

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗（auto_updates，让位）| — | ✗（扫描模型接不到，非 recipe 缺口）| — |

当前生效源: **无**。

## 一键安装
- 状态: 不适用（连检测都做不到）。另外安装包带内核扩展和 FSKit 模块，风险模型和替换一个普通
  `.app` 完全不同。

## 已知问题
- `AppScanner` 的发现模型是"`.app` in 固定目录"。只装 `.prefPane`、`.fs` 文件系统包、
  内核扩展这类软件完全在模型之外——不是 macFUSE 一个的问题。

## 建议下一步
1. **不要**为 macFUSE 加 `GitHubReleaseRule` 或任何 recipe——连不到 `UpdateChecker`，是死代码。
2. 真正的决策点是要不要让扫描认识 `/Library/PreferencePanes/*.prefPane`、`/Library/Filesystems/*.fs`
   这类新的"已安装软件"。这比加一条 recipe 大得多：新的扫描目录、新的 bundle 布局假设、
   选哪个 bundle 的版本（见上面 `macfuse.app` = `1.0` 的坑）、以及含内核扩展的包要不要一键装。
   **这是需要用户拍板的范围决策，不在本次审计里做。**

## 如何复验
```
# GET https://formulae.brew.sh/api/cask/macfuse.json → 5.3.3, auto_updates=true, artifacts: pkg（无 app）
# gh api repos/macfuse/macfuse/releases/latest → macfuse-5.3.3（5.4.0 是 prerelease）
# 下载 macfuse-5.3.3.dmg；hdiutil attach -nobrowse -readonly；pkgutil --expand-full "Extras/macFUSE 5.3.3.pkg" <dir>
#   PreferencePane.pkg/Payload/Library/PreferencePanes/macFUSE.prefPane → io.macfuse.preferencepanes.macfuse 5.3.3
#   Core.pkg/Payload/Library/Filesystems/macfuse.fs/Contents/Resources/macfuse.app → io.macfuse.app 1.0
# 读 AppScanner.defaultLocations → 不含 /Library/PreferencePanes、/Library/Filesystems
```
