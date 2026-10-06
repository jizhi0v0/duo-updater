# GIMP

**这不是审计**：family `org-gimp-gimp`（`Recipes/org-gimp-gimp.swift`）里 GIMP `org.gimp.gimp` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-gimp-gimp.swift — VendorProbe（`gimp_versions.json` 的 `STABLE`）

转引自 recipe 注释，未复测。整段原文。"`STABLE` is a single release object (not an array of channels)" 不成立，写下时也不成立，代码里改写了，见下面的更正。状态码与字节数、"Verified value: `3.2.4`" 搬到这里；代码里留下的结论是那个值与挂载 arm64 dmg 的两个版本字段一致（checked 2026-08-16）。

GIMP — the project's own `gimp_versions.json` (served from gimp.org,
status 200, 139419 bytes when checked 2026-08-16). `STABLE` is a single
release object (not an array of channels), so anchoring on the "STABLE"
key and taking the object's own `"version"` field is enough — no risk of
reading `DEVELOPMENT`'s or `NIGHTLY`'s number instead. Verified value:
`3.2.4`, which matches BOTH `CFBundleShortVersionString` and
`CFBundleVersion` of the mounted arm64 dmg — the same scheme the app
reports, so no `versionIsBuild`.

更正 2026-09-14：`STABLE` 是 release 对象的数组。同一个提交 `b49d0a30`（2026-08-16）里的 `versionPattern` 就是 `"STABLE"\s*:\s*\[\s*\{…`，`GroupAProbeRecipeTests` 的 fixture 里 `STABLE` 也是数组。复测（13:59 UTC，只读 GET `www.gimp.org/gimp_versions.json`，解压后 142,588 B）：顶层键依次是 `STABLE`、`DEVELOPMENT`、`NIGHTLY`；`STABLE` 有 40 个对象，前五个的 `version` 依次是 `3.2.6`、`3.2.4`、`3.2.2`、`3.2.0`、`3.0.8`（新到旧）；`versionPattern` 取到 `3.2.6`，两个安装字段取到 `3.2` 与 `gimp-3.2.6-arm64.dmg`。代码里改成：`STABLE` 是 release 对象的数组、新到旧（checked 2026-09-14），取第一个对象的 `version`。

### Recipes/org-gimp-gimp.swift — VendorProbe（一键 dmg 与包身份）

转引自 recipe 注释，未复测。整段原文；代码里把末句句首的 "Installed-bundle identity confirmed 2026-08-16:" 改成 "Bundle identity: … (checked 2026-08-16)"，核对到的 bundle id、Team 与 spctl 结果不变；文件名标成了示例。

One-click: the JSON carries no download URL, only a `macos` array of
per-arch filenames (`gimp-3.2.4-arm64.dmg`). The real download host
(`download.gimp.org/gimp/v{major.minor}/macos/{filename}`) was confirmed
by HEAD (200, resolves through their mirror network via `Location`), so
the install URL is rebuilt from two captures off the same `macos` block:
the filename's major.minor and the filename itself. The published
`sha512`/`sha256` fields are HEX, not the base64 SHA-512 `checksumPattern`
verifies, so no checksum is wired — the Team-ID signature gate is the
only defense, same tradeoff as Gemini (`Recipes/com-google-GeminiMacOS.swift`).
Installed-bundle identity confirmed 2026-08-16: `org.gimp.gimp`,
notarized Developer ID, Team T25BQ8HSJF (GNOME Foundation) — `spctl`
accepted as "Notarized Developer ID".

### Recipes/org-gimp-gimp.swift — 一键接上 sha256（2026-10-07）

原注释里「hex 摘要接不上、只靠 Team ID 闸」不再成立：`VendorInstallSpec.checksumFormat: .sha256Hex`（#1016）之后，
下载会先对同一条目的 `sha256` 核对。

实测（2026-10-07，`www.gimp.org/gimp_versions.json`，142,588 B）：`STABLE[0]` 是 3.2.6，`macos` 里 x86_64 在前、arm64 在后，
每个条目的键依次是 `date, filename, sha512, sha256, build-id, min-support`。checksum pattern 在这份文件上取到 arm64 的
`854573aec2be6a185aa021109c3c0ca94f210379204b704231bdd191b4060294`，与 JSON 值一致。经镜像（`mirrors.ocf.berkeley.edu`）
下载的 `gimp-3.2.4-arm64.dmg` 的 SHA-256 等于该版本公布的 `294c016d…392b`。`duo install GIMP` 3.2.4 → 3.2.6：
`extracting` 前出现 `verifyingSignature`（摘要闸），安装成功，`spctl` accepted，Notarized Developer ID，GNOME Foundation (T25BQ8HSJF)。
