# Raycast

审计日期：2026-08-27（本机 macOS 27 / Darwin 27.0.0，arm64）

## 基本信息

- Bundle ID: `com.raycast.macos`
- Team ID: `SY64MV22J9`
- 观测版本: `CFBundleShortVersionString = 2.0.6.0`（`CFBundleVersion = 0`，不可用作比较）
- 自更新机制: 自研（无 `SUFeedURL`，非 Sparkle / 非 Electron Squirrel）

## 两条 train（本次审计的核心发现）

Raycast 现在同时开着两条发布线，**归属由机器决定，不是用户偏好**，所以这不是 channel 问题：

| train | 端点 | 产物 | 面向 |
|---|---|---|---|
| v1 | `releases.raycast.com/releases/latest?build=universal` | universal dmg（预签名 R2） | 不满足 v2 要求的所有 Mac |
| v2 | `x.raycast-releases.com/releases/latest?platform=macos&architecture=arm64` | arm64-only dmg（明文 R2 URL） | macOS Tahoe(26)+ 且 Apple Silicon |

v2 要求见官方 https://www.raycast.com/new：「macOS Tahoe and Apple Silicon required」，
FAQ 另称「Raycast v2 is built for macOS Tahoe. If you are still on Sequoia or earlier,
you need to upgrade macOS before installing v2.」
`/releases/latest` 返回的 `builds` 数组里 macOS 只有一条 `arm64`，与之吻合。

**两个端点都不做门控**（2026-08-27 实测）：把 UA 换成
`Raycast/1.104.25 (x-macOS-x86_64 24.0.0)`、Sequoia、或普通浏览器 UA，
`x.raycast-releases.com` 一律 200 返回 `2.0.6.0`。所以闸只能记在我们这边。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓ ×2（v1 + v2）|

当前生效源: **Vendor**。本机 `duo check raycast --all --json` →
`{"source":"Vendor","installedVersion":"2.0.6.0","latestVersion":"2.0.6.0","status":"up-to-date"}`
（`latestVersion` 是 2.0.6.0 而非 v1 的 1.104.25，即 `best(of:)` 选中了 v2 recipe）。

## Channel 详情

两条都是 `channel: .stable`，靠新增的 `VendorHostRequirement` 而非 `channel` 区分。

| recipe | recipeID | hostRequirement | 状态 |
|---|---|---|---|
| v1 | `vendor:com.raycast.macos:stable:v1` | 无 | ✓ |
| v2 | `vendor:com.raycast.macos:stable:v2` | `minimumSystemVersion: "26.0"`, `architectures: [.arm64]` | ✓ |

为什么用 hostRequirement 而不是 channel：channel 表达的是「用户选了哪条质量轨」，
这里用户没得选 —— 能不能用 v2 是硬件和系统版本决定的。放进 channel 会让不满足条件的机器
**完全查不到更新**（channel gate 会整个跳过），而不是回落到 v1。

`VendorProbeSource.probeDiagnostic(for:)` 在 channel gate 之后加了 host gate，
位置在多端点合并 **之前** —— `best(of:)` 的前置条件原文是「every endpoint listed for one
channel must serve a build this machine may legitimately install」，先滤掉跑不了的
recipe 正是在维护这条前置条件，而不是绕过它。

## 更新检测

- v2 响应形状：
  ```
  {"id":2275,"version":"2.0.6.0","title":…,"changelog":"<markdown>","commit_sha":…,
   "created_at":"2026-08-25T07:34:17.976Z","updated_at":…,
   "builds":[{"platform":"macos","architecture":"arm64","url":"…arm64.dmg"},
             {"platform":"windows",…".msix"}],
   "download_url":"https://x-r2.raycast-releases.com/Raycast_2.0.6.0_c3450ccdc9_arm64.dmg",
   "checksum":"f09c22aa30a45e17c346c2b1051cf4c3"}
  ```
- **版本方案已核对**：`version` = `2.0.6.0` = 已装 bundle 的 `CFBundleShortVersionString`，
  逐字相同 → 不需要 `versionIsBuild`。（`CFBundleVersion` 是 `0`，本来也不能比。）
