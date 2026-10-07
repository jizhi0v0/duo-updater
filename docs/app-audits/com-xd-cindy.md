# Cindy（国际版 + 中国大陆版）

一个仓库发两个版本，两个独立的 app，合成一份审计。recipe 各一个 family 文件
（`Recipes/com-xd-cindy.swift`、`Recipes/com-xd-cindycn.swift`），共享理由与 changelog recipe 在前者。

## 基本信息

| 版本 | Bundle ID | Team | 资产后缀 |
|------|-----------|------|---------|
| 国际版 | `com.xd.cindy` | `SX9RG894L5`（XD Entertainment Pte Ltd） | `-global.dmg` |
| 中国大陆版 | `com.xd.cindycn` | `NTC4BJ542G`（X.D. Network Inc.） | `-cn.dmg` |

- App: Cindy — 心动（XD）的 Electron AI agent 客户端，两个版本都叫 `Cindy.app`
- 仓库: `makecindy/cindy`
- 观测版本: 0.1.97（2026-10-03）；观测日期: 2026-10-07
- 签名: 两版都 Developer ID + 公证（arm64 / x64 各一个 dmg，非 universal）
- 自更新机制: 自带。读 `hotfix.cindy.app/cindy`（国内版 `hotfix.cindy.com.cn/cindy`）的
  `manifest-darwin-<arch>[-beta|-canary].json`，`app.hotfix` 是整个 `.app` 的 zip：`ditto` 解开 →
  `rm -rf` 旧 app → `mv` 新 app，所以 `Info.plist` 跟着换，不会出现「app 内版本 ≠ 磁盘版本」。
  无 Sparkle、无 `app-update.yml`
- 分发: 官网 `cindy.app/download` / `cindy.cn/download` + CDN；GitHub Releases 是同一构建：
  0.1.97 的 CDN manifest `app.installer` 的 sha256 与本仓库对应资产四个逐一相同
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | ○（CDN manifest） |
| **beta**   | —       | —        | —   | ✗      | ○           |

当前生效源: **GitHub**（两版都由 channel-verify 实测）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | 见上表 | — | — | `/releases/latest` + tag 锚 `^vX.Y.Z$` + dmg 名锚（含版本后缀） | ✓ |
| beta（`vX.Y.Z-beta`，prerelease）| 同 stable | 共享 | app 设置里的 enableBeta（不在 bundle 里） | — | ✗ 未接入 |

- beta 包的 `Info.plist` 是裸 `X.Y.Z`（0.1.96-beta 真包 = 0.1.96），磁盘上与 stable 分不开。
  beta 号此后不会作为 stable 发（0.1.91-beta → 0.1.92、0.1.96-beta → 0.1.97），所以 beta 副本只会被提示更高的 stable，不会被降级。
- 另有 canary 渠道（manifest 后缀 `-canary`），未调查。

## 更新检测
- 源: `makecindy/cindy` GitHub Releases，`/releases/latest`
- 版本方案: tag `vX.Y.Z` == `CFBundleShortVersionString` == `CFBundleVersion`（0.1.95 / 0.1.97 真包）
- 注意事项 —— **`v1.0.0` 源码快照**: 一个没有任何资产的 release（正文写明官方安装包走官网与 CDN）。
  tag 符合锚，**挡住它的是 dmg 锚**：变异测试去掉 `installAssetPattern` 后，源直接答「1.0.0」
  （`CindyGitHubRuleTests.theAssetlessSnapshotIsWalkedPast`）。
- 注意事项 —— **两版共用 release**: 版本后缀写进 dmg 锚，arch 交给源的架构偏好；四种组合（2 版 × 2 arch）
  端到端测试都落在各自的 dmg。两条规则同仓库同渠道，各带 `variant`（`global` / `cn`），否则共用一个
  `recipeID`（`github:makecindy/cindy:stable`），健康统计与 verify 基线会并成一行
  （`RecipeHealthKeyTests.rulesSharingASlugRecordSeparateHealthEntries` 抓到的）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无（hotfix 是整 app zip） | 无 | 不能 |

