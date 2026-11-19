# Hidden Bar

**这不是审计**：family `com-dwarvesv-minimalbar`（`Recipes/com-dwarvesv-minimalbar.swift`）里 Hidden Bar `com.dwarvesv.minimalbar` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-dwarvesv-minimalbar.swift — stable GitHubReleaseRule（一键 `Hidden-Bar-v<ver>-macos.zip`）

转引自 recipe 注释，未复测。

Hidden Bar — the app DOES carry a Sparkle feed
(`SUFeedURL = api.amore.computer/v1/apps/com.dwarvesv.minimalbar/appcast.xml`),
which is why it looks covered from the outside and isn't: fetched
2026-08-16 the feed answers 200 with a well-formed `<channel>` — title,
link, description — and **no `<item>` at all**.

One-click verified 2026-08-16 by unpacking `Hidden-Bar-v1.10-macos.zip`:
`Hidden Bar.app`, com.dwarvesv.minimalbar, 1.10, universal, Team
W777S7V8TN (Dwarves Foundation Company Limited), notarized Developer ID.

复测 2026-09-14（03:11 UTC，只读 GET）：feed 仍回 HTTP 200，419 字节，`<channel>` 里只有 title / link / description / language，0 个 `<item>`。


### 2026-11-19 · GitHub 仓库迁移和 Sparkle 公钥

旧安装包 1.11.1（16）没有 Sparkle 公钥。[1.11.2 官方发布说明](https://github.com/consolelabs/hidden/releases/tag/v1.11.2)
记录了 Sparkle 的引入。1.11.2 和 1.13.0 的签名副本内置旧 GitHub 仓库地址上的 appcast。1.13.1（22）
已内置 `https://github.com/consolelabs/hidden/releases/latest/download/appcast.xml`。这些带 Sparkle 的版本使用同一公钥。

macOS 27.2 ARM64 VM 的 `duo verify-install --only com.dwarvesv.minimalbar --full` 从新仓库读取了 1.13.1 ZIP，
匹配原 Bundle ID `com.dwarvesv.minimalbar`、Team `W777S7V8TN` 和 universal 架构。夜扫身份保留首次观测的
1.11.1，将记录迁至 `consolelabs/hidden` 并加入这次核对的公钥。

同一台 VM 用 `duo install` 分别从 1.11.1（GitHub）和 1.11.2（旧仓库地址上的 Sparkle appcast）更新，
两次均原地装到 1.13.1（22），签名通过，复查均由 Sparkle 报已是最新。GitHub 路径的装后 Gatekeeper
检查返回 Notarized Developer ID。

## 夜扫覆盖

- 版本和安装扫描分别使用 `github:consolelabs/hidden:stable` 和 `install:github:consolelabs/hidden:stable`，
  携带旧记录的告警历史。旧版 GitHub 路径和新版 Sparkle appcast 在本次观测中指向同一个版本 ZIP。
- GitHub 安装扫描检查包内身份和公钥连续性。Appcast 可达性和独立的 Sparkle 签名验证没有单列夜扫项。
