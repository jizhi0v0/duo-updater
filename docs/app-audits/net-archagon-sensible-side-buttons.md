# SensibleSideButtons

## 基本信息
- Bundle ID: `net.archagon.sensible-side-buttons`
- 仓库: `archagon/sensible-side-buttons`（开源，未归档；最近一次推送 2026-09-19）
- Team ID: `R4MX2B96J2`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.0.7（tag `1.0.7`，资产 `SensibleSideButtons-1.0.7.dmg`，发布于 2026-09-13）；观测日期: 2026-10-26
- 自更新机制: 无（见「更新检测」）
- 分发: GitHub Releases；Homebrew cask `sensiblesidebuttons`（1.0.7，下载地址就是同一个 GitHub 资产，`auto_updates` 未设）；没有 MAS 版；官网 sensible-side-buttons.archagon.net 的下载链接就是 GitHub 上的 `SensibleSideButtons-1.0.7.dmg`（2026-10-26 读页面）
- 停止维护公告: 无（README 顶部、仓库 archived 标志均未见；2018 年的 1.0.6 之后隔了 8 年，2026-09 又连发 1.0.7 和 1.0.9 预发布）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|----------------|---------|----------|-----|--------|-------------|
| **stable**     | —       | ✓（被 GitHub 遮住） | — | ✓ | —        |
| **prerelease** | —       | —        | —   | ○      | —           |

当前生效源: **GitHub**（channel-verify 实测：`winning source  GitHub`）

## 覆盖清单
- 各版本的 bundle id / Team（都读真包）:
  - 1.0.7（2026-09-13）: `net.archagon.sensible-side-buttons`，Team R4MX2B96J2，Notarized Developer ID，universal（x86_64 arm64），`LSMinimumSystemVersion` 10.13
  - 1.0.6（2018）: 同 id、同 Team，Notarized Developer ID，仅 x86_64，`LSMinimumSystemVersion` 10.10
  - 1.0.5（2018）: 同 id、同 Team，spctl 只报 Developer ID（未公证；安装闸不查公证），仅 x86_64
  - 1.0: 同 id、同 Team（scaffold 脚本读真包）
  - 1.0.9 预发布（2026-09-17）: 同 id、同 Team，Notarized Developer ID，universal，`CFBundleVersion` 111，`LSMinimumSystemVersion` 10.11
  - 没有改名：release 历史与 cask 只出现过这一个 bundle id，同仓库也没有别的产品
- 其他轨: 只有 GitHub prerelease 1.0.9（资产名 `SensibleSideButtons.app.zip`，与稳定版 dmg 不同名）。app 里没有渠道开关，Info.plist 没有渠道字段，预发布副本 `ReleaseChannel.detect` 读成 stable。规则读 `/releases/latest`，1.0.9 副本对 1.0.7 判为已是最新（不降级，实测见下）。缺口：1.0.9 副本看不到之后的预发布，只会在出现高于 1.0.9 的稳定版时被提示；要接需要一个能区分预发布副本的信号，现成的只有版本号/构建号，没有接（待用户决定）
- 版本范围、主机下限: tag 是纯点分数字（`1.0`、`1.0.5`、`1.0.6`、`1.0.7`、`1.0.9`），`versionPattern` 带锚点，全部读得到，下一个大版本 `2.0` 也读得到，`1.1.0-rc.1` 这类不读。vendor 下限 10.10–10.13 都低于我们的 deployment target，不构成约束；旧版仅 x86_64 的副本换成 universal 包没有问题

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.archagon.sensible-side-buttons` | — | — | `/releases/latest` | ✓ |
| prerelease | 同上 | 共享 | 无（只有版本号高于最新稳定版） | — | ○ 待用户决定 |

## 更新检测
- 源: `archagon/sensible-side-buttons` GitHub Releases，`/releases/latest`
- 版本方案: tag `1.0.7` → `CFBundleShortVersionString` `1.0.7`、`CFBundleVersion` `5`（构建号不随版本单调：1.0.6 也是 5，1.0.9 是 111，所以只比 short version）
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^SensibleSideButtons-[0-9]+(?:\.[0-9]+)+\.dmg$`
- 自更新：源码（`SensibleSideButtons/AppDelegate.m`，默认分支）没有任何网络请求，只有「打开官网 / 捐赠页」两个 `NSWorkspace openURL`；二进制里的 URL 字符串只有 `http://sensible-side-buttons.archagon.net` 和 `#donations`；包里没有 Sparkle.framework、没有 `app-update.yml`。`feed-discover` 结论: `no Sparkle, no electron-builder update config and no MyGo feed`。不会和我们抢安装
- 读的是轨道上最新的稳定版本，也就是人人可以在 release 页手动下载的那个

