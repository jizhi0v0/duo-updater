# Mayoi

## 基本信息
- Bundle ID: `dev.mayoi.editor`（0.1.0 起没变过）
- Team ID: `KU8S35TEW8`（Developer ID Application: chen cheng），全部 19 个版本（0.1.0–0.11.0 的 arm64 tar.gz，2026-10-19 逐个解开看 `codesign -dv`）一致，0.11.0 amd64 也是；0.1.0 / 0.10.0 / 0.11.0 dmg 的 `spctl` 为 Notarized Developer ID
- 观测版本: 0.11.0（`CFBundleShortVersionString` = `CFBundleVersion` = 0.11.0），取自官方 release 资产 `Mayoi.0.11.0.arm64.dmg`（2026-10-18）；另取 0.10.0、0.1.0 对照
- 自更新机制: MyGo（Go 写的编辑器，自绘 GPU UI；`mygo.json` 的 `updates` 指向 `sorrycc/Mayoi` 的 GitHub release）
- 架构 / OS: 按架构分包（`arm64` / `amd64` 各一个 dmg 和 tar.gz）；`LSMinimumSystemVersion` 13.0
- 开源: `sorrycc/Mayoi`（MIT）。feed、key、签名与版本方案 settled from source：`mygo.json`（`main`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe | MyGo |
|--------------|---------|----------|-----|--------|-------------|------|
| **stable**   | —       | —        | —   | —      | —           | ✓    |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **MyGo**（`MyGoUpdateSource`，读二进制里的 feed 与 key，无 recipe）。

- `feed-discover`（0.1.0、0.10.0、0.11.0 三个包结果一样）：`declared  https://github.com/sorrycc/Mayoi/releases/latest/download/update-darwin-arm64.json (MyGo: the binary links this feed and key kW6/B4DkWNQdyHkFOrU6tpvLfb5xGVvyYhrIQF7Bct4=; MyGoUpdateSource already resolves this app — no recipe)`。key 与 `mygo.json` 的 `updates.publicKey` 一致。
- Homebrew / MAS —：都没有（2026-10-18 `brew search --cask mayoi` 无结果）。
- 已加入 `MyGoFeedCatalog`，供 `duo verify --mygo` 夜扫。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `dev.mayoi.editor` | 独立 | — | — | ✓ |

19 个 release（v0.1.0 至 v0.11.0）都不是 prerelease；`mygo.json` 没有渠道设置。

## 更新检测
- 源: `MyGoUpdateSource`
- 端点: `https://github.com/sorrycc/Mayoi/releases/latest/download/update-darwin-arm64.json`（amd64 包读 `update-darwin-amd64.json`）。地址是从二进制里读出来的：19 个 arm64 版本都内嵌 `…/update-darwin-arm64.json`，0.11.0 amd64 内嵌 `…/update-darwin-amd64.json`（`grep -a` 可执行文件）
- manifest 形状（0.11.0）: `version`、`notes`、`date`、`url`（`.tar.gz`）、`size`、`signature`（Ed25519）、`deltas`、`previous`
- 版本: tag = `v<CFBundleShortVersionString>`，short = build

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（已接） |
| 证据 | MyGo 客户端 | 0.11.0 manifest 的 `deltas` 有 3 条（from 0.10.0 / 0.9.1 / 0.9.0），release 里有对应的 `.delta` 资产 | `MyGoDelta` 现成；端到端 0.10.0 → 0.11.0 只下了 1384466 字节（补丁），全量 tar.gz 是 12227356 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 没查（MyGo 暂存在 `/Applications/.<App>.app.update-*`，见 Leafmark 审计） | 无 | 没查（没观察到停放；`SelfUpdaterStash` 目前不读 MyGo 布局） |
| 证据 | — | 第二轮启动后 45 s，`/Applications` 下没有暂存目录 | `SelfUpdaterStash` 只读 electron-updater 和 Cindy 两种布局 |