- **`version=` 参数是陷阱**：这是一个「我该不该更新」端点，不是「最新是什么」端点。
  传入已是最新的版本 → **204 No Content**（抓包里最常看到的就是这个，容易误判成鉴权失败）；
  传 v1 的三段版本 `1.104.25` → **400 FST_ERR_VALIDATION**（只收四段）。
  所以 recipe **不带** `version`，裸 `/releases/latest?platform=macos&architecture=arm64`
  恒定 200 返回最新版。
- `architecture` 只影响 Windows：`x64` 同样 200 且 `download_url` 仍是 macOS 的 arm64 dmg，
  `x86_64` 则 404。
- 不需要鉴权，无 OAuth。**别把 TLS 握手失败读成鉴权**：经中间人代理探测该端点时会看到
  `SSLV3_ALERT_HANDSHAKE_FAILURE`，那是端点拒绝被拦截，与 auth 无关；直连即 200。

## Changelog

- 来源: `https://www.raycast.com/changelog` — ChangelogRecipe（HTML 正则），服务端渲染。
- **路径是反直觉的**：v2 上线后 `/changelog` 就是 **v2** 的 macOS changelog。
  v1 存档**搬过两次**：先在 `/changelog/macos`，后来那条路径也变成了 v2 页
  （2026-09-14 实测：`<title>` 是 "Raycast - macOS Changelog"，10 条 `2.3` … `0.66`，
  与 `/changelog` 相同），存档移到 `/changelog/macos-v1`（"Raycast - macOS V1 Changelog"，
  10 条 `1.104.0` … `1.95.0`，v1 `entryPattern` 全部解析）。
  v1 的 ChangelogRecipe `source` 和 v1 probe 的 `changelogURL` 都指 `/changelog/macos-v1`。
- **第二次搬家没有任何东西报出来**：`[1, 2)` recipe 在变成 v2 页的 `/changelog/macos` 上
  解析得干干净净，1.104.x 用户看到的是 2.x 的 notes；`duo verify` 的滞后检查只管
  「最新条目落后于检测版本」，2.3 领先于 1.104.x，于是 `verify/baseline.json` 里这条的 `lastGoodVersion`
  在 `6d60b3c7`（2026-08-28）从 `1.104.0` 变成 `2.1`，之后一路记到 `2.3`，一直是 ✓。
  现在 `duo verify` 对声明了版本窗口的 recipe 检查**每一条**解析出的条目都在窗口内，
  否则报 `entriesOutsideVersionWindow`。
- 版本标签是厂商自己的 **minor 训**（"2.0"、"0.71"），app 报的是四段 build（2.0.6.0）。
  这不是要修的错位：Raycast 一个 minor 出一份 notes、下面挂多个 build。
  JSON API 从另一侧印证了这点 —— `/releases` 列表里 2.0.6.0 / 2.0.5.0 / 2.0.4.0 / 2.0.3.0
  的 `changelog` 字段**字节相同**。
- **没有用旁边那个 JSON API**，尽管它直接给 markdown：
  - `/releases` 列表**无视自己的 `platform` 参数** —— `platform=macos` 与 `platform=windows`
    返回**逐字节相同**的 body（2026-08-27 三次复测稳定），且给的是某条 release 的
    **Windows 版**文案，而它的 macOS 双胞胎内容不同。
  - `/releases/latest?platform=macos` 平台是对的，但只有一条 release，没有历史。
- 两条 train 共用一个 bundle id 且同为 `.stable`，所以靠**版本窗口**分开：v1 存档 recipe
  声明 `[1, 2)`，v2 recipe 不声明窗口、接住其余（包括 0.63–0.71 的 v2 beta）。

## 一键安装

- 状态: 两条 train 都支持。
- 格式: dmg。
- v2 的 `download_url` 是**明文、不过期**的 R2 对象（v1 是 1 小时过期的预签名 URL，
  靠每次探测重新解析规避过期）。
- install pattern 钉死 `\.dmg` 结尾：同一个 host 上 `builds` 还挂着 Windows 的 `.msix`。
- `checksum` 是 **MD5 hex**，`VendorInstallSpec.checksumPattern` 只吃 base64 的 SHA-512，
  用不上，留空；签名闸仍由 Team `SY64MV22J9` 把守。