## 按 OS 分轨
- `LSMinimumSystemVersion` = `12.0`；release 不声明逐版本 min/max。
- 架构: arm64 / x64 分包，源按本机架构选。

## Changelog
- 来源: GitHub Release body，经 **ChangelogRecipe**（`.json` 模式正则）结构化，两版共用
- 为什么不用默认解析: 正文是 `### <emoji 标题>` + 一段散文；`## PRs` 后、`---` 后是构建元数据列表
  （commit / source tag / 移动端版本）。`GitHubMarkdownParser` 先收列表，于是只把元数据当「更新」，
  正文全丢（改前实测：0.1.97 只有 7 条，全是 `commit:`、`source tag:`…）；它的散文兜底有 12 行上限，
  这些正文常常超
- 结构化（2026-10-07，channel-verify `changelog pane`）: ✓ `recipe`，20 条版本；0.1.97 12 个小标题 +
  12 段。0.1.17–0.1.20 是列表式，按列表收
- Recipe 状态: 已加（`com_xd_cindy.changelog(for:)`）

## 一键安装
- 状态: **支持**（两版）
- Pattern: 国际版 `^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-global\.dmg$`，国内版同形 `-cn`，kind `.dmg`
- 包验（2026-10-07）: 国际版 0.1.95 / 0.1.96-beta / 0.1.97 arm64 与 0.1.97 x64、国内版 0.1.95 / 0.1.97 arm64 挂载：
  bundle id 与 Team 见上表，`--deep --strict` 0，`spctl` Notarized Developer ID
- 端到端（2026-10-07，arm64）:
  - 不运行: 国际版 0.1.95 → `duo install` `installed`（81 s，304888229 字节 = global dmg）→ 0.1.97、
    inode 变、Team 不变、Notarized、与厂商包 `diff -r` 一致、有备份；国内版 0.1.95 → `installed`
    （304901986 字节 = cn dmg）→ 0.1.97、Team `NTC4BJ542G`
  - 运行中: 国内版 0.1.95 启动，它的更新器 60 s 内把 0.1.97 hotfix 暂存好（`updates/patch-info.json`）→
    `duo install` `installed` → `duo restart Cindy` → 新进程 0.1.97，之后 20 s 无回退。
    暂存的与 duo 装的是同一版本，「暂存旧版被换回」的冲突在这里看不出来
- 机器现状: 国内版 Cindy 0.1.97 仍装在 `/Applications`，未运行

## 已知问题
- **0.1.95 启动会往用户的 agent skill 目录写东西**: 在 `~/.claude/skills` 建了 5 个软链（其中 2 个指向它在
  `~/.agents/skills` 新建的、最终落到 `~/Library/Application Support/Cindy/shared-system-skills`）。
  0.1.97 启动后清掉了它自己的 2 个（与其更新说明「不再往你自己的技能目录里写文件」一致），
  另 3 个指向 `~/.agents/skills` 里原有目录的软链没清。厂商行为，不是安装过程带进来的。
- beta 轨未接入（见上）。

## 如何复验
```
swift run --package-path application-test channel-verify cindy-0.1.97-darwin-arm64-global.dmg   # → up to date
swift run --package-path application-test channel-verify cindy-0.1.95-darwin-arm64-global.dmg   # → UPDATE → 0.1.97
swift run --package-path application-test channel-verify cindy-0.1.97-darwin-arm64-cn.dmg       # → com.xd.cindycn, up to date
#   changelog pane 行: recipe changelog:com.xd.cindy(cn):-: 20 entries; newest 0.1.97: 12 items, headings [...]
curl -s https://hotfix.cindy.app/cindy/manifest-darwin-arm64.json   # app.installer.sha256 == GitHub 资产 digest
```

## 建议下一步
1. beta 轨: 渠道只在 app 设置里，要接需读 Cindy 的设置存储（位置未查）。
