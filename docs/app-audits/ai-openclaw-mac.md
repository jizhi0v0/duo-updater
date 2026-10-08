# OpenClaw

审计 2026-10-08（重审；2026-08-17 那版只核对了 bundle 身份（Team、版本、`SUFeedURL`），没在新旧两个包上跑生产检测，
没查渠道和 changelog 结构，也没跑一键）。

## 基本信息
- Bundle ID: `ai.openclaw.mac`（universal、arm64、x86_64 三种包同一个 id，各自的 `SUFeedURL` 不同，见下）
- Team ID: `FWJYW4S8P8` — Developer ID Application: OpenClaw Foundation（2026.9.7、2026.9.8 universal 与 2026.9.8 arm64
  三个真包相同，均 `Notarized Developer ID`）
- 观测版本: `2026.9.8`（`CFBundleVersion` 2609000890）、上一版 `2026.9.7`（2609000790）。`LSMinimumSystemVersion` 15.0；
  `LSUIElement` = true（菜单栏 app）
- 自更新机制: Sparkle 2.10.0（2064），`SUEnableAutomaticChecks` = true；Sparkle 由 app 自己的
  `SparkleUpdaterController`（`SPUUpdaterDelegate`）驱动，渠道取自 OpenClaw Gateway 的配置（见下）
- Homebrew: cask `openclaw`，`auto_updates: true`，下载的是 GitHub release 里的 universal `.dmg`
- **开源**（MIT）：`github.com/openclaw/openclaw`，默认分支 `main`。feed 就是仓库根下的 `appcast.xml`，生成脚本是
  `scripts/make_appcast.sh`，Sparkle 委托在 `apps/macos/Sources/OpenClaw/AppLifecycleSupport.swift`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（universal / arm64 / x86_64 各读自己的 feed） | —（`auto_updates`，让位） | — | —（不需要：GitHub latest 常是不带 mac 资产的版本，见下） | — |
| **beta**（Sparkle 标签 `beta`） | ○ 客户端支持，feed 当前没有带标签的条目 | — | — | — | — |
| **extended-stable**（Sparkle 标签 `extended-stable`） | ○ 同上；一旦发布，duo 会跨轨推（见缺口） | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`SparkleAppcastSource`，读 bundle 自己的 `SUFeedURL`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `ai.openclaw.mac` | 共享 | — | 默认（无标签）条目 | ✓ |
| beta（Gateway 的 `beta` 或 `dev`） | 同上 | 共享 | Gateway `update.status` 的 `effectiveChannel`，取不到时读 `~/.openclaw/openclaw.json` 的 `update.channel` | Sparkle 标签 `beta`（`allowedChannels`） | ○（feed 无此类条目） |
| extended-stable | 同上 | 共享 | 同上，值 `extended-stable` | 只认 `extended-stable` 标签；`bestValidUpdate` 把默认轨条目也排除 | ○（feed 无此类条目） |

**settled from source**（`main`，2026-10-08 读）:

- `AppLifecycleSupport.swift`：`allowedSparkleChannels(forGatewayUpdateChannel:)` 把 `beta`、`dev` 映射成 `["beta"]`，
  `extended-stable` 映射成 `["extended-stable"]`，其余（含没有值）是 `[]`，即只读默认轨。
  `bestValidUpdate(in:for:)` 只在 `extended-stable` 时生效，注释写明「Sparkle always admits the default channel. Filter it
  here so an extended-stable Gateway is never prompted to leave its release train」。
- 渠道值的来源：启动时先问正在运行的 Gateway（RPC `update.status` → `effectiveChannel`，5 s 超时），失败时用
  `OpenClawConfigFile.gatewayUpdateChannel()`：读 `OpenClawPaths.configURL` 的 `update.channel`（小写化）。
  `configURL` = 环境变量 `OPENCLAW_CONFIG_PATH`，否则 `<stateDir>/openclaw.json`；`stateDir` = `OPENCLAW_STATE_DIR`，
  否则 `~/.openclaw`（命名 profile 时是 `~/.openclaw-<name>`）。文件先按 JSON 读，失败再按 JSON5。
- `scripts/make_appcast.sh`：版本带 `-beta.`/`.beta.` 的加 `--channel beta`；版本形如 `YYYY.M.N` 且 `N ≥ 33` 的加
  `--channel extended-stable`；alpha 不进 Sparkle。beta 轨 2026-07-11（#104171）加入，extended-stable 2026-08-09（#118518）。
