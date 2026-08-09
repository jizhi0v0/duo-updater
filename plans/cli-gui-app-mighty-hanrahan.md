# duo CLI + 定时 recipe 校验

## Context

两个诉求，一个前提：

1. **CLI** —— 不想为了看/装更新去点菜单栏 GUI。目标是完全独立的 `duo` 命令，但**与 app 共享代码**而不是复制一份。安装动作能否真的在独立 CLI 里跑通，需要先做实验验证再决定范围。
2. **定时校验 recipe** —— 这次 pull 里 `2fcbc0a`(IntelliJ 加了版本段)、`92d6e30`(Brave Beta/Nightly 永远报不出更新)、`67960a9`(delta enclosure 让整个 Sparkle feed 隐形) 全是**在日常使用中偶然发现的**。vendor 悄悄改版面，recipe 静默失效，app 只会把它降级成 "unknown"，没人会注意。需要一个定时任务主动发现，坏一条开一个 issue，自愈自动关，你只看 issue 决定要不要发版。

**一个关键澄清**：你担心"规则内置在 app 里 → 校验必须上云 → 安全性"。其实不必。校验器是一个 **link `DuoUpdaterCore` 的 Swift 可执行文件**，规则跟着二进制走，不需要把规则表导出成云端 catalog。再加上跑在**你自己 Mac mini 的 self-hosted runner** 上，代码、凭据、LLM key 全程不离开你的硬件。

### 现状事实（已核实）

- `DuoUpdaterCore/` 零外部依赖；scan / check / install 引擎全在里面，只有 2 个文件 import AppKit。
- `application-test/` 已经有一个 link Core 的独立可执行文件 `channel-verify`，证明这条路是通的；但它一次只能验一个**已安装**的 app，没有遍历 registry 的模式。
- registry 规模：`VendorProbeRegistry.recipes` **89 条**、`GitHubReleaseRegistry.rules` **13 条**、`ChangelogRecipeRegistry.recipes` **50 条**，全是纯值类型字面量，无闭包。
- `RecipeHealth` 已经建模了"这条 recipe 还活着吗"，但**只在内存里、只有 2 个记录点**（`VendorProbeSource.swift:111/113`、`GitHubReleasesSource.swift:233/254`），**`ChangelogService` 一个都没记**。
- 现有 live 测试全用 `if let v = try await …`，**正则零匹配返回 nil 会静默通过** —— 恰好放过了要抓的 bug（`ChannelGuardTests.swift:342/401/481`；`VendorProbeTests.swift:254` 的候选数组还是硬编码空的）。
- 仓库**没有 `.github/` 目录**，零 CI。`gh api repos/jizhi0v0/duo-updater/actions/runners` 当前返回 0 —— mini 上的 runner 还没注册到这个仓库。
- 本机 macOS **27.0 (26A5388g)**。Apple DTS 确认"独立可执行文件无法加入 App Management 列表"是 26.1/26.2 的**已知回归、26.3 beta 已修**，所以 27 上应该可行，**但必须实测**。

---

## 交付物 A：`duo` CLI

### A0. TCC 可行性实验（先做，只 gate 安装范围）

四个可分离的问题，用最小实验回答：

| # | 问题 | 观测手段 |
|---|---|---|
| Q1 | Developer ID 签名的独立二进制，在 macOS 27 上能否拿到**自己的** App Management 条目？ | 拖进设置面板前后跑 `TCCPreflight.appManagementStatus()` |
| Q2 | 从终端启动时，responsible process 是它自己还是 Terminal？ | `launchctl procinfo <pid> \| grep -i responsible` |
| Q3 | 从 launchd 启动时呢？ | LaunchAgent + `procinfo` + 探针写 |
| Q4 | 真往 `/Applications/<第三方 app>.app` 里写，会不会 EPERM？ | `log stream --predicate 'subsystem == "com.apple.TCC"'` + `InPlaceSwap.isAppManagementDenial` |

**实验载体**：在 `App/project.yml` 里加一个 `duo-tcc-spike` target，**设置块照抄现有 `DuoUpdaterHelper` target**（`type: tool` + Manual + `Developer ID Application` + team `RS59HDH7Y3`）—— 这是仓库里已有的、可用的"签名独立 Mach-O"配方。`swift build` 出来的是 ad-hoc 签名，测不出结论（`scripts/install.sh` 的注释已经解释过为什么）。

**探针写必须打第三方 app**：自己造的 `.app` 或 `/Applications/DuoUpdater.app`（同 team 豁免）都会假绿。用一个真实的、非 `RS59HDH7Y3` 签名的已安装 app，写 `Contents/.duo-tcc-probe` 再删掉。

