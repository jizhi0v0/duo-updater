# Hoppscotch

## 基本信息
- App: Hoppscotch Desktop — 开源 API 客户端（Postman 类），Tauri v2；发版仓库 `hoppscotch/releases`（只放二进制），源码在 `hoppscotch/hoppscotch` 的 `packages/hoppscotch-desktop`
- Bundle ID: `io.hoppscotch.desktop`（Cloud 与 Self-Host 两个版本、以及第一代 app 全用这一个 id）
- Team ID: `XBK86CMQGZ`（26.8.2、26.9.0、25.2.0、第一代 25.1.1-2 的真包都是这个；arm64 与 x64 相同）
- 观测版本: 26.9.0（tag `v26.9.0-0`，2026-09-30）；上一版 26.8.2（`v26.8.2-0`）；观测日期: 2026-10-22
- 自更新机制: Tauri v2 `tauri-plugin-updater` 2.3.1（可执行文件里的 user agent 字符串 `tauri-plugin-updater/2.3.1`），读 `https://releases.hoppscotch.com/hoppscotch-cloud-desktop.json`（Cloud）或 `…/hoppscotch-selfhost-desktop.json`（Self-Host）。用户在 app 里点更新时才下载（`updater.rs` 的 `download_and_install_update` 由前端调用），下到内存里，再当场换包
- 分发: GitHub Releases（每版 Cloud + Self-Host 各一对 arm64/x64 dmg、tar.gz），Homebrew cask `hoppscotch`（装 Cloud arm64 dmg）和 `hoppscotch-selfhost`（装 Self-Host arm64 dmg），都没有 `auto_updates`。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用 cask 源，仅 brew 装的副本） | — | ✓ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（channel-verify，非 brew 装的副本；brew 装的副本由排在前面的 `HomebrewCaskSource` 应答）。GitHub 有两条 stable 规则：Self-Host 规则（`variant: "selfhost"`）答可执行文件含 `hoppscotch-selfhost-desktop.json` 的副本，Cloud 规则答其余所有副本。`feed-discover` 对 26.9.0 Cloud dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- **各版本的 bundle id / Team**（读真包）: 23.8.3-1、25.1.1-0、25.1.1-2（第一代）、25.2.0、26.8.2、26.9.0（Cloud 与 Self-Host）都是 `io.hoppscotch.desktop`、Team `XBK86CMQGZ`、`spctl` Notarized Developer ID。没有改过 id，Team 没换过。
- **同一 id 下的两个版本（Cloud / Self-Host）**: 同一个 release 同时发 `Hoppscotch_mac_<arch>.dmg`（Cloud）和 `Hoppscotch_SelfHost_mac_<arch>.dmg`。26.9.0 两个 arm64 包的 Info.plist 字节相同（md5 一样），版本、id、Team 也一样，差别只在可执行文件 `Contents/MacOS/hoppscotch-desktop` 里编进去的更新地址。两条规则各认各的 dmg：`GitHubReleaseRule.installedExecutableMarker` 让 Self-Host 规则只答可执行文件含 `hoppscotch-selfhost-desktop.json` 的副本（经 `ExecutableMarker` 读、有缓存），其余副本（Cloud、x64、读不了的）落到 Cloud 规则，和加这条规则之前一样。所以只发了 Self-Host 资产的 release（`v26.6.1-0`）现在 Self-Host arm64 副本看得到；x64 Self-Host 副本没有完整字面量，仍落在 Cloud 规则上，见「已知问题」。
- **第一代 app（v23.8.3-1 … v25.1.1-2）**: 可执行文件叫 `Hoppscotch`，更新源 `https://releases.hoppscotch.com/central-desktop.json`，bundle 版本保留 tag 的 `-N`（`23.8.3-1`、`25.1.1-0`、`25.1.1-2`）。`central-desktop.json` 至今（2026-10-22）仍是 `v25.1.1-2`，厂商没有把这一代迁到第二代。第二代从 `v25.2.0-0` 开始，bundle 版本不带后缀（`25.2.0`）。第一代副本由 `.installedVersion(^[0-9]+(?:\.[0-9]+)+$)` 挡在一键之外，检测照常（版本比较读到 `25.1.1-2` < `26.9.0`，channel-verify 显示 UPDATE → 26.9.0）。
- **x64 副本**: x64 的 Cloud（25.2.0、26.8.2、26.9.0）和 Self-Host（26.9.0）可执行文件里都**没有**完整的更新地址字面量（只有 `ch-cloud` / `ch-selfh` 这样的碎片），所以 `.executableContains` 对任何 x64 副本都不放行（失败即拒）。DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`），x64 副本只会是 Rosetta 下跑的 Intel 版；它们保留检测、没有一键。
- **版本范围、主机下限**: 所有样本 `LSMinimumSystemVersion` 10.13，低于我们的下限。
- **其他轨**: 88 个 release 全部不是 prerelease，没有 beta/nightly。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（Cloud，第二代 arm64） | `io.hoppscotch.desktop` | 共享 | 可执行文件含 `hoppscotch-cloud-desktop.json`、不含 Self-Host 字面量 | GitHub `/releases/latest` | ✓ 检测 + 一键 |
| stable（Self-Host，第二代 arm64） | 同上 | 共享 | 可执行文件含 `hoppscotch-selfhost-desktop.json`、不含 Cloud 字面量 | Self-Host 规则（`variant: "selfhost"`，按 Self-Host dmg 认版本） | ✓ 检测 + 一键 |
| stable（x64，两种版本） | 同上 | 共享 | 两个字面量都不完整 | Cloud 规则 | ✓ 检测（x64 Self-Host 副本遇只发 Self-Host 资产的 release 会漏），一键由 gate 拒 |
| 第一代 | 同上 | 共享 | bundle 版本带 `-N` | 同一条规则 | ✓ 检测，一键由 gate 拒 |

## 更新检测
- 源: `hoppscotch/releases` GitHub Releases，`/releases/latest`（2026-10-22 是 `v26.9.0-0`）
- 版本: `^v([0-9]+(?:\.[0-9]+)+)-[0-9]+$`，读 tag 的主版本、丢掉 `-N`。88 个非 prerelease tag 全部能读（`-0` 67 个、`-1` 15 个、`-2` 5 个、`-3` 1 个）。`25.1.1`、`24.6.0`、`24.3.1`、`23.12.3`、`23.12.0` 各有 2–3 个 tag，都是第一代的重发
- 资产: Cloud 规则 `^Hoppscotch_mac_(?:aarch64|x64)\.dmg$`，Self-Host 规则 `^Hoppscotch_SelfHost_mac_(?:aarch64|x64)\.dmg$`，都按主机架构选（和 Cloud 一样走 `installableAsset(preferring: hostArch)`）；tar.gz、Windows/Linux 包、对方版本的 dmg 不匹配。`v26.6.1-0` 只发了 Self-Host 资产：Cloud 规则把它当作不存在，Self-Host 规则正常认它
- 选规则: `GitHubReleasesSource.rule(forEditionOf:among:)`（async），在同一 channel 的规则里先找可执行文件含其 marker 的 Self-Host 规则，找不到就用没有 marker 的 Cloud 规则。只有存在带 marker 的规则时才读文件，读放在 `offCooperativePool` 上做，不占协作线程池；结论进 `ExecutableMarker` 的缓存（与 gate 共用同一个键：bundle + marker）。两个字面量都含的副本落在 Self-Host 规则上（只查自己的 marker），检测照常，一键由 gate 拒（见「门控」）
- Release 正文只有一行（`chore: bump cloud-desktop and selfhost-desktop to 26.9.0-0`）

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（`_aarch64` / `_x64`），各自单架构（`lipo -archs`: `arm64` / `x86_64`）。`LSMinimumSystemVersion` 10.13

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | tauri-plugin-updater 2.3.1 只下整包 tar.gz（`download` 返回 `Vec<u8>`） | `hoppscotch-cloud-desktop.json` 每个平台只有 `url` + `signature`（2026-10-22） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 Cloud 26.8.2，没有停放任何东西） | 不需要 |
| 证据 | tauri-plugin-updater 2.3.1 `src/updater.rs`（tag `updater-v2.3.1`）：`download` 把整包读进内存，macOS `install_inner` 把当前 app rename 到临时目录、把 tar.gz 直接解到原路径；不写停放文件 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 26.8.2 起）: `source structured: 1 entries; newest 26.9.0: 1 items, headings []; first items ["chore: bump cloud-desktop and selfhost-d"]`
- **面板只有一行 bump 说明。** GitHub 正文每版只有这一行；完整的发版说明在厂商网站（`https://hoppscotch.com/releases`、`https://hoppscotch.com/changelog` 2026-10-22 都返回 200），Tauri 清单的 `notes` 里另有一段摘要
- 跟随 channel: —（单轨）
- Recipe 状态: 待定（要不要写 ChangelogRecipe 还没决定）

