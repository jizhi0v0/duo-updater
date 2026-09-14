# Qoder IDE

> ⚠️ 先读这段：**「Qoder」是两个 app，不是一个改了名的 app。** 见
> `com-qoder-app.md`。官方论坛（forum.qoder.com/t/qdoer-qoder-qoder-ide/12088，
> 2026-09-06 读）原话："Qoder IDE 用来代码，Qoder 是国际版 QoderWork 的迭代"。
> 两者 bundle id、版本线、发布说明页、下载主机、**Team ID** 全部分开。

## 基本信息
- Bundle ID: `com.qoder.ide`
- Team ID: `T27K5A5ZWD`（Developer ID Application: Alibaba.com Singapore
  E-Commerce Private Limited）
- 观测版本: `1.28.0`（short == build；被换掉的旧版是 `1.27.0`）
- 架构: arm64-only（`lipo -archs` → `arm64`）
- `LSMinimumSystemVersion`: 12.0
- 底座: **VS Code fork**。`Contents/Resources/app/product.json` 里
  `version = 1.106.3`（上游 VS Code 版本，**不是**产品版本）、`quality = stable`、
  `commit = <40 hex>`、`updateUrl = https://center.qoder.sh/algo`
- 自更新机制: VS Code 自带的更新器，走上面那个 `updateUrl`
- 分发: 官网 `qoder.com/download` → `download.qoder.com/release/latest/`
- Homebrew: **无 cask**（`formulae.brew.sh/api/cask/qoder.json` → 404，2026-09-06）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (无 cask) | — | — | ✓ |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.qoder.ide` | 单一渠道 | — | — | ✓ |

单渠道：这台 update server 只答 `stable`——`/api/update/darwin-arm64/insider/latest`
返回 404（实测 2026-09-06）。

## 更新检测
- 源: `https://center.qoder.sh/algo/api/update/darwin-arm64/stable/latest`
  —— VS Code 更新协议原样：`/api/update/<platform>/<quality>/<commit>`。
- 响应（344 字节）:
  ```json
  {"url":"https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-arm64.zip",
   "name":"1.28.0","version":"68cf4c38…","productVersion":"1.28.0",
   "hash":"d712c37e…","timestamp":1788277155505,"sha256hash":"52c46d6d…"}
  ```
- 取 `productVersion`。**不能取 `version`**——那是 commit，40 位 hex，拿去和 `1.27.0`
  比会永远比不出结果。`name` 审计当天（2026-09-06）也是 `1.28.0`（2026-09-14 复测两者都是
  `1.29.0`），但协议里 `name` 是允许厂商塞人话串的那个字段。
- ⚠️ **这是条件端点**（2026-09-06 实测）:
  | 末段 commit | 响应 |
  |---|---|
  | `a48791e9…`（1.27.0，即本机装的那版）| 200 + 1.28.0 的 JSON |
  | `68cf4c38…`（1.28.0，当前最新）| **204，空 body** |
  | 全 0（不可能存在的 commit）| 200 + 1.28.0 的 JSON |
  | `latest`（VS Code 自己的哨兵）| 200 + 1.28.0 的 JSON |

  所以 URL 末段写死 `latest`：把本机 commit 送上去会让**同一个响应形状有两个含义**——
  在有安装的 Mac 上是"你已经最新"，在没有安装的 sweep 里是"端点坏了"。这正是
  `VendorProbeRecipe` 里 Mozilla AUS 几条 recipe 长篇记录的那个坑。用哨兵后，所有用户
  和 sweep 发的是**同一个请求**，永远期待有答案，空 = 明确的失败。
- 发布时间: `timestamp` 是 epoch **毫秒**（1788277155505），`ReleaseDate` 的毫秒窗口
  认这个数量级，所以行上能拿到精确发布时刻而不是公元 58700 年。
- 版本方案: `productVersion` == bundle 的 short == build，同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | VS Code 有自己的 delta 机制 | 该端点只给整包 zip | 不能 |
| 证据 | — | 响应里只有一个 `url` + `sha256hash`，无 patch 条目（2026-09-06） | — |

## Changelog
- 来源: **`https://docs.qoder.com/release-notes/desktop`**（页面标题
  "IDE Release Notes"），服务端渲染的普通 HTML。
- **刻意不用 `qoder.com/changelog?type=ide`**：那是 Next.js 页，条目只存在于 RSC
  payload 里，**所有产品的条目挤在一个文档**、**中英两份**，而且 `type` 判别字段排在
  版本号**后面**——解析它等于赌哪一份 "1.28.0" 排在前。docs 站把同一批 release 渲染成
  一产品一页的静态 HTML。