装到**固定路径** `/usr/local/libexec/duo-tcc-spike`（TCC 行绑路径 + designated requirement，重建换路径就失效）。

**Rung 0 —— disclaim 再 exec（无论结果都值得做）**：macOS 把 TCC 归属到 responsible process，终端起的 CLI 归属给终端。`responsibility_spawnattrs_setdisclaim` 可以脱钩，用 `TCCPreflight.swift` 已有的 `dlsym` 渐进增强写法解析（找不到符号就降级）。新建 `DuoUpdaterCore/Sources/DuoUpdaterCore/Support/Disclaim.swift`，~50 行。**这是实验里性价比最高的一项** —— 可能把"终端下不行"直接变成"哪都行"。

**失败梯子**（由便宜到贵）：

1. CLI 塞进 app bundle：`DuoUpdater.app/Contents/MacOS/duo` + `/usr/local/bin/duo` 软链。`install.sh` 本来就刻意不 `rm -rf` bundle 而是 rsync 就地替换，路径稳定。
2. CLI 把 apply 阶段通过 XPC 交给常驻 app（复刻 `PrivilegedHelperClient.swift` 里的 peer pinning）。丢掉"完全独立"，但顺带解决 CLI/GUI 并发安装冲突。
3. 扩展已有 root helper `com.duoupdater.helper`，加一个 `replaceBundle` 方法。
4. CLI 只做不需要 App Management 的路线：Homebrew、`.pkg`（交给 Installer.app）、`~/Applications` 下的 app。

注意 `InPlaceSwap.privilegedReplace` 走 `osascript ... with administrator privileges`，**无 GUI session 会挂**，任何 headless 路径都不能碰到它。

### A1. 代码共享：install policy 下沉到 Core

判据：**读 prefs 后返回决策的下沉，碰 `installing[id]` / `NSWorkspace` / `@Observable` 的留在 GUI。**

