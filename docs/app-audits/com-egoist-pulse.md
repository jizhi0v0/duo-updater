# Pulse（egoist）

## 基本信息
- App: Pulse — 活动监视器（Mac / Windows / Linux），用 egoist 的 Go GUI 工具包 mygo 写成
- Bundle ID: `com.egoist.pulse`
- 仓库: `egoist/pulse-feedback`（只放 issue 和 release 资产，没有源码）
- Team ID: `GJE9R5VE87`（Developer ID + 公证；0.1.4、0.1.5 的 dmg 与 0.1.11、0.1.12 的 tar.gz 相同）
- 观测版本: 0.1.12（`CFBundleVersion` 同为 `0.1.12`）；观测日期: 2026-10-13（首次审计 2026-10-10，0.1.5）
- 自更新机制: 自研（mygo `internal/update`）。二进制里写死
  `https://github.com/egoist/pulse-feedback/releases/latest/download/update-darwin-arm64.json`，manifest 给出
  `version`、`notes`、`date`、整包 `url`（`pulse-<v>-darwin-arm64.tar.gz`）、ed25519 `signature`，以及从上一版起的
  `deltas`（`previous[]` 列更早的整包）。启动后检查一次，写 `~/Library/Application Support/Pulse/updater.json` 的 `lastCheck`。
  无 Sparkle、无 `SUFeedURL`、无 electron-builder 配置
- 分发: GitHub Releases；官网 `https://pulse.egoist.dev/download?platform=mac` 302 到同一个 release 的
  `Pulse.<v>.arm64.dmg`。没有 Homebrew cask、没有 MAS
- **没有 macOS CLI。** release 里的 `install.sh`（`curl … | sh`）装的是 Linux 版 GUI 到 `~/.local/pulse.app`，脚本
  `command_name=''`，不链任何命令；在 macOS 上第一步就退出：`install.sh: Pulse installs on Linux`（exit 1，实测）。
  官网也没有命令行安装说明

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✗（已换掉，见下） | ✓ |

当前生效源: **Vendor**（channel-verify 实测，2026-10-13）。2026-10-10 接入时走 GitHub（`Pulse.<v>.arm64.dmg`），
2026-10-13 换成 app 自己的 MyGo manifest，与 Moshi Go 同一套机制（原因见「更新检测」）。`GitHubReleasesSource` 在
`SourceStack` 里排在 `VendorProbeSource` 前面，两者不能并存，所以 GitHub 规则删掉了。

## Channel 详情

只有一条轨。9 个 release（v0.1.4–v0.1.12，2026-10-13）没有 prerelease 或 draft；manifest 没有渠道字段；二进制只认一个
`update-darwin-arm64.json` 地址。没有源码可读，单轨结论来自 release 列表与 manifest，不是 settled from source。

## 更新检测
- 源: VendorProbe，`https://github.com/egoist/pulse-feedback/releases/latest/download/update-darwin-arm64.json`
  （app 自己更新器读的同一个地址；`releases/latest/download/` 是 GitHub 的「最新 release」别名，302 到当前 release 的资产）
- 版本 / 日期 / 下载地址都取 manifest 顶层那一条；pattern 与 Moshi Go 相同，带 `(?!"deltas"|"previous")` 防越界，
  因为 `previous[]` 也有 `version` / `url`。顶层 `url` 是绝对地址且带版本 tag
  （`…/releases/download/v0.1.12/pulse-0.1.12-darwin-arm64.tar.gz`），不是会移动的 `latest` 别名，所以探测时读到的版本
  和安装时下的文件不会错位
- `version` 等于 `CFBundleShortVersionString` 也等于 `CFBundleVersion`（0.1.11、0.1.12 实测）
- 为什么从 GitHub dmg 换过来（2026-10-13）:
  1. **增量**: manifest 的 `deltas[]` 现在能吃（#1039 的 `MyGoManifest` / `MyGoDelta`）；0.1.11→0.1.12 补丁 1.3 MB，全量 6.3 MB
  2. **厂商签名**: 整包和补丁都验 MyGo 的 Ed25519 签名（`myGoPublicKey`），在 Team ID 闸之外再加一道。GitHub 资产
     `digest` 只证明和 GitHub 上的文件一样，不证明出自厂商的 key
  3. **和 app 自己的更新器装同一种包**（`.tar.gz`）。由此推断一键装过的副本以后 app 自己更新也能走 delta——**未验证**
     （没让 Pulse 自己的更新器跑过一次补丁）
- 代价:
  - 从官网 dmg 装的副本第一次一键要下补丁 + 全量（7.6 MB，GitHub dmg 路线是 4.8 MB），原因见「增量更新」；之后就是 tar.gz 布局
  - **Release Log 不再回填历史**: `GitHubReleasesSource` 会把整个 release 列表交给 Release Log（`releaseHistory`），
    VendorProbe 只给最新一条（带 manifest 的精确 `date`）。Pulse 一天能发好几版（2026-10-10 一天 0.1.4→0.1.11），
    两次检查之间的中间版本不会进 Release Log。changelog 不受影响（下面的 ChangelogRecipe 读整个 release 列表）
  - 探测不走 GitHub API，不吃匿名 API 限流（这一条是好处）