- 页面结构: 每条 release 是 `data-component-part="update-label"`（日期）+
  `…="update-description"`（版本）+ `…="update-content"`（`<h3>`/`<h4>` 小节和它们下面
  的 `<ul>`）。只有 `<li>` 变成条目，标题被丢掉。
- 实测（2026-09-06，对真实页面跑正则）: 正则在页面上能匹到 **108 条**（`1.28.0` 一直到
  **`0.1.15`**，不是 `1.0.0` —— 尾巴是 `0.2.1 / 0.1.21 / 0.1.20 / 0.1.17 / 0.1.15`），
  `1.28.0` → 2 items、`1.27.0` → 2 items，版本和日期与更新端点完全对得上。
  ⚠️ **面板里能看到的是 40 条**：`maxEntries` 默认 40，两条 recipe 都没覆盖它。108 是
  「正则在这页上够得到多少」，不是「读者能翻多少历史」。
- ⚠️ **锚定 `data-component-part` 到底买到了什么，是量出来的，不是想当然的**：同一页底部
  确实还带一份 RSC payload，但**那份里一个 `</div>` 都没有**，靠元素结构就已经排除了
  （把它接在真实条目后面，条数和版本都不变）。页面自己的 `<div class="eyebrow">Release Notes</div>`
  也不是靠锚定挡在**最新那条的日期**之外的：recipe 最初那一版里是，但条目间隔加了
  tempering 之后，tempering 的哨兵就是 label 属性本身——去掉三个属性前缀、保留 tempering，
  结果不变；只有 tempering 也去掉时页头才会被读成日期（`d8c3a6dc`，2026-09-06 实测）。
  测试 `theNewestEntrysDateIsItsOwnLabelNotThePageHeader` 钉的是这个结果，fixture 为此特意
  带上了页头；锚定本身由两条 `aDamagedEntryCannotBorrow…` 用例钉住。（2026-09-14 更正：
  这里原先写的是「锚定防住页头」，引用的测试名也已改掉。）

## 一键安装
- 状态: **支持**
- 格式: zip —— `Qoder-darwin-arm64.zip`（270,350,184 bytes）
- **读的是**: 更新端点自己给出的 `url`，不是下载页给人的
  `Qoder-IDE-darwin-arm64.dmg`。同一个 release，zip 不用挂载。
- 校验和: 响应带 `sha256hash`，但 `VendorInstallSpec.checksumPattern` 要的是
  **base64 的 SHA-512**，格式对不上，**没接**。签名闸照常生效。
- 包验（2026-09-06，真实下载解包）: `Qoder IDE.app` / `com.qoder.ide` /
  short == build == `1.28.0` == 端点的 `productVersion` / arm64 /
  `Developer ID Application: Alibaba.com Singapore E-Commerce Private Limited
  (T27K5A5ZWD)` / `spctl` = `Notarized Developer ID`——与本机装的 1.27.0 同 Team，
  swap 过闸。
- x64 是同场兄弟（`/api/update/darwin/stable/latest` 给出字节几乎相同的 JSON，只差
  `darwin-x64`），install pattern 锚死 `darwin-arm64` 把它挡掉；测试里就用那份 x64
  响应当反例。

## 已知问题
- `updateUrl` 指向 `center.qoder.sh`，与下载主机 `download.qoder.com` /
  `qoder-ide.oss-accelerate.aliyuncs.com` 是三个不同的域，任何一个换掉都会让 recipe
  失效（表现为 unknown，不会误报）。
- 端点无 `beta`/`insider` 轨，将来厂商开了轨这条 recipe 不会自动跟上。

## 如何复验
```
# GET https://center.qoder.sh/algo/api/update/darwin-arm64/stable/latest
#   → {"productVersion":"1.28.0", "url":"…/release/1.28.0/Qoder-darwin-arm64.zip", …}
# 同一路径末段换成当前 commit → 204 空 body（哨兵存在的理由）
# 解包那个 zip → Qoder IDE.app / com.qoder.ide / T27K5A5ZWD / notarized
duo verify --only qoder.ide
```

## 建议下一步
- 无。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-qoder-ide.swift — stable VendorProbe（条件端点）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（旧版本的 commit 得到最新版的 JSON，当前版本的 commit 得到 204 空 body，保留了实测日期），两个 commit 和版本号搬到这里。唯一的改写：原文说被测的那个 commit 属于"装着的" 1.27.0，按本目录的机器状态规则改成了针对那台被量的机器的说法。