## 一键安装
- 状态: **支持（Cloud 与 Self-Host 第二代 arm64 副本，各装各的 arm64 dmg；brew 装的副本各走各的 cask）**，第一代、x64 副本、两个字面量都含的副本仅检测
- 端到端，加 Self-Host 规则后（2026-10-22，`614c7a02` 的 `make install` + `make cli`）:
  - Self-Host 26.8.2，运行中（可执行文件含 `hoppscotch-selfhost-desktop.json`）: `duo check` → `26.8.2 → 26.9.0 [GitHub, in-place]`；`duo install --yes` `downloading… verifyingSignature extracting verifyingCodeSignature installing done installed.`（16 s）→ 26.9.0，可执行文件 sha256 `5e87fd3f…2e84` 与厂商 26.9.0 Self-Host dmg 里的相同（Cloud 的是 `16b26b59…f2e6`），仍含 Self-Host 标记，`TeamIdentifier=XBK86CMQGZ`、`codesign --verify --deep --strict` 退出 0；`duo restart Hoppscotch` 后新进程（17:01:33 起）跑 `/Applications/Hoppscotch.app`
  - Cloud 26.8.2，运行中（回归）: `duo check` → `26.8.2 → 26.9.0 [GitHub, in-place]`；`duo install --yes`（14 s）→ 26.9.0，可执行文件 sha256 `16b26b59…f2e6` 与厂商 Cloud 包相同、无 Self-Host 标记、签名有效；`duo restart` 后新进程起来