- 已发布的 2026.9.8 二进制里有 `extended-stable`、`effectiveChannel`、`OPENCLAW_CONFIG_PATH` 这些串，和源码对得上。

**服务端今天发不发（实测）:**

- `appcast.xml` 当前 3 条，`<sparkle:channel>` 0 条。翻了这个文件最近 100 次提交（2026-01-21 → 2026-10-03），**每一版**
  都是 0 条带标签。唯一进过 feed 的预发布版是 2026-03 的 `2026.3.8-beta.1`，当时**没带标签**（beta 轨还没加），
  对所有人都是默认轨。
- GitHub 上 beta（`v2026.10.1-beta.1`/`.2`、`v2026.9.1-beta.1` 等）和 extended-stable 号段（`v2026.8.33`–`.35`、
  `v2026.7.35`、`v2026.6.35`）的 release 都**没有 mac 资产**，只有证据/清单文件。
- 所以缺口目前看不到，但机制已在客户端里：
  1. Gateway 在 `beta`/`dev`、而 app 是 stable 构建：将来 feed 出现 `beta` 条目时，OpenClaw 自己会推，duo 不推。
  2. Gateway 在 `extended-stable`：将来 feed 同时有默认轨更新版本时，OpenClaw 只认 `extended-stable`，**duo 会推默认轨**，
     即跨轨推送。这一条比 1 更要紧。
  两条都要一个读 `openclaw.json` `update.channel` 的 `ChannelBinding` 才能补；app 优先信运行中的 Gateway，
  文件只是兜底，binding 读文件是近似（**推断**：多数配置下两者一致，未验证）。

**按架构的三份 feed（实测）:** 仓库根下还有 `appcast-arm64.xml`、`appcast-x86_64.xml`（2026-09-23 起）。
arm64 包（`OpenClaw-2026.9.8-arm64.zip`）的 `SUFeedURL` 就是 `appcast-arm64.xml`，`lipo -archs` = `arm64`，
条目带 `<sparkle:hardwareRequirements>arm64`；`feed-discover` 报 `declared`，`channel-verify` 报 up to date、下载地址是
arm64 zip。x86_64 包没下（**推断**同形）。同一个 bundle id、三份 feed，靠的是各包自己声明的地址，duo 已经跟随。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover`：`declared  https://raw.githubusercontent.com/openclaw/openclaw/main/appcast.xml`）
- 端点: `https://raw.githubusercontent.com/openclaw/openclaw/main/appcast.xml`（`cache-control: max-age=300`，CDN 可能晚几分钟）
- feed 形状（2026-10-08）: 3 条（2026.9.8 / .7 / .6），只保留最近三版；每条 `minimumSystemVersion` 15.0；
  没有 `maximumSystemVersion`、`phasedRolloutInterval`、`criticalUpdate`、deltas；说明内联在 `<description>`（HTML，
  `--embed-release-notes`），没有 `releaseNotesLink`
- 版本方案: `sparkle:version` = `CFBundleVersion`（2609000890），`shortVersionString` = `2026.9.8`，与包一致
- GitHub release 和 feed 不同步：2026-10-08 GitHub latest 是 `v2026.9.9`，只有 Linux/Windows 资产；feed head 仍是 2026.9.8。
  duo 读 feed，不受影响。若加 GitHub 规则反而会推一个没有 mac 包的版本
- feed 曾回退过：2026-09-24 00:14Z 那次提交把 head 从 2026.9.6 退回 2026.9.5，12 小时后恢复 2026.9.6
- 发布日期: RFC 822 `pubDate`，生产解析能读（`release history 3 entries`）

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不适用 |
| 证据 | `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta` 等串（Sparkle 2.10.0） | 2026-10-08 三份 feed 都没有 `<sparkle:deltas>` | `channel-verify`：`deltas 0` |