新建三个文件：

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Engine/UpdateSettings.swift` —— `UpdateSettings` 值类型 + `PreferenceKey`（**per-path key 派生必须从 `App/Sources/Preferences.swift:390-410` 搬过来，不能两边各写一份，否则 CLI 和 GUI 会读到不同 key 空间**）+ `UpdateSettingsStore` 协议 + `UserDefaultsSettingsStore(suiteName: "com.duoupdater.app")`。`VendorInstallPolicy` / `AppStoreUpdateStrategy` 枚举整体搬。
- `.../Engine/UpdatePolicy.swift` —— 纯静态无 I/O，吸收 `AppListModel.swift` 的 `canAutoInstall`(1182)、`requiresInstaller`(~1250)、`defersToSelfUpdater`(1275)，以及 `performInstall` 那个大 switch (~1900–2120) 的**分支选择**那一半，产出 `InstallRoute` 枚举。
- `.../Engine/SourceStack.swift` —— `AppListModel.makeSources`(588) 原样搬，已经是纯函数。

`InstallCoordinator`（actor，吸收 `InstallPermits` + switch 的执行那一半，通过 `InstallHost` 协议回调宿主）留到后期，**App Store 分支可以永远不搬** —— 它最脏（mas outdated pre-flight、区域锁 AX、三路 fallback），而 CLI 本来就不做 AX，直接调 `MASInstaller` 即可。

**第一刀（零行为变化）**：只搬 `UpdateSettings` + `PreferenceKey` + `UpdatePolicy`，`AppListModel` 那三个方法变成一行转发。搬之前先针对现实现写 characterisation 测试锁住行为。这一刀让这段逻辑**第一次变得可单测**（今天它埋在 3801 行 `@MainActor @Observable` 里）。

### A2. CLI 包

**新建顶层 `CLI/` 包**（不放 `application-test/` —— 那个包的 manifest 明说"刻意不进主包，永不随 app 发布"，而 CLI 是要发布的）。两条构建路径共用一份源码：

- `swift build --package-path CLI` —— 快速迭代 + CI 用（校验器不需要 TCC，ad-hoc 签名够）。
- `App/project.yml` 加 `DuoUpdaterCLI` target（设置照抄 `DuoUpdaterHelper`）—— **发布用的 Developer ID 签名二进制**，能持有 TCC 授权。

`make cli` → 新建 `scripts/build-cli.sh`，**原样复用 `install.sh` 的签名验证闸**（拒 ad-hoc、要求 team `RS59HDH7Y3`、要求 `codesign -d -r-` 里有 `anchor apple generic` 而非裸 cdhash），装到固定的 `/usr/local/libexec/duo` + `/usr/local/bin/duo` 软链。

**参数解析手写**（~150 行，照 `channel-verify` 的风格）。理由：发布二进制走 XcodeGen，引 swift-argument-parser 意味着往 `App/project.yml` 再塞一个远程包；且仓库对 Core 的零依赖是刻意姿态。代价是 `--help` 要手写。

子命令：

```
duo list      [--json] [--all] [--source <name>]
duo check     [<app>…] [--json] [--include-ignored]
duo install   <app>… | --all  [--dry-run] [--yes] [--route auto|brew|pkg|vendor|sparkle|mas]
duo restart   <app>…
duo ignore | unignore | skip | unskip   <app>
duo backups   list | restore <app>
duo doctor    [--json]        # TCC 状态 / helper 注册 / token 来源 / 锁持有者
duo verify    …               # 见交付物 B
duo verify-triage …           # 见交付物 B
```

`<app>` 解析顺序：安装路径 → bundle ID → 名字前缀（不唯一就报错，装东西绝不猜）。

`--json` 用 **NDJSON**（每行一个对象），这样 `duo install --all --json | jq` 能流式看到进度而不是等 20 分钟。首行带 `schemaVersion`。退出码：`0` 全好 / `1` 有失败 / `2` 用法错 / `3` 被权限挡住（App Management / Accessibility / helper）。

**与常驻 GUI 共存的三个坑**：

1. `TrafficStore` / `ReleaseTimelineStore` / `ChangelogDiskCache` / `BackupStore` 都硬编码解析到 `~/Library/Application Support/com.duoupdater.app/`，两个进程整文件写会互相覆盖 → 新增 `Support/InstallLock.swift`（`flock(2)` 建议锁，CLI 拿不到就**快速失败并报出持有者 pid**，不要无限等），并给这四个 store 加 **`DUO_STATE_DIR` 环境变量覆盖**（CI 上必须用，见下）。
2. `UserDefaults` 必须显式 `suiteName: "com.duoupdater.app"`；且 `Preferences` 在内存里持有副本并 `didSet` 回写，CLI 写完会被 GUI 下一次写覆盖 → **v1 的 CLI 只读为主**，只有 `ignore/skip` 系列写，写完 `CFPreferencesAppSynchronize` + 发 `DistributedNotificationCenter` 通知让 GUI 重读。
3. 同一个 app 并发安装 → 每 app 一把锁；若走了梯子 rung 2 则天然消失。

---

## 交付物 B：定时 recipe 校验

### B1. 先让失败可归因（Core 侧前置改动）

`VendorProbeSource.probe` 现在把 **8 种失败塌缩成一个 `nil`**：非 2xx、非 3xx、缺 `Location`、URL 畸形、unzip 非零、plist 空、plist 缺 key、正则零匹配。而且 `resolveInstall` 失败是完全静默的 —— 一条"版本还能读、一键已经死了"的半坏 recipe 今天**毫无信号**。

在 `VendorProbeSource.swift` 内加：

```swift
public enum ProbeFailure: Sendable, Equatable {
    case notApplicable(String)                  // toolbox 托管 / 渠道不匹配 / 无 recipe
    case transport(urlErrorCode: Int, String)   // URLError —— INFRA 类
    case httpStatus(Int)
    case redirectMissingLocation
    case malformedResolvedURL(String)
    case archiveExtractionFailed(String)
    case plistKeyMissing(entry: String, key: String)
    case versionPatternNoMatch(sampleBytes: Int)
    case installURLUnresolved                   // 新信号：版本好的，install spec 死了
    case checksumPatternNoMatch
}
public struct ProbeOutcome: Sendable { /* recipeID, remote, failure, httpStatus, bodySample(≤4KB,已脱敏), elapsedMs */ }
public extension VendorProbeSource { func probeDiagnostic(_ recipe: VendorProbeRecipe) async -> ProbeOutcome }
```

实现方式：把 `probe` 重构成内部构造 `ProbeOutcome`，`latestVersion(for:)` 塌缩成 `outcome.remote` —— **行为逐字节不变**。`probeDiagnostic` 必须**长在 `VendorProbeSource` 内部**，才能共用同一个 `noRedirectSession`、同一个浏览器 UA、同一个 `versionFeedCachePolicy`、同一套 `preferHTTPS` 规范化。在 CLI 里另写一遍会产生假绿假红。

另外两项独立有价值的修补：
- `GitHubReleasesSource.swift:254` 有 `Log.source.error("… none matched /pattern/")`，`VendorProbeSource` 正则失配时**什么都不记** → 补一条对称的 error 日志。
- `ChangelogService.load` 在 cache-miss 闭包里补 `RecipeHealth.recordSuccess/recordMiss(id: "changelog:<bundleID>:<channel>", source: "Changelog")`（放 cache-miss 里，命中内存缓存时不刷屏）。这是 app 侧的真 bug，顺手修。再加 `loadUncached(...)` 给校验器用 —— 否则 `ChangelogDiskCache` 会让重复扫描根本不发请求。
- 给 `GitHubReleasesSource` 加对应的 `resolveDiagnostic(_ rule:)`。

因为这三个诊断 API 都接**recipe** 而非 app，校验器**不需要合成 `InstalledApp`**。合成路径只留给可选的 `duo verify --end-to-end`（额外走一遍渠道闸和 toolbox 闸）。

### B2. 失败分类 → 动作

| 类 | 成员 | 动作 |
|---|---|---|
| **RECIPE** | 正则零匹配、4xx、缺 Location、URL 畸形、解压失败、plist 缺 key、`installURLUnresolved`、checksum 失配 | 可开 issue + 可喂 LLM |
| **INFRA** | `transport(*)`、5xx、429 | 本轮退避重试 ×2；仍失败只计数，**绝不开 issue** |
| **SANITY** | 匹配到了但值可疑（见下） | warning 级 issue，可喂 LLM |
| **SKIPPED** | 带凭据的、`notApplicable` | 只报告，不动作 |

**SANITY 启发式**（抓"匹配到了但抓错数字"这一类，全确定性）：不以数字开头 / 超过 6 段 / 超 40 字符；`VersionComparator.isNewer(baseline.lastGoodVersion, than: extracted)` 即**版本回退**；抓到的串原样出现在**请求 URL** 里（说明匹配到了 query string 而非响应体）；形如年份；90 天没变而 Homebrew 报了更新的。

### B3. 交叉验证（确定性 oracle，不需要 LLM）

- **Homebrew**：`HomebrewCaskCatalog.entry(forBundleID:)` / `entry(forAppFilename:)` 目前是 `internal`，需改 `public`。一次 5MB 拉取缓存 6 小时，能覆盖 79 个 vendor bundle ID 里的相当一部分。注意 `byBundleID` 是从 `uninstall.quit` 推出来的，覆盖不全，要 fall back 到 `byAppFilename`，**依赖它之前先量一下实际重合率**。判定：完全一致=绿；只差最后一段=info（brew 滞后）；major/minor 不同=**warning**。
- **GitHub 规则**：把 tag 抽出的版本和**所选 asset 文件名**抽出的版本对照 —— 同一 payload 的两次独立读取，能抓到 `versionPattern` 匹配到 tag 里错误部分的情况。
- **Changelog**：把最新一条 `Changelog.Entry.version` 和同 bundleID 的 probe / GitHub 结果对照。changelog 说 1.2.0 而 probe 说 1.4.0 = `entryPattern` 坏了。

### B4. 基线与持久化

**不要往 `RecipeHealth` 里写**。它的 doc comment 明确说明是刻意的 session-scoped 内存态，Diagnostics 面板回答的是"此刻这个 app session 里它工作吗"；批量扫描写进去会污染这个语义，而且 `Entry` 也装不下样本 / HTTP 状态 / issue 号。

校验器自己的状态，提交进仓库 `verify/baseline.json`：

```json
{ "schemaVersion": 1, "updatedAt": "…",
  "entries": { "vendor:com.example.foo:stable": {
      "lastGoodVersion": "3.4.1", "lastGoodAt": "…",
      "consecutiveFailures": 0, "lastFailureKind": null,
      "issueNumber": null, "closedAt": null } } }
