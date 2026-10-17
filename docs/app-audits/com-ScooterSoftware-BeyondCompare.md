# Beyond Compare

审计 2026-10-16（首次接入；从官方 zip 解包验证，没有装机）。

## 基本信息
- Bundle ID: `com.ScooterSoftware.BeyondCompare`（BC4 与 BC5 共用，五个真包核实: 4.4.6、4.4.7、5.0.0、5.2.5、5.2.6）
- Team ID: `BS29TEJF86` — Developer ID Application: Scooter Software Inc.（上面五个包相同，`spctl` 均 `Notarized Developer ID`）
- 观测版本: BC5 `5.2.6.32774`（`CFBundleShortVersionString`；`CFBundleVersion` `5020.62.77`），上一版 `5.2.5.32528`；
  BC4 `4.4.7.28397`（`CFBundleVersion` `4040.78.39`），上一版 `4.4.6.27483`
- 架构: BC5 universal（`x86_64 arm64`）；BC4 只有 `x86_64`（cask `beyond-compare@4` 标 `requires_rosetta`）
- 系统下限: Info.plist 没有 `LSMinimumSystemVersion`；主程序 `LC_BUILD_VERSION minos` BC5 10.15、BC4 11.0（都低于 duo 的 15.0），不设 `hostRequirement`
- 自更新机制: 自研。「Check for Updates」请求
  `https://www.scootersoftware.com/checkupdates.php?product=bc5&minor=…&maint=…&auth=&build=…&edition=…&cpuarch=…&lang=&platform=osx&osver=…&ospatch=…`
  （BC4 是 `product=bc4`），回一页 HTML，里面是 `download://www.scootersoftware.com/BCompareOSX-<v>.zip` 链接，app 自己下载替换
- 开源: 否
- Homebrew: cask `beyond-compare`（5.2.6.32774，`auto_updates true`）与 `beyond-compare@4`（4.4.7.28397，`auto_updates true`），互相 `conflicts_with`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗（`auto_updates`，`HomebrewCaskSource` 不应答） | — | — | ✓ 一键（BC5 与 BC4 各一条） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（`channel-verify` 的 `winning source  Vendor`，四个包都是）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（BC5） | `com.ScooterSoftware.BeyondCompare` | 与 BC4 共享 | 版本以 `5.` 开头 | `installedVersionPattern ^5\.` | ✓ |
| stable（BC4） | `com.ScooterSoftware.BeyondCompare` | 与 BC5 共享 | 版本以 `4.` 开头 | `installedVersionPattern ^4\.` | ✓ |
| beta | 同上 | 共享 | 构建自带（`&beta` 参数由 beta 构建自己发出，非用户开关） | — | —（厂商当前不发布，见下） |

- **BC4 与 BC5 是两个付费代际，不是同一条线的新旧版。** 厂商升级政策页（`/kb/upgradepolicy`，2026-10-16）: 小版本与维护版免费，
  「a version 5 license will work for all 5.x.x releases」，跨大版本需要新 key（一般半价）。所以每代一条 probe，各用
  `installedVersionPattern` 锁定本代，`versionPattern` 也钉在本代主版本号上。
- BC4 已停止维护: `checkupdates.php?product=bc4` 对 4.4.6 回「Newer version … 4.4.7 build 28398」并附「Beyond Compare 4 has reached
  End of Life」；对 4.4.7 回「You are using the latest version 4 release」。厂商自己不把 BC5 推给 BC4 拷贝，我们也不推。
- BC3 及更早: `/download/v3` 页上没有 macOS 包（实测），Mac 版从 BC4 开始。
- beta: `/beta` 页（2026-10-16）写「Now that we've released version 5.0, the beta program is over」。二进制里有 `&beta` 查询参数和
  「This beta build will stop working on %s」的过期提示，即 beta 是带过期日的独立构建，不是同一构建里的开关。现在没有 beta
  可下，不加轨道（测的）。带 `&beta` 问 5.2.5 时，端点照样回正式版 5.2.6（实测），与我们对 beta 拷贝推正式版的行为一致。
- Standard / Pro 版本: 同一个包，由许可证区分（端点里的 `edition=` 参数），不是另一个 bundle id。

## 更新检测
- 源: `VendorProbeSource`，`Recipes/com-ScooterSoftware-BeyondCompare.swift`
- 端点:
  - BC5: `https://www.scootersoftware.com/download`，`versionPattern` `href="/files/BCompareOSX-(5\.[0-9]+\.[0-9]+\.[0-9]+)\.zip"`
    （页里 macOS 只有这一个链接，Windows/Linux 是 `.exe`/`.deb`/`.rpm`）
  - BC4: `https://www.scootersoftware.com/download/v4`，同形，主版本 4