- 格式: —
- 阻塞项: 包很大（universal zip 约 502 MB，arm64 约 251 MB），每次整包下载

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval` | 否 | 不需要 |
| 按架构 / 按 OS 分轨 | 按架构：三种包各读自己的 feed | 是：`appcast-arm64.xml` 带 `hardwareRequirements arm64`；三份都只有下限 15.0 | 能：读包里的 `SUFeedURL`，`SparkleAppcastSource` 读 `hardwareRequirements` |
| 自更新器会不会和我们抢 | 会：自动检查；`automaticallyDownloadsUpdates` 跟随用户的自动更新设置 | 是：同一个 feed | 端到端第二轮未跑 |
| 更新后的收尾 | 有：Sparkle `willInstallUpdate` 时写 `PostAppUpdateReceipt`，下次启动据此迁移/重启 Gateway；打包版每次启动也会做一次检查（`PostUpdate.swift` 的 `launchReceipt`） | — | duo 换包不写这个 receipt；靠启动时的那次检查兜底（**推断**，来自源码，未验证） |

## Changelog
- 来源: Sparkle inline（`<description>`，由仓库的 `CHANGELOG` 经 `scripts/changelog-to-html.sh` 生成）
- 结构化: `changelog pane  source structured: 3 entries; newest 2026.9.8: 54 items, headings []; first items ["Highlights", "Safer updates and Doctor recovery: prese", "Gateway availability: prevent duplicate "]`
  （2026.9.7、2026.9.8、arm64 三个包相同）
- 判断（修复前）: **分节被压平了**。厂商的 HTML 是 `<h2>OpenClaw 2026.9.8</h2>` 后接 `<h3>Highlights</h3>`、`<h3>Changes</h3>`、
  `<h3>Fixes</h3>` 各带一个 `<ul>`。`AppcastHTMLChangelogParser` 按设计把 `<h2>`–`<h4>` 当作一行文字折进 `items`，
  不产出 `.heading` 块，所以面板里 `Highlights` 是一个普通条目、`headings []`。条目本身完整（54 条）。
- 已修：`AppcastHTMLChangelogParser` 在一条说明里有 ≥2 个分节标签时，把不含数字的 `<h2>`–`<h4>`（以及紧接列表的整段粗体）
  产出为 `.heading` 块、移出 `items`；含版本号的 `<h2>OpenClaw 2026.9.9</h2>` 不算。84 个 appcast 回放：OpenClaw 3 条变化，
  都只是标签行从条目移到标题，内容与顺序不变
  **写 ChangelogRecipe 不是对的修法**：feed 已经内联了说明，问题在通用解析器。让 `AppcastHTMLChangelogParser` 把
  `<h3>`/`<h4>` 产出成 `content` 里的 `.heading`（像 `GitHubMarkdownParser` 在 parser generation 3 做的那样），
  OpenClaw 和其他用 HTML 标题分节的 Sparkle feed 一起受益（已这样修，见上一条）
- 另记: 2026.9.7 那条 `<description>` 有 253 KB（2026.9.8 只有 8.5 KB）
- 跟随 channel: 否（同一份 feed，标签条目当前没有）
- Recipe 状态: 不需要（需要的是通用解析器改进）

## 一键安装
- 状态: ✓（通用 Sparkle 路径，整包 zip）
- 端到端（2026-10-08，第一轮，不启动）: universal 2026.9.7 → `duo check` `update 2026.9.8`、`source Sparkle`；`duo install /Applications/OpenClaw.app --yes --json` → `installed`、`route sparkle`、`bytesDownloaded 501839226`，约 3 min。装后 2026.9.8（2609000890），strict 通过，`Notarized Developer ID`，Team `FWJYW4S8P8`；与厂商 2026.9.8 包逐文件比 SHA-256，77,723 个文件、75 个软链接全部相同。没有启动 app，前后都没有从包内 `Resources/` 起的进程（Gateway 运行中换包仍未验证）
- 格式: zip（universal `OpenClaw-2026.9.8.zip` 501,839,226 B、`OpenClaw-2026.9.7.zip` 501,820,257 B、
  arm64 `OpenClaw-2026.9.8-arm64.zip` 251,254,969 B，均与 feed `length` 相等，`unzip -t` 无错）。GitHub release 里同版本
  还有 `.dmg`（Homebrew 用），Sparkle 不用
- 校验: feed 没有 SHA 摘要，有 `edSignature`。下载 SHA-256（仅作记录）：2026.9.8 `d77ef4aa…5920`、2026.9.7 `0e1315e6…b2d6`、
  arm64 `dfe3437c…92ab`
- **读的是**: 人人可手动下载的 GA（feed 无灰度；同一个 zip 在 GitHub release 公开）
- Team: 上一版、最新版、arm64 同为 `FWJYW4S8P8`
- 嵌套: 没有 `Contents/Library`、没有 LoginItems / Helpers；嵌套 `.app` 只有 Sparkle 的 `Updater.app`。但包里带了大量
  可执行的运行时：`Contents/Resources/node-worker/{arm64,x86_64}/`（带 `bin/node` 和 `openclaw` npm 包，共约 1.2 GB）、
  `Resources/cloudflared/{arm64,x86_64}/cloudflared`、`Resources/cua-driver`，以及 `Contents/MacOS/openclaw-mac`、
  `openclaw-mlx-tts`。app 用 `GatewayLaunchAgentManager` 管一个 Gateway 的 LaunchAgent。**Gateway 进程是否从包内的
  `node-worker` 运行、换包后会不会继续跑旧代码，未验证**；`NestedAppGuard` 只看嵌套 `.app`，不会拦这类进程
- 阻塞: 无已知；包大

## 已知问题
- `beta` / `extended-stable` 两条 Sparkle 轨客户端已支持、duo 没有 binding（今天 feed 里没有带标签的条目，所以还没有实际影响）
- 一键第二轮（app 运行中）未跑；Gateway 进程在换包前后的状态未验证

## 建议下一步
1. 一键第一轮已过（见「一键安装」）。第二轮（app 与 Gateway 运行中）：换包前后用 `ps` 看有没有从 `/Applications/OpenClaw.app/Contents/Resources/`
   起的进程（node、cloudflared、cua-driver），以及换包后它们是否被 app 重启。⚠️ 这是 agent 类 app，启动前后对比 `~/.claude/skills`。
2. 渠道：等 feed 里第一次出现带 `beta` 或 `extended-stable` 标签的条目再做 `ChannelBinding`（读 `~/.openclaw/openclaw.json`
   的 `update.channel`；`beta`/`dev` → 标签 `beta`，`extended-stable` → 只认该标签，并排除默认轨）。extended-stable 那半更要紧。
3. （已做）通用解析器把 `<h3>`/`<h4>` 分节产出为 `.heading` 块（这个解析器的输出只在内存里，不需要 bump parser generation）

## 如何复验

2026-10-08，包从 feed 的 enclosure（GitHub release 资产）直接下载，长度与 feed `length` 相等，`unzip -t` 无错，
`ditto -x -k` 解包，不安装、不启动。

```bash
curl -sS -o feed.xml https://raw.githubusercontent.com/openclaw/openclaw/main/appcast.xml
grep -c "<item" feed.xml                      # 3
grep -c "<sparkle:channel" feed.xml           # 0
curl -fL -C - -O https://github.com/openclaw/openclaw/releases/download/v2026.9.8/OpenClaw-2026.9.8.zip
curl -fL -C - -O https://github.com/openclaw/openclaw/releases/download/v2026.9.7/OpenClaw-2026.9.7.zip
curl -fL -C - -O https://github.com/openclaw/openclaw/releases/download/v2026.9.8/OpenClaw-2026.9.8-arm64.zip
ditto -x -k OpenClaw-2026.9.8.zip new/        # prev/、arm64/ 同理
swift run --package-path application-test feed-discover new/OpenClaw.app
swift run --package-path application-test channel-verify new/OpenClaw.app    # prev/、arm64/ 同理
gh api "repos/openclaw/openclaw/contents/scripts/make_appcast.sh?ref=main" -q .content | base64 -d | grep -n -- '--channel'
gh api "repos/openclaw/openclaw/contents/apps/macos/Sources/OpenClaw/AppLifecycleSupport.swift?ref=main" -q .content \
  | base64 -d | grep -n -A8 'func allowedSparkleChannels'
