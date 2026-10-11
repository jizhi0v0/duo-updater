# Moshi Go

Moshi 桌面端的原生重写（Go + Metal，终端用 libghostty-vt）。它接手了 bundle id
`app.getmoshi.desktop`；它取代的 Tauri 版是另一个 bundle id（`app.getmoshi.desktop.tauri`），见
[Moshi（Tauri）](app-getmoshi-desktop-tauri.md)。2026-10-10 起厂商经 Tauri 自己的 feed 把 Tauri 用户迁到 Moshi Go，
Tauri 副本由 `BundleIDMigration` 归到这个 bundle id 名下，用这里的 recipe 检查与一键更新。

## 基本信息
- Bundle ID: `app.getmoshi.desktop`
- Team ID: `FL442366Y7`（`Developer ID Application: Moshi Tech Limited`）
- 观测版本: `0.5.2`（官网 dmg）、`0.5.3`（feed 与 tar.gz），short == build；2026-10-07。feed `0.5.13`；2026-10-11
- 自更新机制: 自研（MyGo 框架的 `update` 包），读 `desktop-go/update-darwin-arm64.json`
- 开源: 否（官网无源码链接）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓ 一键      |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。

- Sparkle / electron-builder: 都没有，`feed-discover` 结论 `no Sparkle and no electron-builder update config`。
- Homebrew: 厂商的 tap `rjyo/homebrew-moshi` 只有 `moshi-hook`（CLI daemon）一个 formula，没有桌面 app 的 cask；
  官方 tap 也没有（`brew search --cask moshi` 无结果）。
- MAS: 官网的 App Store 链接是 iOS app，不是这个桌面端。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.getmoshi.desktop` | 独立（与 Tauri 版不同 id） | — | — | ✓ |

官网把 Moshi Go 标成 "Alpha"（"Try the Go rewrite: Moshi Go … for macOS Alpha"），但它是一个独立产品：
自己的 bundle id、自己的 feed，feed 里没有第二条轨道。所以对这个 bundle id 来说渠道就是 stable；
`ReleaseChannel.detect()` 在真包上也得出 stable（无 `KSChannelID`、id 无后缀、显示名无渠道词）。

**会不会推给 Tauri 版的安装？** 会，而且是有意的（2026-10-11 起）。两个 id 从没共用过：Tauri 版从 0.1.0 到最后一版
0.4.23 都是 `app.getmoshi.desktop.tauri`（下载 0.1.0 / 0.2.0 / 0.3.0 / 0.4.0 / 0.4.10 / 0.4.17 / 0.4.18 / 0.4.23 的
`.app.tar.gz` 逐个读 Info.plist 核对），Moshi Go 从 0.5.0 起是 `app.getmoshi.desktop`。但厂商已经让 Tauri 的
`desktop/latest.json` 改发 Moshi Go（0.5.12，与本 feed 的 0.5.12 包 `diff -r` 一致），所以 `BundleIDMigration`
登记了 `app.getmoshi.desktop.tauri → app.getmoshi.desktop`（Team `FL442366Y7`，lastFrom 0.4.23，firstTo 0.5.0）：
版本低于 0.5.0 的 Tauri 副本拿这里的 recipe，闸 4 只放行这一个方向、这个 Team。证据与理由见
[Moshi（Tauri）](app-getmoshi-desktop-tauri.md) 的「一键安装」和「历史与实测」。

## 更新检测
- 源: `https://cdn.getmoshi.app/desktop-go/update-darwin-arm64.json`，app 二进制里写死的就是这个地址
  （同在二进制里的还有 `desktop-go/latest/manifest.json`）。只发 arm64：`update-darwin-amd64.json` 404，
  构建本身是 `Mach-O thin (arm64)`。
- 响应形状: 顶层是一个 release（`version` / `notes` / `date` / `url` / `size` / `signature`），后面跟
  `deltas[]` 和 `previous[]`；`previous[]` 里的旧版本也带 `version` 和 `url`。recipe 的三个 pattern
  都用 `(?:(?!"deltas"|"previous")[\s\S])*?` 回火，越不过这两个键，所以版本、日期、下载地址只能取自顶层
  release，与顶层键的先后顺序无关。notes 里出现的 `"previous"` 会被转义成 `\"previous\"`，不会误触发。
