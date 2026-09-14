# Cline Desktop

审计 2026-09-12。两个 channel 是**两个独立 bundle id 的 app**,文档合并在这一份里。

## 基本信息

- Bundle ID: `bot.cline.app`(stable) / `bot.cline.app.beta`(beta)
- Team ID: `6F2AYU54ZH`(Cline Bot, Inc.),两轨都 `spctl` accepted = Notarized Developer ID
- 观测版本: stable `0.0.26`,beta `0.0.23-beta.1`
- 自更新机制: **Tauri**(`tauri-plugin-updater 2.10.1`),不是 Electron 也不是 Sparkle
- 架构: universal(x86_64 + arm64);`LSMinimumSystemVersion` 10.13(Tauri 默认值,两轨相同)

两轨的 `CFBundleShortVersionString` 与 `CFBundleVersion` **逐份相同**(stable 都是
`0.0.26`,beta 都是 `0.0.23-beta.1`),所以 recipe 不需要 `versionIsBuild`。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | ○      | ✓ 一键      |
| **beta**     | —       | —        | —   | ○      | ✓ 一键      |

当前生效源(`UpdateChecker` 优先链中第一个应答的): **VendorProbe**

- **Sparkle —**:两轨 bundle 都不声明 `SUFeedURL`。`feed-discover` 对真实 0.0.26
  bundle 判 `noKnownUpdater`(没有 `SUFeedURL`,也没有 electron-builder 的
  `app-update.yml`)。
- **Homebrew —**:没有 cask。`brew search --cask cline` 只返回 clion /
  font-karla-tamil-inclined / sonic-lineup。
- **MAS —**:非商店分发。
- **GitHub ○**:构件确实发在 `cline/cline` 的 Releases 上,技术上可以写
  `GitHubReleaseRule`,但没有采用——理由见下面「为什么不走 GitHub 源」。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `bot.cline.app` | 独立 | — | 独立端点 | ✓ |
| beta | `bot.cline.app.beta` | **独立** | bundle id `.beta` 后缀 + 版本 `-beta.1` | 独立端点 | ✓ |

Pattern **A**(各 channel 自带 bundle id),所以不需要 `ChannelBinding`,也不存在
「同 id 不可分辨」的风险。`ReleaseChannel.detect()` 有**两条互相独立**的信号都能命中:
bundle id 的 `.beta` 后缀(step 2)和 full-semver 的 `-beta.1`(step 4)。

两轨是磁盘上两个不同的 app,所以 **beta 永远不会被「毕业」到 stable** —— 这跟
CotEditor 那种共享 id、周期性 beta 轨「拿到毕业版才是正确行为」的情况相反。beta 的
`versionPattern` 因此**强制要求** `-beta.<N>`,而不是顺带接受裸 tag。

## 更新检测

- 源: `VendorProbeRecipe` × 2
- 端点:
  - stable `https://github.com/cline/cline/releases/download/desktop-latest/latest.json`
  - beta   `https://github.com/cline/cline/releases/download/desktop-beta/latest.json`

**这两个地址不是猜的,是各自二进制里写着的。** 真正的可执行文件是
`Contents/MacOS/cline-app`(bundle 里另有一个 181 MB 的 `code-sidecar`;没有名为
`Cline` 的可执行文件)。对两个真实 bundle 各跑一次 `strings`,各自只吐出一个
`releases/download/…` 地址,且正是本轨的那一个。所以 probe 读到的就是 Cline 自己的
updater 会装的那一份。

Tauri 的 manifest 是静态 JSON:没有 device id、没有灰度分桶,所以「轨道上的最新」和
「分配给这台机器的」是同一个对象;而且 cline.bot/desktop 的下载按钮直接指向同一个
GitHub release(2026-09-12 实测指向 `…/desktop-v0.0.26/Cline_0.0.26_universal.dmg`),
属于「人人可手动下载的 GA」。

### 为什么不走 GitHub 源

