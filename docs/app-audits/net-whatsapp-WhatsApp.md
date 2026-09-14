# WhatsApp

**这不是审计**：family `net-whatsapp-WhatsApp`（`Recipes/net-whatsapp-WhatsApp.swift`）里 WhatsApp `net.whatsapp.WhatsApp` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/net-whatsapp-WhatsApp.swift — VendorProbe（读 `Location` 而不跟随）

转引自 recipe 注释，未复测。整段原文；代码里把「the ~259 MB installer」改成了「the full installer, a few hundred MB」，文件名标成了示例。原句没写日期，引入它的提交是 `bb79ec92`（2026-08-09）。

WhatsApp — the downloads page's link 302s to a versioned dmg on fbcdn:
`…/WhatsApp-2.26.31.27.dmg`. Read the Location header rather than
following it: the target IS the ~259 MB installer, so a HEAD-follow would
be answered by the CDN with the real payload's headers and any GET would
fetch it outright.

### Recipes/net-whatsapp-WhatsApp.swift — VendorProbe（一键 dmg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（镜像里的 `WhatsApp.app` bundle id 与 Team 和装着那份一致、版本字段等于探针所报、spctl 接受，mounted and checked 2026-08-09），被挂载的 26.31.27 搬到这里。

One-click verified 2026-08-09 by mounting the 26.31.27 image: it holds
`WhatsApp.app` whose bundle id and Team (57T9237FN3) match the installed
copy, its `CFBundleShortVersionString` equals what the probe reports, and
`spctl` accepts it as "Notarized Developer ID". WhatsApp also updates
itself, so this row usually just confirms what already happened — but when
its own updater is behind, the swap is ours to make.

### Recipes/net-whatsapp-WhatsApp.swift — `appStoreCases`（`?platform=mac` 页与 lookup 不一致）

转引自 recipe 注释，未复测。整段原文；这一句里契约与测量缠在一起：契约是「这项巡检从不断言版本值，只断言 shelf 在且可解析」，理由是 Apple 自己的店面缓存前后不一致；测量是 2026-09-04 同一分钟里单次 lookup 与批量 lookup 读到的两个版本号。代码里留下契约、理由和「when checked (2026-09-04)」时两次 lookup 差一个补丁版本这个观察，两个版本号搬到这里。

WhatsApp — `kind == "software"` (an iOS listing), but its Mac build
publishes on its own release line: the `?platform=mac` product
page's `mostRecentVersion` shelf carries a DIFFERENT version than
the plain lookup's `version` field (measured 2026-09-04, same
minute: single lookup → 26.34.72, batched lookup → 26.34.74 —
Apple's own storefront cache is internally inconsistent by a patch
release, which is exactly why this sweep must never assert a
version value, only that the shelf is THERE and parseable).
Exercises `iosOnMacVersion`.

### Recipes/net-whatsapp-WhatsApp.swift — `changelogPages`（key 必须小写）

转引自 recipe 注释，未复测。整段原文；代码里留下的是规则和守卫（混合大小写的 key 查不到，`keysAreLowercased` 守着整张表），这条 entry 曾经的 key 与「never resolved」搬到这里。原句没写日期，引入它的提交是 `16b48496`（2026-08-26）。

WhatsApp — iOS-on-Mac (kind=software); MAS source scrapes the Mac page
for version comparison, but `remote` may be nil at render time if the
check hasn't finished. This catalog entry ensures the Mac App Store page
always shows as changelog fallback regardless of check timing.
`?platform=mac` redirects correctly regardless of storefront region.
Key MUST be lowercase — `url(forBundleID:)` lowercases its argument
before the lookup, so a mixed-case key here is simply unreachable. This
one was `net.whatsapp.WhatsApp` and never resolved; `keysAreLowercased`
now guards the whole table.
