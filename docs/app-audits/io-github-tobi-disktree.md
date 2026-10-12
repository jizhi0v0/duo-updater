# disktree

## 基本信息
- App: disktree — Rust + GPUI 的磁盘占用查看器（Linux / macOS / Windows）
- Bundle ID: `io.github.tobi.disktree`
- 仓库: `tobi/disktree`（MIT，默认分支 `main`）
- Team ID: **无（ad-hoc 签名）**。`codesign -dvvv`: `Signature=adhoc`、`TeamIdentifier=not set`、
  `Identifier=io.github.tobi.disktree`；`codesign --verify --deep --strict` 退 0；`spctl -a -t exec` rejected
- 观测版本: 0.11.0（2026-10-04 发布）；观测日期: 2026-10-12
- 自更新机制: 无。源码（v0.11.0）里没有任何更新检查，也没有 Sparkle / `SUFeedURL`
- 分发: 只有 GitHub Releases；没有 Homebrew cask（`brew info --cask disktree`: No Cask with this name exists）。
  也可从源码 `make install` 自建（厂商 Makefile 装进用户主目录下的 Applications 文件夹，ad-hoc 签名）
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。

## Channel 详情

只有一条轨。settled from source：`.github/workflows/release.yml`（`main`）在推 `v*` tag 时构建，tag 必须等于
`v` + `Cargo.toml` 的 version，否则失败；release 先建成 draft，Linux / macOS / Windows 六个构建都上传后才
`--draft=false --latest` 发布。没有 prerelease 流程，现有 5 个 release 都不是 prerelease。

## 更新检测
- 源: `tobi/disktree` GitHub Releases，`/releases/latest`
- 版本方案（settled from source：`xtask/src/bundle.rs` + `packaging/macos/Info.plist.in`）: `@VERSION@` 是
  `CARGO_PKG_VERSION`，同时写进 `CFBundleShortVersionString` 与 `CFBundleVersion`；tag `v0.11.0` → `0.11.0`。
  四个真包核对一致（0.10.1 / 0.11.0 × arm64 / x86_64）
- `versionPattern` `^v([0-9]+\.[0-9]+\.[0-9]+)$`（锚死，将来若出 `-rc` tag 也读不进来）
- 资产: 每个 release 12 个文件——Linux `tar.gz`、Windows `zip`、macOS `zip`，各两个 arch，各带 `.sha256` 旁文件。
  macOS 只有分 arch 的 zip，没有 universal：`disktree-<v>-aarch64-macos.zip`、`disktree-<v>-x86_64-macos.zip`
- install pattern `^disktree-[0-9]+\.[0-9]+\.[0-9]+-(?:aarch64|x86_64)-macos\.zip$`：只命中两个 macOS zip
  （单测 `DisktreeGitHubRuleTests.onlyTheMacZipsMatch` 用 v0.11.0 的真实 12 个资产名）。
  **`-macos` 这段是承重的**：变异测试把它放宽成 `-[a-z]+`，选择器在两种 arch 上都选中了 **Windows** zip
  （`VersionComparator` 把 `windows` 排在 `macos` 前面），测试转红
- 按架构选包: 资产选择器把 `aarch64` 认作 arm64、`x86_64` 认作 Intel。单测里 arm64 主机选
  `-aarch64-macos.zip`，Intel 主机选 `-x86_64-macos.zip`；Apple silicon 上 channel-verify 实测下载地址是
  `-aarch64-macos.zip`