`cline/cline` 是**单仓多产品**。2026-09-12 实测最新 100 个 release:33 个
`desktop-*`、24 个 `v*`(VS Code 扩展)、22 个 `sdk/sdk/v*`、21 个 `cli-v*`,而且后三
条轨**全部是非 prerelease**。后果:

1. `/releases/latest` 返回的是「最近发布的那个产品」。它今天返回 `desktop-v0.0.26`
   纯属时间巧合——desktop 发于 2026-09-11,另外三轨最近一次是 2026-09-02。
2. 改读列表端点可以绕开这点,但 `per_page=40` 实测 **52,732** gzip 字节,而且按
   `GitHubConditionalCache` 记录的实测:列表端点**不发 `Last-Modified`**,只剩一个随
   `assets[].download_count` 变动的 `ETag`。
3. beta 轨是**周期性**的(末次 `desktop-v0.0.23-beta.1`,2026-09-03),历史上
   `-beta.N` tag 之间最坏间隔 **23 行**。锚死 `-beta` 的 pattern 在轨道停更后会匹配不
   到任何东西,而 `duo verify` 走的是 recipe 不是安装,那会变成一条红。滚动 tag
   `desktop-beta` 不会空。

两个 manifest 分别是 **7,847** 和 **2,525** 字节,而且**都带 `Last-Modified`**(同日实测)。

**代价,写清楚**:`ReleaseHistoryEntry`(Release Log 里的版本+日期序列)只有
`SparkleAppcastSource` 和 `GitHubReleasesSource` 会回填,VendorProbe 不会。这两行因此
没有一次性的历史回填,只有 `publishedAtPattern` 每轮给当前版本打的时间戳。

### 注意事项

- `"version"` 的 pattern **必须带闭合引号**。stable 的值是裸 semver,少了那个 `"`
  就会把 `0.0.23-beta.1` 匹配成前缀 `0.0.23` —— 一个从未发布到该轨的版本号。
  已在真实 beta body 上验证:stable pattern 在那里匹配不到东西,反向亦然。
- `platforms` 里有三个条目,`windows-x86_64` 的 `url` 是 `.exe`。两条 install pattern
  都锚 `_universal.app.tar.gz`;两个 darwin key 指向**同一个** universal tarball,所以
  在「匹配到的条目」之间取首个是对的,而不是在赌顺序。
- 构件命名换过:`Cline-Code_*`(≤0.0.14)→ `Cline_*`(≥0.0.15);架构从
  `aarch64`/`x86_64` 分开(≤0.0.8)并成 `universal`(≥0.0.9)。所以**不要**从版本号拼
  dmg 的 URL——厂商已经让这种拼法失效过一次。

## 增量更新(delta / binary patch)

> 三栏分开写,每栏标证据来源。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | **无** | **无** | 不适用 |
| 证据 | `strings Contents/MacOS/cline-app`:`bspatch`/`hdiff`/`binarydelta`/`zsync` 命中数 **0**;updater 是 `tauri-plugin-updater 2.10.1`,整包替换 | 真实 manifest 全文扫描:含 `diff`/`delta`/`patch` 的键 **none**,`.delta`/`.patch`/`.diff` 结尾的 URL **none** | 没有可消费的对象 |

- 格式: 不适用(Tauri updater 下整个 `.app.tar.gz` 覆盖)
- 阻塞项: 无——这是厂商没做,不是我们接不了

## 按 OS / 按架构分轨

manifest 里**没有**任何 `minimum_version` / OS 相关键(全文扫描,2026-09-12)。
`platforms` 只按 `darwin-aarch64` / `darwin-x86_64` / `windows-x86_64` 分,而两个 darwin
键指向同一个 universal 包。两轨 `LSMinimumSystemVersion` 都是 10.13。没有 per-release
的 OS 上下界要读,所以 recipe 不带 `hostRequirement`。

## Changelog

- 来源: `ChangelogRecipe` × 2,`structuredFormat: .gitHubReleases`,读
  `https://api.github.com/repos/cline/cline/releases?per_page=40`
