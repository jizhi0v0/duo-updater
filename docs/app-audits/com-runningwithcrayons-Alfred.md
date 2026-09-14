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