- **没有 macOS 资产的 release（v0.9.0 / v0.9.1 只有 Linux）**: 读代码的结论是不会被当成更新。
  `GitHubReleasesSource.settle` 对设了 `installAssetPattern` 的 stable rule：`/releases/latest` 那一个 release
  没有匹配资产时改读 releases 列表（只留非 prerelease、非 draft），逐个往回走，跳过没有匹配资产的 release，
  回答最新一个有 macOS zip 的版本，并带一条 `installAssetMissing` 警告；连续超过
  `maxReleasesWithoutMacOSAsset`（5）个都没有才放弃，答 unknown 并记 recipe 健康失败，不会答「已是最新」。
  `carriesInstallableAsset` 对 v0.9.1 的资产为 false（单测 `linuxOnlyReleaseCarriesNoInstallableAsset`）；
  走回去的行为由通用测试 `GitHubAssetWalkBackTests`（`android-only` / `windows-zip-only` 两个形状）覆盖。
  另外厂商的发布流程是全部平台构建完才发布 draft，正常情况下不会出现缺 macOS 包的 latest

## 按架构 / 按 OS 分轨
- arm64 / x86_64 分包，各为单架构（`codesign -dvvv`: `Mach-O thin (arm64)` / `Mach-O thin (x86_64)`）
- `LSMinimumSystemVersion` = `11.0`（`bundle.rs` 的 `MACOSX_DEPLOYMENT_TARGET` 同值），四个真包一致

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 源码没有更新器 | release 只有整包 zip（2026-10-12 的 release 列表） | 无可消费的补丁 |

## Changelog
- 来源: GitHub Release body。`release.yml` 用 `gh release create --generate-notes`，正文是 GitHub 自动生成的
  `## What's Changed`（每个合并的 PR 一条 `* <标题> by @user in <PR 链接>`）+ `## New Contributors` +
  `**Full Changelog**` 链接。v0.9.x 的正文只有 `Full Changelog` 一行（这两个 release 也没有 macOS 包）
- 结构化（2026-10-12，channel-verify `changelog pane`）:
  `source structured: 1 entries; newest 0.11.0: 23 items, headings []; first items ["Integrate Windows scanning, drive picker", "build: pin the toolchain so a fresh clon", "Steam libraries on a second drive show a"]`
- 小节: 厂商没有自己的分类小节，只有 GitHub 的一个 `What's Changed`；`GitHubMarkdownParser` 只在至少两个合格小节时
  才保留标题，所以 `headings []` 是正确结果，不是被压平（标题文字没有混进条目）。`New Contributors` 被跳过，
  `by @user in …` 后缀被去掉。23 条 = v0.11.0 `What's Changed` 下的 23 个 PR
- 条目是 PR 标题，混有 Windows / Linux 的改动（厂商一个 release 发三平台）
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **digest-only**（`installTrust: .publishedDigestOnly`）——用户在设置 → 通用里打开
  「无开发者签名的 app 按文件哈希一键更新」才可用；关闭时只检测
- 格式: zip，里面只有 `disktree.app`（9 个条目，没有 `._*`）；bundle 里没有嵌套 app、framework、XPC 或 helper，
  `Contents/MacOS` 只有一个 `disktree` 可执行文件
- 签名（settled from source：`release.yml` + `xtask/src/bundle.rs`）: 只有仓库配了 `MACOS_CERTIFICATE` 等 secrets 时
  才用 Developer ID 签名并公证，否则 `codesign --force --sign -`（ad-hoc，不带 `--identifier`，标识取自 Info.plist）。
  0.10.1 与 0.11.0 都是 ad-hoc，签名标识两版都是 `io.github.tobi.disktree`（门 4 稳定）。`Info.plist.in` 注释写明
  bundle id 不会改（改了用户要重新授予完全磁盘访问）
- 条件核对（2026-10-12，0.10.1 / 0.11.0 × arm64 / x86_64 共 4 个包）: 封印 `--deep --strict` 退 0；签名标识
  `io.github.tobi.disktree`；short == tag；GitHub 为每个资产发布 `digest`，与下载后 `shasum -a 256` 逐一相同，也与
  厂商的 `.sha256` 旁文件相同:

  | 资产 | 字节 | sha256 |
  |---|---|---|
  | `disktree-0.11.0-aarch64-macos.zip` | 3995990 | `942f2508fbbbd6901f796494492b16250d52227155b0ab59f6a5a446b033600b` |
  | `disktree-0.11.0-x86_64-macos.zip` | 4310671 | `16ddba6c3d983651cb6389d1c7fd6a070ba443aafcf03c2bc857e35e73b43f4d` |
  | `disktree-0.10.1-aarch64-macos.zip` | 3888471 | `90381628fdd0fc5c87aa32ba003ee85f2fb5eb496fab7aa1ee16428aaf7d9eca` |
  | `disktree-0.10.1-x86_64-macos.zip` | 4200605 | `9955a0da39630296aef5709114979d79c8eb6f7e045bf67a056e490e1d3c4b96` |