- 端到端，加 Self-Host 规则前（2026-10-22，当时分支 `make cli` 的 duo）:
  - Self-Host 26.8.2（可执行文件含 `hoppscotch-selfhost-desktop.json`）: `duo check` → `26.8.2 → 26.9.0 [GitHub]`；`duo install` → `Skipping: Hoppscotch — detection only for this copy — this is not a proven Cloud edition copy (Self-Host, or an Intel build); update it from its own updater`，磁盘仍是 26.8.2 Self-Host、inode 不变
  - Cloud 26.8.2，不运行: `duo check` → `26.8.2 → 26.9.0 [GitHub, in-place]`；`duo install` `extracting verifyingCodeSignature installing done installed.` → 26.9.0、可执行文件 inode 变、含 `hoppscotch-cloud-desktop.json`、`TeamIdentifier=XBK86CMQGZ`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 26.9.0 Cloud 包相同
  - Cloud 26.8.2，运行中: 启动（窗口 `main`），`duo install` 后提示 `Still running the old code`；`duo restart Hoppscotch` 后新进程起来，之后 10 s 磁盘一直是 26.9.0、签名有效。启动建了 `~/Library/{Application Support,Caches,Logs,WebKit}/io.hoppscotch.desktop`
- channel-verify（2026-10-22，加 Self-Host 规则后）: Self-Host 26.8.2 arm64 dmg → `winning source GitHub`、`download …/v26.9.0-0/Hoppscotch_SelfHost_mac_aarch64.dmg`、`UPDATE → 26.9.0`；Cloud 26.8.2 arm64 dmg → `…/Hoppscotch_mac_aarch64.dmg`、`UPDATE → 26.9.0`；Self-Host 26.9.0 → `up to date`
- 格式: dmg（UDZO），根目录 `Hoppscotch.app`。检测 pattern Cloud `^Hoppscotch_mac_(?:aarch64|x64)\.dmg$`、Self-Host `^Hoppscotch_SelfHost_mac_(?:aarch64|x64)\.dmg$`，kind `.dmg`；一键只给 arm64 dmg（见「门控」）
- 嵌套: 没有。`Contents` 只有 `MacOS/hoppscotch-desktop`、`Resources/icon.icns`、`Info.plist`、签名；没有 LoginItems / Helpers / LaunchAgent，没有 `LSUIElement`
- 签名: 26.8.2、26.9.0 的 Cloud 与 Self-Host arm64 dmg 都是 `TeamIdentifier=XBK86CMQGZ`，`codesign --verify --deep --strict` 退出 0，`spctl` `source=Notarized Developer ID`（check-bundle，2026-10-22；数据见「历史与实测」）
- 校验: GitHub 资产 `digest`。26.9.0 `Hoppscotch_mac_aarch64.dmg` `sha256:a4aebe60…3a1b`、48686523 字节；26.8.2 `sha256:f307364a…7aab`、48213102 字节；26.9.0 `Hoppscotch_SelfHost_mac_aarch64.dmg` `sha256:2decddd2…795f`、47458621 字节；26.8.2 `sha256:12529633…3bd9`、47156974 字节；下载的 dmg `shasum -a 256` 相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，也是 Homebrew cask 用的资产）
- **门控**（`OneClickGate`，适用于这次所给包的都要放行）:
  1. `.installedVersion(^[0-9]+(?:\.[0-9]+)+$)`，所有包 — 第一代（版本带 `-N`）拒
  2. `.executableContains("hoppscotch-cloud-desktop.json")` 和 `.executableLacks("hoppscotch-selfhost-desktop.json")`，只管 Cloud 包（`offering` `^(?:GitHub:Hoppscotch_mac_aarch64\.dmg|Homebrew:hoppscotch)$`）
  3. `.executableContains("hoppscotch-selfhost-desktop.json")` 和 `.executableLacks("hoppscotch-cloud-desktop.json")`，只管 Self-Host 包（`offering` `^(?:GitHub:Hoppscotch_SelfHost_mac_aarch64\.dmg|Homebrew:hoppscotch-selfhost)$`）
  4. 引擎规则：这个 id 有按包限定的 gate，所给的包不在任何一条的 `offering` 里（x64 dmg、tar.gz、别的 cask、别的源、没有包）就拒（`OneClickGate.unnamedOffer`），在下载之前
  - `executableLacks` 只在整个可执行文件读完、没找到时放行；读不了、超限、没有 plist 都算「不知道」，不放行（失败即拒）。所以两个字面量都含的副本哪个版本的包都拿不到
  - `offering` 只列 arm64 dmg：x64 副本两个字面量都不完整，本来就过不了 gate；arm64 副本被给到 x64 dmg（例如某个 release 只发 x64）时，以前会放行、下完整包后才在装包检查里以 `packageEditionMismatch` 失败，而且每次检查按钮都会再出现；现在在下载前按 `unnamedOffer` 拒。检测用的 `installAssetPattern` 没改，x64 副本照常检测
  - `hoppscotch-selfhost` cask（2026-10-22 决定放开）：与 `hoppscotch` cask 对称。cask 的 URL 是 Self-Host arm64 dmg，brew 按 sha256 校验下载；duo 这边 gate 仍查副本（含 Self-Host、不含 Cloud、第二代）
  - 包身份是 `"<source>:<package>"`：Homebrew 取 cask token，其余取下载 URL 最后一段（GitHub 资产名）。读 `Contents/MacOS/<CFBundleExecutable>`，按 4 MiB 分块 `read(2)`、不映射。真包结果: Cloud arm64 25.2.0 / 26.8.2 / 26.9.0 只含 Cloud 字面量；Self-Host arm64 26.8.2 / 26.9.0 只含 Self-Host 字面量；x64 Cloud 25.2.0 / 26.8.2 / 26.9.0、x64 Self-Host 26.9.0 两个都不完整；第一代 25.1.1-2 拒
  - 结果：Cloud 包只给只含 Cloud 字面量的副本，Self-Host 包只给只含 Self-Host 字面量的副本；跨版本（含 brew 的 `hoppscotch` cask 落在 Self-Host 副本上、`hoppscotch-selfhost` cask 落在 Cloud 副本上）、两个都含一律拒。即使选规则出错，gate 也不放行跨版本的包（变异测试见 PR）
  - **装之前查包**：`VendorInstaller` 解出 `.app` 后、签名闸和换包之前，按所给包对应的 gate 读下载的可执行文件（不走缓存）：必须含本版本的字面量、并且整读后不含另一版本的，否则抛 `packageEditionMismatch`，什么都不动。只在 `.vendor` 路线（我们自己下载解包）上有；Sparkle、`.installer`（pkg）、Xcode、App Store、Homebrew 路线都不查（`OneClickGateRegistry.packageMarkers` 的注释写明）。`OneClickGateTests.everyOfferAScopedGateNamesHasAPackageCheck` 对全部按包限定的 gate 做探测：所给包走的路线没有装包检查就失败，只有 `Homebrew:hoppscotch`、`Homebrew:hoppscotch-selfhost` 两个列明的例外（brew 自己换包）；这是探测（用每个路由源名 × pattern 里写出的包名），不是对 pattern 语言的证明
