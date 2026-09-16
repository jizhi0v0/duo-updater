# Cua Driver

## 基本信息
- Bundle ID: `com.trycua.driver`
- Team ID: **YCK386LBJ7**（`Developer ID Application: Cua AI, Inc.`），notarization ticket stapled，
  hardened runtime
- 观测版本: `0.28.2`（short == build == tag 的版本段，三者同构）
- `LSUIElement = true`，是个后台 daemon，不在 Dock 里；`LSMinimumSystemVersion = 13.0`
  （⚠️ 官方 install 文档写的是 "macOS 14 (Sonoma) or later"，与包里的 13.0 不一致，以包为准的话
  下限更低。没有在 13/14 上实测过，这里只记两个来源不一致这件事）
- 自更新机制: **有，但全是手动触发的**。`cua-driver check-update` 只查、
  `cua-driver update --apply` 才换，外加启动时一条被动 banner（文档原话是三条路径，
  并要求 "Keep the check and apply steps separate"）。**没有常驻的自动更新**：装完
  `launchctl list | grep -i cua` 无命中、`~/Library/LaunchAgents` 下无条目、
  `cua-driver doctor` 自报 `legacy LaunchAgent: not present`；检查发生在它自己进程运行时，
  结果缓存在 `~/.cua-driver/version_check.json`。所以不会和 DuoUpdater 的 swap 抢同一个 bundle
- 分发: 只有 `curl … | bash`（`https://cua.ai/driver/install.sh`），产物来自
  `trycua/cua` 的 GitHub Releases。无 Sparkle feed；Homebrew 无 cask 也无 formula
  （`cua-driver` / `cua` / `cua-driver-rs` 六个 API 端点全 404）；Mac App Store 无上架
  （`itunes.apple.com/search` `entity=macSoftware` `country=us` 搜 "Cua Driver" 只回一条
  无关的 `com.prolific.cdc.PLCdcFSDriver`）

### macOS 上「产品」就是那个 .app

这条决定了一键安装可不可行,所以单列。安装脚本在 macOS 上只做两件事:

1. 把 `CuaDriver.app` 拷进 `/Applications`;
2. 建 `~/.local/bin/cua-driver` → `/Applications/CuaDriver.app/Contents/MacOS/cua-driver` 的软链。