```

这一个文件同时是**单调性基线 + 抖动抑制器 + issue 去重表**，所以对账逻辑永远不用去 GitHub 搜。运行产物 `verify/report.json` / `report.md` 不提交，走 `actions/upload-artifact`。

### B5. 速率与礼貌

vendor **全局并发 4、每 host 并发 1**，同 host 间隔 250ms 抖动，尊重 `Retry-After`，支持 `--only <bundleID>` 点验。GitHub 13 个请求，把 `${{ github.token }}` 经 `GitHubToken.resolve(explicit:)` 传进去（5000/时 而非 60/时 —— 那台 mini 上可能还有别的东西在共享出口 IP）。changelog 约 70 个（部分 `indexLinkPattern` 要两跳），且要**强制绕过两层缓存**。合计 ≈175 个请求，4 并发下约 3 分钟。**每天一次**。

### B6. 安全规则（硬要求）

1. **凭据标记编码在 Core 里而不是 CLI 里**，避免漂移：给 `VendorProbeRecipe` / `GitHubReleaseRule` / `ChangelogRecipe` 加 `credentialBearing: Bool = false`。已知成员：**CleanShot**（解析出的 appcast URL 带 `?key=<licenseKey>`，`CleanShotChannel.swift` 自己的注释就写着"加任何 feed-URL 日志前先重审"）、**Alcove**（Bearer JWT，且下载复用它）。**TablePlus 不是密钥**（`X-Tiny-Beta-Update: true` 是字面量），可以验，但 header 照样从输出里抹掉。
2. `AlcoveUpdateSource` 不在任何 registry 里，校验器天然够不到 —— **加一条测试锁住这个事实**，防止将来重构把它拖进来。
3. 默认**跳过**所有 `credentialBearing`。`--include-credentialed` 只给本地用，且再加一道 `DUO_ALLOW_CREDENTIALED=1` 环境变量闸，让误改的 workflow 打不开它。
4. **一个 `Redactor`，套在所有离开进程的字符串上**（报告文件 / issue 正文 / LLM payload / stdout / 日志）：丢弃名为 `key|token|license|auth|sig|signature|access_token|instance|api_key` 的 query item；整条丢弃 `Authorization`/`Cookie`/`Set-Cookie`；正则抹 `gh[pousr]_[A-Za-z0-9]{20,}`、`eyJ[A-Za-z0-9_-]{10,}\.`、`[A-Fa-f0-9]{32,}`、`sk-ant-[A-Za-z0-9_-]{20,}`；样本截 4KB；剥 `<script>`。**用真实的 CleanShot / Alcove URL 形状写单测。**
5. **校验器绝不下载安装包** —— 只解析 URL，最多 `HEAD`。在 verify 命令路径上加代码级断言，永不调用 `VendorInstaller.download` / `Downloader`。
6. 带凭据的源只记 host，不记解析后的完整 URL。

### B7. LLM 分诊阶段

**准入闸**（全满足才调用）：类别为 RECIPE 或 SANITY；`credentialBearing == false`；`consecutiveFailures >= 2`（一轮抖动不花钱）；熔断未触发。

**熔断**：一轮里超过 30 条被标记 = 基础设施故障（DNS / 门户认证 / mini 断网），不是 30 家 vendor 同时改版 → 整段跳过 LLM、跳过开 issue，只留运行注记。硬上限 `--llm-max-calls 20`。

**送什么**：app 名、bundle ID、渠道、**只给 host**（或剥掉 query 的 URL）、`mode`、当前 `versionPattern`、失败类型、`baseline.lastGoodVersion`、脱敏后的响应体样本 —— **取前 3000 字符 + 后 1000 字符**（版本 feed 的最新条目在头在尾都有可能，仓库里已经为此有 `bodyPatternLast` 这种机制，天真的头部截断会漏掉升序 feed）。

**绝不送**：任何 credentialBearing 的东西、原始 header、未脱敏正文、`Keychain.swift` 里的一切、GitHub token。

输出走受约束 JSON schema：`{"diagnosis":…, "proposedVersionPattern":…, "extractedFromSample":…, "confidence":…}`，用前先校验。

**抓回来的 vendor 页面是不可信的、可被攻击者影响的内容。** prompt 必须把它明确框定为"待分析的数据"而非指令；输出是固定 schema；输出不被执行、不被 eval、不写进源码。这一点写进 prompt 也写进 `verify-triage` 的 doc comment。

**确定性复核（这一段才是可信的部分）**：LLM 给的正则先 `NSRegularExpression` 编译（编不过直接扔），再用**生产用的** `VendorProbeRecipe.extractVersion(from: sample, pattern: proposed)` 跑存下来的样本。issue 里就显示：

> ✅ 建议的 pattern 从样本中抽出 `4.7.9`（上次正常值：`4.7.6`）

这一行是确定性的、可信的；旁边那段散文不是，要明确标注。

**模型/密钥/成本**：分诊用 Haiku 级（4KB 片段上重推正则完全够），`confidence < 0.6` 才升到 Sonnet 级，永不用 Opus。约 5KB in / 500 tokens out 每条，配合 `--llm-max-calls 20`，最坏每月远低于 $1，稳态（0–3 条）就是几分钱。**密钥放 mini 的登录钥匙串**（`security find-generic-password -s duo-verify-anthropic -w`）而不是 Actions secret —— self-hosted runner 上的 Actions secret 会被物化进你自己机器上的进程环境，那台 runner 上跑的任何 workflow 都能读到；钥匙串则完全不进 GitHub。**代价**：runner 必须装成**用户 LaunchAgent**（`./svc.sh install` 不加 sudo），否则登录钥匙串是锁的。不行就退回 Actions secret。

**权限边界**：LLM 输出只能作为 issue 里 `<details>` 折叠块中的建议文本，前缀"未经验证的建议，未经测试不要直接应用"。**绝不允许**改 `VendorProbeRecipe.swift` / `ChangelogRecipe.swift` / `GitHubReleasesSource.swift`，绝不允许开 PR。自动 PR 明确不在 v1 范围。

### B8. mini 上的 self-hosted runner + workflow

**注册**（当前 0 runner，必须做）：

```bash
TOKEN=$(gh api -X POST repos/jizhi0v0/duo-updater/actions/runners/registration-token -q .token)
mkdir -p ~/actions-runner && cd ~/actions-runner
# 下载 actions-runner-osx-arm64 并解包
./config.sh --url https://github.com/jizhi0v0/duo-updater --token "$TOKEN" \
            --name duo-mini --labels self-hosted,macOS,ARM64,duo-mini \
            --work _work --unattended --replace
