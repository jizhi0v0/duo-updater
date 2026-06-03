# 合并 Changelog / Traffic / Settings 为单一工作台窗口，并修五个问题

## Context

DuoUpdater 当前有三个独立的顶层窗口：`Changelog`（`ChangelogWindowView`）、`Traffic`（`TrafficWindowView`）、标准 `Settings` 场景。它们各自打开、互不相干，导致一组体验问题：

1. 点设置图标，窗口不弹到最前（`openSettings()` 的 SwiftUI 已知激活问题）。
2. 授予 App Management 权限后，系统没给「Quit & Reopen」，新权限不生效。
3. Changelog 来回切换卡顿、每次点击都转圈、像每次都重新抓取（detail 用 `.id(selected.id)` 整块重建，`StructuredChangelogView` 的 `@State` 每次复位重跑 `.task load()`；WebView fallback 每次重建 `WKWebView` 重新加载页面）。
4. 每次启动都弹「DuoUpdater.app would like to access data from other apps.」（冷启动时 `init`→`reschedule` 立即跑后台检查 → `beginTestFlightLoad` 读 TestFlight 沙盒容器 → 触发 App Data TCC 提示）。
5. Traffic 显示 Zero KB（`~/Library/Application Support/com.duoupdater.app/` 目录根本不存在 → 从未记录过；只有经我们自己 `Downloader` 的下载——Sparkle/Vendor/GitHub/pkg——才计量，brew / App Store / “Open”/托管类一律不计，所以空白其实是覆盖范围 + 文案问题，不是写入坏了）。

用户已确认要把三者**合并为一个 window**，采用 **App 为中心**的结构：左侧 App 列表，右侧 detail 用一个开关在「更新日志 ⇄ 流量」之间切，Settings 放 toolbar 齿轮（sheet）。菜单栏弹窗**保留**为「快速一瞥 + 一键更新」。

预期结果：一个统一的工作台窗口承载日志/流量/设置；五个问题随结构重做一并解决。

## 目标结构

- **菜单栏弹窗**（`MenuContentView`）：保持更新列表 + 一键更新；footer 用单个「打开窗口」按钮打开工作台；header 齿轮 → 打开工作台并直接弹设置 sheet。
- **工作台窗口**（新 `WorkbenchWindowView`，`windowID = "workbench"`，标题 "Duo Updater"）：`NavigationSplitView`，左 App 列表，右 detail 按模式切换；toolbar 有 segmented `Picker`（Release Notes / Traffic）+ 齿轮按钮（设置 sheet）。
- **Settings**：保留 `Settings {}` 场景供 ⌘, 用（同一个 `SettingsView`），但主入口是工作台齿轮的 sheet。

## 改动清单

### 1. 新建 `App/Sources/WorkbenchWindowView.swift`（吸收并删除旧的两个窗口文件）

把 `ChangelogWindowView.swift` 与 `TrafficWindowView.swift` 合并进此文件，然后删除这两个旧文件。复用其中的子视图：`ReleaseNotesText`、`StructuredChangelogView`、`ChangelogEntryView`、`WebView`、`TrafficDetail` 的事件行渲染等（整体搬过来）。

- `static let windowID = "workbench"`；`@State selection: String?`、`@State mode: DetailMode`（`.releaseNotes | .traffic`）、`@State showSettings`。
- **侧栏**：按 `mode` 决定排序与 trailing 标签——
  - `.releaseNotes`：沿用现有 `apps`（有更新置顶，其余字母序），trailing 显示版本箭头（复用 `ChangelogSidebarRow`）。
  - `.traffic`：按字节降序（用 `model.trafficStats` 排），trailing 显示该 App 字节数（`model.trafficStats.first { $0.appID == result.app.id }`，`InstalledApp.id == path.path` 与 traffic 的 `appID` 同源）。
  - 侧栏 footer 常驻「Total downloaded: X」（`model.trafficTotalBytes` + `ByteFormat.string`），保住原 Traffic 窗口的总量信息。
- **detail**：选中 App + `mode`——
  - `.releaseNotes`：抽出原 `ChangelogDetail` 的 `notes` 渲染逻辑为可复用视图，但走下面第 3 条的缓存修复。
  - `.traffic`：渲染该 App 的下载历史（复用 `TrafficDetail`）；无记录时给空状态，文案点明「brew / App Store / 托管类下载不计量，只统计经本应用下载的更新」。
- **toolbar**：segmented `Picker($mode)`；齿轮 → `showSettings = true`。
- `.sheet(isPresented: $showSettings)`：包一层 `NavigationStack` + toolbar「Done」关闭，内嵌 `SettingsView(prefs: model.prefs, model: model)`。
- 搬运 `ChangelogWindowView` 已有的窗口生命周期逻辑：`.task` 首开刷新、`didBecomeKeyNotification` + 15s timer 的 `refreshLocal`、`onAppear` 提升 `.regular` / `onDisappear` 回 `.accessory`。
- **观察 `model.pendingShowSettings`**：为 true 时自动 `showSettings = true` 并复位（菜单齿轮的路由）。

### 2. `App/Sources/DuoUpdaterApp.swift`

- 删掉 `Window("Changelog", …)` 和 `Window("Traffic", …)` 两个场景，替换为单个 `Window("Duo Updater", id: WorkbenchWindowView.windowID) { WorkbenchWindowView(model: model) }`，`.defaultSize` ~ 900×600，`.windowResizability(.contentMinSize)`。
- 保留 `MenuBarExtra` 与 `Settings { SettingsView(...) }`（⌘, 支持）不变。

### 3. `App/Sources/AppListModel.swift` —— 修 #3、#4、#5 的数据层