- 为什么不用 app 自己的 `checkupdates.php`: 它要求查询里带上**已装版本**（缺 `auth=`、`lang=` 等任何一个参数都回 400，实测），
  回的是对话框 HTML。下载页是同一个 zip（对话框链接 `BCompareOSX-5.2.6.32774.zip` 与下载页一致），也是 cask `livecheck` 读的页。
- 版本方案: 四段营销版本含构建号，与包内 `CFBundleShortVersionString`、zip 文件名完全相同；`versionIsBuild` 保持默认
  `false`。v5changelog 上 23 个版本（5.0.0.29773 到 5.2.6.32774）、v4changelog 上 45 个版本（4.0.0.18847 到 4.4.7.28397）
  全是四段纯数字，都能被对应 pattern 读到。
- 下一个大版本: `/download` 是「最新代际」页（没有 `/download/v5`，该路径 Page Not Found，实测）。BC6 发布后它会换成
  `BCompareOSX-6…zip`，BC5 probe 的 pattern 读不到 → 失败行 + `duo verify` 报红，而不是把付费升级当小版本推给 BC5 拷贝。
  届时要把 BC5 probe 改指厂商给 BC5 的新地址（按 BC4 先例应是 `/download/v5`）。
- 已知不读: 厂商 `checkupdates.php` 对 4.4.6 报的是「build 28398」，下载页和 zip 是 28397（厂商端点自己的笔误，我们读下载页，不受影响）。

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无（字符串层面） | 无 | — |
| 证据 | `Contents/Frameworks` 只有 `LetsMove.framework`、`lib7z`、`libunrar`、`libcloudstorage`，没有 `Sparkle.framework`；主程序里 `bspatch|binarydelta|deltaupdate|diffpatch|hdiff` 0 命中，`.patch` 只出现在文件类型过滤串里（`*.diff;*.patch`） | `checkupdates.php` 只给一个完整 zip 链接；`/files/` 下每版一个完整 zip | — |

- 格式: —
- 阻塞项: —

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 请求带 `auth`、`edition`、`osver` 等参数 | `cpuarch=arm64, edition=pro`（`build` 32528 与 1）和 `cpuarch=x86_64, edition=std, osver=15` 问到的都是同一个 5.2.6 zip（实测） | 不需要 |
| 按架构 / 按 OS 分轨 | `cpuarch=x86_64`/`arm64` 参数 | 否: 同一个 universal zip | — |
| 自更新器会不会和我们抢 | 会: app 自己下载并替换（`download://` 链接） | 用户点了才下（实测，见下） | 无害：在 duo 装好的 5.2.6 上再装一次同版本，签名完好（运行中一轮实测） |
| 已停放整包 | 没查 | 没查 | 没查 |

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（下完立即换包） | — |
| 证据 | 2026-10-16 真机：“New version available...” → “Program Updates and News” → “Click here to update”（`download://www.scootersoftware.com/BCompareOSX-5.2.6.32774.zip`），只在用户点击后下载 | 下载后解到 `$TMPDIR/BC5_<随机>/Beyond Compare.app`，随即原地替换 `/Applications/Beyond Compare.app` 并自行重启，临时目录自己删掉 | — |

- 记录文件与字段: 无（没有停放）
- 容器: 厂商包是 zip，包根是 `Beyond Compare.app`
- 两份副本会不会共用这个目录: 不适用（临时目录用完即删）

## Changelog
- 来源: 两条 `ChangelogRecipe`，按版本窗口分代际: `https://www.scootersoftware.com/download/v5changelog`（`minimumAppVersion 5`，
  `belowAppVersion 6`）与 `/download/v4changelog`（4 到 5）。服务端渲染，整页一份历史，每版
  `<h2>5.2.6.32774 - September 24, 2026</h2>` 后接若干 `<h4>` 分节和 `<ul>`
- 结构化: `channel-verify` 原文:
  - 5.2.5 / 5.2.6 包: `changelog pane  recipe changelog:com.ScooterSoftware.BeyondCompare:-:5-6: 23 entries; newest 5.2.6.32774: 10 items, headings ["Notable Changes", "Cloud Services", "Command Line", "Installer", "Misc", "Text Compare", "Third Party Libraries", "Crashes"]; first items ["General polish, stability improvements, ", "Windows: MIME types for uploaded files a", "Linux: Fixed command injection vulnerabi"]`
  - 4.4.6 / 4.4.7 包: `changelog pane  recipe changelog:com.ScooterSoftware.BeyondCompare:-:4-5: 40 entries; newest 4.4.7.28397: 15 items, headings ["Notable Changes", "File Formats", "Folder Compare", "Hex Compare", "Installer", "Misc", "Options", "Crashes"]; …`