./svc.sh install    # 不加 sudo —— 用户 LaunchAgent，登录钥匙串才够得到
./svc.sh start
```

self-hosted runner 在**私有**仓库上是被支持的，正因为 fork 跑不了任意代码。这个仓库私有且单人，没问题 —— 但将来任何协作者的 PR 都会在 mini 上执行。mini 休眠会让定时任务排队直至失败，配 `pmset repeat wake` 或 `caffeinate -s`。

**`.github/workflows/recipe-verify.yml`**（仓库今天完全没有 `.github/`）：

- `on: schedule: cron "17 4 * * *"`（避开整点，GitHub 整点队列拥堵）+ `workflow_dispatch`（带 `only` / `skip_llm` 输入）
- `concurrency: { group: recipe-verify, cancel-in-progress: false }` —— 绝不中途杀掉，否则 baseline 写一半
- `permissions: { issues: write, contents: write }`
- `runs-on: [self-hosted, macOS, ARM64, duo-mini]`，`timeout-minutes: 30`
- `env: DUO_STATE_DIR: ${{ runner.temp }}/duo-state` —— **runner 跑在用户 `bobby` 下，和 GUI app 同一个用户**，不隔离就会写进正在用的 `ChangelogDiskCache`
- 步骤：checkout → `swift build -c release --package-path CLI --product duo` → `duo verify --all`（`continue-on-error: true`，recipe 坏了不能让 job 红）→ `duo verify-triage` → `scripts/verify-reconcile.sh` → upload artifact → 提交 `verify/baseline.json`（`[skip ci]`）

**为什么 `GITHUB_TOKEN` 就够**：issue 开在**同一个**仓库里，`${{ github.token }}` 是 per-job 的、精确 scope 到该仓库的安装令牌，配 `permissions: issues: write` 即可。公有/私有在这里不相关 —— 令牌是按仓库授权而非按可见性。只有往**别的**仓库（比如 `duo-updater-releases`）开 issue 才需要 PAT，本方案不需要。

两个调度坑：`schedule:` **只在默认分支上生效**，workflow 必须先合进 `main` 才会跑；仓库 60 天无活动会被自动禁用定时 workflow —— 上面每天提交 baseline 恰好保持"活跃"。

### B9. issue 对账（`scripts/verify-reconcile.sh`，用 `gh`）

**身份**：一条 recipe 一个 issue，id 形如 `vendor:<bundleID>:<channel>` / `github:<owner>/<repo>` / `changelog:<bundleID>:<channel>`。三重携带：`baseline.json` 里的 `issueNumber`（主）、正文里的 `<!-- duo-verify-id: <id> -->`（回退，靠 `gh issue list --search`）、标签 `recipe-broken` + `recipe:<id>`。

| 当前 | 本轮结果 | 动作 |
|---|---|---|
| 无 issue，`consecutiveFailures < 2` | RECIPE 失败 | 只计数不开（杀掉一轮抖动） |
| 无 issue，`>= 2` | RECIPE 失败 | `gh issue create`，标题 `Recipe broken: <App> (<source>) — <failureKind>`；正文含失败类型、endpoint host、当前 pattern、上次正常版本、脱敏样本节选、确定性复核行、`<details>` LLM 建议 |
| 有 open issue | 同一失败类型 | **每 7 轮才追评论一次** —— 每天刷评论是这套系统被无视的最大风险 |
| 有 open issue | 失败类型变了 | 立刻评论（形状变了 = 新信息） |
| 有 open issue | 成功 + 通过 sanity + 单调性 | `gh issue close --comment "Self-healed: resolved <v> at <date>."` |
| 已关，`closedAt` 在 14 天内 | RECIPE 失败 | **reopen 同一个 issue**，绝不新建重复 |
| 任意 | INFRA 类 | 永不开 issue |

**熔断**：单轮最多新开 **10** 个 issue，超了就改开一个汇总 issue —— 防止一次断网过夜生成 89 个 issue。

---

## 进度

**阶段 1、2、3 已完成**（2026-08-09）。阶段 3 唯一未做的是 **mini 上的 runner 注册**（需要在那台机器上执行，见下方命令）。

阶段 3 的两处偏离原计划：

- **对账用 Swift 而不是 `scripts/verify-reconcile.sh`。** 状态机是这套系统最容易砸掉的地方（噪音过大 → 被静音 → 什么也抓不到），写成纯函数 `Reconcile.decide(finding:entry:reportable:)` 才能穷举测试；`gh` 只做执行层。13 条测试覆盖"不重复发言""改变形状立刻发言""自愈自动关""14 天内复发 reopen 而不是新建"。
- **`Baseline.Entry` 必须有宽容的 `init(from:)`。** Swift 合成的 decoder 忽略属性默认值、缺 key 直接抛，而 `load` 在解码失败时回退到空 baseline —— 空 baseline 意味着**所有 issue 号丢失，下一轮把每个已开的 issue 都重开一遍**。一次字段改名就能触发。（我自己在阶段 3 改字段名时就撞上了。）

`consecutiveFailures` 改名为 `consecutiveActionable`，且 **warn 也计入** —— `installURLUnresolved` 从来不产生 broken，而 Outlook 和 Signal 两次真实的一键失效都只表现为 warn。

**阶段 1、2 完成时的记录：**实施中相对原计划的修正，都是被真实数据推翻后改的：

1. **原设计只能抓到两个历史 bug 中的一个。** IntelliJ（正则零匹配）能抓；Brave（版本方案错配）什么都不失败，抓不到。补了 `RecipeSanity.remoteBehindInstalled` —— 厂商 feed 不该落后于已装版本。判据必须逐字段镜像 `UpdateChecker.evaluate`（含 JetBrains 产品码归一化），第一版没镜像，把**修好之后**的 Brave recipe 又标红了。
2. **`credentialBearingBundleIDs` 按 bundle id 键有表达力上限。** Alcove 同一个 bundle id 下既有公开 CDN 镜像（registry 里，安全）又有 license 门控 API（不在 registry），列进去会跳过无害的那条而什么也没保护。真正的保护是 `theAuthenticatedAlcoveSourceIsInNoRegistry` 测试。
3. **噪音过滤是承重结构，不是装饰。** 三条 check 的初版分别产生了：Sublime "Build 4200" 误报（改成"完全不含数字"）、6 条 changelog 滞后误报中 5 条是正常行为（改成只比 major.minor）、Figma/Notion 把标题句子当版本号比较（加 version-shaped 门）。每一条都是先跑出来才发现的。
4. **版本模板化的 changelog recipe 单独跑会假红。** `--changelog` 不带版本源时 `resolvedSource` 静默回退到未模板化的 `source`，TB/微信全部报 broken。改成从已装 app 兜底取版本，仍拿不到就报 skipped 并说明原因。
5. **body sample 的截断方式决定它有没有用。** 头部 3KB 在 Next.js 站点上全是 `<link rel="preload">`。加了 `ResponseSample`：先剥 `<head>`/`<style>`（**保留 `<script>`** —— Typeless/Warp 的版本就藏在内联 JSON 里），再头尾各留一段。
6. **`ChangelogService` 需要自己的失败分类**，否则 404 和"版面改了"长得一模一样，报告会把人往错误方向指。加了 `loadDiagnostic`。
7. Homebrew 交叉验证实测覆盖 **28/79 (35%)** 的 vendor bundle id，且**只单向报警**（cask 领先我们才报；cask 落后是常态）。它是 CI 上唯一可用的交叉验证 —— 那里没有已装 app。

---

## 阶段划分

| 阶段 | 内容 | 依赖 | 估时 |
|---|---|---|---|
| **0** | TCC 实验（A0）：`duo-tcc-spike` target、Q1–Q4、disclaim 再 exec 测试 | 只 gate CLI 安装范围 | 0.5–1 d |
| **1 ← 最小可用第一刀** | `CLI/` 包 + `VendorProbeSource.probeDiagnostic` + `duo verify --vendor`（89 条，纯确定性，文本报告，手动跑） | **无** —— 不需要 TCC、不需要代码下沉、不需要 CI | 1–2 d |
| 2 | 扩到 GitHub + Changelog registry；`verify/baseline.json`；sanity + 单调性 + Homebrew 交叉验证；`--json`/markdown 报告；`credentialBearing` + `Redactor` + 其单测 | 1 | 2–3 d |
| 3 | runner 注册 + `recipe-verify.yml` + `verify-reconcile.sh`（纯确定性 issue，暂不接 LLM） | 2 | 1 d |
| 4 | `verify-triage` LLM 阶段 + 钥匙串取 key + 确定性复核 + 熔断 | 3 | 1 d |
| 5 | A1 第一刀：`UpdateSettings` / `PreferenceKey` / `UpdatePolicy` + characterisation 测试 | 0 | 1–2 d |
| 6 | `duo list` / `check` / `doctor`；`SourceStack` 下沉；`DUO_STATE_DIR`；`InstallLock` | 5 | 2 d |
| 7 | `InstallCoordinator` + `duo install`（路线集合由阶段 0 结论决定）；`make cli`；`scripts/build-cli.sh` | 0 + 6 | 3–5 d |
| 8 | 把网络容忍的旧测试改成断言失败**类型**而非 optional | 1 | 0.5 d |

阶段 1 刻意排第一：当天就有价值、不依赖实验结论、而且正是暴露"你今天完全看不见的 recipe 失效"的那一块。

---

## 验证方式

- **阶段 0**：`launchctl procinfo` 输出 + System Settings ▸ Privacy ▸ App Management 里是否出现该二进制 + `log stream --predicate 'subsystem == "com.apple.TCC"'` 有无拒绝 + 探针写的 errno。结论写进一条 memory。
- **阶段 1–2**：`swift run --package-path CLI duo verify --only <bundleID>` 对**已知坏过**的 recipe 跑（把 `92d6e30` 之前的 Brave Beta pattern、`2fcbc0a` 之前的 IntelliJ pattern 临时还原成 fixture），确认校验器能把它们标红 —— **这是这套系统唯一有意义的验收标准：它必须能抓住已经发生过的那几次真实失效。**
- **阶段 2**：`Redactor` 单测喂真实形状的 CleanShot / Alcove URL，断言 key 不出现在任何输出里。断言 `AlcoveUpdateSource` 不在任何 registry 中。
- **阶段 3**：先 `workflow_dispatch` 手动跑一次，检查 artifact 与 issue；再等一次定时触发确认 cron 生效（注意必须先合进 `main`）。
- **阶段 5**：characterisation 测试在搬迁前后都必须绿；`make test` 全绿。
- **阶段 7**：`duo install --dry-run --all` 与菜单栏 app 的判断逐行一致（同一份 `UpdatePolicy`，理应如此）；真装一个低风险 app（如 Homebrew 路线的）验证端到端 + `duo doctor` 报告正确。

## 风险 / 建前必核

1. `InPlaceSwap.isAppManagementDenial` 与 `replace` 目前是 `internal`，CLI 和实验都需要 `public`。
2. `HomebrewCaskCatalog.entry(forBundleID:)` / `entry(forAppFilename:)` / `CaskEntry` 目前 `internal`，需 `public`；且 `byBundleID` 从 `uninstall.quit` 推导，覆盖不全 —— **依赖它当主 oracle 前先量重合率**。
3. runner 与 GUI 同用户，不设 `DUO_STATE_DIR` 会污染线上缓存。第一次 CI 跑之前必须确认。
4. `URLSession.updates` 有私有 URLCache；`versionFeedCachePolicy` 是 `.reloadRevalidatingCacheData`（总会重校验，304 也算真检查），但**正文样本**可能来自缓存 —— 对 LLM 阶段有影响，被标记的 recipe 要强制取新正文。
5. `privilegedReplace` 走 `osascript with administrator privileges`，无 GUI session 会挂 —— headless 路径必须断言不可达。
6. `SMAppService.daemon` 无法从独立 CLI 调用（需要 bundle），MAS 路线依赖 GUI 至少注册过一次 helper —— `duo doctor` 必须明说。
7. TCC 行绑二进制的 designated requirement **和路径**，`build-cli.sh` 必须复用 `install.sh` 的闸并装到固定路径。
8. 抓回来的 vendor 正文进 LLM 属于 prompt injection 面 —— 靠"数据非指令"框定 + 固定 schema + 输出永不落源码 三道防线。
9. **评论刷屏是这套系统最可能被无视的原因** —— "每 7 轮一评"和"单轮 10 个 issue 上限"是承重设计，不是装饰。
