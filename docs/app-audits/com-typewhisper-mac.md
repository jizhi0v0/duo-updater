# TypeWhisper

## 基本信息
- Bundle ID: `com.typewhisper.mac`
- Team ID: `2D8ALY3LCL`
- 观测版本: `1.6.0` (build `1091`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://typewhisper.github.io/typewhisper-mac/appcast.xml`）
- 分发: GitHub Releases (`TypeWhisper/typewhisper-mac`) / Homebrew cask `typewhisper`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | — | — |
| **release-candidate** | ✓ | — | — | — | — |
| **daily**  | ✓       | —        | —   | —     | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe；三条轨都靠 feed 的 `<sparkle:channel>` 标记分轨）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.typewhisper.mac` | 共享 | — | default（无标记） | ✓ |
| release-candidate | `com.typewhisper.mac` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>release-candidate` | ✓ |
| daily   | `com.typewhisper.mac` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>daily` | ✓ |

共享 bundle id。appcast 3 条（观测 2026-08-30）：default = `1.6.0/1091`（stable），
`release-candidate` = `1.6.0-rc2/1083`，`daily` = `1.7.0-daily.20260830/1161`。
三轨互不串：`usableItems` 只允许装机 build 命中的那条 channel + 始终开放的 default 轨。

> ⚠️ 2026-08-31：rc 轨当时**没有真的分出来**。rc2 包的
> `CFBundleShortVersionString` 是 `1.6.0`——跟 default 条目一模一样（版本号在 feed 里
> 才带 `-rc2`，包里不带），而 `channel(ofInstalled:)` 当时按文档序取第一个「build 命中
> **或** short 命中」的条目，于是排在前面的 default 条目先靠 short 命中，rc 条目那个精确的
> build `1083` 没机会比。rc 安装被判成 stable。daily 轨没事，因为它的包 short 是
> `1.7.0`，不撞。
>
> 表现不是推错版本（当天 default head 1091 本来就比 rc 1083 新，两边都会提供它），而是
> **rc 用户自己那条轨消失**：rc 条目被 `usableItems` 滤掉，rc 轨再往前走也收不到。
> 已修为两趟匹配（先全表比 build，再全表比 short）。**装 rc2 真包上机复验过**：
> 修前 `releaseHistory` 1 条，修后 2 条（default + rc）。

配套的一个 GitHub 陷阱（写进 audit 免得下一个人踩）：该 repo 的**非 prerelease
release 全是 plugin 包**（`plugin-whisperkit-v1.2.0` 等，资产只有插件 zip），app
本体走 prerelease 的 daily tag。如果有人给这个 bundle 加 GitHub rule，
`/releases/latest` 会指到最新的 plugin release——GitHub 源不是这个 app 的版本面，
Sparkle feed 才是。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short 与 build 双轨；比较落在 build，显示走 short。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: **`ChangelogRecipe`**，解官网 https://www.typewhisper.com/en/changelog/
- 跟随 channel: **否**——官网把三轨排在同一张列表里，装 stable 也会看到 daily 条目在上面。
  每条都带自己的版本号标签，接受这个折中。
- Recipe 状态: 2026-08-31 新增
- ⚠️ 2026-08-31 更正：原先写「Sparkle inline（feed `<description>`）」，是错的。
  feed 3 条**一条都没有** `<description>`，真包跑生产链拿到 0 字符 —— 此前没有任何说明。
- 这张页面**同时列 macOS 和 Windows 两个产品**（实测 203 个 mac 卡片 / 167 个 Windows
  卡片），所以 `entryPattern` 锚在版本标题前面那枚平台徽章上；锚错了就会把 Windows 的
  说明挂到 Mac 版本下面。
- 卡片之间用了 tempered 惰性扫描而不是 `.*?`：有少数老卡片没有正文块，裸 `.*?` 会越过它
  跑进下一张卡片，把后者的说明记到前者的版本上（0.6.1、0.5.1 实测就是这样）。
- daily 的说明是**累积**的（连着几天的 daily 重复同一批条目），所以 `maxEntries` 收到 20。

## 一键安装
- 状态: **支持**（Sparkle 原生路径，各轨 feed enclosure）
- 格式: `TypeWhisper-v{ver}.zip`
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，v1.6.0 解包）: `com.typewhisper.mac` / `1.6.0` / build
  `1091`，Team `2D8ALY3LCL`，notarized

## 已知问题
- 无。

## 如何复验
```
# GET https://typewhisper.github.io/typewhisper-mac/appcast.xml
#   → 3 条：default=1.6.0，rc=1.6.0-rc2，daily=1.7.0-daily.20260830
# 解包 TypeWhisper-v1.6.0.zip → com.typewhisper.mac / 1.6.0 / 1091
# channel-verify --check com.typewhisper.mac → winning=Sparkle, up to date
```

## 建议下一步
无。三轨检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