- 架构安全网：即使 host gate 失效，`SignatureVerifier` 第 5 道闸（`verifyRunnableArchitecture`）
  会读真实 Mach-O，在 Intel 机上拒绝 arm64-only 包。**但 OS 下限没有安装期闸**
  —— 这正是 host gate 必须存在于检测期的原因。

## 已知问题

- v2 的 `title` 在多个 build 之间重复（"🎉Raycast 2.0 is out of Beta!"），
  因为一份 notes 覆盖一整条 minor 训。
- `/releases` 列表端点的 platform 参数无效，见上。别拿它当 changelog 源。

## 建议下一步

1. 无。检测（两 train）、changelog、一键安装均已接入并对真实端点验证通过：
   `duo verify --only raycast` → vendor ✓2 / changelog ✓2 / ✗0 ⚠0（2026-09-14，
   v1 存档 recipe 读到 `1.104.0`、10 条；v2 读到 `2.3`、10 条）。
2. 观察点：v1 train 停更那天，`vendor:com.raycast.macos:stable:v1` 会开始报
   `remoteBehindInstalled` 之类的 advisory —— 那是把 v1 recipe 退役的信号，不是故障。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-raycast-macos.swift — 两条 train（开头的说明）

转引自 recipe 注释，未复测。整段原文；代码里留下「截至 2026-08-18 仍在发版」，版本号搬到这里。

  v1 (this recipe): `releases.raycast.com`, universal, still shipping
     (1.104.25 on 2026-08-18). This is the train for every Mac that
     cannot run v2.
  v2 (below): `x.raycast-releases.com`, arm64-only, macOS 26+.

### Recipes/com-raycast-macos.swift — stable VendorProbe v1（`variant: "v1"`）

转引自 recipe 注释，未复测。整段原文；除 baseline 改名那句外都原样留在代码里。原句没写日期，引入它的提交是 `6e1088ee`（2026-08-27）。

Raycast v1 — official "latest release" endpoint; `version` is first.
Carries an explicit `variant` for the same reason v2 does: a duplicated
(bundleID, channel) group must declare every member deliberately. Its
verify baseline entry was renamed with it (`…:stable` → `…:stable:v1`)
rather than left to start over.
One-click: the same JSON's `downloadURL` is the dmg (a
worker.raycast-releases.com proxy URL wrapping a presigned R2 object;
resolved fresh from each probe so its signed expiry is never stale).

### Recipes/com-raycast-macos.swift — stable VendorProbe v2（`x.raycast-releases.com`）

转引自 recipe 注释，未复测。整段原文（开头是原注释里的响应形状摘录）。代码里去掉了括号里说明在哪台机器上核对的那个从句（类别：核对所在的机器），版本号标成了示例。唯一的改写：同一个从句，一处本机状态措辞（核对所在的机器），按本目录的机器状态规则改成了针对那台被核对的机器的说法。原句没写日期，引入它的提交是 `6e1088ee`（2026-08-27）。

```
Shape: {"id":…,"version":"2.0.6.0","title":…,"changelog":…,
  "commit_sha":…,"created_at":"2026-08-25T07:34:17.976Z","updated_at":…,
  "builds":[{…,"url":…}],"download_url":"https://x-r2.…arm64.dmg",
  "checksum":"<md5>"}
```

`version` is the marketing string the installed bundle reports verbatim
(2.0.6.0 == CFBundleShortVersionString, verified on the machine checked that day), so no
`versionIsBuild`. The install URL is the top-level `download_url` — a
plain, unsigned R2 object, unlike v1's presigned link — and the `.dmg`
suffix in the pattern keeps it off the Windows `.msix` builds listed in
`builds`. `checksum` is an MD5 hex digest, which `checksumPattern`
(SHA-512, base64) cannot consume, so it is left unused; Team SY64MV22J9
gates the swap.

### Recipes/com-raycast-macos.swift — ChangelogRecipe v2（`/changelog`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（同一个 minor 下的几个 build 在 JSON API 里拿到逐字节相同的说明），build 列表搬到这里。原句没写日期，引入它的提交是 `6e1088ee`（2026-08-27）。

