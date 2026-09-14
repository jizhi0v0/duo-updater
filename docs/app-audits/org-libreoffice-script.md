# LibreOffice

**这不是审计**：family `org-libreoffice-script`（`Recipes/org-libreoffice-script.swift`）里 LibreOffice `org.libreoffice.script` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-libreoffice-script.swift — VendorProbe（一键 dmg 的 `.versionTemplate`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（这个地址 302 到按请求变化的 MirrorBrain 镜像，所以从规范主机拼、不缓存；深一层的路径不是阻碍，`.bodyTemplate` 才是），HEAD 的日期改成挂在镜像示例后面的 "checked by HEAD 2026-08-16 and 2026-09-14"，「以前这里说深一层路径是阻碍」的说法搬到这里。

ONE-CLICK, via `.versionTemplate`. The mac artifact sits two levels below
the index, at a path that is fully determined by the version:
`<ver>/mac/aarch64/LibreOffice_<ver>_MacOS_aarch64.dmg` (HEAD 2026-08-16:
302 to a MirrorBrain mirror, e.g. `mirror.usi.edu` / `mirror.fcix.net` —
the mirror changes per request, which is why the URL is built from the
canonical host and never cached). An earlier note here called the deeper
path a blocker; it isn't — what would have been a blocker is
`.bodyTemplate`, whose regexes take the FIRST match while this index is
sorted alphabetically and `selectHighest` deliberately picks a different
entry, so the URL could name an older release than the one reported.
`.versionTemplate` fills the resolved version instead, which is exactly
the string that was compared.

复测 2026-09-14（14:11 UTC，对 `download.documentfoundation.org/libreoffice/stable/26.2.5/mac/aarch64/LibreOffice_26.2.5_MacOS_aarch64.dmg` 连发两次只读 HEAD，不跟随重定向）：两次都是 302，`Location` 依次在 `southfront.mm.fcix.net` 与 `mirror.usi.edu` 上。当天索引页列出的版本目录是 `25.8.7/`、`26.2.5/`、`26.2.6/`、`26.8.0/`。

### Recipes/org-libreoffice-script.swift — VendorProbe（只取 aarch64）

转引自 recipe 注释，未复测。整段原文。两处按当前代码不成立，代码里改写了，见下面的更正。

aarch64 only, like the other arm64-pinned recipes here (GIMP, pgAdmin,
Meld). On an Intel Mac the download is refused by the runnable-arch gate
rather than installed — the fail-safe direction; LibreOffice does publish
an x86-64 dmg, and picking between them needs arch-aware plumbing the
vendor path doesn't have yet (only the GitHub rules do).

更正 2026-09-14：(1) DuoUpdater 只有 arm64 构建（`App/project.yml:23` `ARCHS: arm64`），没有 Intel 宿主，所以「Intel Mac 被 runnable-arch 闸拒掉」这条路径不存在；(2) "picking between them needs arch-aware plumbing the vendor path doesn't have yet (only the GitHub rules do)" 写下时（`8561dc60`，2026-08-16）成立，提交 `9f7e660e`（2026-08-27）给 `VendorProbeRecipe` 加了 `hostRequirement`（`Sources/VendorProbeRecipe.swift:250`，经 `runs(onOS:arch:)` 过滤，`:1038`；`Sources/VendorProbeSource.swift:267` 传入 `HostArch.current`）之后不再成立。代码里改成：只取 aarch64，Apple silicon 是 DuoUpdater 运行的每一台宿主，所以同时发布的 x86-64 dmg 从来不是要的那个。

### Recipes/org-libreoffice-script.swift — VendorProbe（版本段数陷阱与包身份）

转引自 recipe 注释，未复测。整段原文。代码里去掉了 "(the one flagged in the brief)"：它指向写这条 recipe 时的一份任务说明，不在仓库里，读者循着它找不到任何东西（引入它的提交是 `309de2c2`，2026-08-16）；两个版本号标成了示例；挂载 aarch64 dmg 读到的签名、Team 与 spctl 结果单独成句，日期挂在句末。

VERSION SCHEME TRAP (the one flagged in the brief): the index publishes
3-segment versions (`26.2.5`) but the installed bundle reports 4
(`CFBundleShortVersionString` AND `CFBundleVersion` both `26.2.5.2`,
verified 2026-08-16 by mounting the aarch64 dmg — notarized Developer ID,
Team 7P5S3ZLCN7, "The Document Foundation", spctl accepted). Comparing a
bare `26.2.5` against `26.2.5.2` is safe either way `VersionComparator`
treats missing trailing components as `0`: it reads the installed copy as
(at worst) equal, never triggers a phantom update. The only blind spot is
a pure 4th-component hotfix under an unchanged 3-segment folder, which
this index can't see at all — same acceptable direction as OneDrive's
first-three-components recipe (`Recipes/com-microsoft-OneDrive.swift`).
