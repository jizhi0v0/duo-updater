# DSH Desktop / DSH NEXT (DeepSeek Harness)

## 基本信息
- Bundle ID:
  - stable: `ai.deepseek.dsh.desktop`（DSH Desktop）
  - next: `ai.deepseek.dsh.desktop.next`（DSH NEXT）
- Team ID: `UM3Z9G5DNH`（两个 bundle 相同）
- 观测版本: `2.0.18`（stable）、`2.0.20-next`（NEXT）；2026-10-30 另挂载真包 `2.0.21-next`
- 自更新机制: 无 `SUFeedURL`。NEXT 包内有 `app-update.yml`，但它是 `provider: github`，repo 名
  `deepseek-harness-desktop`（GitHub 重定向到 `dsh-desktop`）；`ElectronManifestSource` 不为
  `provider: github` 构造地址，所以两个渠道都由 GitHub 规则接管。
- 分发: GitHub Releases (`anywhere-labs/dsh-desktop`) / 官网；无 Homebrew cask。
- 关系: NEXT 是同一社区项目的预发布桌面客户端（release notes 注明「社区维护，并非 DeepSeek 官方产品」），
  与 stable 并列安装，**不是**同一个 bundle 的 edition，因此各有自己的 bundle id 和规则。
- 不是本 family: `com.deepseek.dsh` 是 DeepSeek 官方的 0.2.x 上游 Harness（Team `NAN929V4UM`，
  `download.deepseek.com` 的 generic nightly feed），本 family 不覆盖。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |
