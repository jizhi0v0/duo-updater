# HBuilderX

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/alpha 两 channel 已检测（独立 bundle id）**

## 基本信息
- Bundle ID: `io.dcloud.HBuilderX`（Alpha 独立：`io.dcloud.HBuilderXAlpha`）
- Team ID: `YQM5H857L5`（stable 和 alpha 共用同一 Team）
- 自更新机制: 内置更新（DCloud 自研）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓ +一键      |
| **alpha**    | —       | —        | —   | —      | ✓ +一键      |

当前生效源: **VendorProbe**

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `io.dcloud.HBuilderX`      | 独立 | bundle id 无 channel 词 → stable       | ✓ |
| alpha   | `io.dcloud.HBuilderXAlpha` | 独立 | bundle id 含 `Alpha` + 名称 → `.alpha` | ✓ |

## 更新检测
- stable: `https://download1.dcloud.net.cn/hbuilderx/release.json`（**2026-07-03 改**：原为第三方镜像 `update.liuyingyong.cn/…/alpha/…`，只有 manifest 会滞后；官方 `release.json` 同时带版本+安装包，更权威更新鲜，与 changelog recipe 同源）（更正 2026-09-14：自 `0b92a57f`（2026-08-22，「changelog: read HBuilderX from the official markdown, one hop」）起，stable 的 ChangelogRecipe 读 `hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md`，不再读 `release.json`（`Recipes/io-dcloud-HBuilderX.swift` 的 stable `ChangelogRecipe` 的 `source`）。「与 changelog recipe 同源」因此不再成立。）
  - versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"` 末尾 `"` 关键——防止匹配 `displayVersion`(2 段)或 `-alpha`/`-beta` 后缀
- alpha: `https://download1.dcloud.net.cn/hbuilderx/alpha.json`
  - versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-alpha)"` 捕获含后缀的完整版本
  - `channel: .alpha`——VendorProbeSource channel gate 必须与安装的 `.alpha` 一致

## Changelog
- stable: ChangelogRecipe ✓（读 `hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md`；`hx.dcloud.net.cn/Tutorial/HistoryVersion` 是两条 VendorProbe 的 `changelogURL`）
- alpha: ChangelogRecipe ✓（读 `…/ReleaseNote_alpha.md`，单独 bundleID `io.dcloud.HBuilderXAlpha`；VendorProbe 的 changelogURL 与 stable 相同）
- 更正 2026-09-14：这两行原来把 `HistoryVersion` 写成 ChangelogRecipe 的来源；那是两条 VendorProbe 的 `changelogURL`，两条 ChangelogRecipe 自 `0b92a57f`（2026-08-22）起读的是上面的 markdown（`Recipes/io-dcloud-HBuilderX.swift` 两条 `ChangelogRecipe` 的 `source`）。

## 一键安装
- stable: **一键 ✓**（2026-07-03 加，随版本源改到 `release.json` 一并接入）。`files[]` 里带
  `mac_simple_arm64` 的 `…arm64.dmg`；`.bodyPattern` 锁 `\.arm64\.dmg`（x64 `mac_simple` `.dmg`
  排前面，同 alpha 一样必须锚 arm64）；dmg 同 Team `YQM5H857L5`、已公证（`spctl` accepted），
  过 `VendorInstaller` 签名门。仅 arm64。
- alpha: **一键 ✓**（2026-06-05 加）。同一个 `alpha.json` 的 `files[]` 里就带安装包；
  `.bodyPattern` 锁 `…-alpha.arm64.dmg`（x64 的 `mac_simple` `.dmg` 排在前面，必须用
  `\.arm64\.dmg` 锚定，否则首个匹配会抓到 Intel 包）；dmg 与已装 alpha 同 Team
  `YQM5H857L5`、已公证（`spctl` accepted），过 `VendorInstaller` 签名门。仅 arm64。

## 已知问题
- stable 端点路径含 `/alpha/`（DCloud 命名混乱）；非 alpha 版本确认为官方 stable 构建（5.07.2026041006 = 最新正式版），非预发布
- Alpha 真正的版本字符串带 `-alpha` 后缀（`5.11.2026052520-alpha`），`VersionComparator` 将 `-alpha` 作为尾文本，纯数字版本高于它——比较正确

