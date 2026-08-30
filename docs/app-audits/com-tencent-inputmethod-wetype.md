# 微信输入法 (WeType)

> 审计于 2026-08-28。腾讯的输入法，官网 `z.weixin.qq.com` 下载。
> 结论：**检测 + changelog 早已接入；一键 2026-08-28 重新接入**，走输入法专用的
> Contents 轮换，并带用户数据快照。真机红→绿（656 → 657）与回滚均已实测。

这份文档是补写的——WeType 的 recipe 早在 2026-08 就在跑了，但它的知识一直只散在
`VendorProbeRecipe.swift` 的注释和一条 memory 里。2026-08-16 的一键撤回事件也在那里，
下一个人要重新拼一遍才能读懂，所以补上。

## 基本信息
- Bundle ID: `com.tencent.inputmethod.wetype`
- Team ID: `88L2Q4487U`
- 观测版本: `2.2.3`（`CFBundleShortVersionString`），build `657`（`CFBundleVersion`）
- 安装路径: `/Library/Input Methods/WeType.app`（`root:staff`，**每一级都是 775**）
- Info.plist 关键位: **无 `SUFeedURL`**（bundle 里有 Sparkle.framework，feed 在运行时才设）
- 自更新机制: 自带 `Contents/Helpers/WeTypeUpdater.app`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✗¹      | —        | —   | —      | ✓ ★         |

1. 有 Sparkle framework，但 `Info.plist` 里没有 `SUFeedURL`（运行时设），
   而写死在二进制里的那份公开 appcast **停在 1.4.1（2025-07）**，2.x 走微信内推送通道。
   所以 Sparkle 这条路对我们是死的。

## 更新检测

- 源: `VendorProbe`（`mode: .responseBody`）
- 端点: `https://z.weixin.qq.com/web/mac/download?channel=InstallInfo`
  ——**厂商自己的安装器读的那个接口**，302 到一份 per-build 的 JSON manifest。
- 真实响应（2026-08-28）:
  ```json
  {
    "zip_download_url": "https://download.weread.qq.com/app/wxkb/mac/2.2.3/WeType_2.2.3_657.zip",
    "zip_download_md5": "001fb418c7974c112bfc7ebbf47d483e",
    "zip_version": "2.2.3.657",
    "package_type": ""
  }
  ```
- `versionPattern` 取第 4 段 → `657`（`versionIsBuild: true`，与装机 `CFBundleVersion` 同 namespace）
- `displayVersionPattern` 取前 3 段 → `2.2.3`（行上显示）

### ⚠️ 上一版 recipe 读的是**安装器壳自己的版本**

此前的 recipe 从 `z.weixin.qq.com/web/change-log/macos` 上抓
`WeTypeInstaller_<x.y.z>_<build>_<letter>.zip` 文件名。那串数字是**安装器 stub 的版本，
不是 app 的**——手上的 stub 是 2.2.0 (643)，它装出来的是 2.2.3 (657)。
两者长期贴得很近，所以看起来一直是对的：**一个用错 namespace 的 recipe 不会失败，
它只是拿另一个命名空间的号来回答你**。最后是夜扫里的
`remote is BEHIND the installed copy` 把它抓出来的。

那个页面本身也滞后（内嵌 per-platform JSON 还写着 Mac 2.2.2 时 2.2.3 已经在发），
所以**它的文件名和它的 notes 都不是版本源**。

## Changelog

- `changelogURL`: `https://z.weixin.qq.com/web/change-log/macos`（Next.js 页面，
  数据是服务端渲染进 `__next_f` 的 RSC blob，不需要跑 JS）
- 该页是**全平台混排**的扁平列表，`"platform":1`=iOS、`2`=Android、`3`=macOS、`4`=Windows。
  entry pattern 锚在 `version` 先于 `platform` 出现这个字段顺序上，把版本绑在**它自己那个对象**的
  `"platform":3` 上；`[^"]*` 跨不过结构性引号，所以够不到相邻的 iOS 对象。
  没有这道锚，一个「取最高版本」的写法会抓到 iOS 的 3.4.0 → 幽灵更新。

## 一键安装

