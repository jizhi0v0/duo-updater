# Xcode

**这不是审计**：family `com-apple-dt-Xcode`（`Recipes/com-apple-dt-Xcode.swift`）里 Xcode `com.apple.dt.Xcode` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-apple-dt-Xcode.swift — ChangelogRecipe（Apple developer release notes JSON）

转引自 recipe 注释，未复测。

Xcode — Apple's own release notes, which `XcodeReleasesSource` already
links per release (`links.notes.url` in `xcodereleases.com/data.json`)
and which the pane could only ever embed: the `/documentation/…` URL
serves a 17 KB SPA shell with no note text in it (fetched 2026-09-03).

### Recipes/com-apple-dt-Xcode.swift — ChangelogRecipe（每个版本列车一页）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`07d150fc`（2026-09-03）。

One page per release train, and every beta of a train shares its page:
the top of `xcode-27-release-notes` IS beta 6's notes, with each earlier
beta below it under `Updates in Xcode 27 Beta N`.

复测 2026-09-14（UTC 2026-09-14 00:49，只读 GET）：`xcode-27-release-notes.json` 的 `metadata.title` 是 `Xcode 27 RC Release Notes`，全文没有 `Updates in` 标题（109 个 heading，第一个是 `Overview`）。

## `requires`：每个版本的 macOS 下限（2026-09-15 实测）

`curl -s https://xcodereleases.com/data.json`（只读 GET，2026-09-15）：451 条目**每条都带** `requires`，而且**同一个 Xcode 版本内并不是同一个值**：

| 条目 | build | `requires` |
|---|---|---|
| 27.0 RC 1 | `27A266a` | `26.6` |
| 27.0 beta 6 | `27A5252f` | `26.4` |
| 27.0 beta 1–5 | `27A5194q` … `27A5237l` | `26.4` |
| 26.6 release / RC | `17F113` | `26.2` |

全 451 条的 `requires` 都能按版本号解析（没有 `null`、没有非数字开头的写法；出现最多的值是 `15.6` 32 次、`26.2` 28 次、`10.7` 27 次）。

`XcodeReleasesSource` 此前根本没读这个字段，所以 macOS 26.0–26.5 的机器会被显示 27.0 RC 可用（#640）。现在它既过滤候选（取「跑得动的最新那个」，26.4 的机器拿到 beta 6 而不是 RC），也写进 `RemoteVersion.minimumSystemVersion`。
