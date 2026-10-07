# Moshi Go

Moshi 桌面端的原生重写（Go + Metal，终端用 libghostty-vt）。它接手了 bundle id
`app.getmoshi.desktop`；它取代的 Tauri 版是另一个 bundle id、另一条 feed，见
[Moshi（Tauri）](app-getmoshi-desktop-tauri.md)。

## 基本信息
- Bundle ID: `app.getmoshi.desktop`
- Team ID: `FL442366Y7`（`Developer ID Application: Moshi Tech Limited`）
- 观测版本: `0.5.2`（官网 dmg）、`0.5.3`（feed 与 tar.gz），short == build；2026-10-07
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

**会不会推给 Tauri 版的安装？** 不会。Tauri 版从 0.1.0 起就是 `app.getmoshi.desktop.tauri`
（下载 0.1.0 / 0.2.0 / 0.3.0 / 0.4.0 / 0.4.10 / 0.4.17 / 0.4.18 的 `.app.tar.gz` 逐个读 Info.plist 核对），
Moshi Go 从 0.5.0 起是 `app.getmoshi.desktop`。两个 id 从没共用过。

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
| 结论 | 有 | 有 | 不能 |
| 证据 | feed 的 `deltas[]` 就是给 app 自己的更新器用的 | 2026-10-07 的 feed 列了 `0.5.0/0.5.1/0.5.2 → 0.5.3` 三个 `.delta`（0.89–1.19 MB，全量 15.2 MB） | 文件头是 `mygo delta 1`，厂商自有格式；`DeltaApplier` 只会 Sparkle BinaryDelta |

- 阻塞项: 需要实现 `mygo delta 1` 的应用器，且要验厂商的 ed25519 `signature`。目前不做。

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
- 校验: feed 的 `signature` 是厂商对归档的 ed25519 签名（64 字节 base64），不是摘要；body 里没有 sha256/sha512，
  不接 `checksumPattern`，靠 Team ID 闸。
- **读的是**: 人人可手动下载的 GA —— 所有安装读同一份 feed，无灰度；同版本的 dmg 在 CDN 上也能直接下到。
- 阻塞: 无。

## 已知问题
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
```

## 建议下一步
1. 厂商若把 Moshi Go 转正、让 Tauri 版的 feed 指向它，回来看 Tauri recipe 是否该退役。

## 历史与实测
- 2026-10-07 接入。官网 dmg 0.5.2，feed 0.5.3（当天 10:16 UTC 发布），manifest 共 4 个版本（0.5.0–0.5.3，全在同一天）。
