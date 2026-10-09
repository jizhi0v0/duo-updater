# Jan

审计 2026-10-08（重审；2026-08-17 那版只核对了一个真包的 bundle 身份，没在新旧两个包上跑生产检测，
没查 nightly / beta、没看 changelog 面板，也没跑一键）。2026-10-09 补跑 nightly 一键端到端两轮，见「一键安装」。

## 基本信息
- Bundle ID: `jan.ai.app`（stable）。nightly 是**另一个** bundle id `jan-nightly.ai.app`，beta 构建脚本给
  `jan-beta.ai.app`（见 Channel 详情）
- Team ID: `F8AH6NHVY5` — Developer ID Application: JAN AI PTE. LTD.（0.8.4、0.8.5、nightly 0.8.4-5203
  三个真包相同，均 `Notarized Developer ID`；2026-10-09 端到端用的 nightly 0.8.4-5195 也是这个 Team）
- 观测版本: stable `0.8.5`（2026-10-08 发布，short = build）、上一版 `0.8.4`；nightly `0.8.4-5203`。
  `LSMinimumSystemVersion` 10.13；主程序 universal（`x86_64 arm64`）
- 自更新机制: Tauri updater（`tauri.conf.json` `plugins.updater.endpoints` =
  `https://apps.jan.ai/update-check`、`https://github.com/janhq/jan/releases/latest/download/latest.json`；
  更新包是 `Jan.app.tar.gz` + minisign 签名）
- 主程序从 0.8.5 起改名：`Contents/MacOS/Jan` → `Contents/MacOS/Jan-Desktop`（0.8.5 发布说明也写了）；
  `bun`、`uv` 仍在 `Contents/MacOS/`，0.8.4 有的 `jan-cli` 在 0.8.5 里没有了
- Homebrew: cask `jan`，`auto_updates: true`，版本 `0.8.4`（2026-10-08，比 GitHub 晚当天这一版）
- 开源: `janhq/jan`（默认分支 `main`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，让位） | — | ✓ 一键 | — |
| **nightly**（`jan-nightly.ai.app`） | — | — | — | — | 已接入：一键 `.app.tar.gz`，每个架构一条（`delta.jan.ai/nightly/latest.json`） |
| **beta**（`jan-beta.ai.app`） | — | — | — | —（最后一个 beta prerelease 是 2025-06） | ✗ 现无公开 feed |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`GitHubReleasesSource`，规则在
`Recipes/jan-ai-app.swift`）；nightly → **VendorProbe**（`.nightly` 渠道，每个架构一条 recipe，各带 `hostRequirement`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `jan.ai.app` | 独立 | — | tag `vX.Y.Z` | ✓ |
| nightly | `jan-nightly.ai.app` | 独立（Pattern A） | bundle id；app 名 `Jan-nightly`；`detected channel → nightly` | 独立 feed `delta.jan.ai/nightly/latest.json` | 已接入（VendorProbe，见下） |
| beta | `jan-beta.ai.app`（构建脚本，未见真包） | 独立 | — | `delta.jan.ai/beta/latest.json` | ✗ feed 403 |

**渠道怎么分（settled from source: `.github/scripts/rename-tauri-app.sh` 与
`.github/workflows/template-tauri-build-macos.yml` on `main`）:** 非 stable 构建在 CI 里改写
`tauri.conf.json`：`productName = "Jan-<channel>"`、`identifier = "jan-<channel>.ai.app"`、
`mainBinaryName = "Jan-Desktop-<channel>"`，Info.plist 里的 `jan.ai.app` 也替换掉。updater endpoints
改为 nightly：`apps-nightly.jan.ai/update-check` + `delta.jan.ai/nightly/latest.json`；其他非 stable：
`delta.jan.ai/<channel>/latest.json`。所以每条轨是独立安装，没有应用内开关，也不存在「同一个 app
切渠道」的偏好文件。

**实测（2026-10-08）:**

- GitHub release 列表（最近 40 条）：prerelease 只有 `v0.5.15-rc5-beta` … `v0.5.18-rc6-beta`（最后一条
  2025-06-16）。0.6.0 之后没有 prerelease。规则的 tag 正则 `^v([0-9]+(?:\.[0-9]+)+)$` 不匹配这些 tag
- nightly 不发到 GitHub：`delta.jan.ai/nightly/latest.json` 200，`"version": "0.8.4-5203"`，
  `pub_date 2026-09-30T20:56:54.516Z`，mac 两个平台都指向 `Jan-nightly_0.8.4-5203.app.tar.gz`；
  `apps-nightly.jan.ai/update-check` 回同一份。0.8.5 发布说明的 “Nightly” 节给出的
  `app.jan.ai/download/nightly/mac-universal` 302 到 `delta.jan.ai/nightly/Jan-nightly_0.8.4-5203_universal.dmg`
