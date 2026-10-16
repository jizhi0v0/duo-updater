# Mounty for NTFS

菜单栏小工具：把以只读挂上的 NTFS 卷用 ntfs-3g（2.0 起依赖 ntfs-3g + macFUSE）重新挂成读写。
厂商只在自己的单页站点 `mounty.app` 发布，页面「Version History」一节列出全部版本和各自的 dmg。

## 基本信息
- Bundle ID: `com.cu4uc.mounty`（1.1、1.9、1.10、1.16、2.0、2.3、2.4 七个真包相同）
- Team ID: `SG6DU88C24`（Developer ID Application: Uwe Hollatz；上述七个真包相同）
- 观测版本: short `2.4`, build `33`（2026-10-16）
- 自更新机制: 无。没有 Sparkle、没有 electron-builder 配置；主二进制 `strings` 里没有任何 `http(s)://` 地址，也没有 update / appcast 字样
- 分发: 官网 dmg；Homebrew 官方 cask `mounty`（url 就是 `mounty.app/releases/Mounty-2.4.dmg`，`auto_updates` 未设）。
  没有 MAS（1.1 的说明：因沙盒限制放弃上架）、没有 GitHub release
- 开源: 否（页面没有源码链接）

## 覆盖清单

| 副本分组 | 结论 |
|---|---|
| 其他 bundle id（改名、其他版本） | 无。1.1（2014）到 2.4 抽查七个真包，id 都是 `com.cu4uc.mounty` |
| 其他发布轨（beta / nightly） | 无。站点只有一条版本列表，没有 beta 链接；cask 只有 `mounty`，没有 `@beta` 之类 |
| 版本范围 | 版本号全是两段（`1.1` … `1.16`、`2.0` … `2.4`），页面上 21 条全部被版本正则读到；`1.10` 正确比 `1.9` 大。Team 自 1.1 起不变，旧副本都能过 Team 闸 |
| 宿主下限 | 包内 `LSMinimumSystemVersion` = `11.0`，低于 DuoUpdater 自身的 macOS 15，不需要 `hostRequirement` |
| brew 装的副本 | cask 无 `auto_updates`，由 `HomebrewCaskSource` 先应答（从代码读出，未在 brew 装的副本上实测） |
| 一键 | 全部官网副本可走（同 Team、公证、dmg）；1.1–1.10 是 x86_64，下载的 2.4 是 universal |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（仅 brew 装的副本） | — | — | ✓（一键 dmg） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: 官网下载的副本 **Vendor**（channel-verify 实测）；brew 装的副本 **Homebrew**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.cu4uc.mounty` | — | — | — | ✓ |

只有一条轨。

## 更新检测
- 源: `VendorProbeRecipe`，读 `https://mounty.app/`（HTML 抓取）
- 版本: `<h4>\s*Version\s+([0-9]+(?:\.[0-9]+)+)\s+-`，`selectHighest`。只读「Version History」里每版的 `<h4>` 标题；
  尾部的 ` -` 让 `2.5b1`、`2.5 beta`、`2.5-rc1` 这类标题读不出版本（单测覆盖），下一个大版本 `3.0` 能读
- 页面版本号就是 `CFBundleShortVersionString`（2.4 包写 `2.4`，2.3 包写 `2.3`）；`CFBundleVersion` 是递增构建号（2.3=31，2.4=33），不参与比较
- 按 OS 分轨: 页面不写系统版本字段；每个包自己的 `LSMinimumSystemVersion`（2.4 = `11.0`）
- 按架构: 厂商说明写 1.11 起 universal；实测 1.10 只有 x86_64，1.16 / 2.0 / 2.3 / 2.4 是 `x86_64 arm64`。没有分架构的包

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | app 没有更新器（二进制里无网络地址） | 站点只有整包 dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（运行中一轮实测） | — |
| 证据 | 没有更新器 | — | — |

## Changelog
- 来源: recipe，读同一页 `https://mounty.app/` 的「Version History」：每版一个 `<h4>`（版本、日期、download 链接），
  后面是 `<ul>` 的 `<li>`；最早的 1.1 是两段 `<p>`。正文截到下一个 `<h4>` 或本节的 `</div>`，后面的 Disqus 不会混进来
- 结构化（2026-10-16，channel-verify `changelog pane`）: `recipe changelog:com.cu4uc.mounty:-: 21 entries; newest 2.4: 1 items, headings []; first items ["credits page updated"]`
- 分节: 厂商不分节，`headings []` 是如实
- 跟随 channel: —（单轨）
- Recipe 状态: 已有