# 历史上的标签：逐个 commit 取 raw 文件数 <sparkle:channel>
gh api "repos/openclaw/openclaw/commits?path=appcast.xml&per_page=100" -q '.[].sha'
```

| 包 | bundle id | short / build | Team | `SUFeedURL` | detected | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 2026.9.7 universal | `ai.openclaw.mac` | 2026.9.7 / 2609000790 | FWJYW4S8P8 | `…/main/appcast.xml` | stable | **UPDATE → 2026.9.8** | source structured: 3 entries; 54 items, headings [] |
| 2026.9.8 universal | 同上 | 2026.9.8 / 2609000890 | FWJYW4S8P8 | `…/main/appcast.xml` | stable | **up to date** | 同上 |
| 2026.9.8 arm64 | 同上 | 2026.9.8 / 2609000890 | FWJYW4S8P8 | `…/main/appcast-arm64.xml` | stable | **up to date**（下载地址为 arm64 zip） | 同上 |

三个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`、来源 `Notarized Developer ID`；`lipo -archs`：
universal 为 `x86_64 arm64`，arm64 包为 `arm64`。`channel-verify` 三个包都是 `winning source  Sparkle`、`deltas 0`、
`release history 3 entries`、`release notes 8483 chars inline, changelogURL <nil>`。