Linux/Windows 那套 `~/.cua-driver/packages/releases/<版本>-<target>/` 版本化目录
**在 macOS 上不用**(`_install-rust.sh` 自己的注释:".app 放在 /Applications 是 TCC
认身份的前提,把它搬进 $HOME_DIR 的版本目录会破坏这一点")。实测本机装完
`~/.cua-driver/packages/` 是空的。

所以替换 `/Applications/CuaDriver.app` 就是一次完整更新:软链指向的路径没变,
仍然解析得到新二进制;TCC 的辅助功能/屏幕录制授权挂在 designated requirement
(`com.trycua.driver` + 那个 Team ID)上,签名身份不变,授权也就不掉。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub  | VendorProbe |
|------------|---------|----------|-----|---------|-------------|
| **stable** | —       | ✗        | ✗   | ✓ 一键  | —           |
| **nightly**| —       | ✗        | ✗   | ✓ 一键  | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.trycua.driver` | 与 nightly **共享** | `~/.cua-driver/release-channel` 缺失或非 `nightly` | tag 锚 `^cua-driver-rs-vX.Y.Z$` | ✓ 一键 |
| nightly | `com.trycua.driver` | 与 stable **共享** | `~/.cua-driver/release-channel` == `nightly` | tag 锚 `^nightly-cua-driver-rs-vX.Y.Z-nightly.…$` + `githubChannelProofs` | ✓ 一键 |

⚠️ **两轨在磁盘上分不出来。** 实测下了 nightly 的
`cua-driver-rs-0.28.3-nightly.20260916.35055871159-darwin-universal.tar.gz`,
里面的 `CuaDriver.app` 是 `CFBundleIdentifier=com.trycua.driver`、
`CFBundleShortVersionString=0.28.3`、`CFBundleVersion=0.28.3` —— **版本串里没有
nightly 后缀**,和一个（尚未发布的）stable 0.28.3 逐字相同。唯一的轨道信号是
`~/.cua-driver/release-channel` 这个文本文件。**安装器只在显式传过 `--channel` 时才写它**
（本机默认安装后该文件不存在,`cua-driver channel status` 仍答 `stable`）——
但⚠️ **它不是只有安装器会写**:`cua-driver channel set <轨>` 自己就会改写它,
不下载、不安装、一秒完成（实测连着跑 `nightly`→`stable`→`nightly` 三次都生效）。
这决定了"不给它挂 FSEvents 监听"的代价是**切轨要等到下一轮扫描才被看见**,
而不是"反正只有重装才会变"。

所以轨道判别**只能靠 `~/.cua-driver/release-channel`**,由 `CuaDriverChannel` 这个
`ChannelBinding` resolver 读。它是本 registry 里第一个读**普通文本文件**(而不是
CFPreferences / plist)的 binding,形态上最接近 `SuperconductorChannel`。

⚠️ **那个文件记的是「意图」,不是「装的是什么」,而且厂商自己就这么分。**
`cua-driver channel status` 分别打印 `Selected channel`(来自文件)和 `Current channel`
(来自二进制自己),两者会真的分叉 —— 实测:在一台 `release-channel == nightly` 的机器上
用 `CUA_DRIVER_RS_VERSION=0.28.2` 钉装 stable,文件**原样不动**,于是变成
`Selected: nightly / Current: stable`。这不是 bug,是写进文档的设计:
"The pin is one-shot: it does not change the saved update channel... a machine following
nightly keeps following nightly",安装脚本的错误信息也写着
`exact pins do not change saved channel state`。

**跟随意图是对的,也正是厂商的行为**:在那个分叉态下它自己的 `check-update` 给出的是
最新 nightly,也就是把这份拷贝带回用户选的那条轨。我们的 `.nightly` 解析让 duo 做同一件事,
实测一致(见「历史与实测」的端到端那段)。

「装的到底是哪条轨」那一半我们**拿不到,且没有价钱可以买**:它只活在可执行文件里
(`cua-driver --version` 知道),而让扫描器去执行第三方二进制来读版本不是这个项目愿意做的交易。

安全方向:只有记录为 `nightly` 才会离开 stable。文件缺失(默认安装就不写)、读不到、为空、
或者是个连厂商自己都会拒绝的值,一律落到 `.stable`。没要过 nightly 的人不会被推 nightly。

## 更新检测
- 源: `trycua/cua` GitHub Releases，**列表端点**（`usePrereleases: true`）
- 版本方案: tag `cua-driver-rs-v0.28.2` → `0.28.2` == 包的 short 与 build。同构，无陷阱。
- ⚠️ **这个仓库的全部 `cua-driver-rs-v*` 发布都带 `prerelease: true`，是厂商故意的。**
  厂商在每条 release 正文里用一节 "Why GitHub says 'Pre-release'" 解释：
  这个 monorepo 同时发至少八条产品线，把驱动标成 prerelease 只是为了不让仓库级的
  "Latest" 指针在产品之间乱跳。它的安装脚本把同一件事写成
  "Cua Driver's stable tags are marked prerelease in GitHub metadata, so tag
  syntax—not the prerelease flag—defines the channel"。
  后果：`/releases/latest`（GitHub 定义上排除 prerelease）会答成**别的产品**——
  2026-09-16 实测是 `sandbox-v0.8.0`。所以 `usePrereleases: false` 在这里不是"会过时"，
  是"在读另一个产品"。
- ⚠️ **pattern 两端都锚，而且锚挡的是两样东西**：
  1. **nightly tag 里含有一个完整的 stable tag**。`NSRegularExpression` 不锚就随处匹配，
     不锚的 `cua-driver-rs-v([0-9]+\.[0-9]+\.[0-9]+)` 打在
     `nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159` 上会匹配中间那段
     `cua-driver-rs-v0.28.3` 并交出 `0.28.3` —— 一个还没发布的 stable 版本，**每天夜里一次**。
  2. 退役的 Swift 版驱动仍在同一个仓库里，tag 前缀是 `cua-driver-v*`（共 23 条，
     最后一条 `cua-driver-v0.2.0`）。`^` 把它们挡在外面。
- tag 语法直接抄厂商的 `_install-rust.sh`：stable 是 `^[0-9]+\.[0-9]+\.[0-9]+$`，
  nightly 是 `^[0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}\.[1-9][0-9]*$`。
- `listPageSize: 25`。2026-09-16 用 Python 独立复算（不是从 Swift 规则里重读）：最新 100 条
  release 里 21 条命中，相邻两条命中之间最大间距 18（`v0.20.0` → `v0.19.3`，中间五天全是
  nightly / lume / fleet / sandbox），所以下限 19，登记在
  `GitHubListPageSizeTests.measuredMinimumDepth`（全历史 683 条重算一遍，最大间距同样是 18，
  所以下限不随窗口变）。25 是在下限之上留余量，和 Bitwarden 的
  10 相对其下限 8 同一个做法。**代价是实打实的**：`curl --compressed` 实测同一端点
  per_page=20 → 76.4 KB、25 → 101.8 KB、40 → 144.0 KB（gzip 线上字节，和请求账本同一单位）。
  这是本 registry 里最贵的一条 GitHub 规则。
  stable 轨若安静得比一页还久，最新那条命中会被挤出页面 —— 那条路径的出口是
  `recordMiss` + 行变 `.unknown`，不是自信地报"已最新"。
- `probesNewestFirst: false`：全仓 683 条 release 里 stable 驱动 tag 占 88 条（12.9%），
  nightly job 几乎每天早上发一版，所以第 0 行基本不会是这条规则要的那条。探一页一行
  （4.7 KB）几乎每轮都会落空再去付整页的钱。
- ⚠️ **`.newest` 是"第一个命中就赢"，而这个仓库的列表顺序不严格等于 semver 顺序。**
  把全部 683 条重放一遍：88 条 stable 驱动 tag 里有**两处**逆序，而且都发生在同一天的
  进位上 —— `v0.9.1`（2026-07-20 12:11Z）排在更新的 `v0.10.0`（20:48Z）**前面**，
  `v0.2.9` 排在 `v0.2.18` 前面。列表顺序不是 `created_at`、不是 `published_at`、也不是
  `id` 降序（三者都与它不符），这大概就是厂商自己的安装脚本宁可把命中项按数字排序、
  也不取第一条的原因。`settle()` 里没有这个排序。
  后果有界：那两个窗口里（到下一条 stable release 为止，分别约两天和约六天）这条规则会给出**偏低**的版本，
  即"暂时过时的提示"，不会是"错误的提示"。没有绕过去，是因为 `GitHubCandidateScope`
  里没有一个既不依赖顺序、又适用于"全部 release 都被标成 prerelease"的选项。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 无 Sparkle，无 `latest-mac.yml`；厂商自更新是整包换 | release 资产只有整包 tar.gz/zip/whl/tgz | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回，**无需 ChangelogRecipe**）
- ⚠️ **而且这里也加不了 `.gitHubReleases` recipe**：`StructuredChangelogDecoder.decodeGitHubReleases`
  用 `wantsPrerelease = channel != nil && channel != .stable` 做轨道判别，
  `nil`/`.stable` 的 recipe 只收 `prerelease == false` 的 release —— 而本仓库这条产品线
  **一条都没有**。写一条 recipe 只会得到 0 条目、`decodeGitHubReleases` 返回 nil。
  想绕过只能把 recipe 声明成非 stable 轨，那样 `ChangelogRecipeSelection` 又不会把它
  选给一个 stable 装机。**所以 changelog 只能走内联那条路，这是测量出来的，不是省事。**
- 内联那条路的产出是干净的。厂商每条正文都带同一批样板：一段 install 片段、
  一节 "Why GitHub says 'Pre-release'"、一个约 20 行 SHA256 的 fenced 代码块、
  一行 compare 链接。实测这些**一条都进不了面板**：
  - `GitHubMarkdownParser` 的严格趟只取顶层 bullet，样板里没有 bullet；
  - `qualifyingHeadings` 丢掉带数字的标题（`SHA256 Checksums`）和
    `full changelog` / `contributors` 两个样板关键词。
  - 0.28.2 的真实正文跑出来是：`items` 恰好那 4 条 fix，`content` 是
    `heading("Fixes")` + 4 条 `note`。`CuaDriverGitHubRuleTests` 把这个结果钉住了，
    并且按名字断言 `install.sh` / 校验和前缀 / `Pre-release` / `Checksums` / `compare/`
    都不出现——数条目数是看不出泄漏的。
- 版本轨（`releaseHistory`）由同一页 release 顺带填上，不额外发请求。
- nightly 轨的 changelog 同理走内联解析，由 nightly rule 自己那一页带回。

## 一键安装
- 状态: **已接入**（`.tarGz`）
- 资产: `cua-driver-rs-<版本>-darwin-universal.tar.gz`，就是厂商安装脚本在 macOS 上取的那个
  （`_install-rust.sh` 对所有 `darwin-*` 目标都用 `darwin-universal`）。
- ⚠️ **必须排掉 `-binary` 那个同名兄弟**：`…-darwin-universal-binary.tar.gz` 里只有裸可执行文件，
  没有任何 `.app`，`ArchiveExtractor` 会以 `noAppFound` 失败。pattern 以
  `-darwin-universal\.tar\.gz$` 结尾就是这道闸。
- 归档里 `CuaDriver.app` 嵌在 `cua-driver-rs-<版本>-darwin-universal/` 一层目录下，
  `ArchiveExtractor.firstApp` 正好**向下递归一层**，够得到。
- pattern 里不含 `|` 也不含 `\-`，所以不进 `GitHubAssetSelectionTests.ambiguousRegistryPatterns`；
  实测 88 条 stable release 每条都恰好有**一个**资产命中该 pattern，选择没有二义、
  也永远不会触发 `settle()` 里的 walk-back。
- **nightly 轨同样已接一键**，资产形状相同（`…-nightly.<日期>.<run>-darwin-universal.tar.gz`），
  `-binary` 兄弟同样被结尾锚排掉；全历史 23 条 nightly release 每条恰好一个资产命中。
  它带 `installAssetPattern` 且不在 stable 轨，所以**必须**在 `githubChannelProofs` 里
  登记一条 proof（`channelProofsCoverEveryChannelRecipe` 的 GitHub 版会拦）。登记的是
  `.artifact(#"/download/nightly-cua-driver-rs-v[0-9.]+-nightly\."#)` —— tag 在 URL 路径里，
  所以能给出比 `.recipeAnchor` 更强的证明。
- **两条轨的 pattern 互不吃对方**（实测四个方向，`CuaDriverGitHubRuleTests` 钉住）：
  stable 的 tag/资产 pattern 拒 nightly 的，nightly 的拒 stable 的。这是这类「一个 bundle id
  两条 rule、且互相是最顺手的抄写来源」最容易出的事故。
- 包验（2026-09-16，真下 `cua-driver-rs-0.28.2-darwin-universal.tar.gz`）：
  - `codesign -dvvv`: `Identifier=com.trycua.driver`、
    `Authority=Developer ID Application: Cua AI, Inc. (YCK386LBJ7)`、
    `TeamIdentifier=YCK386LBJ7`、`flags=0x10000(runtime)`、`Notarization Ticket=stapled`
  - `codesign --verify --deep --strict`: 退 0
  - `spctl -a -t exec`: 退 0，`source=Notarized Developer ID`
  - 对应到闸：`SignatureVerifier` gate 2（deep/strict）、gate 3（Team ID 与被替换拷贝相同）
    都过 —— 而 gate 3 天然成立，因为装机上的那份就是同一个厂商产物。
- ✅ **它是 `vendorDownloadPassesSignatureGate` 的 `tarGz` 证人。** 那个闸之前只有 zip 和 dmg
  两行，所以 `ArchiveExtractor.fromTar` 和 `firstApp` 向下递归的那一层从来没有对**真实下载的厂商字节**
  跑过。选它当头一个候选正是因为嵌套：实测 2026-09-16，Cline（`Cline.app/`）和
  Conductor（`Conductor.app/`）都把 bundle 放在归档根上，只有这个包需要递归。
  变异验过：把 `firstApp` 的递归关掉，这条测试当场红在 `noAppFound`。
  闸按装机拷贝的轨道选 rule：`~/.cua-driver/release-channel` 缺失时走 stable 那条
  （两条轨资产形状相同，所以哪条都覆盖同一段递归）。
  ⚙️ **只在本机生效**：runner 镜像只有 Safari / Chrome / Edge / Firefox，CI 上这一行打
  “no tarGz candidate installed here”。每跑一轮 +66 MB。

## 已知问题
- ⚠️ **nightly 只能做到 base 版本粒度，同一 base 下的后续 nightly 看不见。**
  根因是 nightly 包的 `CFBundleShortVersionString` / `CFBundleVersion` 就是裸 base
  （实测三份 0.28.2 系的构建全是 `0.28.2`），所以 nightly rule 的 `versionPattern`
  只能从 tag 里捕 base —— 捕全串 `0.28.3-nightly.20260916.…` 去跟盘上的 `0.28.3` 比，
  semver 上 prerelease < release，`isNewer` 恒假，**一次都不会提示**。
  代价量化（全历史）：23 条 nightly 发布落在 **12** 个不同 base 上，所以约 **52%** 的 nightly
  发布会产生提示，其余 48% 静默。
  **重启条件**：厂商哪天把 nightly 标识写进 `Info.plist`（任何一个字段都行）。
  唯一的替代方案是执行 `cua-driver --version` 去读真实版本，不做。
- **切轨不会被立刻看见。** `cua-driver channel set <轨>` 一秒就改写那个文件（实测），
  而我们刻意没给 `~/.cua-driver` 挂 FSEvents（daemon 往同目录持续写遥测），
  所以切轨要等下一轮扫描 / app 启动 / app 退出才生效。
- **我们不跟厂商做降级。** `channel set stable` 之后如果盘上是更高版本的 nightly，
  厂商的 `check-update` 会提示"装最新 stable"（实质是降级），而 duo 走 `isNewer`，
  `0.28.2 < 0.28.3` → 显示"已最新"，不提示。方向是安全的，但和厂商的答案会不一致。
- **列表顺序偶发逆序**（见「更新检测」）。历史上两次，各约两天，表现为暂时给出偏低的版本。
- **文档与包对 macOS 下限说法不一致**：文档 14.0，`Info.plist` 13.0。两边都没实测。
- **这条规则在流量上是本 registry 里最贵的 GitHub 规则**（101.8 KB/轮）。
  monorepo + 每日 nightly 是根因，换不掉；能换的只有页大小，而页大小的下限是测出来的。

## 如何复验

```sh
# 全部 release 的 tag / prerelease 标志（注意 stable 也都是 true）
gh api 'repos/trycua/cua/releases?per_page=100' -q '.[] | "\(.tag_name)\t\(.prerelease)"'
# /releases/latest 会答成别的产品
gh api repos/trycua/cua/releases/latest -q .tag_name
# 厂商自己怎么定义轨道（搜 extract_published_release_versions / BAKED_VERSION）
curl -fsSL https://cua.ai/driver/_install-rust.sh | sed -n '600,720p'
# 包验：真下 darwin-universal，解包后
codesign -dvvv <dir>/CuaDriver.app
codesign --verify --deep --strict <dir>/CuaDriver.app; echo $?
spctl -a -t exec <dir>/CuaDriver.app; echo $?
# 端到端（检测）
duo verify --only com.trycua.driver
# 端到端（一键）：先钉旧版，再让 duo 升回来
CUA_DRIVER_RS_VERSION=0.28.1 /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)"
duo check com.trycua.driver && duo install com.trycua.driver --yes
cua-driver --version && cua-driver doctor

# 端到端（nightly 轨）：切轨后 duo 必须给出 nightly 的包
curl -fsSL https://cua.ai/driver/install.sh | bash -s -- --channel nightly
cat ~/.cua-driver/release-channel          # 必须是 nightly；默认安装则该文件不存在
duo check com.trycua.driver
cua-driver --version                       # 装完必须自报 …-nightly.<日期>.<run>
cua-driver channel status                  # Selected / Current 应当一致
```

## 历史与实测

### 2026-09-16 —— 接入（检测 + changelog + 一键）

- 本机按官方 `install.sh` 装了一份（0.28.2），路径 `/Applications/CuaDriver.app`，
  软链 `~/.local/bin/cua-driver` 指进 bundle 内部。`~/.cua-driver/packages/` 是空的，
  `release-channel` 文件不存在，`cua-driver channel status` 答 `Selected channel: stable`。
- release 列表：翻到底共 **683** 条（7 页，第 7 页不满 100 即到底），`cua-driver-rs-v<x.y.z>` **88** 条（占 12.9%，最老一条 `v0.1.3` 位于索引 200，所以这 88 条就是全部，不是某个窗口里的），
  **全部 `prerelease: true`、`draft: false`**；同仓另有 nightly 驱动、`sandbox-*`、
  `fleet-*`、`npm-fleet-*`、`lume-*`、`computer-server-*`、`cua-hyprland-kit-*`、
  以及退役 Swift 驱动的 `cua-driver-v*`（23 条，最后一条 `cua-driver-v0.2.0`）。
- `gh api repos/trycua/cua/releases/latest` 当天答 **`sandbox-v0.8.0`** —— 一个完全不同的产品。
  这就是 `usePrereleases: false` 在这里会读到的东西。
- `listPageSize` 下限：用 Python 在最新 **100** 条的窗口上独立复算（和本表其它下限同一窗口），
  21 条命中，相邻命中最大间距 **18**（`cua-driver-rs-v0.20.0` → `v0.19.3`，中间五天），
  故下限 19。次大的几个间距是 12 / 11 / 8 / 8；当天第一条命中位于索引 3。
- 列表顺序的两处逆序：`v0.9.1`（`created_at` 12:06Z / `published_at` 12:11Z）排在
  `v0.10.0`（20:42Z / 20:48Z）**之前**，`v0.2.9`（05-21 12:20Z）排在 `v0.2.18`（21:10Z）之前。
  两处都是同一天的进位。逆序窗口各持续到下一条 stable 发布为止：0.9.1 那次到 07-22 的
  `v0.11.0`（约两天），0.2.9 那次到 05-27 的 `v0.3.1`（约六天）。
  实测 `id` 降序、`created_at` 降序、`published_at` 降序三者都与实际返回顺序不符。
  ⚠️ 这是**用今天的返回顺序重放历史**得出的，不是当时的现场观测：结论「那两个窗口里会给出偏低
  的版本」依赖「GitHub 的排序键稳定、当时的相对顺序与今天相同」这个前提，该前提没有独立证据。
  能直接证实的只有今天这一份返回里确实存在这两处逆序。
- `darwin-universal.tar.gz` 资产：**全历史** 88 条 stable release **每条都有，且每条只有一个**；
  `-binary` 兄弟从未被本 pattern 命中。
- 一键端到端（红→绿走真实路径）：
  1. `CUA_DRIVER_RS_VERSION=0.28.1` 钉装旧版 → `Info.plist` 0.28.1，inode 250089576；
  2. `duo check com.trycua.driver` → `Cua Driver 0.28.1 → 0.28.2 [GitHub, in-place]`；
  3. `duo install com.trycua.driver --yes` → `downloading / extracting /
     verifyingCodeSignature / installing / done`，9.8 秒；
  4. 换后 `Info.plist` 0.28.2、inode 250090241（确实换了一份新的，不是原地写）、
     owner 仍是 `bobby`、`codesign -dv` 仍是 `TeamIdentifier=YCK386LBJ7`、
     `--deep --strict` 退 0、`spctl -a -t exec` 退 0；
  5. `~/.local/bin/cua-driver` 仍然解析，`cua-driver --version` → `0.28.2`；
  6. **厂商自己的健康检查在我们换过的 bundle 上全绿**：`cua-driver doctor` 的
     `binary` / `install dir` / `home dir` / `telemetry` / `legacy LaunchAgent` /
     `legacy update script` 六项都是 `[ok]`，`install dir` 打印的正是
     `/Applications/CuaDriver.app/Contents/MacOS/cua-driver`；
  7. `cua-driver check-update` 答 `Current: 0.28.2 / Latest: 0.28.2 / You're on the
     latest release.` —— 与本规则解析出的版本一致，是一个独立证人。
- `lipo -archs`：`x86_64 arm64`（两个 darwin tarball 里的 `.app` 都是 universal，
  `darwin-arm64` 那个也是；两者只差旁边的裸二进制，所以取 universal 与厂商一致）。
- 页大小实测（`curl --compressed`，gzip 线上字节）：per_page=1 → 4.7 KB、
  20 → 76.4 KB、22 → 81.6 KB、25 → 101.8 KB、30 → 115.3 KB、40 → 144.0 KB。
- changelog：0.28.2 正文过 `GitHubMarkdownParser` 得到 `items` 4 条 fix、
  `content` 为 `heading("Fixes")` + 4 条 `note`，install 片段、校验和块、
  "Why GitHub says 'Pre-release'" 一节都没进去。

### 2026-09-16 —— 补接 nightly 轨

- **三份真包实测轨道在磁盘上不可分辨**：`cua-driver-rs-v0.28.2`（stable）、
  `…-v0.28.2-nightly.20260914.34806428689`、`…-v0.28.2-nightly.20260915.34929088253`，
  三个 `CuaDriver.app` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` **全是 `0.28.2`**。
  而同一份 nightly 的二进制自报 `cua-driver 0.28.2-nightly.20260915.34929088253` ——
  **版本只活在可执行文件里**。
- 轨道信号实测：`install.sh --channel nightly` 之后 `~/.cua-driver/release-channel`
  出现，内容 `nightly`（8 字节，含换行）；默认安装后该文件**不存在**，
  `cua-driver channel status` 仍答 `stable`。脚本里那行写在 `if [[ "$CHANNEL_EXPLICIT" == "1" ]]` 里。
- **意图/事实分叉实测**：在 `release-channel == nightly` 的机器上
  `CUA_DRIVER_RS_VERSION=0.28.2` 钉装 stable → 文件仍是 `nightly`、二进制是 `0.28.2`，
  厂商自报 `Selected channel: nightly / Current channel: stable`，而它的 `check-update`
  给出最新 nightly。**是设计不是 bug**（装文档："The pin is one-shot: it does not change
  the saved update channel"）。
- nightly 资产签名与 stable 同级：`Developer ID Application: Cua AI, Inc. (YCK386LBJ7)`、
  `Notarization Ticket=stapled`、`flags=0x10000(runtime)`，`codesign --verify --deep --strict`
  与 `spctl -a -t exec` 各退 0。
- nightly rule 的页深度（同 100 行窗口）：23 条命中，**第一条命中在索引 0**，最大间距 8 → 下限 9，
  取 12。`probesNewestFirst` 保持默认 true —— 和 stable 那条正好相反，因为 nightly 几乎天天是第 0 行。
  全历史 23 条 nightly release 每条恰好一个 `…-darwin-universal.tar.gz` 命中，零条缺失、零条多命中。
- **端到端（红→绿，而且是从上面那个分叉态出发）**：
  1. 起点 `release-channel = nightly`、二进制 `0.28.2`（stable）、inode 250225860；
  2. `duo check com.trycua.driver` → `Cua Driver 0.28.2 → 0.28.3 [GitHub, in-place]`，
     与厂商 `check-update` 给的 `0.28.3-nightly.20260916.35055871159` 是同一条 release；
  3. `duo install --yes` 跑完 → **`cua-driver --version` 自报
     `0.28.3-nightly.20260916.35055871159`**，即装进去的确实是 nightly 那份；
  4. `Info.plist` 是 `0.28.3`（只有 base，符合上面那条约束），inode 250332939；
  5. 签名 `TeamIdentifier=YCK386LBJ7` 不变，`--deep --strict` 与 `spctl` 各退 0；
  6. 厂商 `channel status` 变成 `Selected: nightly / Current: nightly` ——
     **分叉被 DuoUpdater 治好了，方向与厂商自己的 `update --apply` 一致**；
     `check-update` 答 "You're on the latest release."