## 一键安装
- 状态: **支持**（dmg）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：2.3 → 2.4，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg（`.versionTemplate` → `https://mounty.app/releases/Mounty-{version}.dmg`，用探到的版本号拼，比较的版本就是下载的版本）。
  无 SLA（`hdiutil imageinfo`: `Software License Agreement: false`）
- 包内容: 只有 `Mounty.app`。嵌套 app 只有 `Contents/Library/LoginItems/MountyHelper.app`（`com.cu4uc.MountyHelper`，
  `LSBackgroundOnly`，同 Team）：主程序用 `SMLoginItemSetEnabled` 登记它做登录启动；它的 `strings` 只有
  `launchApplication:` / `terminate:` 和 `com.cu4uc.mounty`，即拉起 Mounty 后退出，不常驻（从 strings 推断，未运行观察）。
  主程序调用 ntfs-3g 走 `do shell script … sudo -S`，不在 bundle 外装 daemon / helper；Info.plist 里的 `SMPrivilegedExecutables`
  指向的 `com.cu4uc.mounty.HelperTool` 不在包里（`Contents/Library/` 下只有 `LoginItems`）
- 签名: 2.4 / 2.3 / 2.0 / 1.16 / 1.10 / 1.9 `spctl` = Notarized Developer ID，1.1 = Developer ID（2014 年未公证）；Team 都是 `SG6DU88C24`
- 校验: 页面不发摘要；不接 `checksumPattern`。下载的 2.4 dmg SHA-256 `b5f0867a…c5d72888`，与 cask 的 `sha256` 相同
- **读的是**: 人人可手动下载的 GA（官网列表里最新那条，也是 `releases/Mounty.dmg` 当前指向的同一字节）
- 阻塞: 无

## 已知问题
- HTML 抓取：页面改版会让探针读不出版本（落回 unknown，不会误报）
- 厂商最后一版是 2023-12-29 的 2.4，之后没有发布；old→new 只能用 2.3 → 2.4 验

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：2.3 运行中（首启弹 “Important Notice” 模态框，未关）`duo install --yes` → `installed.` 并提示 `Still running the old code: Mounty for NTFS`；`duo restart` → `restarted`，新进程映射 2.4 的主程序（`lsof` inode 与磁盘一致）。Team `SG6DU88C24`、Notarized；`codesign --verify --deep --strict` 报 `MountyHelper.app` 有 `resource fork, Finder information, or similar detritus`，厂商 `Mounty-2.4.dmg` 原包同样报（包内文件带 `com.apple.lastuseddate#PS`），不是我们装出来的。新增文件只有 `~/Library/Preferences/com.cu4uc.mounty.plist`，登录项前后无差异

## 如何复验

```bash
# 1. 版本列表
curl -sS https://mounty.app/ | grep -oE '<h4>Version [0-9.]+ - [^<]*' | head -3

# 2. 生产检测 + changelog（挂载真包，只读）
swift run --package-path application-test channel-verify <Mounty-2.3.dmg> --expect stable
swift run --package-path application-test channel-verify <Mounty-2.4.dmg> --expect stable

# 3. 签名
codesign -dvv Mounty.app 2>&1 | grep -E "Identifier|TeamIdentifier"
spctl -a -vv -t exec Mounty.app
```

2026-10-16 实测:
- `channel-verify` 2.3: `detected channel → stable`、`VendorProbe ✓ recipe answered for channel 'stable'`、`verdict UPDATE 2.3 → 2.4`、
  `download https://mounty.app/releases/Mounty-2.4.dmg`；全链 `winning source Vendor`、`status UPDATE → 2.4`
- `channel-verify` 2.4: `verdict up to date`；全链 `winning source Vendor`、`status up to date`
- `channel-verify` 1.9: `verdict UPDATE 1.9 → 2.4`、`winning source Vendor`

## 历史与实测

### 2026-10-16 · 接入
- 页面 28 个 `<h4>`，其中 21 个是版本标题（2.4 … 1.1），版本正则 21/21；changelog 正则在 Python 与生产解析器上都是 21 条
- `releases/Mounty.dmg`（无版本号）与 `Mounty-2.4.dmg` 字节相同（SHA-256 同为 `b5f0867a…c5d72888`，2,006,058 bytes），
  `Last-Modified: Fri, 29 Dec 2023`。recipe 不用它：它不带版本号，`.versionTemplate` 能保证下载的就是比较的那版
- 抽查的真包: 1.1 / 1.9 / 1.10 / 1.16 / 2.0 / 2.3 / 2.4，bundle id、Team 全部一致；1.1–1.10 只有 x86_64，1.16 起 universal