- marker 的结论按 bundle 缓存，键是 Info.plist 和可执行文件各自的 (device, inode, size, mtime)；重复询问只做两次 `stat`，不重新解析 plist。安装时（`InstallCoordinator.perform`）不走缓存、重读一次。只读普通文件（`open` 带 `O_NONBLOCK`，再 `fstat`），超过 256 MiB 不读、不放行
- 门控开销（2026-10-22，Release 构建，`OneClickGate.admits` 减同一路径上立即返回的 requirement，n=12 次首次调用、144 次重复调用；当时 load average 约 55，有一个 xcodebuild 在跑）:
  - 首次调用（缓存空）: Cloud 26.9.0（标记在 15.9 MB 处，读到第 4 块就停）冷读中位 12.7 ms / p90 12.9 ms，热读 11.6 / 12.0 ms；Self-Host 26.9.0（67 MB 全读）冷读 48.7 / 49.7 ms，热读 46.8 / 47.7 ms
  - 重复调用（命中缓存）: 中位 12–13 µs，p90 15–20 µs
- 选规则开销（2026-10-22，Release 构建 `swift test -c release --build-system native`，临时探针调 `GitHubReleasesSource.rule(forEditionOf:among:)`，减同一副本上 `.installedVersion` 的立即返回；26.9.0 两种 arm64 app 各 12 个 APFS 克隆路径做首次调用、每个再问 12 次；页缓存状态没有控制，克隆和刚拷出来的源共享块，大概率是热读）。跑两次，load average 分别约 12→128（release 构建刚结束）和约 118（别的会话在跑）:
  - 首次调用: Cloud 副本（Self-Host 字面量不存在，67 MB 全读）中位 51.1 / 46.8 ms，p90 51.7 / 47.9 ms；Self-Host 副本（命中即停）中位 13.2 / 11.2 ms，p90 13.6 / 11.5 ms
  - 重复调用（命中缓存）: 中位 7.0–7.5 µs（减地板后），p90 10–15 µs
  - 在哪跑: `latestVersion(for:)` 是非隔离 async，由 `UpdateChecker` 的检查循环调用，不在主线程；选规则读文件经 `offCooperativePool`。主线程上的 `canAutoInstall` 问所给包对应的两个 gate：Cloud 副本的「不含 Self-Host」与选规则共用缓存键、命中缓存，「含 Cloud」首次读到 15.9 MB 处；Self-Host 副本的「含 Self-Host」命中缓存，「不含 Cloud」首次要整读 67 MB（按上面 Self-Host 全读的数估约 50 ms，**未单独测**）。brew 装的副本由 Homebrew 源应答、不经选规则，两个 gate 都是首次读（同样未测）
