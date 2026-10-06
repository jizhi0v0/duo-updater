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

### Recipes/com-anthropic-claudefordesktop.swift — rollout 一键接上 sha256（2026-10-07）

rollout 端点的 `updateTo` 现在带 hex `sha256`（和 `size`）；2026-08-15 抓的 body 里还没有。rollout recipe 接上它（`checksumFormat: .sha256Hex`，#1016），
在 Team `Q6L2SF6YDW` 闸之上先核下载字节。pattern 取「body 里第一个 Claude zip URL 所在的那个对象」里的 `sha256`，即 install pattern 读的那一项，与键序无关；
该对象没有 `sha256` 时什么都不读，不会借后面另一个 release 的摘要。GA 端点是一个 307，`Location` 里没有摘要，所以不设 `checksumPattern`；
`VendorProbeSource.best` 交出的是整个 outcome，GA 胜出时它的 `RemoteVersion` 不带 SHA-256，rollout 的摘要不会套到 GA 的 zip 上。

实测（2026-10-07，只读 GET + 下载；没有碰本机装着的 Claude.app 和它的进程，只读了 `ant-did` 拿 device id）：
- rollout（本机 device id）：`currentRelease` 1.46388.4，`url` `…/1.46388.4/Claude-50e62f90….zip`，`sha256` `494c3c6e…8617`，`size` 355,648,442。
  下载这个 zip：355,648,442 B，SHA-256 `494c3c6e…8617`，一致。
- GA：307 → `…/2.19675.1/Claude-8613680e….zip`，无摘要。
- 生产路径（`VendorProbeSource.probeDiagnostic` 两个 recipe 各跑一次，再 `best(of:)`）：rollout 的 `expectedSHA256` 是 `494c3c6e…`，GA 为 nil；
  `best` 选 GA（2.19675.1 更高），结果 `expectedSHA256` 为 nil。`VendorInstaller.verifySHA256` 对下载的 rollout zip 通过，翻转一个字节的副本抛 `checksumMismatch`（临时测试，跑完已删）。没有跑 `duo install`。
- 观测（**未查原因**）：这台机器的 rollout 端点答 1.46388.4，比 GA 的 2.19675.1 低一个大版本，所以眼下 rollout 不会胜出，这次接上的摘要在本机暂时用不到。