- 状态: **已接入（2026-08-28）**，走**Contents 轮换**，不是整包覆盖。
- 历史：一键 0.3.25 上线，**当天撤回**（2026-08-16），因为用户的输入法设置丢了。

### 撤回那次的证据链（如实记，它并不构成定论）

- `/Library/Input Methods/WeType.app` 的 mtime 当时仍是厂商安装那天、版本没变 →
  **提权替换那条路从来没真跑过**；
- 同一时间窗里，做那个一键的 agent 把**旧版 2.2.1** 摆进 `~/Applications` 装了一遍、
  并两次重启运行中的输入法，而 `~/Library/Application Support/WeType/{userDict,mmkv}`
  正好在那个窗口被改写；
- 用户「我的设备」里出现**两个同名 Mac** → 第二份副本以新设备身份注册了。

所以更像"身份被顶掉"，而不是"文件被删"。**swap 没有被定罪，一份更旧的副本自行注册了才是。**
无论哪种，波及面都是用户的词库和设置，这类 app 不适合拿来学习。

### 为什么现在可以做了

`WeTypeInstaller.app` 的 `install.sh` 是**首装**路径：`rm -rf` 整个 `WeType.app`、
`mv` 新的进去、`chown -R root:staff` + `chmod -R 775`、去 quarantine、
`killall System Preferences` / `SystemUIServer`；安装器**二进制**还额外做输入源注册
（字面量 `Registered input source from /Library/Input Methods/WeType.app, result: `，
以及 `killall -9 TextInputMenuAgent / TextInputSwitcher / pboard`）。

但**每一次普通版本更新**跑的不是它，是 bundle 里的 `WeTypeUpdater.app`，
而它保留外层 `.app`、只轮换 `Contents`：

```
/Library/Input Methods/WeType.app/.Contents.update
/Library/Input Methods/WeType.app/.Contents.old
/Library/Input Methods/WeType.app/.Contents.abandoned
"will exchange Contents: previous="   "old Contents removed: "   "cleanup old Contents failed: "
```

（本机更新日志里也有 `stage successful: …/.Contents.update` 和
`install committed: previous=2.2.3(655), target=2.2.3(656)`；更新器运行期间自己就位于
`…/.Contents.old/Helpers/WeTypeUpdater.app`。）

被 `TISRegisterInputSource` 注册的是**那个路径**，所以要保的是外层目录，不是里面的代码。
`InPlaceSwap.rotateContents` 复刻的就是这条：外层 `.app` 的 inode、属主、模式全不动。

### `chmod -R 775` 是承重的，不是洁癖

两家 installer 结尾都是 `chown -R root:staff && chmod -R 775`，**递归**。
本机实测 `WeType.app` 里每一个目录都是 775，而厂商 payload zip 解出来是 755/644。
组写位在他们更新的**收尾**那一步才用上：轮换完要 `rm -rf` 被换下的那份 Contents，
而删一棵 root 拥有的树需要树里每一层目录都可写——更新器二进制里那句
`cleanup old Contents failed:` 就是为这个准备的。

所以**轮换**把组写位一路带到底（`chmod -R g+w`，而不是照抄 `-R 775`：后者会把普通文件也变成可执行）。
只保外两层的话，"能预备、不能清理"，每次厂商自更新在 app 里留一份全尺寸残留。

**这条递归只在轮换里，不在整包覆盖那条路上**：输入法已经不走整包覆盖了，
而那条路上真有组可写根目录的 app（本机 137 个 bundle 里 5 个 g+w 根，其中
Microsoft Word 和 Excel 走提权路径，`root:wheel` 775），拿输入法量出来的规则去
放宽它们的整个内部，是没人要求过的改动。整包覆盖那条路的保证因此**恰好是两层**。

### 产物

`zip_download_url` 直接就是**真包**（notarized `WeType.app`，Team 88L2Q4487U），
不是官网页面上那个 ~3 MB 的 stub，所以不需要 DoubaoIme 那样的 `nestedArchivePath`。
响应里的 `zip_download_md5` 没有接——`checksumPattern` 是 SHA-512 base64，
**宁可不声明也不要错声明**；真正的闸是签名 + Team + bundle id + 架构那四道。

### 提权在这里不可用