- nightly 真包（`.app.tar.gz`，105,001,696 B，SHA-256 `99cb56cc…decd`）：bundle id `jan-nightly.ai.app`，
  short = build = `0.8.4-5203`，与 feed 的 `version` 逐字相同；`channel-verify`：`inferred nightly`，
  `winning source <none>`，`status unknown (no source answered)`（接入 VendorProbe 之前；之后 5203 → Vendor up to date）
- `delta.jan.ai/beta/latest.json` 403（S3 `AccessDenied`），没有可读的 beta feed

## 更新检测
- 源: `GitHubReleasesSource`，`janhq/jan`，tag `v0.8.5` ↔ Info.plist `0.8.5`
- `feed-discover`（0.8.5）: `—  no Sparkle and no electron-builder update config`（Tauri updater 不在它的识别范围，
  由 GitHub 规则覆盖）
- 资产（v0.8.5，11 个）: `jan-mac-universal-0.8.5.zip`（规则选这个）、`Jan_0.8.5_universal.dmg`、
  `Jan.app.tar.gz`（Tauri 自更新用）、`latest.json`，另有源码 / 依赖归档与 Linux / Windows 包。资产正则
  `^jan-mac-universal-[0-9.]+\.zip$` 锚定得住
- Jan 自己的检查 `apps.jan.ai/update-check`（响应头 `x-served-by: jan-analytics`）回的 JSON 与 GitHub 的
  `latest.json` 版本、`pub_date` 相同（0.8.5，`2026-10-08T04:11:16.638Z`）；请求里没有设备参数

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无（推断） | 无 | 不适用 |
| 证据 | Tauri updater 只按 `platforms.<target>.url` 下整包；没在二进制里找差分实现（推断，未逐项核） | `latest.json` 每个平台一个整包 URL（mac 是 `Jan.app.tar.gz`），没有 patch 字段 | — |

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 请求不带设备标识（endpoints 是固定 URL） | 否：`apps.jan.ai/update-check` 与 GitHub `latest.json` 一致 | 不需要 |
| 按架构 / 按 OS 分轨 | mac 一个 universal 包 | **0.8.5 起本地模型只在 Apple Silicon 上跑**：随包的 `Contents/Resources/resources/bin/jan-llama-worker` `lipo -archs` = `arm64`，主程序仍是 universal；发布说明原话 “If you rely on local models on an Intel Mac, stay on v0.8.4” | **能**：包里没有可读的「Intel 不该升」信号，所以写在规则上——GitHub 规则的 `architectureRequirement`（0.8.5 起仅 arm64），Intel Mac 停在 0.8.4（见已知问题） |
| 自更新器会不会和我们抢 | Tauri updater；Jan 是否后台自动下载 / 安装没查（未验证） | 同一个版本 | stable 第二轮未跑；nightly 第二轮已跑（见「一键安装」），退出后没有被换回 |

## Changelog
- 来源: GitHub release 正文（Markdown）
- 结构化: `changelog pane  source structured: 1 entries; newest 0.8.5: 38 items, headings ["Migration", "Bug Fixes", "Known issues", "Nightly", "Engineering"]; first items ["macOS and Linux: a `jan` that v0.8.4 ins", "Windows: updating from v0.8.4 removes th", "llama.cpp **Parallel Sequences**: a valu"]`
  （0.8.4 与 0.8.5 两个包同一行）
- **结构化了，但丢了正文里最要紧的部分。** 用生产解析器（`GitHubMarkdownParser.parse`，临时测试，已删）逐块看：
  43 块 = 5 个 heading + 38 条 note，38 正好是正文里 `- ` 开头的行数。没进面板的是所有**非列表段落**：
  - 第一节 `## This release is fixes only` 整节（标题和两段说明都没有）
  - `## Migration` 下的六段粗体引言：llama.cpp 改为随包、**Intel Mac 不再能跑本地模型**、可执行文件改名
    `Jan-Desktop`、`jan` CLI 不再随 app、Local API Server 的 Trusted Hosts、`bash` 工具改名 `shell`，
    以及 “Settings that change on update” 这句引导语
  面板里 Migration 下只剩它们之间夹着的 6 条列表项
- 判断（修复前）: 这是 `GitHubMarkdownParser` 对「段落 + 列表混排」正文的通病，不是 Jan 特有；为 Jan 单写
  `ChangelogRecipe` 不对路。官网 `https://www.jan.ai/changelog` 存在，没评估其结构
- 跟随 channel: nightly 没有 release 正文（feed 的 `notes` 为空串）
- Recipe 状态: 不需要 per-app recipe；解析器的段落问题建议另开（见「建议下一步」）

