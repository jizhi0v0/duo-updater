# Supacode

## 基本信息
- Bundle ID: `app.supabit.supacode`
- Team ID: `9ZLSJ2GN2B` (SUPABIT COMPANY LIMITED)
- 观测版本: default `0.10.8` (build `1785775286`)；tip `0.10.8` (build `1787740786`)
- 自更新机制: **Sparkle** — `SUFeedURL = https://supacode.sh/download/latest/appcast.xml`
- 分发: 官网 / Homebrew cask `supacode`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | —      | —           |
| **tip**    | ✓       | —        | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe——`SUFeedURL` 在 Info.plist 里，feed 实测可解析）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.supabit.supacode` | 共享 | feed 内无 `<sparkle:channel>` 的条目 | 默认渠道始终允许 | ✓ |
| tip     | `app.supabit.supacode` | 共享 | feed 条目标 `<sparkle:channel>tip</sparkle:channel>` | 按装机 build 在 feed 里反查 | ✓ |

Pattern C：一个 bundle id、一条 feed、`<sparkle:channel>` 标记区分条目。tip 不是独立的
app 或 bundle，装 tip 构建后 `ReleaseChannel.detect()` 依旧读作 stable——正确，因为它本来
就没有稳定渠道之外的命名。真正的门控在 `SparkleAppcastSource.allowedChannels`：默认
（无 tag）渠道对所有人开放，tip 只对"装机 build 与 tip 条目 `sparkle:version` 吻合"的
安装开放。不需要 `ChannelBinding`。

> ⚠️ 2026-08-31：这条门控**当时是坏的**，本文档原先声称它由
> `SparkleChannelTests.channelOfInstalledMatchesOnBuildThenShortVersion` 背书——
> 那条用例的两个键（`"x"`/`"1.5"`）永远不会指向不同条目，所以它从来没跑到出问题的那条路径上。
>
> 真实形状：`channel(ofInstalled:)` 当时是 `items.first { build 命中 || short 命中 }`，
> **按文档序**取第一个。tip 构建（build `1787740786`）是 feed 第 10 条，而第 0 条 default
> 的 short 也是 `0.10.8`——tip 包的 short 跟它一模一样，于是 default 条目先靠 short 命中，
> 精确的 build 命中根本没机会比。结果 tip 安装被判成 default 轨。
>
> 这个错**不会表现为推错版本**（default 轨对所有人开放，而当天 default head 恰好不比 tip
> 新），它表现为**用户自己那条轨看不见**：`usableItems` 把 11 条 tip 全滤掉，下一个 tip
> 构建永远不会被提供，说明和历史也来自 stable 那条线。已修为两趟匹配（先全表比 build，
> 再全表比 short），回归用例 `aTipBuildIsNotStolenByTheDefaultItemAheadOfIt` 用的就是这份
> 真实 feed 的形状。真包实测：修前 `releaseHistory` 10 条（只有 default），修后 21 条。

## 更新检测
- 源: 泛化 Sparkle。feed 共 21 条：10 条 default + 11 条 tip（`supacode-history-*` 历史构建）。
- **版本方案陷阱**：`CFBundleShortVersionString` 长期停在一个短号上（default 与 tip 现在
  都叫 `0.10.8`），真正动的是 `CFBundleVersion`（时间戳型 build）。feed 的
  `sparkle:version` 正是这个 build（`1785775286` / tip `1787740786`），与包的
  `CFBundleVersion` 同构，而 `comparisonKey` 取 `version ?? shortVersionString` —— 所以
  比较落在 build 上，变更能被看见；显示仍走 short。这与 Amp/Surge 的既有结论一致，
  不要在任何调用点改成"只比 marketing"。
- `pubDate` 不可靠（cask livecheck 注释同结论）：tip 条目的日期在 default 之后/之间
  乱序。`usableItems` 按 `comparisonKey` 排序、不依赖文档序或 pubDate。
- 防跨渠道: tip 条目带 channel 标记，default 安装不会收到 tip build；tip 安装按 Sparkle
  规则仍可见更新的 default 条目（`betaUserStillGetsNewerStable` 语义）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目只有 `enclosure` zip，无 `<sparkle:deltas>`（观测 2026-08-30） | 没有补丁可读 |

## Changelog
- 来源: Sparkle inline（`<description sparkle:format="markdown">`，每版一段）
- 跟随 channel: 是——`structuredChangelog` 只读 `usableItems`
- Recipe 状态: 不需要
- ⚠️ 2026-08-31 两点更正：
  1. `sparkle:fullReleaseNotesLink` **我们不消费**。`RemoteVersion.changelogURL` 取的是
     `sparkle:releaseNotesLink`，这份 feed 没有那个字段，所以真包跑下来 `changelogURL`
     是 nil。inline 那段是有的（default head 1022 字符）。
  2. **tip 轨没有任何说明**：11 条 tip 条目 `<description>` 全是空的，只有 10 条 default
     带正文。渠道推断修好之后，tip 安装看到的是自己那条轨的 head，于是 inline 说明从
     1022 字符变成 0——这不是回归，是修好之后才看清的事实：在此之前 tip 用户看到的是
     **stable 条目的**说明。要给 tip 补说明只能另找来源。

## 一键安装
- 状态: **支持**（Sparkle 原生路径，无 SUPublicEDKey 时走签名 + Team + bundle id 闸）
- 格式: feed enclosure 是 `…/supacode.app.zip`（universal x86_64+arm64，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）；tip 条目同样公开可下
- 包验（2026-08-30，两条轨都验）:
  - default dmg（cask URL `/download/v0.10.8/supacode.dmg`）与 feed zip
    （`/download/v0.10.8/supacode.app.zip`）：bundle 一致、build `1785775286`、
    Team `9ZLSJ2GN2B`、`spctl accepted / Notarized Developer ID`
  - tip zip（`/download/tip/supacode.app.zip`）：同 bundle、build `1787740786`、
    同 Team、公证通过

## 已知问题
- 两条轨的 short version 相同（都显示 `0.10.8`），行上"去往"一侧只靠 build 区分；
  0.3.70 起的 relaunch 行处理已覆盖这种"只有 build 动"的形状。
- `LSMinimumSystemVersion = 26.0`（feed 条目同样声明 `sparkle:minimumSystemVersion` 26.0），
  macOS 26 以下安装不会被安装到，检测侧由 `usableItems` 的 min 过滤兜住。

## 如何复验
```
# 官方 appcast，21 条：10 default + 11 条 <sparkle:channel>tip</sparkle:channel>
# GET https://supacode.sh/download/latest/appcast.xml
# 装 default 构建 → channel-verify --check app.supabit.supacode
#   winning=Sparkle, 0.10.8/1785775286 up to date
# 换 tip 构建（build 1787740786）→ 同命令，仍 up to date 且不串轨
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