见 [豆包输入法的同一节](com-bytedance-inputmethod-doubaoime.md#️-提权在这里是不可用的不是不需要)：
App Management 对 root 同样生效，写 bundle **内部**一律 EPERM，写 bundle **旁边**没问题。
轮换因此一律不提权，`needsElevatedReplace` 对输入法只问 bundle 本身可写与否。

### 用户数据安全网

撤回那次丢的东西全部在 bundle 之外：

```
~/Library/Application Support/WeType/userDict     词库
~/Library/Application Support/WeType/mmkv         设置与状态
~/Library/Preferences/com.tencent.inputmethod.wetype.plist
~/Library/Preferences/com.tencent.WeTypeSettings.plist      ← 注意：不共享 bundle id 前缀
```

`InputMethodDataBackup` 跟着 bundle 回滚点一起打快照（APFS clone，103 MB 的
Application Support 目录几乎零成本），`duo backups` 还原时一起还原。
**关掉「保留回滚点」就没有快照**——不绕过用户的选择，代价是那种配置下没有安全网。

**发现的一条：`com.tencent.WeTypeSettings` 和 bundle id 没有公共前缀**，
只按 bundle id 前缀找 plist 会漏掉设置面板的偏好；只按 app 名字找又会漏掉 DoubaoIme 的
`…doubaoime.settings` / `.installer`（那三个都在 bundle id 前缀下）。
所以 `locations()` 两条规则都要：**bundle id 前缀 OR 名字包含**。两家各证一条。

## 验证记录（2026-08-28）

| 检查 | 命令 | 结果 |
|------|------|------|
| 全量测试 | `make test` | Core 1359 / CLI 161 全绿 |
| 活体端点 | `duo verify --samples`（全量 270） | ✗ 0；WeType vendor probe `ok` |
| 正则独立复算 | Python 打真实响应体 | 3 个 pattern 各命中**恰好 1 次** |
| 端到端 红→绿 | 见下 | ✓ 656 → 657 真机真更新 |
| 回滚 | `duo backups restore WeType --yes` | ✓ 回到 656，4 处用户数据一并还原 |

### 端到端实测（2026-08-28）

657 就是最新，本机本来没有可验的更新——所以**造了一个真的红**：
厂商历史 payload 仍然可取（`download.weread.qq.com/app/wxkb/mac/2.2.3/WeType_2.2.3_656.zip`，
实测 200，307 MB，公证过、Team `88L2Q4487U`、`CFBundleVersion 656`）。
用**厂商自己那套手法**（ditto 进 bundle → 两次 rename）把 656 的 Contents 摆成在装版本，
再跑我们的一键。夹具那步刻意不用我们的代码，免得测试自证。

```
duo check   → installedBuild 656 / latestBuild 657 / route in-place
duo install → backed up → downloading → extracting → verifyingCodeSignature → installing → done
```

| 检查 | 结果 |
|------|------|
| 外层 `.app` inode | `212955694` → `212955694`，**未变** |
| 版本 | 656 → **657** |
| 残留 | bundle 内只有 `Contents` |
| `Contents` 下无组写目录 | `find … ! -perm -g+w` → 空 |
| 代码签名 | `valid on disk` + `satisfies its Designated Requirement` |
| 用户数据快照 | 4 处，含只能靠名字命中的 `com.tencent.WeTypeSettings.plist` |
| 回滚 | `duo backups restore` → 657 → 656，4 处用户数据还原，日志带"运行中的输入法要重启才会用上" |
| 再更新 | 656 → 657，机器留在当前版本 |

全程**没有密码框**。

## 建议下一步

1. 盯 `.Contents.update` / `.Contents.old` / `.Contents.abandoned` 这三个名字：
   轮换开工前会检查它们存在与否（存在＝厂商更新器正在飞，拒绝而不是抢它）。
   名字变了这道保护会**静默失效**——判据是这三个字符串还在不在 `WeTypeUpdater` 二进制里。
3. `zip_download_url` 与 `zip_version` 出自同一份 manifest、同一次响应，
   不存在"版本和产物指向不同发布"的漂移面。这条是这个 recipe 比多数 recipe 更稳的地方。