- 版本方案: feed `version` == `CFBundleShortVersionString` == `CFBundleVersion`（0.5.2、0.5.3 真包核对）。
- 按 OS 分轨: feed 不带 min/max system version；包的 `LSMinimumSystemVersion` 是 `13.0`，低于 DuoUpdater
  自己的下限（15.0），不需要 `hostRequirement`。
- 灰度: 无 rollout 字段，所有安装读同一份文件。
- 官网滞后: 2026-10-07 官网下载按钮仍指向 `Moshi Go 0.5.2.dmg`，feed 已是 0.5.3（`Moshi%20Go%200.5.3.dmg`
  在 CDN 上也存在）。recipe 不读官网。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | **能（已接入）** |
| 证据 | feed 的 `deltas[]` 就是给 app 自己的更新器用的 | 2026-10-07 的 feed 列了 `0.5.0/0.5.1/0.5.2 → 0.5.3` 三个 `.delta`（0.89–1.19 MB，全量 15.2 MB） | `MyGoManifest` 从同一个 body 读出 `deltas[]`，`MyGoDelta` 在进程内应用 |

- 格式（settled from source: `internal/update/delta.go`、`bsdiff.go` on `egoist/mygo` `main`，MIT）:
  `mygo delta 1\n` + 索引长度（uvarint）+ 索引（JSON，raw DEFLATE）+ 各文件数据。索引列出新 bundle 的整棵树：
  目录、链接、文件（mode / size / SHA-256）；文件要么从已装 bundle 原样复制、要么对已装文件打 bsdiff 式补丁、
  要么整份（DEFLATE）。`MyGoDelta` 是 `ApplyDelta` / `Patch` 的移植，校验照搬：路径必须是 `fs.ValidPath`、
  链接不得指出 app、数据长度必须正好铺满文件、每个文件的 size 和 SHA-256 必须对上。
- 测试夹具用 MyGo 自己的 Go 代码（`WriteDelta` / `Diff`，commit 49b7a7f）生成，并先用参考实现 `ApplyDelta`
  回放过（`MyGoDeltaTests`）。
- 真包: 三个真实 delta 分别应用到厂商 0.5.0 / 0.5.1 / 0.5.2 的 `.tar.gz` 解出的 bundle 上，产物与厂商 0.5.3
  bundle `diff -r` 一致、权限一致，`codesign --verify --deep --strict` 通过，`spctl` `accepted` /
  `Notarized Developer ID`，Team `FL442366Y7`（2026-10-07）。
- **只有从 `.tar.gz` 装的副本能吃 delta。** 厂商的 `.tar.gz` 里多一个 `Contents/CodeResources`（1674 B，
  与 `_CodeSignature/CodeResources` 内容不同），`.dmg` 里的同版本 bundle 没有它；而每个 delta 都从已装 bundle 的
  `Contents/CodeResources` 打补丁重建这个文件。所以从官网 dmg 装的副本应用 delta 会在这个文件上失败
  （`made Contents/CodeResources wrong`），安装随即退回全量包。一键装过一次（装的是 `.tar.gz`）或 app 自己更新过的副本，
  下次就能走 delta。
- 端到端（2026-10-07，`make cli` 后的 `duo install --yes --json`）:
  - `.tar.gz` 的 0.5.2 → `bytesDownloaded: 891233`，4.5 s；产物与厂商 0.5.3 `diff -r` 一致，签名 / 公证通过。
  - dmg 的 0.5.2 → `bytesDownloaded: 16118320`（= 891233 + 15227087，失败的 delta 也计入流量），9.2 s；
    产物同样与厂商 0.5.3 一致。
