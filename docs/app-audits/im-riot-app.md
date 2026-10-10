# Element

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/nightly 两 channel 已检测**

## 基本信息
- Bundle ID: `im.riot.app`（Nightly 独立：`im.riot.nightly`）
- 自更新机制: Squirrel（自更新）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **nightly**  | —       | —        | —   | —      | ✓           |

当前生效源: **VendorProbe**

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `im.riot.app`       | 独立 | bundle id 无 channel 词 → stable | ✓ |
| nightly | `im.riot.nightly` | 独立 | bundle id `.nightly` 后缀        | ✓ |

注: stable 的历史 bundle id `im.riot.app` 保留至今；Nightly 的真实 id 是 `im.riot.nightly`（同 `im.riot.*` 命名族，非 `io.element.*`）。

## 更新检测
- stable: `https://packages.element.io/desktop/update/macos/releases.json` → `"currentRelease": "X.Y.Z"`
- nightly: `https://packages.element.io/nightly/update/macos/releases.json` → 同 pattern（nightly 版本是 `YYYYMMDDNN` 构建戳）
- 仅检测（Element 自更新）

## Changelog
- **stable**：changelogURL `https://github.com/element-hq/element-web/releases`；ChangelogRecipe ✓ ——
  `.gitHubReleases` 读 `api.github.com/repos/element-hq/element-web/releases?per_page=40`，
  `tagPattern: ^v([0-9]+\.[0-9]+\.[0-9]+)$`。`element-hq/element-desktop` 已归档（release 停在 1.12.13），
  desktop 版本现在由 element-web 出，tag `v1.12.30` 去掉 `v` = `currentRelease`。tagPattern 必需：同一个
  Releases 列表还发 `module/banner/v2.1.1` 等模块包，且它们**不是** prerelease，光靠 stable 过滤会混进来；
  `-rc.N` 是 prerelease，被 stable 过滤掉，`$` 锚也拒。
- **nightly**：changelogURL 同样改为 `https://github.com/element-hq/element-web/releases`（原 element-desktop 仓库已归档）；
  不写 recipe —— 版本是 `YYYYMMDDNN` 构建戳，没有自己的 tag 或 release notes，没有任何条目能对上
  （`ChangelogCoverage.acknowledged` 里那一行保留）。

## 一键安装
- 状态: **已接入**。此前记为「仅检测」，是旧策略的残留。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- 若该 bundle 带 `Contents/Frameworks/Squirrel.framework`（扫描时判定），还会额外受
  `SelfUpdaterStaging` 保护：app 自己已staged 的更新会让一键让位给 Relaunch。

## channel-verify 状态
- ✓ **已验证 2026-06-04**（两 channel 官方 zip，解压后对真实 `.app` 跑 `channel-verify`，未安装）
- ⚠️ **此次验证抓到已发布 bug**：nightly recipe 原 key 为 `io.element.nightly`（不存在的 bundle id），
  真实 nightly 是 `im.riot.nightly`，probe 永远 miss；单测因用了同一错 id 而假性通过。
  已修 `VendorProbeRecipe.swift` + `ChannelGuardTests.swift` 并复验 green。
- 证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify "/tmp/Element.app"         --expect stable
swift run --package-path application-test channel-verify "/tmp/Element Nightly.app" --expect nightly
```

## 历史与实测

### Changelog recipe（stable）接入，2026-10-10

- `gh api repos/element-hq/element-desktop` → `archived: true`，`pushed_at` 2026-03-25；最新 release `v1.12.13`（2026-03-24）
  （接入前 changelogURL 指向这里）。
- `gh api "repos/element-hq/element-web/releases?per_page=40"`：前 40 条里 stable `v*` 12 条（v1.12.30 … v1.12.19），
  其余是 `-rc.N` prerelease 和 10 条非 prerelease 的 `module/*` 包 release。`packages.element.io/desktop/update/macos/releases.json`
  同时 `currentRelease: 1.12.30`，与最新 stable tag 一致。
- `v1.12.29` 的正文只有一句 "Update modules in element-web modules Docker image"，照样渲染成一条。