- 跟随 channel: 是(stable / beta 各一条)
- Recipe 状态: 已有

release body 就是变更说明,是裸 `- ` bullet 列表、没有 `##` 小标题,走
`GitHubMarkdownParser` 的 bullet 一趟即可。

**这条 recipe 需要 `tagPattern`,而且两半都承重。** 单仓多产品意味着同一个列表里混着
四个产品:实测真实 `per_page=40` 页(2026-09-12),stable 轨留下 13 条,而如果没有这个
pattern,还会**多渲染 20 条别的产品的 release**(`v4.1.17`、`cli-v3.0.61`、
`sdk/sdk/v0.0.82` …)——比真条目还多,且每条都不畸形,看不出错。第二半是捕获组:
`stripLeadingV` 只去掉开头的 `v`,所以没有捕获组时每条都会标成 `desktop-v0.0.26`,永远
对不上行上显示的版本。

滚动 feed tag(`desktop-latest` / `desktop-beta`)本身也是这个列表里的 release,
`desktop-beta` 还是 `prerelease: true` 且带正文——只靠 `prerelease` 过滤会把它留下,
变成一条版本号永不变化的常驻条目。`$` 锚把两个都挡掉了。

`includesPromotedStable` 在 beta recipe 上**不设**(取 Yaak 的立场而非 CotEditor 的),
理由比两者都硬:两轨是不同 bundle id,stable release 根本不是这一行能被安装的东西。

## 一键安装

- 状态: **支持**,两轨都支持
- 格式: `.tarGz`(`.app.tar.gz`)
- **读的是**: **人人可手动下载的 GA**。端点即 Cline 自己 updater 读的那一个(由各自
  二进制的 `strings` 证明),Tauri manifest 静态无灰度,且 cline.bot/desktop 的下载按钮
  指向同一个 release。
- 装的是 manifest 自己点名的 `.app.tar.gz`,不是 dmg:manifest 只给 tarball,而从版本号
  拼 dmg URL 是一个厂商已经推翻过一次的假设(见上面的改名史)。
- 验证(2026-09-12,两个 tarball 都真下真解):各自根部**只有一个** `.app`,
  `spctl` accepted = Notarized Developer ID,Team `6F2AYU54ZH`,universal。
- `.pkg` 不需要:app 不在自己 bundle 之外装任何东西(没有 daemon / launch item /
  system extension)。
- beta 的 channel proof 已在 `ChannelProofRegistry` 登记:`.artifact` 形式,锚
  `Cline-Beta_…-beta.N_universal.app.tar.gz` —— 产品名和 tag 的 prerelease 计数各锚一次。

## 如何复验

```sh
# 两轨真实 bundle 的身份(dmg 只读挂载,不必安装)
swift run --package-path application-test channel-verify "<Cline.app>"       --expect stable
swift run --package-path application-test channel-verify "<Cline Beta.app>"  --expect beta

# 端点
duo verify --only cline
```

2026-09-12 的观测结果:

| | stable | beta |
|---|---|---|
| bundle id | `bot.cline.app` | `bot.cline.app.beta` |
| `CFBundleShortVersionString` | `0.0.26` | `0.0.23-beta.1` |
| `CFBundleVersion` | `0.0.26` | `0.0.23-beta.1` |
| `detect()` | `stable` | `beta` |
| 二进制里的 updater 端点 | `…/desktop-latest/latest.json` | `…/desktop-beta/latest.json` |
| 签名 | Team `6F2AYU54ZH`,notarized | Team `6F2AYU54ZH`,notarized |

接入前的基线(同日):两轨 `channel-verify` 都是 `winning source <none>` /
`status unknown (no source answered)` —— 即这两条 recipe 之前两行都是 `.unknown`。

## 已知问题

- Release Log 对这两行没有历史回填(见「为什么不走 GitHub 源」的代价一节)。
- beta 轨周期性停更。这对当前实现**无害**(滚动 tag `desktop-beta` 恒在,读到的就是
  最后一个 beta),但如果哪天改走 GitHub 列表,就会踩到 CotEditor 注释里记的那个引信。