- **Changelog 缓存（#3）**：新增 observable `private(set) var changelogByBundleID: [String: Changelog]` 与 `func loadChangelog(for: UpdateResult) async`：字典命中即同步返回（detail 不转圈），未命中再走 `ChangelogService.load`（其本身已有 15min 网络缓存）并存字典。detail 仅在「字典无键且首次加载」时显示一次 spinner，来回切换读字典 → 瞬时、无转圈。在 `performRefresh` 现有 `ChangelogCache.shared.invalidateAll()` 旁一并清空 `changelogByBundleID`。
- **TestFlight 门控（#4）**：给 `refresh` / `performRefresh` 加 `allowTestFlight: Bool` 参数，向下穿到 `beginTestFlightLoad`：
  - 后台 `scheduler` 的 `backgroundRefresh` 传 `false` → 不碰 TestFlight 容器、冷启动**不再弹** App Data 提示；TestFlight 标记沿用上次「用户在场」检查的结果（`refreshLocal` 已保留 Toolbox/TestFlight 状态）。
  - 用户在场路径（菜单首开 / 工作台首开 / 手动刷新）传 `true`；加一个 session 级 `@ObservationIgnored var testFlightReadThisSession` 标志，确保每次会话首个「用户在场」刷新读一次 TestFlight（此刻弹提示是用户主动触发，自然；Developer ID 签名后授权可跨启动持久）。
- **设置路由（#1）**：新增 `var pendingShowSettings = false`，供菜单齿轮置位、工作台消费。

### 4. `App/Sources/MenuContentView.swift`

- footer：移除「Changelog…」「Traffic…」两个按钮，换成单个「打开窗口」按钮 → `openWindow(id: WorkbenchWindowView.windowID)` + `NSApp.activate(ignoringOtherApps: true)`。
- header 齿轮：改为 `model.pendingShowSettings = true; openWindow(workbench); NSApp.activate(...)`（窗口随之弹到最前，#1 由结构解决；不再依赖会激活异常的 `openSettings()`）。
- `model.start(showUpdates:)` 闭包里 `openWindow(id: ChangelogWindowView.windowID)` 改为 workbench id。
- `.task` 首开逻辑：若结果非空仍想读一次 TestFlight，则调用带 `allowTestFlight: true` 的刷新（用 session 标志避免重复）。

### 5. `App/Sources/SettingsView.swift` —— 修 #2

在 `DiagnosticsSettings` 的 Permissions section（现有「Grant App Management…」下方）增加：
- 一段说明：通过拖拽面板授予 App Management 后，macOS **不会**像系统原生授权那样弹「Quit & Reopen」，新权限可能要重启本应用才生效。
- 「Relaunch DuoUpdater」按钮：`/usr/bin/open -n <Bundle.main.bundleURL>` 拉起新实例后 `NSApp.terminate(nil)`（标准重启自身手法，低风险）。

### 6. 其它

- `NotificationController` / `UpdateNotifier` 中任何「View」动作打开 changelog 窗口的地方，改指 workbench id（`model.start` 已覆盖主路径，搜一遍 `ChangelogWindowView.windowID` / `"changelog"` / `"traffic"` 残留引用一并改掉）。
- WebView fallback 类 App 的转圈（#3 残留）：在工作台文件里加一个 AppKit 侧 `WKWebView` 缓存（仿 `AppIconCache`，按 URL 缓存、上限 ~8），切回已看过的页面复用已加载实例、不再重载。

## 复用点（避免新写）

- 子视图：`ReleaseNotesText` / `StructuredChangelogView` / `ChangelogEntryView` / `WebView`（`ChangelogWindowView.swift`）、`TrafficDetail` / `TrafficSidebarRow`（`TrafficWindowView.swift`）、`ChangelogSidebarRow`。
- `AppIconCache`（`MenuContentView.swift`）、`ByteFormat`、`ChangelogService.load` + `ChangelogCache`、`ChangelogCatalog` / `ChangelogRecipeRegistry`。
- 窗口生命周期模式（`.regular`/`.accessory` 提升、`didBecomeKey` + 15s timer `refreshLocal`）直接搬自 `ChangelogWindowView`。
- TestFlight 门控复用现有 `beginTestFlightLoad` / `reapplyTestFlightWhenGranted` 机制，仅加一个开关参数。

## 验证

- 构建：`xcodebuild -project App/DuoUpdater.xcodeproj -scheme DuoUpdater -configuration Debug build`（按 memory「构建/运行」：UI 改动必须重新 xcodebuild App，`swift test` 只编 core 不会更新 app 二进制）。
- core 单测仍应通过：`cd DuoUpdaterCore && swift test`（本次为纯 UI 改动，预期不受影响）。
- 跑起来逐项手测：
  1. 菜单齿轮 → 工作台弹到最前并直接显示设置 sheet（#1）。
  2. 设置 Diagnostics 里有「Relaunch DuoUpdater」，点击后应用重启（#2）。
  3. 工作台左列切换多个有 recipe / 有 web 页的 App，来回点：首次短转圈、再切回**瞬时无转圈、不重抓**（#3）。
  4. 冷启动应用，**不再**立即弹「access data from other apps」；首次主动打开菜单/工作台时才（按需、一次）出现，授权后跨启动不再弹（#4）。
  5. 走一次可计量安装（Sparkle/Vendor/GitHub/pkg 任一），确认 `~/Library/Application Support/com.duoupdater.app/traffic.json` 生成、工作台 Traffic 模式出现该 App 与总量；无记录的 App 显示解释性空状态（#5）。
```
```
```

注：用户当前 0 流量是因为从没经可计量路径装过更新；此项重点是结构呈现 + 诚实空状态文案，而非「修好一个坏掉的写入器」。