- 签名（settled from source: `internal/update/update.go` 的 `Verify`、`cmd/mygo/updates.go` 的 ldflags on `egoist/mygo` `main`）:
  feed 里每个 `signature` 都是 MyGo 的 Ed25519，签的是**文件的 SHA-256**，不是文件本身。公钥由
  `-X github.com/egoist/mygo.packageUpdateKey=…` 链进二进制，是一段裸字符串；发布的二进制是 stripped 的（符号表只剩 156 个，
  没有这个变量），周围也没有可定位的标记，所以从已装 app 读公钥只能靠扫描像 key 的字符串。因此**公钥写在 recipe 里**
  （`VendorInstallSpec.myGoPublicKey` = `iXWMulHl+4m/dByqrJ8a1YOzcDIBeUOPiZ/AFj6k4VI=`），由 `DeltaApplier.reconstruct`
  在应用前校验：有 key 就必须有能验过的签名，否则这次 delta 作废、退回全量包。
  **全量 `.tar.gz` 同样校验**：`MyGoManifest.archiveSignature` 只在 feed 顶层 `version` 等于解析出的版本、且顶层 `url`
  正好是要下载的那个文件时取它的 `signature`（`previous[]` 里旧归档的签名永不读取），`VendorInstaller` 在解包前、
  Team ID 闸之前验证。声明了 key 却找不到签名：安装直接拒绝（不退化成不校验），探测时报 `myGoSignatureNoMatch` 让夜扫先看到。
  - 取证（2026-10-07）: 二进制里所有 44 字符 base64 候选（8 个）里只有这一把能验过 0.5.2→0.5.3 delta 的签名；
    随后 feed 里全部 6 个签名（3 个 delta + 0.5.3/0.5.2/0.5.1 三个归档）都用它验过，且都只在「签 SHA-256」时成立，签原文时全部不成立。
  - 端到端红→绿见下面「如何复验」。
  - 厂商换 key（或不再发签名）的后果: delta 和全量包都验不过，**一键安装整体失效**，直到 recipe 的 key 更新；
    更新本身仍会显示。这是有意的：MyGo 自己的更新器（`updater.go` 的 `download` → `update.Verify`）用编译进已装 app 的 key
    校验每个文件，同样的情况下也会失败（报 "the update is not signed with the app's key"），MyGo 文档说丢 key 会让已装 app
    "strand"。所以 duo 的拒绝不比厂商自己的更新器更严。届时按上面的方法从新二进制里重新取 key。

## Changelog
- 来源: recipe —— `https://cdn.getmoshi.app/desktop-go/latest/manifest.json`，
  `{latest, releases[{version, notes, date}]}`，newest first，`notes` 是 Markdown。
  update feed 自己的 `notes` 只有当前一版，所以不用它。
- 结构化: `recipe changelog:app.getmoshi.desktop:-: 4 entries; newest 0.5.3: 4 items, headings []`
  （`channel-verify`，2026-10-07）。每条 notes 开头的 `## What's Changed` 是通用标题，不保留。
- 全量比对: 用生产 `ChangelogExtractor` 解析当天的 manifest，和 JSON 解码后的 notes 逐条对照，
  4 个条目、22 条，版本 / 日期 / 条目全部一致；`\u2318`（⌘）、`\u2026`（…）、`\"` 都被正确反转义，
  没有残留的 `**` 或反斜杠。
- 两处取舍:
  - 0.5.0 的条目以 `- **Drawn on the GPU.** The whole window…` 这种加粗导语开头。导语被吃掉，只留后面的句子：
    纯文本渲染下 `**` 会原样显示，而导语是后面句子的摘要。
  - 0.5.0 的 notes 在列表前有一段介绍性的散文（"Moshi for Mac is rewritten from the ground up…"），
    不是列表项，不进条目。
- 跟随 channel: 单渠道，不涉及。
- Recipe 状态: 已有。