- 分节标题保留（`headingPattern` 读 `<h4>`），没有被压平。页面是全平台的，条目保留厂商的「Windows:」「Linux:」前缀，没有过滤
- 4.0.0.18847 那一条在页上没有 `<li>`，默认上限 40 条也取不到它
- 跟随 channel: 否（单轨）；跟随代际: 是
- Recipe 状态: ✓

## 一键安装
- 状态: 支持（两代都接）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：5.2.5.32528 → 5.2.6.32774，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: zip，包根直接是 `Beyond Compare.app`；URL 由解析出的版本拼成 `https://www.scootersoftware.com/files/BCompareOSX-{version}.zip`
  （BC4 的 zip 也在 `/files/` 下，实测 200）
- 校验: 下载页与端点都不发摘要，只靠 Team 闸。实测 SHA-256: 5.2.6 zip `d52a9f15…6bba`（= cask sha256），5.2.5 zip `f913d05e…aba3`
- **读的是**: 人人可手动下载的 GA（官网下载页，也是 app 自己更新对话框链接的那个 zip）
- Team: 5.0.0、5.2.5、5.2.6、4.4.6、4.4.7 同为 `BS29TEJF86`，没有换过 Team
- 嵌套: 只有 `Contents/PlugIns/BCFinder.appex`（`com.ScooterSoftware.BeyondCompare.BCFinder`，`NSExtensionPointIdentifier`
  `com.apple.FinderSync`，同 Team），没有 helper app、LoginItems、LaunchAgent/Daemon。Finder Sync 扩展由系统按需起进程，替换后
  旧扩展进程可能继续跑到 Finder 重新加载它（推断，没测）
- 命令行 `bcomp` 在包内 `Contents/MacOS/`；cask 把它链进 brew 的 `bin`，链接指向包内路径，替换后仍有效（推断）
- 阻塞: 无已知

## 已知问题
- `/download` 是「最新代际」页，BC6 发布时 BC5 probe 会失败（有意为之，见「更新检测」）

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：5.2.5 运行中，`duo install --yes` → `installed.` 并提示 `Still running the old code: Beyond Compare`；随后在旧进程里点 “Click here to update”：它下载 zip、原地替换成 5.2.6（同版本，新 inode）并自行重启，结果 Team `BS29TEJF86`、`codesign --strict` 0、Notarized、`duo check` 报 up to date，没有管理员授权框。它刚自行重启后那一次 `duo restart` 报 `still running — likely a save prompt`（AX 看不到任何窗口；10 秒后普通退出立即成功），重开后再试 `duo restart` → `restarted`，没再复现，原因没查。`BCFinder.appex` 从包内路径注册，没看到扩展进程。新增 `~/Library/{Application Scripts/…BCFinder, Application Support/Beyond Compare 5, Caches/…, Containers/…BCFinder, HTTPStorages/…, WebKit/…}`，登录项前后无差异
2. BC6 发布后把 BC5 probe 改指厂商给 BC5 的下载页

## 历史与实测

- 2026-10-16 `channel-verify`（从官方 zip 解出的 .app，`--expect stable`）:
  - 5.2.5.32528: `detected channel → stable`，`verdict UPDATE 5.2.5.32528 → 5.2.6.32774`，`winning source Vendor`
  - 5.2.6.32774: `verdict up to date`，`status up to date`
  - 4.4.6.27483: `verdict UPDATE 4.4.6.27483 → 4.4.7.28397`，`winning source Vendor`
  - 4.4.7.28397: `verdict up to date`
- 2026-10-16 `checkupdates.php` 实测: 参数齐全时 200；去掉 `auth=`/`lang=` 回 400、0 字节。`build=1` 时回 5.2.6 并附 macOS 10.8 的提示
- 2026-10-16 下载: `BCompareOSX-5.2.6.32774.zip` 56,212,663 B，`-5.2.5.32528.zip` 56,210,794 B，`-4.4.7.28397.zip` 27,415,403 B，
  `-4.4.6.27483.zip` 27,415,556 B，`-5.0.0.29773.zip` 55,201,854 B，全部 `/files/` 下 200