| **next**   | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**，两条规则分别对应两个 bundle。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ai.deepseek.dsh.desktop` | 独立 | tag `vX.Y.Z` + `DSH.Desktop-`/`DSH-Desktop-…dmg` | tag 锚 `^vX.Y.Z$`；资产 `Desktop-` 后紧跟数字 | ✓ |
| next    | `ai.deepseek.dsh.desktop.next` | 独立 | tag `vX.Y.Z-next` + `DSH-NEXT-…-next-universal.dmg` | tag 锚 `^vX.Y.Z-next$`；资产 `DSH-NEXT-<v>-next-universal.dmg` | ✓ |

同一个版本号会在仓库里同时出现三个 release（观测 2026-10-30）：
- `vX.Y.Z-beta.N`：**prerelease**，资产 `DSH-Desktop-Beta-…`；bundle id、Team、是否与 stable 共存未审计。
- `vX.Y.Z`：stable，资产 `DSH.Desktop-…`（≤ v2.0.15）/ `DSH-Desktop-…`（≥ v2.0.16）。
- `vX.Y.Z-next`：**不是** prerelease，资产 `DSH-NEXT-…`，bundle `ai.deepseek.dsh.desktop.next`。

两条规则的锚互为镜像：stable 的 tag 锚拒掉 `-beta.N` 和 `-next`，资产锚要求 `Desktop-` 后紧跟数字；
next 的 tag 锚只接受 `-next`，资产锚只接受 `DSH-NEXT-<version>-next-universal.dmg`。

## 更新检测
- 源: `anywhere-labs/dsh-desktop` GitHub Releases。
- stable: `/releases/latest`。2026-10-30 它返回的是 `v2.0.21-next`（不是 prerelease，且比 stable 晚发），
  tag 锚拒掉它；没有匹配资产，于是走 list 回退（`stableOnly`）落到 `v2.0.18`。每次检查从 1 个请求
  变成 2 个，结果是对的。
- next: `/releases/latest` 返回 `v2.0.21-next`，tag 与资产都匹配，一次请求命中。
- 版本方案: tag 去掉前导 `v` 就是 `CFBundleShortVersionString` / `CFBundleVersion`（含 `-next`），
  `2.0.21-next` 按 token 比较大于 `2.0.20-next`。next 规则的捕获值保留 `-next` 后缀——只取 `X.Y.Z`
  虽然也能比较，但行里显示的版本会和包内 Info.plist 不一致。
- `variant: "next"`: 两条规则共用同一 repo、同一 channel，没有它就会共用 recipe id、健康行和
  verify baseline。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 universal dmg 与 Windows exe（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回），两个渠道各自跟随自己的 release。
- 跟随 channel: 是，stable / next 分开。
- Recipe 状态: 不需要。

## 一键安装
- 状态: **两个渠道都支持**，均为 universal dmg。
- stable 格式: v2.0.1–v2.0.15 是 `DSH.Desktop-{v}-universal.dmg`（GitHub 把 "DSH Desktop" 的空格换成点），
  v2.0.16 起是 `DSH-Desktop-{v}-universal.dmg`。Pattern `^DSH[.-]Desktop-[0-9.]+-universal\.dmg$`。
- next 格式: `DSH-NEXT-{v}-universal.dmg`，Pattern `^DSH-NEXT-[0-9.]+-next-universal\.dmg$`。
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）。
- 包验（2026-08-30，v2.0.4 挂载）: `ai.deepseek.dsh.desktop` / `2.0.4`，Team
  `UM3Z9G5DNH`，`spctl accepted / Notarized Developer ID`。
- 包验（2026-10-09，v2.0.17 挂载，`DSH-Desktop-2.0.17-universal.dmg`，sha256 与 `SHA256SUMS.txt` 一致）:
  `ai.deepseek.dsh.desktop` / `2.0.17`（short == build），Team `UM3Z9G5DNH`，
  `spctl accepted / Notarized Developer ID`，`x86_64 arm64`，`LSMinimumSystemVersion` 13.0，仍无 `SUFeedURL`。
  `duo verify-install --only dsh-desktop` → `✓ 2.0.17  ai.deepseek.dsh.desktop / UM3Z9G5DNH`
- 包验（2026-10-30，v2.0.21-next 挂载，`DSH-NEXT-2.0.21-next-universal.dmg`，sha256
  `ec48040c…cff2dc` 与 `SHA256SUMS.txt` 一致）: `ai.deepseek.dsh.desktop.next` / `2.0.21-next`
  （short == build），Team `UM3Z9G5DNH`，`spctl accepted / Notarized Developer ID`，
  `x86_64 arm64`，`LSMinimumSystemVersion` 13.0，无 `SUFeedURL`；包内 `app-update.yml` 为
  `provider: github` / `repo: deepseek-harness-desktop`。

## 已知问题
- **stable 轨道停在 v2.0.18**（2026-10-17 发布），而 NEXT 已到 v2.0.21-next（2026-10-29）。这是上游节奏，
  不是 recipe 坏了；stable 拷贝此时报「up to date」是对的。要不要在 UI 上提示 stable 用户迁移到 NEXT
  是产品决策，不要在 recipe 层把 stable 的行指向 NEXT。
- `-beta.N` 渠道仍未审计：没下包，bundle id、Team、是否与 stable 共存都不知道。不接。
- 2026-09-29 – 10-09 曾坏过：v2.0.16 起 dmg 改名为 `DSH-Desktop-…`，旧 pattern `^DSH\.Desktop-…` 匹配不上，
  规则一路回退，把 2.0.15 当最新报出来，而且每次检查都显示健康。由 `claude/github-asset-rename` 分支新加的
  `installAssetRenamed` 警告发现；已把 pattern 改成两种拼法都接受。
- NEXT 的 `app-update.yml` 指向旧 repo 名 `deepseek-harness-desktop`（GitHub 重定向到 `dsh-desktop`）。
  若这个重定向消失，NEXT 自己的 electron 更新和本 family 的 GitHub 规则会一起受影响，需复查。

## 如何复验
```
gh api 'repos/anywhere-labs/dsh-desktop/releases?per_page=8' --jq '.[]|"\(.tag_name) \([.assets[].name]|join(", "))"'
duo verify --only dsh                        # 两条规则：stable 与 next
duo verify-install --only dsh                # 下载真包 → stable 2.0.18 / next 2.0.21-next
# 运行中的 NEXT 拷贝（2.0.20-next）应收到 2.0.21-next，而不是 stable 的 2.0.18
duo check | grep -i "DSH NEXT"
# 端到端安装放到 VMPal macOS VM 里跑（不动本机正在运行的 DSH NEXT）：
#   在 VM 里跑 `duo check`，再 `duo install "DSH NEXT" --yes`。
```

## 建议下一步
stable 与 NEXT 的检测 + 一键 + changelog 均已覆盖。
`-beta.N` 仍未审计；要接得先下 `DSH-Desktop-Beta-…dmg`，核对 bundle id 与 Team，再走 `/app-audit`。