## 按架构 / 按 OS 分轨
- 只有 Apple silicon: `lipo -archs` = `arm64`，release 里没有 Intel dmg 或 darwin-amd64 包。Intel Mac 装不上
  Pulse，也就不会有需要提醒的 Intel 安装
- `LSMinimumSystemVersion` = `12.0`（0.1.4、0.1.5 相同）；manifest 不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | **能（已接入，2026-10-13）** |
| 证据 | 二进制含 mygo `update.Delta` / `update.delta (%d passes)` / `damaged delta update` | 2026-10-13 manifest（0.1.12）`deltas[]` 三条: from 0.1.11（1301845 B）、0.1.10（1296143 B）、0.1.8（1310361 B），全量 6343718 B | `MyGoManifest` 从同一个 body 读出 `deltas[]`，`MyGoDelta` 在进程内应用（#1039，Moshi Go 同一套） |

- 格式: `mygo delta 1`，与 Moshi Go 相同（格式 settled from source 见 [Moshi Go 审计](app-getmoshi-desktop.md)；Pulse 自己没有源码）。
  补丁真包用生产代码 `MyGoDelta.apply` 应用，结果见下
- **只有从 `.tar.gz` 装的副本能吃 delta**（2026-10-13 实测）: 厂商 0.1.11 和 0.1.12 的 `.tar.gz` 都比同版本 dmg 多一个
  `Contents/CodeResources`（0.1.11 为 1653 B），其余 `diff -r` 一致。0.1.11→0.1.12 补丁:
  - 打在 tar.gz 解出的 0.1.11 上 → 成功，产物与厂商 0.1.12 tar.gz 的 bundle `diff -r` 一致、权限一致，
    `codesign --verify --deep --strict` 通过，`spctl` `Notarized Developer ID`，Team `GJE9R5VE87`
  - 打在 dmg 挂载出的 0.1.11 上 → `MyGoDelta.Failure.madeWrong("Contents/CodeResources")`；安装随即退回全量包
    （端到端字节数见「一键安装」）
- 签名: 补丁 0.1.11→0.1.12 的 `signature` 用 recipe 的 key 验过（`SignatureVerifier.verifyMyGoSignature`，签的是文件 SHA-256），
  换成 Moshi 的 key 验不过（对照）
- 0.1.9 没有补丁（`deltas[]` 跳过了它），装着 0.1.9 的副本直接下全量

## Changelog
- 来源: `ChangelogRecipe`，`api.github.com/repos/egoist/pulse-feedback/releases?per_page=40`，`structuredFormat: .gitHubReleases`。
  release 正文是 `- ` 列表，与 manifest 的 `notes` 同文；manifest 只带最新一版的 notes，所以历史从 release 列表读。
  换源前 changelog 由 `GitHubReleasesSource` 顺带给出；换成 VendorProbe 后它不再跑，所以要单独的 recipe
- 结构化（2026-10-13，channel-verify `changelog pane`，从 0.1.11 起）: `recipe changelog:com.egoist.pulse:stable: 9 entries;
  newest 0.1.12: 3 items, headings []; first items ["An Apps page, on a Mac, lists what is in", "About This Mac moves to ⌘0, as Apps take",
  "The processes table's columns no longer "]`（9 条 = 当时全部 9 个 release）
- 跟随 channel: —（单轨）
- Recipe 状态: 已有

## 一键安装
- 状态: **支持**
- 格式: `.tar.gz`（manifest 顶层 `url`）；解出的 `Pulse.app` 只有一个主可执行文件，没有嵌套 app、helper 或 LaunchAgent
  （与 dmg 内的 bundle 只差一个 `Contents/CodeResources`）
- 校验: manifest 不发摘要，没有 `checksumPattern`。整包和补丁都验 MyGo 签名（Ed25519，签文件的 SHA-256），
  `myGoPublicKey` = `WzJsOGNIuf6mcEqo5ff8jub+NoQQOEk4JXreLPYjgyQ=`。0.1.12 整包和 0.1.11→0.1.12 补丁的签名都用它验过，
  用 Moshi 的 key 验不过（对照）。声明了 key 就必须有能验过的签名：补丁验不过就退回全量，整包验不过就终止安装
  （`VendorInstaller`，与 Moshi Go 同一条路径）
- **读的是**: 人人可手动下载的 GA。manifest 无灰度字段，每个副本读同一个文件；`.tar.gz` 和 dmg 挂在同一个公开 release 上
- 端到端（2026-10-13，`make cli` 后；0.1.11 → 0.1.12）:
  - 不运行，dmg 装的 0.1.11: `duo check` `0.1.11 → 0.1.12 [Vendor, in-place]` → `duo install --yes --json` `installed`，
    `bytesDownloaded: 7645563`（= 补丁 1301845 + 全量 6343718：补丁在 `Contents/CodeResources` 上失败、退回全量），11.3 s
    → 0.1.12 / `0.1.12`、inode 变、`--deep --strict` 通过、`spctl` Notarized Developer ID、Team `GJE9R5VE87`、
    与厂商 0.1.12 tar.gz 的 bundle `diff -r` 一致、`duo backups` 有 0.1.11
  - 不运行，tar.gz 装的 0.1.11: `installed`，`bytesDownloaded: 1301845`（只下补丁），9.2 s → 0.1.12，签名 / 公证 / Team
    同上，与厂商 0.1.12 `diff -r` 一致
  - 运行中，dmg 装的 0.1.11: 启动后它立即检查了更新（`updater.json` 的 `lastCheck` 更新），60 s 内磁盘 bundle 不变、
    没有暂存包。`duo install --yes --json` `installed`（7645563 B，10.2 s）→ `duo restart pulse` → 新进程跑 0.1.12，
    之后 10 s 磁盘保持 0.1.12；签名 / 公证 / Team 同上