- 阻塞: 无

## 已知问题
- **两个字面量都含的副本 / 包**：已发布的 arm64 包里两种标记互斥（见「历史与实测」），但引擎不再依赖这一点：gate 要求含本版本、整读后不含另一版本，装包检查也一样，两者都含的副本没有一键，两者都含的包不换（测试用编造的双字面量夹具，`aCopyWithBothEditionsMarkersIsWithheld`、`theInstallerRefusesAPackageOfTheOtherEdition`）。这类副本检测仍走 Self-Host 规则
- **只发 Self-Host 资产的 release：arm64 Self-Host 副本已补上，x64 Self-Host 副本仍漏。** 加了 Self-Host 规则（2026-10-22）后，arm64 Self-Host 副本按 Self-Host dmg 认版本，`v26.6.1-0` 这类 release 会作为更新出现（`HoppscotchEditionRuleTests.aSelfHostCopySeesASelfHostOnlyRelease` 回放了它）。x64 Self-Host 副本的可执行文件没有完整的 Self-Host 字面量，仍落在 Cloud 规则上：遇到只发 Self-Host 资产的 release 时，`/releases/latest` 无 Cloud dmg、回退列表、跳过该 tag，答出前一个有 Cloud dmg 的版本（`v26.6.1-0` 做 latest 的约 15 天里就是这样）。读不出可执行文件的副本同理。反向（缺 Self-Host 资产的 release 让 Self-Host 副本看到没有 Self-Host 包的更新）现在不会发生：Self-Host 规则只认 Self-Host dmg。`hoppscotch-selfhost` cask 装的副本由 Homebrew 源先答，不受影响。
- 第一代、x64 副本只有检测没有一键，见上。x64 副本被拒是因为字面量不完整，不是因为它是别的版本；可执行文件里另有 `Sitemap: https://hoppscotch.io/sitemap.xml`（Cloud）/ `Sitemap: http://localhost:3000/sitemap.xml`（Self-Host）可以同时分出两种架构（上面所有样本都对得上），没有用
- changelog 面板只有一行 bump 说明，见上
- `hoppscotch-selfhost` cask 装的副本：已放开（加进 Self-Host gate 的 `offering`，与 `hoppscotch` cask 对称）。被 `hoppscotch-selfhost` cask 认领的 Cloud 副本（用户拿 Cloud dmg 覆盖了 cask 装的 Self-Host）由 Self-Host gate 拒，不会被 brew 装回 Self-Host。**待真机验证**：brew 路线（`hoppscotch-selfhost` cask 装的 Self-Host 副本一键升级）还没在真机上跑过，由用户跑
- x64 dmg 不再给一键：以前 arm64 副本可能被给到 x64 dmg，gate 放行、下完整包后装包检查以 `packageEditionMismatch` 失败（理由误导），且每次检查按钮重现；现在 `offering` 只列 arm64 dmg，下载前拒
- 安装时的 gate 在 `InstallCoordinator.perform` 开头读一次（不走缓存），到换包之间副本若被换成别的版本，不会再查
- 下载下来的包现在查版本（见「门控」），但只在 `.vendor` 路线；brew 路线（`Homebrew:hoppscotch`、`Homebrew:hoppscotch-selfhost`）换包由 brew 做，不查。这两个是 `everyOfferAScopedGateNamesHasAPackageCheck` 里列明的例外；brew 按 cask 的 sha256 校验下载，但不知道版本标记
- 现在有「不包含」（`.executableLacks`），但 x64 副本两个字面量都不完整，「不含 Self-Host」也证明不了它是 Cloud，所以 x64 副本仍一起拒掉

