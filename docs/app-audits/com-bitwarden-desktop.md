# Bitwarden

**这不是审计**：family `com-bitwarden-desktop`（`Recipes/com-bitwarden-desktop.swift`）里 Bitwarden `com.bitwarden.desktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-bitwarden-desktop.swift — GitHub rule（`bitwarden/clients` monorepo）

转引自 recipe 注释，未复测。

Bitwarden — the ONLY rule here that can't read `/releases/latest`: the
monorepo tags every client, and the newest release is usually `web-…` or
`cli-…`, not the desktop app (on 2026-08-16 `/releases/latest` was
`web-v2026.7.1` while the desktop app sat at `desktop-v2026.7.0`).

Measured over the newest 100 releases,
consecutive `desktop-v` tags are at most 7 apart (re-verified
2026-09-04: same 7, `desktop-v2026.6.0`→`desktop-v2026.5.0` and three
other pairs), so the desktop tag sits well inside a page of 10 today
— chosen over the observed 7 to leave margin rather than trim to the
minimum, per the same logic as every other rule in `GitHubReleaseRegistry` — but a long
burst of web/cli/browser releases would still push it off the page,
and the rule would then resolve nothing, which surfaces as the row
going quiet rather than as an error.

The newest release of this monorepo is a web/CLI/browser tag far
more often than the desktop one (measured 2026-09-05: the one-row
page was `web-v…`, and the same shape held across the newest 100
releases, `desktop-v` tags at most 7 apart), so a one-row probe
here would fall back to the full page most rounds and only add a
request.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`repos/bitwarden/clients/releases?per_page=100` 首条 `web-v2026.8.1`，第一个 `desktop-v` 在第 3 位，相邻 `desktop-v` 最大间隔 7，21 个 `desktop-v` tag 全是裸版本号、非 prerelease。
