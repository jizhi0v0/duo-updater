# ChatGPT Atlas

> ⚠️ **这个 app 已经停产**：OpenAI 于 2026-07-09 宣布下线，2026-08-09 正式停止运行，
> 后续能力并入 ChatGPT 桌面端与 Chrome 扩展。feed 仍然在线，但最后一条就是
> `1.2026.189.1`（2026-07-24），不会再有新版本。既有安装照旧被读作 up-to-date，
> 这是对的；**不要再为它投入 changelog / 一键的工作**。
> 来源：[9to5Mac 2026-07-09](https://9to5mac.com/2026/07/09/openai-is-discontinuing-chatgpt-atlas-its-standalone-desktop-browser/)、
> [MacRumors 2026-07-10](https://www.macrumors.com/2026/07/10/openais-chatgpt-atlas-browser-shutting-down/)。

## 基本信息
- Bundle ID: `com.openai.atlas`
- Team ID: `2DC432GLL2` (OpenAI)
- 观测版本: `1.2026.189.1` (build `20260724200710000`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://persistent.oaistatic.com/atlas/public/sparkle_public_appcast.xml`）
- 分发: 官方静态 CDN `persistent.oaistatic.com/atlas/public/` + Homebrew cask
  `chatgpt-atlas`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.openai.atlas` | 单一渠道 | — | — | ✓ |

单渠道。appcast 3 条（观测 2026-08-30），全部无 `<sparkle:channel>` 标记，
head = `1.2026.189.1`。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `1.2026.189.1`（四段：大版本.年份.序.补丁）与 build
  `20260724200710000`（日期+时间戳）双轨；feed 两个字段都有，比较落在 build，
  显示走 short。四段 short 由既有版本比较机制按段处理。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（内嵌 Sparkle） | **有** | **能** |
| 证据 | `Sparkle.framework` 在包里 | head 条目带 `<sparkle:deltas>`，5 个 `.delta` enclosure；从 `20260717210119000` 升上来的那个是 7.9 MB，对比全量 dmg 270 MB（复核 2026-08-31） | `RemoteVersion.deltas == 5`，`DeltaApplier` 按 `sparkle:deltaFrom == 装机 build` 选补丁 |

> ⚠️ 2026-08-31 更正：本节原先写「服务端实际下发：无 / 我们能否消费：不能」，
> 依据是「feed 条目无 `<sparkle:deltas>`」。实测 feed head 条目里就有，而且还带
> `<sparkle:criticalUpdate/>` 和 `<sparkle:hardwareRequirements>arm64`。
> 结论虽然因为停产而不再有实际收益，但**这条断言当时就是错的**——写「无」之前没有
> 去数一遍。

## Changelog
- 来源: **没有**，且**不会再有**（app 已停产）
- Recipe 状态: 无，不打算加
- ⚠️ 2026-08-31 更正：原先写「Sparkle inline（feed `<description>`）」，是错的。
  feed 3 条**一条都没有** `<description>`；真包跑生产链 `releaseNotesHTML` 0 字符、
  `changelogURL` nil。

## 一键安装
- 状态: **支持**（Sparkle 原生路径）
- 格式: feed enclosure 是 `ChatGPT_Atlas_Desktop_public_{short}_{build}.dmg`
  （版本化文件名，官方 CDN）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，1.2026.189.1 挂载）: `com.openai.atlas` /
  `1.2026.189.1`，Team `2DC432GLL2`，notarized

## 已知问题
- **已停产**（见文首）。仍装着 Atlas 的用户会永远停在 `1.2026.189.1`，
  DuoUpdater 报 up-to-date 是正确的，但它是一个不再收安全更新的浏览器。
  要不要在 UI 上给停产 app 一个提示，是一个独立的产品问题，本审计不处理。

## 如何复验
```
# GET https://persistent.oaistatic.com/atlas/public/sparkle_public_appcast.xml
#   → 3 条，head=1.2026.189.1
# 挂载 ChatGPT_Atlas_Desktop_public_1.2026.189.1_….dmg → com.openai.atlas
# 本审计未从已安装副本取证，所以 channel-verify --check 这条不适用（它要 AppScanner
# 先找到一个已装的 app）。2026-08-31 的复验是对下载下来的真包跑同一条生产源链：
# winning=Sparkle、up to date、deltas=5。
```

## 建议下一步
**不要再往这个 app 上投入。**它已停产，feed 不会再更新。既有覆盖（泛化 Sparkle，零 recipe）
留着即可——它对仍装着 Atlas 的用户报 up-to-date，是正确答案。
