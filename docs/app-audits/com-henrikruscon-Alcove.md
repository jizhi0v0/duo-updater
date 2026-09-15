# Alcove

**这不是审计**：family `com-henrikruscon-Alcove`（`Recipes/com-henrikruscon-Alcove.swift`）里 Alcove `com.henrikruscon.Alcove` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-henrikruscon-Alcove.swift — 公开 VendorProbe（`download.tryalcove.com/latest`，detection-only）

转引自 recipe 注释，未复测。唯一的改写：一处本机状态措辞（那台机器上授权版的 build），按本目录的机器状态规则改成了针对那台被量的机器的说法。第一段括号里的 "see GitHubReleasesSource" 迁移时已经指不到东西（`GitHubReleasesSource.swift` 里没有 Alcove）。

The old endpoint (update.tryalcove.com) is GONE — verified 2026-07-29 it no
longer resolves at all (NXDOMAIN), so the previous recipe silently produced
no version and left uncredentialed users with ZERO Alcove detection (the
henrikruscon/alcove-releases GitHub mirror had already been retired for
lagging; see GitHubReleasesSource).

Verified 2026-07-29
it reported exactly 1.7.9 (203), matching the licensed build installed on the machine verified that day
build-for-build — so unlike every mirror before it, this one is IN SYNC with
the licensed channel rather than trailing it. Single-channel: `?channel=beta`
404s ("No releases available") and an `X-Channel` header changes nothing.

The public
binaries at download.tryalcove.com/{Alcove.dmg,Alcove.zip} are the *trial*
build and lag this metadata badly: on 2026-07-29 the dmg was 1.7.7 (199)
(`x-alcove-version: 1.7.7`, confirmed by mounting it and reading the
bundle's Info.plist) while /latest already said 1.7.9. Installing it while
claiming 1.7.9 would leave a permanent phantom "update available" that no
install can ever clear. There is no versioned public download path either
(`/1.7.9/Alcove.dmg`, `?version=…` etc. all 404 or serve the same stale
trial build), so users without a license key are sent to the download page
by hand — and Alcove's own updater keeps them current regardless.

复测 2026-09-14（03:13 UTC；DNS 查询、只读 GET、对 dmg/zip 只发 HEAD）：`update.tryalcove.com` 仍是 NXDOMAIN；`/latest` 仍回 `1.7.9`（build 203，`published_at` 2026-06-30）；`?channel=beta` 回 404 `{"message":"No releases available."}`，带 `X-Channel: beta` 头回的仍是同一份 1.7.9；`Alcove.dmg` 与 `Alcove.zip` 的 `x-alcove-version` 都还是 `1.7.7`；`/1.8.0/Alcove.dmg` 回 404。

That page is not what gets parsed:
www.tryalcove.com/changelog is a real page — it server-renders every version
and date, newest 1.7.9 — but it is not scrapable: each entry's body is an
empty placeholder, with the actual features/fixes arrays inlined in a
content-hashed minified route chunk (`/assets/ChangelogPage-<hash>.js`)
whose filename changes on every deploy.

复测 2026-09-14（03:14 UTC，只读 GET，默认 UA 与 Safari UA 各一次）：`www.tryalcove.com/changelog` 与 `tryalcove.com/changelog` 都回 16,916 字节的 HTML，里面没有任何 `x.y.z` 形状的版本号，也没有名为 `ChangelogPage-*.js` 的资源（只有 `index-*.js`、`jsx-runtime-*.js` 等 modulepreload）。代码里这句已改写成「这份 HTML 里没有版本文本」。原句来自 `c2927845`（2026-08-09）。

There is no GitHub rule: the
`henrikruscon/alcove-releases` mirror one used to read LAGS the real release
(2026-06-14: stuck at 1.7.2 while the vendor served 1.7.3).

### `minimum_system_version`：厂商声明的 macOS 下限（2026-09-15 实测）

`curl -s https://download.tryalcove.com/latest`（只读 GET，2026-09-15）整份响应体：

```json
{"version":"1.7.9","build":203,"published_at":"2026-06-30T20:57:57.000Z","assets":[{"name":"Alcove.zip","size_bytes":15269999},{"name":"Alcove.dmg","size_bytes":16086914}],"minimum_system_version":"15 Sequoia"}
```

注意写法是 `15 Sequoia`，不是一个裸版本号——数字后面跟一个文本 token。`VersionComparator` 里文本 token 排在数字之下，所以它等价于「15.0 起」：14.7.2 的机器在下限之下，15.0.0 不在。

`AlcoveUpdateSource` 从**授权**端点解同一个键，写进 `RemoteVersion.minimumSystemVersion`，而在 #640 之前没有任何消费者——这是一道没上膛的闸。现在 `AlcoveUpdateSource.remote(from:token:osVersion:)` 在**挑候选的那一步**读它：低于下限就不返回 `RemoteVersion`，跟 Sparkle 的 `usableItems` 丢掉超窗条目、Xcode 的 `offer` 按 `requires` 圈候选是同一个形状。判定放在源里而不是 `UpdateChecker.evaluate`，理由见 `HostOS` 的文档注释。⚠️ 今天的值 `15 Sequoia` 任何受支持的宿主都满足，所以这道闸**当前一次都不会触发**——它是为厂商抬高下限的那天上的膛。⚠️ 授权端点 `api.tryalcove.com/updates/latest` 本次**没有复测**（这个 checkout 没有 license key），只测了公开端点。

### Recipes/com-henrikruscon-Alcove.swift — ChangelogRecipe（`api.tryalcove.com/changelog`）

转引自 recipe 注释，未复测。唯一的改写：一处本机状态措辞（那台机器上那份拷贝的版本），按本目录的机器状态规则改成了针对那台被量的机器的说法。

Newest is 1.7.9, matching
the copy installed on the machine checked on 2026-08-22.