## 如何复验
```
gh release view v26.9.0-0 -R hoppscotch/releases --json assets -q '.assets[]|.name+" "+.digest'
swift run --package-path application-test feed-discover Hoppscotch_mac_aarch64.dmg        # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify <26.8.2 Cloud dmg> --expect stable   # → GitHub，UPDATE → 26.9.0
swift run --package-path application-test channel-verify <26.9.0 Cloud dmg> --expect stable   # → up to date
.claude/skills/coverage-discovery/scripts/check-bundle.sh <dmg>                          # → XBK86CMQGZ, Notarized
grep -a -c -F hoppscotch-cloud-desktop.json <app>/Contents/MacOS/hoppscotch-desktop      # Cloud arm64 1, Self-Host 0
curl -s https://releases.hoppscotch.com/central-desktop.json | head -3                     # 第一代仍是 v25.1.1-2
swift test --package-path DuoUpdaterCore --filter "OneClickGateTests|HoppscotchEditionRuleTests"
swift run --package-path application-test channel-verify <26.8.2 Self-Host dmg> --expect stable   # → GitHub，…/Hoppscotch_SelfHost_mac_aarch64.dmg，UPDATE → 26.9.0
```

## 历史与实测
- 2026-10-22（GitHub API `repos/hoppscotch/releases/releases`，共 88 条，全部非 draft、非 prerelease，逐条数 dmg 资产）：只有 `v26.6.1-0` 没有 Cloud dmg（`Hoppscotch_mac_*.dmg` 0 个，`Hoppscotch_SelfHost_mac_*.dmg` 2 个）。创建/发布时间 `v26.6.1-0` 2026-07-15 08:39Z / 12:42Z，下一版 `v26.7.0-0` 2026-07-30 12:02Z / 19:09Z，前一版 `v26.6.0-0` 2026-06-30；`/releases/latest` 因此约 15 天（07-15 到 07-30）是没有 Cloud dmg 的 `v26.6.1-0`。资产组合：Cloud 有 Self-Host 无 49 个（`v25.3.2-0` 及更早）、两者都有 38 个（`v25.4.0-0` 起，不含 `v26.6.1-0`）、只有 Self-Host 1 个（`v26.6.1-0`）。当天 `/releases/latest` 是 `v26.9.0-0`。
- 2026-10-22（从 `io-hoppscotch-desktop.swift` 注释迁出）：原文「the pattern reads every tag's base version and the suffix is dropped: all 88 tags read (2026-10-22). v26.6.1-0 shipped SelfHost assets only: nothing to install then.」——当天 88 个非 prerelease tag 全部读得出；v26.6.1-0 只有 SelfHost 资产。

