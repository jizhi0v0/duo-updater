# 三族更新清单：什么能自动覆盖，什么结构上不可能

2026-08-31 的一轮调查记录。写下来是因为结论反直觉，而且**每一条都是打真实端点、读真实 bundle 量出来的**，重做一遍很贵。

⚠️ 这份文档刻意不记录任何机器清单——不写扫了多少个包、装了哪些 app、哪个 app 在哪条渠道上。
那是 `/docs/*` 被 `.gitignore` 挡住的原因（见该文件注释）。这里只留**厂商侧的事实**和**结论**，
比例一律写成"多数 / 少数"。要复现数字，跑 `feed-discover --scan`。

---

## 一、三族对照

| | 地址在哪 | 多 channel 怎么表达 | 用户在哪条轨 | 能否零 per-app 覆盖 |
|---|---|---|---|---|
| **Sparkle** | `Info.plist` 的 `SUFeedURL`（**可被代码覆盖**） | feed 内 `<sparkle:channel>` 标签，或每轨一个 feed | **不在包里**——靠拿装机 build 去 feed 里对认推断 | ✅ `SparkleAppcastSource` |
| **electron-updater** | 包内 `Contents/Resources/app-update.yml`（构建时自动生成） | `channel:` 字段 → `<channel>-mac.yml` 文件名 | **写在包里** | ✅ `ElectronManifestSource` |
| **Squirrel.Mac** | 无清单文件，运行时 `setFeedURL` 算出来 | 完全由 app 自己决定 | 在算地址那个函数里 | ❌ 结构上不可能 |