## channel-verify 状态
- ✓ **两 channel 已验证 2026-06-04**（`--scan`，两条轨各有一份真实 bundle）。stable `io.dcloud.HBuilderX` 5.07… 与 alpha `io.dcloud.HBuilderXAlpha` 5.11…-alpha 是独立 bundle id；两条 VendorProbe 均应答=installed。证据见下文「如何复验」。
- ✓ **stable 复验 2026-07-03**（版本源改 `release.json` + 加一键后）：`channel-verify /Applications/HBuilderX.app --expect stable` → detected stable，VendorProbe 应答 `UPDATE 5.07.2026041006 → 5.14.2026070214`，download 抠出 `HBuilderX.5.14.2026070214.arm64.dmg`

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan io.dcloud.HBuilderX --expect stable
swift run --package-path application-test channel-verify --scan io.dcloud.HBuilderXAlpha --expect alpha
```

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/io-dcloud-HBuilderX.swift — stable VendorProbe（开头：与 changelog recipe 同源）

转引自 recipe 注释，未复测。整段原文。「the SAME `release.json` the changelog recipe already reads」迁移时已不成立，代码里改写了，见下面的更正。

HBuilderX (DCloud) — the vendor's own download-site config. This is the
SAME `release.json` the changelog recipe already reads (see
ChangelogRecipe), and it carries BOTH the version and the installer
`files[]`, so one source drives detection and one-click alike — the same
shape as the alpha recipe below.

更正 2026-09-14：自 `0b92a57f`（2026-08-22，「changelog: read HBuilderX from the official markdown, one hop」）起，stable 的 ChangelogRecipe 读 `hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md`，不再读 `release.json`（`Recipes/io-dcloud-HBuilderX.swift` 的 stable `ChangelogRecipe` 的 `source`）。代码里改成「(The changelog recipe no longer reads this file; see ChangelogRecipe.)」；同一说法在本审计「更新检测」一节的副本也加了更正。

### Recipes/io-dcloud-HBuilderX.swift — stable VendorProbe（此前的第三方镜像）

转引自 recipe 注释，未复测。整段原文；代码里改成一句否决说明留下（第三方镜像只提供更新 manifest、没有安装包、可能落后于厂商），「官方 release.json 更新鲜、直接列出 arm64 dmg」这句由开头一段承担。

Previously this pointed at a third-party mirror
(update.liuyingyong.cn/…/alpha/…) that only served the update manifest,
no installer, so it was detection-only and could lag the vendor. The
official release.json is fresher and lists the arm64 dmg directly.

### Recipes/io-dcloud-HBuilderX.swift — alpha VendorProbe（一键 arm64 dmg）

转引自 recipe 注释，未复测。整段原文；末句括号里的「arm64-first」迁移时已不准确，代码里改写了，见下面的更正。

One-click: the SAME alpha.json that yields the version also lists the
installer under `files[]`. We grab the arm64 dmg explicitly — its
`mac_simple_arm64` entry appears AFTER the x64 `mac_simple` `.dmg`, so a
naive `\.dmg` `.bodyPattern` (first match) would pull the Intel build;
the `\.arm64\.dmg` anchor pins the right one regardless of order. The dmg
is notarized under the same Team ID YQM5H857L5 as the installed alpha, so
it clears VendorInstaller's signature gate. (Apple-silicon only; an Intel
Mac would need the plain `…-alpha.dmg`, but this repo is arm64-first.)

更正 2026-09-14：DuoUpdater 不是「arm64 优先」而是只有 arm64（`App/project.yml:23` `ARCHS: arm64`），所以不存在需要 plain `…-alpha.dmg` 的 Intel 宿主。代码里改成「Apple-silicon only, which is every host DuoUpdater runs on」。

### Recipes/io-dcloud-HBuilderX.swift — stable ChangelogRecipe（单跳 markdown）

转引自 recipe 注释，未复测。整段原文；代码里只去掉了「~95 KB」。原句没写日期，引入它的提交是 `0b92a57f`（2026-08-22）。

HBuilderX (DCloud) — SINGLE-hop now, not two-stage: hx.dcloud.net.cn
serves a plain markdown changelog directly (200, ~95 KB, no redirect,
no per-request tokenized CDN hop), so there is no index page to follow
and no `indexLinkPattern` here anymore (that's how the old
download1.dcloud.net.cn/release.json + HTML-detail-page two-stage
fetch worked; this recipe replaces it wholesale, not on top of it).
NOT `structuredFormat`: that decoder path (`StructuredChangelogDecoder`)
is for feeds too irregular for the regex extractor; this one is a
clean, uniform `## <version>` / `* <item>` document that the regex
path handles directly — and `structuredFormat` would also disable
`indexLinkPattern` handling in `ChangelogService`, which is irrelevant
here anyway since there's no second hop to disable.

### Recipes/io-dcloud-HBuilderX.swift — stable ChangelogRecipe（尾部链接的剥离）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（绝大多数行的尾部链接被剥掉，链接在句中的少数行保留原样），1301/1303、618/685 和「每份文档各一条例外」搬到这里；版本标题标成了示例。原句没写日期，引入它的提交是 `0b92a57f`（2026-08-22）。

Format: `## 5.24.2026081301` heading (the build IS the version, no
separate date — same as the old HTML: there was never a `date` group
there either, so this is not a regression), then `* ` bullet lines,
e.g. `* 修复 ... [详情](https://issues.dcloud.net.cn/...)`. The
trailing `[详情](url)` / `[文档](url)` markdown link (occasionally two
in a row, occasionally followed by a bare `<url>` autolink) is stripped
by the item pattern rather than kept literal — flattening it to just
the link text (as `StructuredChangelogDecoder.bulletItems` does for
the structured path) isn't reachable from here without a much bigger
change to the regex extractor, so instead the pattern simply excludes
any *trailing* link syntax from the captured item. This covers the
overwhelming majority of lines (verified: 1301/1303 items across both
documents — 618 in release, 685 in alpha — have their link(s) fully
stripped this way; the sole exception in EACH document is one line
where the link sits mid-sentence rather than at the end — that rare
case is left with its `[text](url)` literal intact).

### Recipes/io-dcloud-HBuilderX.swift — stable ChangelogRecipe（`maxEntries` 旁的版本数）

转引自 recipe 注释，未复测。整段原文（行内注释）；代码里把「32 versions」换成了「History has its length」。原句写于提交 `0b92a57f`（2026-08-22）。

The doc is a years-long cumulative list (32 versions); cap to the
recent handful, same as before.

### Recipes/io-dcloud-HBuilderX.swift — alpha ChangelogRecipe（`maxEntries` 旁的版本数）

转引自 recipe 注释，未复测。整段原文（行内注释）；代码里改成「Same cap as stable (History has the alpha document's length)」。原句写于提交 `0b92a57f`（2026-08-22）。

Alpha document lists 67 versions; same cap as stable.