- 2026-10-22（加 Self-Host 规则时，`check-bundle.sh` 与挂载后 `grep -a -c -F`，四个 arm64 dmg 自己下到 `mktemp -d`）：
  - `v26.8.2-0` Cloud: `io.hoppscotch.desktop` 26.8.2、`TeamIdentifier=XBK86CMQGZ`、`codesign-verify-exit=0`、`spctl source=Notarized Developer ID`、`archs=arm64`；Cloud 字面量 1、Self-Host 0；可执行文件 68026000 字节；sha256 `f307364a…7aab`
  - `v26.8.2-0` Self-Host: 同 id、版本、Team、公证；Cloud 0、Self-Host 1；66958960 字节；sha256 `12529633…3bd9`；Info.plist md5 与 Cloud 相同（`ae904e0b…878e`）
  - `v26.9.0-0` Cloud: 26.9.0，同上；Cloud 1、Self-Host 0；68517472 字节；sha256 `a4aebe60…3a1b`
  - `v26.9.0-0` Self-Host: 同 id、版本、Team、公证；Cloud 0、Self-Host 1；67253440 字节；sha256 `2decddd2…795f`；Info.plist md5 与 Cloud 相同（`5400602f…035e90`）
- 2026-10-22（全量扫描：GitHub API 列出的全部非 prerelease release 中每个 `Hoppscotch_mac_aarch64.dmg` 与 `Hoppscotch_SelfHost_mac_aarch64.dmg`，逐个下载、挂载，对 `Contents/MacOS/hoppscotch-desktop` 做 `LC_ALL=C grep -a -c -F`）：第二代 Cloud 45 个（`v25.2.0-0`…`v26.9.0-0`）全部 Self-Host 字面量 0、Cloud 字面量 1；Self-Host 39 个（`v25.4.0-0`…`v26.9.0-0`，含只有 Self-Host 的 `v26.6.1-0`）全部 Self-Host 1、Cloud 0。两种标记在已发布的 arm64 包里互斥。有 API `digest` 的包 sha256 全部相同，`v25.5.1-0` 及更早的资产 API 不给 digest（17 个，无从比对）。第一代（版本带 `-N`，42 个）没有 `hoppscotch-desktop` 这个可执行文件，不在规则范围内。

## 建议下一步
1. 真机验证 `hoppscotch-selfhost` cask 的 brew 一键（已决定放开，与 `hoppscotch` cask 对称；用户来跑）。
2. 决定要不要为 hoppscotch.com 的发版说明写 ChangelogRecipe。
