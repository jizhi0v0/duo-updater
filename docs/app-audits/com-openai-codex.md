# ChatGPT（原 Codex 桌面端）

**这不是审计**：family `com-openai-codex`（`Recipes/com-openai-codex.swift`）里 ChatGPT `com.openai.codex` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-openai-codex.swift — stable VendorProbe（backend appcast 端点 vs 静态 feed）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（静态 feed 与端点可以连续几个小时说法不一，在这时装静态 feed 的版本会和 app 自己的 Sparkle 打架），2026-08-22 那次的版本号搬到这里。

The app's `codexSparkleFeedUrl` is
`persistent.oaistatic.com/codex-app-prod/appcast.xml`, and reading it is
what we used to do. But `production-appcast-bootstrap.json` carries
`backendAppcastEnabled: true`, and Sparkle then asks the endpoint below,
which 307s to a per-target `appcast-<version>.xml`. The static file is a
PUBLISHING manifest; the redirect target is what the vendor is actually
shipping. On 2026-08-22 they disagreed for hours — the static feed listed
26.818.41705 (published 06:11Z, real zip, real signature) while every
machine asking the endpoint was told 26.818.41509 was newest. Installing
the published-but-unshipped build starts a fight the app wins: its own
Sparkle stages 41509, waits for a quit, and our restart is the quit.

### Recipes/com-openai-codex.swift — stable VendorProbe（`app_version`、`os-version`、`codex_cache_bust`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（`app_version` 必填但不参与；另外两个参数 2026-08-24 实测不改变重定向目标），试过的值搬到这里。`app_version` 那组值原句没写日期，引入它的提交是 `fe22d48b`（2026-08-22）。唯一的改写：一处本机状态措辞（具体版本号），按本目录的机器状态规则改成了针对那台被量的机器的说法。

`app_version` is required (omit it, or send something unparseable, and
there is no redirect) but does not participate: 0.0.0, the version installed on the machine measured on 2026-08-22,
and 99.999.99999 all resolved to the same target. A sentinel is
deliberate — if OpenAI ever does step upgrades, 0.0.0 is the value most
likely to be rejected outright, which `duo verify` reports, rather than
to answer plausibly and wrongly. The app also sends `os-version` and a
`codex_cache_bust` counter; neither changes the redirect target
(measured 2026-08-24: os-version 13.0.0 / 26.0.0 / 27.0.0 / omitted
resolve alike, and the counter is not stable even across the app's own
checks — 8, then 2, then 4), so this URL stays as short as it can be.

### Recipes/com-openai-codex.swift — stable VendorProbe（`plan_type` 与两条灰度轨）

转引自 recipe 注释，未复测。四段整段原文（中间的表格是原注释里缩进的摘录）；代码里留下的是结论：消费者档与企业档落在两条轨上、未知或省略落在企业轨、这是 openai/codex 0.146.0 的企业计划识别、分叉只是一个时间窗。表格、字节比较、61809/41509 这两个版本号和当天 15:29Z 的合流时间搬到这里。「by 15:29Z the same day」那句来自提交 `4f130a1c`（2026-08-25 00:06 +0800），表格那段来自 `09c3c395`（2026-08-24）。

`plan_type` is the second thing the endpoint keys on, and unlike
`app_version` it decides the answer. Measured 2026-08-24, same
installation_id, only this parameter varying:

```
    free | go | plus | pro | team   → appcast-26.818.61809.xml
    business | enterprise | ent26   → appcast-26.818.41509.xml
    unknown | omitted | nonsense    → appcast-26.818.41509.xml
```

Two rollout tracks, not per-tier builds: the five consumer values
return byte-identical XML, as do the three enterprise ones. The
enterprise feed does not merely sort 61809 lower — it has no such
item. This is the "enterprise-plan recognition" of openai/codex
0.146.0 (PRs #35238, #35537): business tiers roll out behind consumer
ones so IT can qualify a build.

The split is a WINDOW, not a standing structure: by 15:29Z the same
day every value above — `business`, `enterprise` and omitted included
— resolved to 26.818.61809. So nothing can assert on the split, and
`duo verify` cannot tell whether this parameter is doing anything:
outside the window both answers agree. It earns its place only inside
the window, which is exactly when getting it wrong starts the fight
described below.

### Recipes/com-openai-codex.swift — stable VendorProbe（省略 `plan_type` 时的那次误报）

转引自 recipe 注释，未复测。整段原文；第一句和末句原样留在代码里，搬走的是中间那次误报。原句没写日期，引入它的提交是 `09c3c395`（2026-08-24）。

So omitting it is not neutral — it silently books this machine onto
the enterprise track. That is what made `duo verify` report "remote is
BEHIND the installed copy" while ChatGPT itself was installing 61809.
And hardcoding a consumer value is worse than omitting: on an actual
business account we would offer a build that account's own updater
refuses, which is precisely the fight described above — its Sparkle
stages the older build, waits for a quit, and our restart is the quit.

### Recipes/com-openai-codex.swift — stable VendorProbe（`~/.codex/auth.json` 与 app 的关系）

转引自 recipe 注释，未复测。两段整段原文；代码里留下的是三条观察的结论和末句 "It does not consult this file to answer."。

What is shared is the FILE and the LOGIN EVENTS. The VALUE is not.
Measured on one machine, 2026-08-24:

  * signing out of ChatGPT.app DELETES `~/.codex/auth.json`, after
    which `codex login status` reports "Not logged in" — the app
    drives that file;
  * signing in again through `codex` recreates it, and the app returns
    to a signed-in state on its own;
  * but with the file holding a `team` token while the app's session
    was `free`, the app sent `plan_type=free` and never touched the
    file (mtime unchanged). It does not consult this file to answer.

### Recipes/com-openai-codex.swift — stable VendorProbe（`downloadURL` 为什么不指 `Codex.dmg`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（那个 dmg 跟的是发布清单）。

The tempting alternative is the direct artifact the site's button
serves, `codex-app-prod/Codex.dmg`. Do not use it, and not only
because `PageURLTests` requires a page: that dmg tracks the
PUBLISHING manifest. Its Last-Modified was 06:12:52Z on 2026-08-22,
ninety seconds after 26.818.41705 published — the very build the
rollout was still withholding. Pointing anything at it walks straight
back into the fight this recipe exists to end.