## 建议下一步

1. 无待办。两轨检测 + 一键 + changelog 均已接入并验证。
2. 若将来要 Release Log 的历史回填,再评估换 `GitHubReleaseRule`——代价写在上面,
   `listPageSize` 至少要按 beta 的实测最坏间隔 23 行来定。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/bot-cline-app.swift — stable + beta VendorProbe（Tauri `latest.json`）

转引自 recipe 注释，未复测。

So a probe here resolves the same build Cline's own updater would
install, for everyone on that track. Tauri's manifest is static — no
device id, no rollout bucket — so "newest on the track" and "the build
allocated to this machine" are the same object, and the vendor's own
download button (cline.bot/desktop, measured 2026-09-12, links
`…/desktop-v0.0.26/Cline_0.0.26_universal.dmg`) hands over that same
release by hand.

`/releases/latest` therefore
answers with whichever product shipped last; it returns
`desktop-v0.0.26` today only because desktop shipped 2026-09-11 and the
other three last shipped 2026-09-02.

These two manifests are 7,847
and 2,525 bytes and DO serve `Last-Modified` (measured the same day).

Mounted both real disk images
(2026-09-12): stable is `bot.cline.app` / `0.0.26`, beta is
`bot.cline.app.beta` / `0.0.23-beta.1`, both short and build version
fields identical per copy (hence no `versionIsBuild`), both
`LSMinimumSystemVersion` 10.13, both universal (x86_64 + arm64), both
`spctl` accepted as Notarized Developer ID under Team 6F2AYU54ZH.

Both tarballs were downloaded and unpacked
2026-09-12: each holds exactly one `.app` at the archive root, notarized,
Team 6F2AYU54ZH.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`repos/cline/cline/releases/latest` 答 `desktop-v0.0.27`。

### Recipes/bot-cline-app.swift — beta VendorProbe（`downloadURL`）

转引自 recipe 注释，未复测。

NOT cline.bot/desktop, which the stable recipe uses: that page
publishes only the stable dmg and the Windows exe (measured
2026-09-12 — a scan for any beta artifact URL returns nothing),
while it mentions the word "beta" in prose.

### Recipes/bot-cline-app.swift — stable + beta ChangelogRecipe（GitHub releases，`tagPattern`）

转引自 recipe 注释，未复测。

Both rails fit inside it today: 13 stable and 6 beta.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`per_page=40` 那一页里 `^desktop-v…$` 14 条、`^desktop-v…-beta.N$` 6 条。

### Recipes/bot-cline-app.swift — beta channel proof（`Cline-Beta_`）

转引自 recipe 注释，未复测。

Verified against the live manifest 2026-09-12 —
the resolved URL was
`…/desktop-v0.0.23-beta.1/Cline-Beta_0.0.23-beta.1_universal.app.tar.gz`,
and the stable manifest's URL matches neither half.

### Recipes/bot-cline-app.swift — stable + beta VendorProbe（Tauri `latest.json`，未写日期的数字）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`cc44a957`（2026-09-12）。

Cline — Tauri (`tauri-plugin-updater 2.10.1`), not Electron and not
Sparkle, so nothing generic reaches it: `feed-discover` on the real
0.0.26 bundle prints `noKnownUpdater` (no `SUFeedURL`, no
`app-update.yml`), and there is no Homebrew cask at all
(`brew search --cask cline` → clion / font-karla-tamil-inclined /
sonic-lineup).

`strings`
on `Contents/MacOS/cline-app` (the real binary; `Contents/MacOS/Cline`
does not exist — the bundle ships `cline-app` plus a 181 MB
`code-sidecar`) yields exactly one `releases/download/…` address per
build:

The list endpoint avoids that but
costs 52,732 gzipped bytes at `per_page=40` and, per
`GitHubConditionalCache`, carries NO `Last-Modified` and an `ETag` that
rotates with `assets[].download_count`.
