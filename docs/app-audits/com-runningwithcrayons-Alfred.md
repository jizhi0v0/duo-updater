# Alfred

**这不是审计**：family `com-runningwithcrayons-Alfred`（`Recipes/com-runningwithcrayons-Alfred.swift`）里 Alfred `com.runningwithcrayons.Alfred` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-runningwithcrayons-Alfred.swift — beta VendorProbe（`prerelease.xml`）

转引自 recipe 注释，未复测。整段原文；代码里去掉了当时两个端点同为哪个 build 的例子。原句没写日期，引入它的提交是 `f1b18ab2`（2026-08-08）。

Same plist shape as stable, different endpoint. The two frequently serve
the SAME build — both were 5.7.3 (2320) here — so being on beta doesn't by
itself mean a newer version is on offer.

### Recipes/com-runningwithcrayons-Alfred.swift — stable VendorProbe（一键 `.tar.gz`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（`location` 指向根目录就是 `Alfred 5.app` 的 tarball，保留了核对日期），bundle id、Team 和 `spctl` 结果搬到这里。

One-click added 2026-08-08 after verifying what `location` points at: the
tarball holds `Alfred 5.app` at its root, whose bundle id
(`com.runningwithcrayons.Alfred`) and Team (`XZZXE9SED4`) match the
installed copy, and `spctl` reports "Notarized Developer ID". That URL
carries the version, so it's read from the same body rather than fixed.
Alfred still self-updates on its own; this only means the row can too.

### Recipes/com-runningwithcrayons-Alfred.swift — beta channel proof

转引自 recipe 注释，未复测。整段原文；代码里去掉了 2026-08-09 两个端点同为哪个 build 的例子。

Alfred serves stable and pre-release from two endpoints that frequently
carry the SAME build (both were 5.7.3 (2320) on 2026-08-09), and the
tarball name never mentions a channel — only the endpoint can prove it.
Endpoint-scoped for the same reason as IntelliJ EAP: this recipe's
install `bodyPattern` is byte-identical to the stable Alfred recipe's
(same plist shape, different endpoint) and its `versionPattern` differs
only in strictness — neither names a channel. So the endpoint is not
merely the best evidence, it is the only evidence there is, and the
proof says so.

复测 2026-09-14（约 07:35 UTC，只读 GET `www.alfredapp.com/app/update5/general.xml` 与 `prerelease.xml`）：两者都是 `version` 5.8、`build` 2348，仍是同一个 build。

### Recipes/com-runningwithcrayons-Alfred.swift — ChangelogRecipe（`alfredapp.com/changelog/`）

实测 2026-10-10（只读 GET，curl 与生产解析器 `ChangelogService.loadDiagnostic` 各一次）：200，21525 字节，
23 个条目，`5.8.1`（Build 2349, Thursday 24th September 2026）到 `5.0`；页底的 `Alfred 5.0 EA3` / `EA2`
两条早期测试版不计入。同日 `general.xml` 与 `prerelease.xml` 都是 `version` 5.8.1、`build` 2349，
`verify/baseline.json` 的 stable 与 beta 两行也都是 `5.8.1`：页面版本号、plist 的 `version` 与两行
offered 同一口径（build 号只出现在日期前那段文字里）。beta 渠道查到的是同一个 recipe。

### Alfred 6 正式发布后的更新与迁移（2026-11-20）

- 直装 Alfred 5 的稳定、预览 feed 保持在 `/app/update5/`。官网发行说明已进入 6.x，Alfred 6 的 `/app/update6/general.xml` 与 `prerelease.xml` 在 VM 都返回 6.0.2（3222），位置是 `https://cachefly.alfredapp.com/Alfred_6.0.2_3222.tar.gz`。归档根目录为 `Alfred 6.app`，Bundle ID 仍为 `com.runningwithcrayons.Alfred`、Team `XZZXE9SED4`，严签通过，包内最低系统要求为 macOS 12。
- 5.x 先完成其原更新轨的适用补丁，随后显示 6.x 大版本提示并打开官方迁移说明。官网要求另装 Alfred 6，首次启动使用 Migration Assistant，Powerpack 需 Alfred 6 授权。已装 6.x 的稳定与预览继续按各自 feed 更新。Homebrew 的 Alfred cask 同样以 `Alfred 6.app` 独立命名。
- 夜扫用 `alfred5` 与 `alfred6` 区分同 Bundle ID、同渠道的两个版本代际。原 5.x 安装身份和基线随 recipe ID 改名保留。

[官方迁移与授权说明](https://www.alfredapp.com/blog/tips-and-tricks/getting-started-with-alfred-6/) · [Homebrew cask 元数据](https://formulae.brew.sh/api/cask/alfred.json)
