# Opera

**这不是审计**：family `com-operasoftware-Opera`（`Recipes/com-operasoftware-Opera.swift`）里 Opera `com.operasoftware.Opera` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-operasoftware-Opera.swift — stable VendorProbe（目录索引，版本方案）

转引自 recipe 注释，未复测。整段原文；代码里留下的是版本方案的结论（marketing 只有两段、`CFBundleVersion` 是四段、与目录名一致，保留了核对日期），挂载核对的细节搬到这里。

VERSION SCHEME TRAP: verified 2026-08-16 by mounting
`Opera_134.0.5954.56_Setup.dmg` — it holds `Opera.app`, notarized
Developer ID (Team A2P9LX4JPN, "Opera Software AS"), spctl accepted. But
`CFBundleShortVersionString` is only `"134.0"` while `CFBundleVersion` is
`"134.0.5954.56"` — exactly what the folder name carries. Comparing the
4-part folder version against the 2-part marketing string would read
every release as a phantom major upgrade forever, so this is a build
comparison (`versionIsBuild`), not a marketing one.

### Recipes/com-operasoftware-Opera.swift — stable VendorProbe（一键 `.versionTemplate` dmg）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（2026-08-16 挂载时里面就是 `Opera.app` 本体，`CFBundleVersion` 等于目录名），大小、架构、Team 搬到这里。

Despite the "Setup" in the filename this dmg is NOT a stub
downloader (the 1Password trap): verified 2026-08-16 by mounting
`Opera_134.0.5954.56_Setup.dmg` (260,530,261 B) — it carries
`Opera.app` itself, 560 MB on disk, com.operasoftware.Opera,
universal (x86_64 + arm64), Team A2P9LX4JPN (Opera Software AS),
notarized Developer ID, spctl accepted. Its `CFBundleVersion` is
`134.0.5954.56`, i.e. exactly the folder name this recipe compares,
which is what makes the template safe as well as the comparison.

### Recipes/com-operasoftware-Opera.swift — ChangelogRecipe（`changelog-for-{major}`）

转引自 recipe 注释，未复测。末句的 "`source` is the current page" 迁移时已不成立（见下面的复测），代码里改成了「`source` 是某一个固定大版本的页」。

`{major}`, not `{version}`: the page covers a whole major line, and
Opera ships a new major every few weeks, so a fixed URL would quietly
stop covering the installed build. `source` is the current page, used
only if no version is ever supplied.

复测 2026-09-14（07:26 UTC，只读 GET）：`get.geo.opera.com/pub/opera/desktop/` 里数值最大的目录是 `135.0.5973.133/`；`blogs.opera.com/desktop/changelog-for-134/`、`-135/`、`-136/` 都回 200。`source` 仍是 `changelog-for-134`，已不是当前大版本的页。