⚠️ CONDITIONAL ENDPOINT — the reason the last path segment is `latest`
and not a commit. Measured 2026-09-06: the commit of the 1.27.0 installed on the machine measured that day
(`a48791e9…`) is answered with the 1.28.0 JSON, and the CURRENT 1.28.0
commit (`68cf4c38…`) is answered **204, empty body**. Sending this
machine's own commit would make one response shape mean two things —
"you are current" on a Mac that has it, "the endpoint is broken" in a
sweep that has no install — which is exactly how a check goes quietly
dead (the trap the Mozilla AUS recipes (`Recipes/org-mozilla-firefox.swift`) document at length).
`latest` is the token this repo's own VS Code recipes already use in
that slot, and Qoder answers it with the newest build: every user and
every sweep then sends the identical request, an answer is always
expected, and empty is unambiguously a failure.

### Recipes/com-qoder-ide.swift — stable VendorProbe（`productVersion` 与 `name`）

转引自 recipe 注释，未复测。"though both read "1.28.0" today" 里的版本号迁移时已过期（见下面的复测），代码里改成了带复测日期的说法；本文件「更新检测」一节里同一句也改了。

`productVersion`, not `name`, though both read "1.28.0" today: `name`
is the field the protocol lets a vendor put a human string in, and
`productVersion` is the one defined to be the version. `version` is the
COMMIT — matching it would compare a 40-hex string against `1.27.0`
forever.

复测 2026-09-14（约 07:28 UTC，只读 GET `center.qoder.sh/algo/api/update/darwin-arm64/stable/latest`）：`name` 与 `productVersion` 都是 `1.29.0`，`url` 指向 `…/release/1.29.0/Qoder-darwin-arm64.zip`。

### Recipes/com-qoder-ide.swift — stable VendorProbe（一键 zip 与单渠道）

转引自 recipe 注释，未复测。两段整段原文；代码里留下的是结论（解包后 short == build == 端点的 `productVersion`，与装着的那份同 Team），签名细节搬到这里。第二段只把 "measured same day" 改成了具体日期——它原本指的是前一段里被搬走的那个日期。

The install spec takes the zip the API itself names, not the
`Qoder-IDE-darwin-arm64.dmg` the download page hands a human. Same
release, and the zip needs no mount. Verified 2026-09-06 by unpacking
it: `Qoder IDE.app`, `com.qoder.ide`, CFBundleShortVersionString ==
CFBundleVersion == 1.28.0 == the API's `productVersion`, arm64-only,
signed "Developer ID Application: Alibaba.com Singapore E-Commerce
Private Limited (T27K5A5ZWD)" and accepted by `spctl` as Notarized
Developer ID — the same Team as the installed 1.27.0 copy, so the swap
passes the VendorInstaller gate.

Single channel: `stable` is the only quality this server answers —
`/api/update/darwin-arm64/insider/latest` 404s (measured same day).

### Recipes/com-qoder-ide.swift — ChangelogRecipe（docs 站，`data-component-part` 锚定）

转引自 recipe 注释，未复测。两段整段原文，代码里留下的是结论。第一段的计数原句没写日期，引入它的提交是 `d8c3a6dc`（2026-09-06）。

Nor, any longer, is it what keeps the page's own
`<div class="eyebrow">Release Notes</div>` header out of the newest
entry's date. That WAS true of the first version of this recipe, and
stopped being true when the gaps below were tempered — the sentinel they
temper on is the label attribute, so it does that job now. Measured on
both live pages: stripping the three attribute prefixes while keeping
the tempered gaps changes nothing at all (108 and 7 entries, same
versions, same dates); the header is only captured when the tempering
goes too.

Measured on the real pages 2026-09-06: the pattern MATCHES 108 blocks on
the IDE page (1.28.0 back to 0.1.15) and 7 on the app's (0.1.8 back to
0.1.0), versions and dates agreeing with the products' own version
endpoints exactly. Two numbers below that, and neither is 108:
`ChangelogExtractor` yields 107, because 1.19.1's notes are prose with no
`<li>` and an entry with no items is dropped; and the pane shows the
`maxEntries` default of 40, which neither recipe overrides. 108 is the
pattern's reach over the page, not history a reader gets.

复测 2026-09-14（约 07:28 UTC，只读 GET 两页，只数了块，没有跑 `ChangelogExtractor`）：IDE 页 109 个 `update-label` 块，Qoder 页 11 个；按 `update-content` 到 `</div></div></div>` 切出的正文里，两页带属性的 `<li …>` 都是 0 个——代码里 "no entry on either page carries an attribute there today" 因此原样保留。
