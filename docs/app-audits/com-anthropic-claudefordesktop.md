# Claude Desktop

**这不是审计**：family `com-anthropic-claudefordesktop`（`Recipes/com-anthropic-claudefordesktop.swift`）里 Claude Desktop `com.anthropic.claudefordesktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-anthropic-claudefordesktop.swift — GA redirect + Squirrel rollout VendorProbe

转引自 recipe 注释，未复测。

GA alone goes blind for the whole ramp: on
2026-08-15, 1.30096.5 had been on the CDN for a day and the app's own
updater had already staged it for relaunch, while GA still said
1.30096.1 — we'd have reported "up to date" the entire time.

`device_id` is REQUIRED (no id → HTTP 400) and selects
the rollout bucket: four synthetic ids sampled on 2026-08-15 answered
.1/.5/.1/.1, which is exactly why the id must be this machine's real one
(`~/Library/Application Support/Claude/ant-did`, a base64-wrapped UUID)
and never a fabricated one.

### Recipes/com-anthropic-claudefordesktop.swift — rollout VendorProbe（`pub_date`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`b41af17a`（2026-08-15）。

`pub_date` is UTC (39s after the artifact's Last-Modified),
and it's what finally gets Claude into the Release Log timeline.