## 一键安装
- 状态: 支持（GitHub 规则带 `installAssetPattern` + `installerKind: .zip`）
- 端到端（2026-10-08，第一轮，不启动）: 0.8.4 → `duo check` `update 0.8.5`、`source GitHub`；`duo install /Applications/Jan.app --yes --json` → `installed`、`route vendor`、`bytesDownloaded 102310987`（GitHub zip），约 12 s。装后 0.8.5，strict 通过，`Notarized Developer ID`，Team `F8AH6NHVY5`；与厂商 0.8.5 zip 逐文件比 SHA-256，27 个文件全部相同（包内无软链接）。`duo restart` 与主程序改名的交互没有测（没有启动 app）
- nightly 端到端（2026-10-09，CLI 由当天 `origin/main` `make cli` 构建）: 旧版用 `delta.jan.ai/nightly/Jan-nightly_0.8.4-5195.app.tar.gz`
  （feed 只列最新的 5203，5195 的同形 URL 仍 200），解包后 `ditto` 进 `/Applications`。`duo check` →
  `Jan-nightly  0.8.4-5195  →  0.8.4-5203  [Vendor, in-place]`。
  - 第一轮（不运行）: `duo install /Applications/Jan-nightly.app --yes --json` → `outcome installed`、`route vendor`、
    `bytesDownloaded 105001696`（feed 的 `.app.tar.gz`）。装后 0.8.4-5203，strict 通过，Team `F8AH6NHVY5`
  - 第二轮（运行中）: 换回 5195、启动，运行约一分钟后 `duo install` → 同样 `installed`；运行中的进程仍是旧 PID，
    `duo restart /Applications/Jan-nightly.app` → `restarted`，新 PID（主程序 `Jan-Desktop-nightly`，按 bundle 拉起正常）；
    正常退出后仍是 5203、strict 通过，`duo check --all` → `up to date`。子进程是否残留没查
- 格式: zip（universal，0.8.5 为 102,310,987 B）
- 校验: GitHub 资产 `digest`。下载 SHA-256 与 digest 相等：0.8.5 `dfd7b4f9…c8e1`、0.8.4 `2ae6e410…edf1`
- **读的是**: 人人可手动下载的 GA（GitHub 正式版，与 Jan 自己的 update-check 同一版本）
- Team: 0.8.4 / 0.8.5 同为 `F8AH6NHVY5`，`codesign --verify --deep --strict` 均退出 0
- 嵌套: `check-bundle.sh` 没列出 nested app；没有 `Contents/Library`、`Contents/Helpers`、`Contents/Frameworks`。
  `Contents/Resources/resources/bin/` 下有 `jan-llama-worker`、`mlx-server` 两个子进程程序；0.8.5 发布说明说
  Jan 自己的应用内更新会在安装前停掉引擎、MCP 服务器和 agent shell。duo 走正常退出时这些子进程会不会随之退出，
  没查（未验证）
- 阻塞: 无硬阻塞。两个要在端到端里看的点：主程序改名后 `duo restart` 是否按 bundle 正常拉起（预期按 bundle 启动、
  与可执行名无关，未验证）；子进程是否残留

## 已知问题
- **Intel Mac 停在 0.8.4（已处理）**：GitHub 规则带 `architectureRequirement`（0.8.5 起仅 arm64）。Intel Mac 上
  `/releases/latest` 指向 ≥0.8.5 时回退到 releases 列表（只取 stable），给 0.8.4 和它自己的 zip；列表上没有低于门槛的
  release 时是 `notApplicable`。厂商原话是有条件的：「If you rely on local models on an Intel Mac, stay on v0.8.4.」——
  0.8.5 在 Intel 上能启动、远程 / 自定义 provider 可用，只是 llama.cpp 本地模型不能加载；这个闸对只用远程 provider 的
  Intel 用户也停在 0.8.4（取保守一侧）。0.8.5 里 `jan-llama-worker`、ggml dylib、`mlx-server`、`bun`、`uv` 只有 arm64；
  0.8.4 里 `bun` / `uv` / `mlx-server` 已经只有 arm64、没有随包的 `jan-llama-worker`
- 面板仍不显示 `## This release is fixes only` 这一段（不在「迁移 / 注意」类标题下，有意不收）
- Homebrew cask 比 GitHub 慢（当天仍是 0.8.4）；cask 是 `auto_updates`，不影响检测

## 建议下一步
1. stable 一键第一轮已过（见「一键安装」），第二轮（app 运行中）未跑；nightly 两轮已过
2. （已做）nightly：VendorProbe 读 `delta.jan.ai/nightly/latest.json`，`.nightly` 渠道、每个架构一条 recipe（各带
   `hostRequirement`、只读本平台那一项），版本正则要求 `-<build>` 后缀；一键装 feed 给的 `.app.tar.gz`（Jan 自己的更新器装的
   就是它，feed 只有 minisign 签名、没有摘要，靠 Team 闸）；`ChannelProofRegistry` 登记 `.artifact("/nightly/Jan-nightly_")`。
   `VersionComparator` 实测：`0.8.4-5210 > 0.8.4-5203`、`0.8.5-5300 > 0.8.4-5203`、`0.8.4-10000 > 0.8.4-9999`、`0.8.4-5203 > 0.8.4`。
   `channel-verify`：5203 → Vendor up to date，5195 → `UPDATE → 0.8.4-5203`。一键端到端 5195 → 5203 两轮已跑（2026-10-09，见「一键安装」）
