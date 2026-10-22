# Itsytv

## 基本信息
- App: Itsytv — 菜单栏里的 Apple TV 遥控器（`LSUIElement`），MIT 开源
- Bundle ID: `com.itsytv.app`（所有 GitHub 版本一致；Mac App Store 版同 id，见下）
- 仓库: `nickustinov/itsytv-macos`（默认分支 `main`）
- Team ID: `R892A93W42`（Developer ID Application: Nikolajs Ustinovs）；1.0.0、1.0.3、1.1.0、1.2.1 四个版本是 `6484NTXXS4`（Developer ID Application: StoryjarApp, Inc.），见「覆盖清单」
- 观测版本: 1.6.2（`CFBundleVersion` 16201）；上一版 1.6.1（16101）；观测日期: 2026-10-22
- 自更新机制: **只提示**。settled from source: `itsytv/Utilities/UpdateChecker.swift` on `main`（`main` 只比 v1.6.2 多一处 `scripts/build-release.sh` 改动）。菜单「Check for updates...」点了才跑：读 `api.github.com/repos/nickustinov/itsytv-macos/releases/latest` 的 `tag_name` 和 `html_url`，比 `CFBundleShortVersionString`，新就弹 `NSAlert`，点「Open downloads」用 `NSWorkspace.open` 打开 release 网页。不下载、不暂存、不换包；启动时不自动检查（`AppController.swift` 里唯一的调用点是这个菜单项）。整段在 `#if !APPSTORE` 里，商店版没有。1.0.3 起才有（v1.0.3 release 说明），v1.0.4 源码同样只在菜单里调用
- 分发: GitHub Releases（每版一个 dmg）；Homebrew cask `itsytv`（官方 homebrew-cask，autobump，`auto_updates` 未设，url 指向同一个 GitHub dmg）；Mac App Store `id6759216148`（付费、iOS/Mac 通用购买）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用） | ✓（通用） | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测，对 dmg 里的非商店副本）。brew 装的副本由排在前面的 `HomebrewCaskSource` 应答（cask 不是 `auto_updates`）；商店副本只由 `MacAppStoreSource` 应答。`feed-discover` 对 1.6.1 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（24 个 release 的 dmg 全部读了真包，`check-bundle.sh`）：bundle id 全是 `com.itsytv.app`。Team 在两家之间来回：`6484NTXXS4` = 1.0.0、1.0.3、1.1.0、1.2.1；其余 20 个（含 1.6.1、1.6.2）= `R892A93W42`。四个 `6484NTXXS4` 版本的副本，一键会被 Team 闸拒（`teamIdentifierMismatch`），检测照常显示更新，用户手动更新一次后就回到 `R892A93W42`。这不是要用 gate 隔开的另一个产品：同一个 app、同一个作者仓库，只是那几版用另一个开发者账号签的
- 包名：1.0.0–1.4.1 的资产是 `itsytv-<version>.dmg`、里面是 `itsytv.app`（可执行文件 `itsytv`）；1.4.2 起是 `Itsytv-<version>.dmg`、`Itsytv.app`（可执行文件 `Itsytv`）。规则只装最新版的资产，pattern `^[Ii]tsytv-…\.dmg$` 两种都收，免得厂商改回小写时一键静默消失
- 其他轨：没有。24 个 release 都不是 prerelease，仓库里没有 beta/nightly 的构建脚本或 tag；`scripts/build-release.sh` 只出一个 Developer ID dmg
- Mac App Store 版：`project.yml` 的 `Release-AppStore` 配置用同一个 `PRODUCT_BUNDLE_IDENTIFIER: com.itsytv.app`，iTunes lookup（2026-10-22）`bundleId com.itsytv.app`、`version 1.5.1`，版本线和 GitHub 不同步。商店副本不会走到这条规则：`UpdateChecker` 对 `isMASApp` 只问 `answersAppStoreCopies` 的源，`GitHubReleasesSource.latestVersion` 里另有 `guard !app.isMASApp`
- 版本范围、主机下限：所有版本 `LSMinimumSystemVersion` 14.0，低于 DuoUpdater 自己的下限，不用门控；都是 universal（`x86_64 arm64`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.itsytv.app` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `nickustinov/itsytv-macos` GitHub Releases，`/releases/latest`
- 版本: tag `v1.6.2` → `^v([0-9]+(?:\.[0-9]+)+)$` → `1.6.2`，等于 `CFBundleShortVersionString`（`build-release.sh` 从 `project.yml` 的 `MARKETING_VERSION` 取版本、`gh release create v$VERSION`）。24/24 个已发布 tag 都读得出；`v2.0.0`、`v1.7` 读得出，`v1.7.0-rc.1`、`v1.7.0-beta` 不匹配（锚定）
- `CFBundleVersion` 是递增整数（1…17、150、154、160、16101、16201），不参与比较
- 注意事项: 无

## 按架构 / 按 OS 分轨
- 架构: 每版一个 universal dmg（`x86_64 arm64`）；`LSMinimumSystemVersion` 14.0（每版相同，cask 也写 `>= 14`）。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 自带检查只打开网页（上面的源码） | 每个 release 只有一个 dmg 资产 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没跑运行中一轮（见一键安装）；源码里不下载 | 不需要 |
| 证据 | `UpdateChecker.swift` 不下载任何东西 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 1.6.1 起）: `source structured: 1 entries; newest 1.6.2: 1 items, headings []; first items ["Fix pairing hanging for ~30 seconds afte"]`
- 全部 24 个 release body 跑了生产解析器（临时测试调用 `GitHubMarkdownParser.parse`，跑完已删）：23 个的 items 数等于正文的列表项数，`content` 里没有 heading block。正文基本是不带小标题的列表；1.4.4、1.0.2–1.0.5 开头的 `## What's new` / `## What's changed` 是盖住全部条目的泛称，被丢掉，没有混进 items（不是压平）。1.5.4 列表后的 `osascript` 代码块、1.5.1 列表后的「Fixes #42.」被丢掉，和列表前后正文的通用取舍一致。1.0.0 只有一行 Full Changelog 链接，解析为 nil
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机不运行一轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 格式: dmg（UDZO，`hdiutil imageinfo`），根目录 `Itsytv.app` + `Applications` 软链。kind `.dmg`
- 嵌套: 没有 LoginItems / Helpers / XPC / framework / LaunchAgent plist。「Launch at login」是菜单里的勾选项，`SMAppService.mainApp.register()` 把 app 本身登记为登录项，默认不开，没有常驻 helper
- 沙盒: Developer ID 版也带 `com.apple.security.app-sandbox` + `network.client`，数据在 `~/Library/Containers/com.itsytv.app`
- 签名: 1.6.1、1.6.2 都是 `TeamIdentifier=R892A93W42`，`spctl` Notarized Developer ID，hardened runtime；Team 来回的四个旧版见「覆盖清单」
- 校验: GitHub 资产 `digest`。下载的 1.6.1 / 1.6.2 dmg `shasum -a 256` 分别为 `cdd88872…f546b3` / `6ad433fd…be50ae`，与 API 的 `digest` 相同，字节数等于资产大小（4211298 / 4182941）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，README 的下载说明指向它）
- 端到端:
  - 第一轮（不运行）: 1.6.1 → `duo check` `1.6.1 → 1.6.2 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 1.6.2、可执行文件 inode 变、`TeamIdentifier=R892A93W42`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 1.6.2 包相同
  - **运行中一轮没跑**：一启动就做 Bonjour 发现，可能在开发机屏幕上弹系统的本地网络授权框；它的更新器只提示不下载，运行中换包走的是通用的 quit → swap → relaunch 路径（同批其他 app 已真机过）
- 启动副作用（读源码，未在真机上观察）:
  - 首次启动弹 iOS 版推广窗口并 `NSApp.activate(ignoringOtherApps:)` 抢前台，直到点掉（`iosPromoDismissed`，`IosPromoView.swift`，1.6.1 / 1.6.2 的可执行文件里都有）
  - 启动会做本地网络 Bonjour 发现（`_companion-link._tcp`、`_mediaremotetv._tcp`），可能弹本地网络授权框
  - 自带检查不会和我们抢；不点菜单就不联网查更新
- 阻塞: 无

## 已知问题
- 从 1.4.1 及更早（`itsytv.app`）一键到 `Itsytv.app`：新包的 bundle 目录名和可执行文件名大小写都变了。安装器在原路径换包，换完的目录名是否保持小写没有验证（我的推断：不影响启动，`CFBundleExecutable` 跟着新 Info.plist 走）

## 如何复验
```
gh api repos/nickustinov/itsytv-macos/releases --paginate -q '.[]|.tag_name+" "+([.assets[]|.name+" "+.digest]|join(" "))'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Itsytv-1.6.1.dmg Itsytv-1.6.2.dmg itsytv-1.0.0.dmg   # Team R892A93W42 / R892A93W42 / 6484NTXXS4
swift run --package-path application-test feed-discover Itsytv-1.6.1.dmg                       # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify Itsytv-1.6.1.dmg --expect stable      # → GitHub，UPDATE → 1.6.2
swift run --package-path application-test channel-verify itsytv-1.4.1.dmg --expect stable      # → GitHub，UPDATE → 1.6.2
swift run --package-path application-test channel-verify Itsytv-1.6.2.dmg --expect stable      # → up to date
curl -sS "https://itunes.apple.com/lookup?id=6759216148&country=us"                            # 商店版 bundleId com.itsytv.app
```

## 建议下一步
1. 运行中一轮可在一台能点掉本地网络授权框的机器上补跑。
