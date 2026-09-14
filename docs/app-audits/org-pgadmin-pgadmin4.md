# pgAdmin 4

**这不是审计**：family `org-pgadmin-pgadmin4`（`Recipes/org-pgadmin-pgadmin4.swift`）里 pgAdmin 4 `org.pgadmin.pgadmin4` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-pgadmin-pgadmin4.swift — VendorProbe（挂载核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（挂载 arm64 dmg 读到的 `CFBundleShortVersionString` 与目录版本一致、Notarized Developer ID、Team、spctl，checked 2026-08-16），dmg 文件名与版本号搬到这里。

Verified 2026-08-16 by mounting `pgadmin4-9.17-arm64.dmg`: `pgAdmin 4.app`,
CFBundleShortVersionString exactly `"9.17"` (matches the probe 1:1, no
build/marketing mismatch here), notarized Developer ID, Team TCHGL2R7C5
("David Page"), spctl accepted.

### Recipes/org-pgadmin-pgadmin4.swift — VendorProbe 一键（挂载核对与架构）

转引自 recipe 注释，未复测。整段原文。代码里留下的是结论（与上一组相同的挂载核对，外加 bundle id），dmg 文件名、字节数与版本号搬到这里，`CFBundleVersion` 的值标成了示例。末句 "an Intel Mac is refused by the runnable-arch gate rather than given a build it can't run" 按当前代码不成立，代码里改写了，见下面的更正。

Verified 2026-08-16 by mounting `pgadmin4-9.17-arm64.dmg`
(233,075,920 B): `pgAdmin 4.app`, org.pgadmin.pgadmin4,
CFBundleShortVersionString `9.17` — exactly what the index publishes,
so no scheme mismatch — Team TCHGL2R7C5 (David Page), notarized
Developer ID, spctl accepted. (`CFBundleVersion` is an unrelated
`4280.88`; the recipe compares marketing, which is the field that
agrees.) arm64-only artifact, like the other arm64-pinned recipes
here; an Intel Mac is refused by the runnable-arch gate rather than
given a build it can't run.

更正 2026-09-14：DuoUpdater 只有 arm64 构建（`App/project.yml:23` `ARCHS: arm64`），没有 Intel 宿主，所以「Intel Mac 被 runnable-arch 闸拒掉」这条路径不存在。代码里改成：arm64-only 的产物，Apple silicon 是 DuoUpdater 运行的每一台宿主（`App/project.yml`，`ARCHS: arm64`）。