3. （已做）`GitHubMarkdownParser` 收「迁移 / 升级 / 破坏性变更 / 注意 / 已知问题 / 弃用」类标题下 1–2 段、无列表的说明，
   Migration 的粗体引言（含 Intel 警告）现在进面板。更宽的「只要一节只有段落就收」在 3,710 个 release 正文上会多出 58 个来源
   2,758 行样板话，所以没用；`This release is fixes only` 因此仍不进
4. （已做）Intel 推送：`GitHubReleaseRule.architectureRequirement`（见「已知问题」）

## 如何复验

2026-10-08。包从 GitHub release 资产和 `delta.jan.ai` 下载（`curl -fL --retry 5 -C -`），各放一个空目录；
zip / tar.gz 解包，不安装、不启动。

```bash
gh api "repos/janhq/jan/releases?per_page=40" -q '.[] | [.tag_name, .prerelease, .published_at] | @tsv'
gh api "repos/janhq/jan/contents/src-tauri/tauri.conf.json?ref=main" -q '.content' | base64 -d   # plugins.updater
gh api "repos/janhq/jan/contents/.github/scripts/rename-tauri-app.sh?ref=main" -q '.content' | base64 -d
curl -sS https://apps.jan.ai/update-check
curl -sS https://delta.jan.ai/nightly/latest.json
curl -sS -o /dev/null -w '%{http_code}\n' https://delta.jan.ai/beta/latest.json        # 403
curl -fL -o jan-mac-universal-0.8.5.zip https://github.com/janhq/jan/releases/download/v0.8.5/jan-mac-universal-0.8.5.zip
curl -fL -o jan-mac-universal-0.8.4.zip https://github.com/janhq/jan/releases/download/v0.8.4/jan-mac-universal-0.8.4.zip
curl -fL -o Jan-nightly_0.8.4-5203.app.tar.gz https://delta.jan.ai/nightly/Jan-nightly_0.8.4-5203.app.tar.gz
swift run --package-path application-test channel-verify <Jan.app>   # 三个包各跑一次
lipo -archs <Jan.app>/Contents/Resources/resources/bin/jan-llama-worker
```

以下是接入 nightly VendorProbe **之前**的实测（nightly 行之后是 Vendor，见「建议下一步」2）。

| 包 | bundle id | short / build | Team | detected | winning | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 0.8.4 zip | `jan.ai.app` | 0.8.4 / 0.8.4 | F8AH6NHVY5 | stable | GitHub | **UPDATE → 0.8.5** | source structured: 1 entries; 38 items, 5 headings |
| 0.8.5 zip | `jan.ai.app` | 0.8.5 / 0.8.5 | F8AH6NHVY5 | stable | GitHub | **up to date** | 同上 |
| nightly tar.gz | `jan-nightly.ai.app` | 0.8.4-5203 / 同 | F8AH6NHVY5 | nightly | `<none>` | unknown (no source answered) | none |

三个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`（`source=Notarized Developer ID`）。
stable 两个包的 `download` 都是 `https://github.com/janhq/jan/releases/download/v0.8.5/jan-mac-universal-0.8.5.zip`。

**一键端到端预备（第一轮已用它跑通）:** 上一版用 `v0.8.4` 的 `jan-mac-universal-0.8.4.zip`（上表第一行），解包出的
`Jan.app` 就是要 `ditto` 进 `/Applications` 的那个。预期 `duo check` 报 update 0.8.5，
`duo install --yes --json` 走 `route vendor`（GitHub zip），先比 digest `dfd7b4f9…c8e1` 再过 Team 闸。

## 重审更正（相对 2026-08-17 版）
- 原文「Homebrew ✗」：cask 是有的（`jan`），只是 `auto_updates: true`，让位
- 原文只有 stable：nightly 是独立 bundle id 的另一条轨，有公开 feed，重审时 duo 报 unknown（同日已接入 VendorProbe）；beta 轨在构建脚本里存在、
  现在没有公开 feed
- 原文「GitHub release body」：现在有面板实测行，并查明非列表段落（含 Intel 警告）进不了面板
- 原文「一键 ✓」没有端到端证据；本次第一轮端到端已跑通（见「一键安装」）
- 新增：0.8.5 起 Intel Mac 失去本地模型；重审时 duo 照推，同日加了 `architectureRequirement`，Intel 停在 0.8.4