- 阻塞: 无

## 已知问题
- **dmg 装的副本第一次一键要多下一个补丁。** 官网下载给的是 dmg，而补丁是对着 `.tar.gz` 布局切的，必然在
  `Contents/CodeResources` 上失败（实测见「增量更新」）；失败的补丁也计入流量（7.6 MB vs 全量 6.3 MB）。装过一次之后是
  tar.gz 布局，往后走补丁。Moshi Go 同样如此
- **自更新默认要用户确认。** 发现新版后弹 Sparkle 式的「Software Update」窗口（release notes + Skip This
  Version / Remind Me Later / Install Update），底部的「Automatically download and install updates in the
  future」默认不勾（2026-10-10 截图，0.1.4 → 0.1.5）。所以默认设置下 60 s 内只检查、不下载，与上面两次运行中实测一致。
  二进制里有 `automaticChecks` / `automaticDownloads` / `skippedVersion` 字串，勾选状态大概率写进
  `updater.json`——**未拨开关验证**。
- **勾了自动安装后的碰撞没测。** manifest 地址写死在二进制里，找不到让它暂存更旧版本的覆盖开关；它暂存的只会是
  duo 要装的同一个版本，碰撞即便发生也看不出来。
- **厂商换 MyGo key 时一键整体失效**，直到 recipe 的 key 更新；更新提示照常显示。与 Moshi Go 相同，理由见其审计
- **Release Log 不回填中间版本**，见「更新检测」的代价
- `install.sh` 不是 macOS 的 CLI，见「基本信息」。若以后 mygo 给 macOS 加命令行入口，需要重新审计。

## 建议下一步
1. 出现 Intel 包（`update-darwin-amd64.json`）时，加第二个 probe 并用 `hostRequirement` 分架构。
2. （可选，未做）安装前若已装 bundle 缺 `Contents/CodeResources` 就跳过 MyGo 补丁，省掉 dmg 副本那次必败的补丁下载。
   会影响 Moshi Go 与 Pulse 两个 recipe，属于 `DeltaApplier` 的改动，不在本次范围。

## 如何复验
```
# GET https://github.com/egoist/pulse-feedback/releases/latest/download/update-darwin-arm64.json → version 0.1.12（2026-10-13）
swift run --package-path application-test channel-verify <Pulse.0.1.11.arm64.dmg>
#   detected channel → stable；VendorProbe latest 0.1.12，download …/v0.1.12/pulse-0.1.12-darwin-arm64.tar.gz
#   winning source Vendor；deltas 3；changelog pane → recipe …: 9 entries; newest 0.1.12: 3 items
swift run --package-path application-test feed-discover <Pulse.0.1.5.arm64.dmg>    # → no Sparkle and no electron-builder update config（2026-10-10）
sh install.sh                                                                        # macOS 上 → install.sh: Pulse installs on Linux
# tar.gz vs dmg（0.1.11、0.1.12 各一次）: diff -rq → 只有 tar.gz 有 Contents/CodeResources
# 补丁（生产代码 MyGoDelta.apply，临时测试，跑完删除）:
#   tar.gz 解出的 0.1.11 + pulse-0.1.11-to-0.1.12-darwin-arm64.delta → 成功，diff -r 厂商 0.1.12 一致
#   dmg 挂载出的 0.1.11 + 同一补丁 → madeWrong("Contents/CodeResources")
# 端到端: ditto <0.1.11 bundle> /Applications/ → duo install pulse --yes --json
#   dmg 布局 → bytesDownloaded 7645563；tar.gz 布局 → bytesDownloaded 1301845
```

## 历史与实测
- 2026-10-10 接入，GitHubReleaseRule 读 `Pulse.<v>.arm64.dmg`（#1148）。当时审计把增量写成「不能消费，`DeltaApplier`
  只吃 Sparkle `BinaryDelta`」——写的时候已经过时：#1039（2026-10-07）已经为 Moshi Go 加了原生 MyGo 补丁与签名校验。
- 2026-10-13 换成 MyGo manifest 的 VendorProbe（本审计）。manifest 0.1.12（`date` `2026-10-11T10:12:38Z`），
  `deltas[]` from 0.1.11 / 0.1.10 / 0.1.8，`previous[]` 0.1.11 / 0.1.10；release 共 9 个（0.1.4–0.1.12，0.1.4–0.1.11 同在 2026-10-10）。