Squirrel 那一行不是推断：[官方文档](https://github.com/Squirrel/Squirrel.Mac)明确说服务端返回 JSON（只有 `url` 必填）、无更新时**必须回 204 No Content**、**包里没有任何清单文件**。实测 Claude.app 印证：asar 里是
`o.autoUpdater.setFeedURL({url: tW(), serverType:'json'})`，`getUpdateChannel` 返回
`'nest' | 'production'`——**channel 是算地址那个函数的输入**。包里能捞到最完整的字面量是
`https://downloads.claude.ai/releases/darwin/universal/`，一个基路径。

⚠️ 那个 204 会骗过发现器：拿装机版本去问，已是最新时收到空应答，会被读成"端点坏了"。要区分必须拿一个假的低版本去问。（但别一概而论：ChatWise 的端点实测 `version=26.8.0` 和 `0.0.0` 返回**完全相同**的 36KB 列表，它是列表式不是条件式。）

---

## 二、Sparkle 更优雅的地方，和它唯一的软肋

**优雅**：一份文档同时承载版本 / 下载 / EdDSA 签名 / release notes / 版本历史 / delta / OS 下限 / 渠道。electron 的 `latest-mac.yml` 只有版本 + 文件 + 校验和，notes 和历史都没有。

**软肋在 channel**：**stable 是用「没有标签」表达的**，缺席即默认。两个后果：

1. feed 把每条都打了标签就没有默认轨了。这不是假想——OrbStack 的 appcast 每一条都带
   `stable`/`beta`/`canary` 标签，一条未打标签的都没有，而且见过整份 feed 全部标 `beta` 的。
2. 渠道推断依赖「装机 build 在 feed 里找得到」。掉出 feed 窗口 → 推断得 nil → `allowedChannels` 只剩 `{nil}` → 若 feed 里一条未打标签的都没有，**可用条目为 0，永远收不到更新且零报错**。

electron 反过来：渠道带外、写在包里、零推断；代价是每轨一个文件，且 channel 与架构挤在同一个字段（Typeless 用它装 `arm64`）。

---

## 三、自动发现能收回多少：实测净新增 0

`feed-discover`（`application-test/Sources/feed-discover`）扫一遍已装 app，结论是：
绝大多数根本没有可识别的更新器；有的那批里，**自带 `SUFeedURL` 的已经被
`SparkleAppcastSource` 覆盖了**；剩下要人判的占多数；能自动采纳的极少数，而且**跑出来的
那几个早就有覆盖**。

**净新增 = 0。** 原因是一条通则：

> 会把地址藏在代码里的 app，恰恰同时在干别的非标准事——模板拼地址、灰度分桶、按架构分 feed、按 macOS 大版本分目录。老实的 app 直接把地址写进 `SUFeedURL` / `app-update.yml`，而那些本来就不需要发现。
>
> **「能被自动发现」和「需要被自动发现」在这批数据上几乎不相交。**

四个典型（全部实测）：

| app | 判定 | 真实原因 |
|---|---|---|
| OrbStack | `templatedAddress` | 真地址是 `api-updates.orbstack.dev/%s/appcast.xml?bucket=%d`——架构 + **灰度桶号**，而且和 recipe 用的 `cdn-updates` 是**不同主机** |
| Brave Beta | `templatedAddress` | `updates.bravesoftware.com/sparkle/%@/%s/appcast.xml` |
| The Unarchiver | `templatedAddress` | `updates.devmate.com/%@.xml`，模板填 bundle id |
| Orion (Kagi) | `noCandidate` | 地址不是字面量，按 macOS 大版本拼（`updates/26_0/`；`27_0` 已存在且内容相同，`28_0` 尚 404） |
| Docker | `noKnownUpdater` | 发 appcast，但包里**没有 Sparkle**——它自己的更新器在读 |

多候选那批（Ghostty 两条、Tailscale 三条、VLC 按架构两条，还有若干 stable+beta 成对的）
地址**全都挖到了**，卡住的是渠道归属，而且**「哪个 feed 含我的 build」答不了**：预发布 feed
通常是稳定 feed 的**超集**，抽样里绝大多数两份都含同一个 build。唯一可解的形态是 Ghostty
那种——`tip` 是独立轨（版本号是 commit hash），不是超集——而它已有手写 binding。

**结论**：`FeedDiscovery` 是接入期工具（产出给人复核的提案），**不是** update source。闭集是特性——`duo verify` 要有主语、测试要有推导源、"支持哪些 app"要答得上来、两个用户行为要一致。

---

## 四、抓包真正用在哪

不是"藏在代码里"那一类，是**"参数会改变返回内容"**那一类。

| 类别 | 靠什么拿到地址 | 例子 |
|---|---|---|
| 写在 plist | 读一个 key | 最常见的一类 |
| 藏在代码里 | **读二进制字面量 / 打公开端点** | Ghostty、Tailscale、VLC、Helium（`SparkleFeedCatalog` 注释写明"in the binary alongside a `custom-update-server-url` flag"） |
| 参数化 / 条件端点 | **抓包**，或厂商开源仓库 | 搜狗（必需参数）、Raycast（204 语义）、ChatGPT（`plan_type`，参数表来自 openai/codex 开源仓库）、Alcove（license 门控） |

审计文档里 `抓包` 出现在 7 处，多数是**"需要抓包才能确认，本次未做"**（Little Snitch、CapCut），CCC 那条后来证明根本不需要。

**未验证**：OrbStack 用的 `cdn-updates.orbstack.dev`（二进制里只有 `api-updates…?bucket=%d`，另一个主机）和 WeChat 的 `dldir1.qq.com`（二进制里扫不到）——这两个地址不在包里，提交信息也没记来源。

---

## 五、`ElectronManifestSource` 为什么挂在最后

它是**通用机制**（零 per-app 地址），但排在 `VendorProbeSource` **之后**，这样只能在没人应答的地方新增覆盖，不会换掉任何现有 recipe 挑的产物。退休一条 recipe 的方式是**删掉它**，一次一个、验过再删。

**2026-08-31 的比对结论：候选一个都不该删。**

| app | recipe 给的产物 | 新源给的产物 | 删掉会丢 |
|---|---|---|---|
| Canva | `Canva-…-universal.dmg` | `…-universal-mac.zip` | `downloadURL`（下载页） |
| Typeless | `Typeless-…-arm64.dmg` | `…-arm64.zip` | 页链接 + changelog 链接 |
| ChatWise | 另一端点的 `arm64.zip` | latest-mac.yml 的 `arm64.zip` | changelog 链接 |
| Notion | **不读 yml**（`redirectFilename` → `Notion-7.31.3-universal.dmg`） | `Notion-arm64-7.31.3.zip` | 页链接 + 一段专门论证过的 changelog 页 |

`downloadURL` / `changelogURL` 是**清单里根本没有的 per-app 事实**。要真退休，得先让 changelog 迁进 `ChangelogCatalog`，而页链接目前无处安放。

另外 Antigravity / BaiduNetdisk 声明的地址今天 404——recipe 该留。

### 两个架构坑（都是跑生产代码打真实 bundle 才露出来的）

1. **清单顶层 `path` 不一定是运行它那台机器要的产物。** ChatWise 26.8.0 的 `path` 是 `ChatWise-26.8.0-x64.zip`。
2. **文件名没有架构标记也不代表通用。** Notion 的 `latest-mac.yml` 里是 `Notion-7.31.3.zip`（126 MB，实为 Intel），`arm64-mac.yml` 里才是 `Notion-arm64-7.31.3.zip`（121 MB）——**兄弟清单存在与否是唯一信号**。

现在的规则：按架构从 `files:` 里选（arm64 > universal > 顶层 path，且 path 带外来架构 token 就拒绝给下载）；并且**只在 `latest-mac.yml` 旁边**探 `arm64-mac.yml`——在 `beta-mac.yml` 旁边探会把 beta 用户挪到 stable 包上，那是跨轨道不是跨架构。
