# AnythingLLM

## 基本信息
- Bundle ID: `com.anythingllm`
- Team ID: `35S2NMU3G4` (Timothy Carambat)
- 观测版本: `1.16.1`（short == build）
- 自更新机制: 无（Electron 包内 `app-update.yml` 指向 electron-vite **模板** repo 的
  陈旧 URL，不是能用的更新器；无 `SUFeedURL`）
- 分发: 官方 CDN `cdn.anythingllm.com/latest/` + Homebrew cask `anythingllm`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.anythingllm` | 单一渠道 | — | — | ✓ |

单渠道，vendor 无 beta/nightly 面。

## 更新检测
- 源: `https://cdn.anythingllm.com/latest/version.txt` —— 一行纯文本版本体。
  **这正是 Homebrew 自家 `anythingllm` cask 的 `livecheck` 用的端点**，第三方
  已依赖同一端点做同一件事，所以是 vendor 意图内的版本面，不是猜的。
- 版本方案: version.txt 的 `1.16.1` == 包的 short 与 build。同构，无陷阱。
- `versionPattern` 锚 `^…$`：端点将来多出一行（比如开始追加 changelog 行）时
  读作 unknown，而不是误取第一行。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | CDN 无 `.delta`/`.patch` 资产；非 Sparkle（观测 2026-08-30） | — |

## Changelog
- 来源: 无内联 notes；未接 ChangelogRecipe（vendor 页面结构未查）
- Recipe 状态: 暂无——UI 回落到嵌入式网页

## 一键安装
- 状态: **支持**
- 格式: dmg — `AnythingLLMDesktop-Silicon.dmg`（arm64-only）
- **读的是**: 人人可手动下载的 GA（vendor 自有 CDN 的 `/latest/` 移动指针）
- 已知风险（已写进 recipe 注释）: 下载 URL 是**无版本号的 `/latest/` 指针**，
  CDN 上不存在 `1.16.1/…` 版本化路径（404 实测）。同发布时差 73 秒内成对更新
  （2026-08-30 Last-Modified 同分钟），且这正是 cask 自己 `url` + `livecheck`
  的搭配——漂移风险与 Homebrew 共享，非我们发明。签名闸仍兜底身份。
- 包验（2026-08-30，挂载）: `com.anythingllm` / `1.16.1`，
  `Developer ID Application: Timothy Carambat (35S2NMU3G4)`，`spctl accepted /
  Notarized Developer ID`，arm64-only；自包含 bundle（无 LaunchDaemons/Agents、
  无 `Contents/Library`）→ `kind: .dmg` 正确，无 bundle 外组件可留旧。

## 已知问题
- 见上：`/latest/` 移动指针无校验和（cask 也是 `sha256 :no_check`）。

## 如何复验
```
# GET https://cdn.anythingllm.com/latest/version.txt → "1.16.1"
# 挂载 AnythingLLMDesktop-Silicon.dmg → com.anythingllm / 1.16.1
# channel-verify --check com.anythingllm → winning=Vendor, up to date
```

## 建议下一步
- changelog：vendor 官网/更新页结构未查，可后续补 ChangelogRecipe。