## Changelog
- 来源: manifest 的 `notes` 只有当前一版，历史由 `Recipes/dev-mayoi-editor.swift` 读仓库的 `CHANGELOG.md`（`raw.githubusercontent.com/sorrycc/Mayoi/main/CHANGELOG.md`）补。文件开头写明每个 release 都必须有 `## <版本>` 一节、app 的更新窗口显示的就是这一节。19 个 release 的 manifest `notes` 与对应小节逐个比过：18 个相同，0.2.0 只差一个空行。
- 没用 GitHub release 列表：0.3.3 起正文与 manifest 相同，但 0.1.0–0.3.2 这 6 个正文只有一行「Full Changelog」链接，而它们的 manifest 有真正的说明（252–2323 字），读 release 列表会少 6 版。
- 结构化（channel-verify，从 0.10.0 起，2026-10-18）:
  - 有 recipe：`recipe changelog:dev.mayoi.editor:-: 19 entries; newest 0.11.0: 65 items, headings []; first items ["Settings sync no longer undoes a change ", "Windows: a file opened from quick open, ", "Windows: renaming refuses a name with / "]`。一次临时测试（已删）把 `ChangelogService.parse` 跑在真实文件上：19 条的条目数与各小节的 `- ` 数逐个相同（0.11.0=65 … 0.1.0=2），折行的条目整条保留；`## Unreleased` 不进（版本须以数字开头）。
  - 没 recipe 时：`source structured: 1 entries; newest 0.11.0: 181 items, headings [] (rendered as markdown)`。181 是 `content` 按行切的备用计数；面板用 `ChangelogMarkdown` 渲染原文，一次临时测试（已删）在真实 notes 上得到 65 个 list item，与原文 65 个 `- ` 一致，折行已并回同一条。
  - 小节是不带 `###` 的 `- ` 列表，所以 `headings []` 是原样。`CHANGELOG.md` 不写日期，历史条目没有日期。
  - `stripTags: false`、`decodeEntities: false`：这是 markdown 不是 HTML，说明里用尖括号写占位符（0.3.1 `Mayoi.<version>.<arch>.dmg`、0.3.2 `mayoi <dir>`、0.10.0 `mayoi <path>`），默认的 `<[^>]+>` 清洗会把它们删掉（review round 2 指出，`MayoiChangelogRecipeTests` 用这三段原文钉住：打开 `stripTags` 时四个占位符全丢）。文件里没有 HTML 实体。
  - 一处外观残留：0.10.0 那条的行内代码跨了行（`` `mayoi`` 换行 ``<path>` ``），`ChangelogExtractor.clean` 先去反引号（只认单行）再折叠空白，所以显示为 `` `mayoi <path>` ``，反引号还在、字没丢。要改得动共用的清洗顺序，不在这次范围。
- 跟随 channel: 不适用
- Recipe 状态: ✓ 已有

## 一键安装
- 状态: 支持（MyGo 路径：manifest 的 `.tar.gz` 或 delta，Ed25519 签名 + Team ID 闸）
- 端到端（2026-10-18）:
  - 第一轮（未运行）：0.10.0（官方 dmg）放进 `/Applications`。`duo check Mayoi` → `0.10.0 → 0.11.0 [MyGo, in-place]`；`duo install Mayoi --yes --json` → `outcome: installed`，`bytesDownloaded: 1384466`（delta），7.5 s。之后为 0.11.0，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，Team `KU8S35TEW8`。和厂商 0.11.0 的 tar.gz 用 `diff -r --no-dereference` 比对一致；和 dmg 版比只多一个 `Contents/CodeResources`：那是装订进 app 的公证票据，tar.gz 里的 app 带、dmg 里的 app 不带（dmg 版把票据装订在 dmg 上）。起点是 dmg 版 0.10.0（不带这个文件），delta 照样用上了，没有退回全量（Pulse 的 dmg 副本第一次会退回全量，见它的审计）。
  - 第二轮（运行中）：重新放入 0.10.0 并启动。它在启动时自己检查了一次（`~/Library/Application Support/Mayoi/updater.json` 写入 `lastCheck`），45 s 内 `/Applications` 下没有出现暂存目录，Caches / Application Support / Containers 下也没有新的大文件。`duo install` → `installed`（1384466 B，delta）→ `duo restart Mayoi` → `restarted`，进程换新，之后 10 s 磁盘一直是 0.11.0，`codesign --verify --deep --strict` 通过。
- 格式: tar.gz / delta
- 校验: MyGo Ed25519 签名（key 取自已装 app 的二进制）+ Team ID 闸
- **读的是**: 人人可手动下载的 GA。manifest 就在 GitHub 的 `releases/latest/download/` 下，指向公开 release 资产
- 嵌套: 无
- 阻塞: 无

## 已知问题
- 无。

## 如何复验

```sh
gh release download v0.11.0 -R sorrycc/Mayoi --pattern '*arm64.dmg' --pattern 'update-darwin-arm64.json'
swift run --package-path application-test feed-discover Mayoi.0.11.0.arm64.dmg
gh release download v0.10.0 -R sorrycc/Mayoi --pattern '*arm64.dmg'
swift run --package-path application-test channel-verify Mayoi.0.10.0.arm64.dmg
gh api "repos/sorrycc/Mayoi/contents/mygo.json?ref=main" -q .content | base64 -d
```

2026-10-18：channel-verify（0.10.0）`winning source MyGo`、`latest 0.11.0`、download `…/v0.11.0/mayoi-0.11.0-darwin-arm64.tar.gz`、`deltas 3`、`status UPDATE → 0.11.0`。

## 建议下一步
1. 无。