- 生产闸在真包上（2026-10-12，临时测试，跑完已删）: 真实 rule 经 `GitHubReleasesSource.latestVersion` 对 0.10.1
  答 `0.11.0`、`-aarch64-macos.zip`、`expectedSHA256` = 上表的值、`publishedDigestOnly`；
  `SignatureVerifier.verifyPublishedDigest` 对真 zip 通过；`verifyInstallArtifact`（0.10.1 → 0.11.0，digest 路线）
  通过；翻转一个字节的 zip → `publishedDigestMismatch`；把 0.10.1 的 bundle 当 0.11.0 → `infoPlistVersionMismatch`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，README 叫用户从这里下载）
- 端到端: **未跑**——真机 `duo install` 由维护者在本 agent 之后串行进行（并行 agent 不碰 `/Applications` 与 CLI）
- 阻塞: 无

## 已知问题
- **厂商改用 Developer ID 后会断一次。** `release.yml` 已备好签名 + 公证步骤，只差仓库 secrets。一旦启用，
  装着 ad-hoc 旧版的用户一键会被 `teamIdentifierAppeared` 拒绝（信任只升不降），要手动更新一次；rule 也要改回
  默认的 Team-ID 路线。
- **完全磁盘访问授权可能每次更新后失效（未验证）。** ad-hoc 签名每次构建 cdhash 都变；app 要靠完全磁盘访问
  才能看全磁盘。更新后授权是否仍被认可没有实测。这与谁来装无关，厂商自己的手动更新路径一样。
- 从源码 `make install` 自建的副本（厂商 Makefile 装进主目录下的 Applications 文件夹，并把
  `~/.local/bin/disktree` 链到 bundle 里的可执行文件）bundle id 与签名标识都相同，有更新时一键会换成 release 构建；链接指向的路径不变，仍然有效。

## 建议下一步
1. 真机端到端（维护者）: 0.10.1 arm64 → `duo install`，设置关闭时应被拒、打开后 `installed`。
2. 厂商仓库若出现 Developer ID 签名的 release（`codesign -dvvv` 有 TeamIdentifier），把 rule 改为默认 `installTrust`。

## 如何复验
```
gh api repos/tobi/disktree/releases --jq '.[] | .assets[] | select(.name|test("macos.zip$")) | "\(.name) \(.digest)"'   # 对照 shasum -a 256
ditto -x -k disktree-0.10.1-aarch64-macos.zip old/ && ditto -x -k disktree-0.11.0-aarch64-macos.zip new/
swift run --package-path application-test channel-verify old/disktree.app   # → winning source GitHub, UPDATE → 0.11.0
swift run --package-path application-test channel-verify new/disktree.app   # → up to date
codesign -dvvv new/disktree.app 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier'
```

channel-verify 原文（2026-10-12，Apple silicon，0.10.1 arm64）:
```
    winning source  GitHub
    latest          0.11.0
    download        https://github.com/tobi/disktree/releases/download/v0.11.0/disktree-0.11.0-aarch64-macos.zip
    release notes   0 chars inline, changelogURL https://github.com/tobi/disktree/releases/tag/v0.11.0
    changelog pane  source structured: 1 entries; newest 0.11.0: 23 items, headings []; first items ["Integrate Windows scanning, drive picker", "build: pin the toolchain so a fresh clon", "Steam libraries on a second drive show a"]
    status          UPDATE → 0.11.0
```
0.11.0 arm64 同样 `winning source GitHub`、`status up to date`。