## 按架构 / 按 OS 分轨
- 架构: 1.0.7 universal（x86_64 arm64），每个 release 只有一个资产，不分架构
- `LSMinimumSystemVersion`: 1.0.7 是 10.13，1.0.9 预发布降回 10.11；没有上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 无自更新器（源码、包内容、`feed-discover`） | release 只有整包 dmg（GitHub releases API，2026-10-26） | 不适用 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | — | — |
| 证据 | 没有自更新器 | 不适用 | 不适用 |

## Accessibility 授权与换包
- app 启动时调用 `AXIsProcessTrustedWithOptions`，`kAXTrustedCheckOptionPrompt` 为 YES：没被信任时系统会弹出辅助功能授权框，菜单显示「需要授权」模式
- 换包会不会丢授权: 三个包的 designated requirement（`codesign -d -r-`）逐字相同：
  `anchor apple generic and identifier "net.archagon.sensible-side-buttons" and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = R4MX2B96J2)`（1.0.6、1.0.7、1.0.9 实测）
- Apple TN2206 说系统靠 DR 识别「同一个程序的新版本」（钥匙串等按 DR 跟踪）：https://developer.apple.com/library/archive/technotes/tn2206/_index.html 。该文档没有提到 TCC。所以「DR 不变、换包后辅助功能授权保留」是推断，未验证，要在真机一键时确认（换包后 app 菜单不进入授权模式、系统设置里的开关仍开着）

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: `changelog pane  source structured: 1 entries; newest 1.0.7: 2 items, headings []; first items ["Recompiled for Apple Silicon + Intel. So", "Minimum macOS version bumped to 10.13 (t"]`。正文是两段纯文字，没有标题，所以 `headings []` 不是压平；两段各成一条
- 只有 1 条记录：1.0.6、1.0.5、1.0 的 release 正文是空的，没有可显示的说明
- 跟随 channel: 只有稳定版
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（Developer ID、Team R4MX2B96J2、Notarized，dmg）
- 端到端: 待主会话
- 格式: .dmg（`hdiutil imageinfo` 退出码 0），包内 `SensibleSideButtons.app` 和指向 /Applications 的链接
- 嵌套 / 常驻组件: 无（没有 LoginItems、Helpers、XPC、launchd plist）
- 校验: GitHub digest `sha256:fb823f17eeedf367c7af5f969d9a569a6e432440baacdc2de23d26577459e27d`，与下载的包一致；1.0.6 及更早的资产上传于 GitHub 加 digest 之前，没有 digest（不影响，安装的是最新版）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- Team 闸: 1.0.7 以前的每个版本都是同一个 Team，旧副本都能一键

## 已知问题
- 运行中的旧进程持有事件 tap，换包后要重启才跑新代码（`duo restart`）；app 是 LSUIElement，没有窗口
- 未被授权的副本一启动就弹系统辅助功能授权框

## 如何复验
```bash
gh release download 1.0.7 --repo archagon/sensible-side-buttons --pattern 'SensibleSideButtons-1.0.7.dmg'
gh release download 1.0.6 --repo archagon/sensible-side-buttons --pattern 'SensibleSideButtons-1.0.6.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh SensibleSideButtons-1.0.7.dmg
swift run --package-path application-test channel-verify SensibleSideButtons-1.0.6.dmg --expect stable
swift run --package-path application-test channel-verify SensibleSideButtons-1.0.7.dmg --expect stable
# 挂载后比 DR
codesign -d -r- <mount>/SensibleSideButtons.app
```

2026-10-26 实测：
- 1.0.6: `detected channel  → stable`，`winning source  GitHub`，`latest  1.0.7`，`status  UPDATE → 1.0.7`
- 1.0.7: `detected channel  → stable`，`winning source  GitHub`，`latest  1.0.7`，`status  up to date`
- 1.0.9 预发布（zip 解开后的 .app）: `detected channel  → stable`，`latest  1.0.7`，`status  up to date`
- 三者 `changelog pane` 同上

## 建议下一步
1. 主会话真机一键：装 1.0.6（或 1.0.5）→ `duo install` 到 1.0.7，确认辅助功能授权在换包后仍有效
2. 预发布副本是否单独接一个 prerelease 规则，待用户决定