Versions here are the vendor's own MINOR labels — "2.0", "0.71" — while
the app reports a four-segment build (2.0.6.0). That is not a mismatch to
fix: Raycast publishes one set of notes per minor train and ships several
builds under it (the JSON API confirms this from the other side — its
/releases list hands 2.0.6.0, 2.0.5.0, 2.0.4.0 and 2.0.3.0 byte-identical
changelog text). The 0.6x–0.71 entries are the v2 BETA train, which is
what preceded the 2.0 GA number.

### Recipes/com-raycast-macos.swift — ChangelogRecipe v1 存档（原注释写的地址是 `/changelog/macos`）

转引自 recipe 注释，未复测。两段都是 `6c4d6189` 时的整段原文。第一段：本 PR 原本只搬走末句的核对记录，#622（`d58d0e00`）之后代码里这一段是 #622 改写的版本（新地址、2026-09-14 的核对），这里保留的仍是原文；第二段代码里留下的是结论（存档最新条目比 v1 端点旧不代表页面过期，Raycast 每个 minor 一份说明），两边的版本号搬到这里。第二段原句没写日期，引入它的提交是 `6e1088ee`（2026-08-27）。

Raycast v1 archive — /changelog/macos, the page titled "Raycast - macOS
V1 Changelog". Byte-for-byte the same component as the v2 page above, so
the patterns are the same three strings; only `source` and the version
window differ. Verified against the live page 2026-08-27: 10 entries,
1.104.0 back to 1.95.0, all parsing.

Its newest entry is 1.104.0 (December 16, 2025) while the v1 endpoint is
serving 1.104.25 — not a stale page. Raycast publishes one set of notes
per MINOR and ships patches under it, and v1 has been on patches alone
since v2 development took over; 1.104.x installs belong under the 1.104.0
entry. (The same grouping is visible on the v2 side, where 2.0.6.0
through 2.0.3.0 share one note.)

复测 2026-09-14（约 07:58 UTC，只读 GET）：`releases.raycast.com/releases/latest?build=universal` 回 `1.104.29`（2026-09-10）。`www.raycast.com/changelog/macos` 的 `<title>` 已是 "Raycast - macOS Changelog"，内容与 `/changelog` 相同——10 个 `<span id>`，依次是 `2.3`、`2.2`、`2.1`、`2.0`、`0.71` … `0.66`，没有一个 1.x 条目。也就是说复测时这张页已经不是 v1 存档。约 09:09 UTC 另读 `www.raycast.com/changelog/macos-v1`：200，130,061 B，`<title>` 是 "Raycast - macOS V1 Changelog"，10 个 `<span id>` 从 `1.104.0` 到 `1.95.0`——v1 存档搬到了这个地址。

更正 2026-09-14：#622（squash 提交 `d58d0e00`）把 v1 ChangelogRecipe 的 `source` 和 v1 probe 的 `changelogURL` 改指 `/changelog/macos-v1`，并改写了代码里描述这几个地址的注释；本文件上面「Changelog」一节是 #622 写的现状。

### Recipes/com-raycast-macos.swift — ChangelogRecipe v1 存档（`/changelog/macos-v1`，收尾批次）

转引自 recipe 注释，未复测。整段原文，是 #622（`d58d0e00`）改写之后的版本（改写之前的原文见上一组）；#625（`c57c9fc6`）在段末加了临时的 `snapshot-lint:allow` 标记，不是正文，没有抄进来，代码里已删掉。代码里留下的是结论（与 v2 页同一个组件，同样的三条 pattern 能解析这一页的全部条目），日期写成 "(checked 2026-09-14; …)"，条数和版本范围搬到这里。

Raycast v1 archive — /changelog/macos-v1, the page titled "Raycast - macOS
V1 Changelog". Byte-for-byte the same component as the v2 page above, so
the patterns are the same three strings; only `source` and the version
window differ. Verified against the live page 2026-09-14: 10 entries,
1.104.0 back to 1.95.0, all parsing.

复测 2026-09-15（UTC 2026-09-14 16:14，只读 GET `www.raycast.com/changelog/macos-v1`）：200、129,641 B、`<title>` "Raycast - macOS V1 Changelog"；10 个 `<span id>`，从 `1.104.0`（December 16, 2025）到 `1.95.0`（April 9, 2025），`entryPattern` 匹配 10 条。
