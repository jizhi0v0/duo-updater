# DSH Desktop (DeepSeek Harness)

## 基本信息
- Bundle ID: `ai.deepseek.dsh.desktop`
- Team ID: `UM3Z9G5DNH`
- 观测版本: `2.0.4`（short == build）；2026-10-09 复验 `2.0.17`（short == build）
- 自更新机制: 无（无 `SUFeedURL`）
- 分发: GitHub Releases (`anywhere-labs/dsh-desktop`) / 官网（无 Homebrew cask）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ai.deepseek.dsh.desktop` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

我们只接 stable。仓库里同一个版本号还会同时发两个兄弟 release（观测 2026-10-09）：
- `vX.Y.Z-beta.N`：**prerelease**，资产是 `DSH-Desktop-Beta-…`（自 v2.0.5-beta.1 起）
- `vX.Y.Z-next`：**不是** prerelease，资产是 `DSH-NEXT-…`（自 v2.0.14-next 起）

stable 规则用两道判据把它们挡在外面：tag 锚 `^v([0-9]+(?:\.[0-9]+)+)$` 拒掉 `-beta.N` / `-next`；
资产 pattern 要求 `Desktop-` 后面紧跟数字，`DSH-Desktop-Beta-…` 和 `DSH-NEXT-…` 都匹配不上。

**这两个渠道还没审计过**：没下包，bundle id、Team、是否与 stable 共存都不知道。不是「已调查不可行」。

## 更新检测
- 源: `anywhere-labs/dsh-desktop` GitHub Releases，`/releases/latest`
- 2026-10-09 起 `/releases/latest` 返回的是 `v2.0.17-next`（`-next` 不是 prerelease，且比 v2.0.17 晚发几十秒）。
  tag 锚拒掉它、它也没有匹配的资产，于是走 list 回退（`stableOnly`）落到 `v2.0.17`。每次检查从 1 个请求变成 2 个，结果是对的。
- 版本方案: tag `v2.0.4` → `2.0.4` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 universal dmg 与 Windows exe（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — v2.0.1–v2.0.15 是 `DSH.Desktop-{v}-universal.dmg`（GitHub 把 "DSH Desktop" 的空格换成点），
  v2.0.16 起是 `DSH-Desktop-{v}-universal.dmg`。x64-Setup.exe 是 Windows 兄弟；v2.0.14 起另有 deb / AppImage / tar.gz / `SHA256SUMS.txt`。
- Pattern: `^DSH[.-]Desktop-[0-9.]+-universal\.dmg$`, kind `.dmg`（两种拼法都接受）
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v2.0.4 挂载）: `ai.deepseek.dsh.desktop` / `2.0.4`，Team
  `UM3Z9G5DNH`，`spctl accepted / Notarized Developer ID`
- 包验（2026-10-09，v2.0.17 挂载，`DSH-Desktop-2.0.17-universal.dmg`，sha256 与 `SHA256SUMS.txt` 一致）:
  `ai.deepseek.dsh.desktop` / `2.0.17`（short == build），Team `UM3Z9G5DNH`，
  `spctl accepted / Notarized Developer ID`，`x86_64 arm64`，`LSMinimumSystemVersion` 13.0，仍无 `SUFeedURL`。
  `duo verify-install --only dsh-desktop` → `✓ 2.0.17  ai.deepseek.dsh.desktop / UM3Z9G5DNH`

## 已知问题
- 无（当前）。
- 2026-09-29 – 10-09 曾坏过：v2.0.16 起 dmg 改名为 `DSH-Desktop-…`，旧 pattern `^DSH\.Desktop-…` 匹配不上，
  规则一路回退，把 2.0.15 当最新报出来，而且每次检查都显示健康。由 `claude/github-asset-rename` 分支新加的
  `installAssetRenamed` 警告发现；已把 pattern 改成两种拼法都接受。

## 如何复验
```
gh api 'repos/anywhere-labs/dsh-desktop/releases?per_page=6' --jq '.[]|"\(.tag_name) \([.assets[].name]|join(", "))"'
duo verify-install --only dsh-desktop      # 下载真包 → 2.0.17 / ai.deepseek.dsh.desktop / UM3Z9G5DNH
# /releases/latest 现在是 v2.0.17-next，会回退到 list；挂载 DSH-Desktop-2.0.17-universal.dmg → ai.deepseek.dsh.desktop / 2.0.17
# channel-verify --check ai.deepseek.dsh.desktop → winning=GitHub, up to date
```

## 建议下一步
stable 的检测 + 一键 + changelog 均已覆盖。
`-beta.N` 与 `-next` 两个兄弟渠道还没审计（见 Channel 详情），要接得走 `/app-audit`。