## 一键安装
- 状态: **支持**
- 端到端（2026-10-07，`make cli` 后的 `duo`）:
  - 未运行: 从官网 0.5.2 dmg `ditto` 到 `/Applications`，`duo install --yes --json` →
    `{"applied":true,"bytesDownloaded":15227087,"outcome":"installed","route":"vendor"}`，约 11 s；
    之后 0.5.3 / 0.5.3，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted` /
    `Notarized Developer ID`，Team `FL442366Y7`，与厂商 tar.gz 解出的 bundle `diff -r` 一致，`duo backups` 有 0.5.2。
  - 运行中: 0.5.2 启动后，它的更新器没有暂存任何东西（0.5.2 起更新改为用户在设置里手动触发，
    新版本只点亮设置里的小圆点）。`duo install` → installed，`duo restart` → restarted，之后 12 s 内磁盘一直是 0.5.3、
    inode 不变。厂商更新器没有改 feed 地址的开关，造不出"暂存一个更旧版本"的对照，所以碰撞测试只覆盖了"它不暂存"这一种情况。
- 格式: `.tar.gz`（`moshi-go-<ver>-darwin-arm64.tar.gz`），里面只有 `Moshi Go.app`，没有 helper、
  没有 login item、没有 AppleDouble。
- 校验: body 里没有 sha256/sha512，不接 `checksumPattern`；feed 的 `signature` 是 MyGo 的 Ed25519（签文件的 SHA-256），
  用 recipe 写死的厂商 key 校验，叠在 Team ID 闸之上（见「增量更新」的签名一节）。
- **读的是**: 人人可手动下载的 GA —— 所有安装读同一份 feed，无灰度；同版本的 dmg 在 CDN 上也能直接下到。
- 阻塞: 无。

## 已知问题
- 从官网 dmg 装的副本第一次更新吃不到 delta（见上），会多下载一个 delta 的量（约 1 MB）再走全量。
- 只有 arm64。厂商以后若发 amd64，地址会是 `update-darwin-amd64.json`；DuoUpdater 本身只支持 arm64，不影响。

## 如何复验
```
# GET https://cdn.getmoshi.app/desktop-go/update-darwin-arm64.json → version 0.5.3（2026-10-07）
swift run --package-path application-test channel-verify "Moshi Go 0.5.2.dmg"
#   app.getmoshi.desktop / 0.5.2 / detected channel → stable
#   VendorProbe latest 0.5.3, download …/moshi-go-0.5.3-darwin-arm64.tar.gz, verdict UPDATE 0.5.2 → 0.5.3
#   winning source Vendor
#   changelog pane → recipe changelog:app.getmoshi.desktop:-: 4 entries; newest 0.5.3: 4 items
swift run --package-path application-test feed-discover "Moshi Go 0.5.2.dmg"
#   no Sparkle and no electron-builder update config
# tar.gz 解包: Moshi Go.app → app.getmoshi.desktop / 0.5.3 / Team FL442366Y7 / Notarized Developer ID / arm64
# delta 头: head -c 12 moshi-go-0.5.2-to-0.5.3-darwin-arm64.delta → "mygo delta 1"
#   channel-verify 同一次运行: deltas 3
# delta 端到端: ditto <moshi-go-0.5.2-darwin-arm64.tar.gz 解出的 Moshi Go.app> /Applications/
#   duo install "/Applications/Moshi Go.app" --yes --json → bytesDownloaded 891233
#   diff -r /Applications/Moshi\ Go.app <0.5.3 tar.gz 解出的 bundle> → 无差异
# 签名红→绿（2026-10-07，同一个 tar.gz 的 0.5.2）:
#   recipe 的 myGoPublicKey 换成随机 key → make cli → duo install → bytesDownloaded 16118320（delta 被拒，退回全量）
#   换回厂商 key → make cli → duo install → bytesDownloaded 891233（delta 验签通过后应用）
# 全量归档签名红→绿（2026-10-07，dmg 的 0.5.2，delta 必然失败、只剩全量）:
#   随机 key → duo install → outcome failed，"The download's signature doesn't match the vendor's update key that
#     DuoUpdater keeps for this app. …"（`myGoSignatureInvalid`），盘上仍是 0.5.2
#   厂商 key → duo install → installed，bytesDownloaded 16118320，与厂商 0.5.3 diff -r 一致
```

## 建议下一步
1. Tauri 副本经 `BundleIDMigration` 一键换成 Moshi Go 还没在真机上跑过（2026-10-11），见 Tauri 那份的「建议下一步」。

## 历史与实测
- 2026-10-07 接入。官网 dmg 0.5.2，feed 0.5.3（当天 10:16 UTC 发布），manifest 共 4 个版本（0.5.0–0.5.3，全在同一天）。
- 2026-10-11: feed 0.5.13（`date` `2026-10-11T03:00:14Z`），`deltas[]` 的 `from` 是 0.5.12 / 0.5.11 / 0.5.10；manifest 10 个版本
  （0.5.4–0.5.13），每条都有 `date`。Tauri 的 feed 开始发 Moshi Go，Tauri recipe 退役，Tauri 副本改由本 recipe 接住
  （`BundleIDMigration`）。0.5.0 / 0.5.12 / 0.5.13 的二进制里都有 `MigrateFromTauri` 和
  `settings: migrated %d keys from the Tauri app`（读字符串，没实跑）。
