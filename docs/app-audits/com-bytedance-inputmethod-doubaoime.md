# 豆包输入法 (DoubaoIme)

> 审计于 2026-08-21。ByteDance 的输入法，官网 `shurufa.doubao.com` 下载。
> 结论：**检测 + changelog + 一键全部已接入**。一键 2026-08-28 接入，走
> 输入法专用的 Contents 轮换（原「输入法整类闸」已按安装动作的形状重写）。

## 基本信息
- Bundle ID: `com.bytedance.inputmethod.doubaoime`
- Team ID: `96L78H6LMH`（Developer ID Application: Beijing Chuntian Zhiyun Technology Co., Ltd.）
- 已安装版本: `0.9.6`（`CFBundleShortVersionString`）
- 已安装 build: `90602`（自定义键 `Wave Build Version Number`；`CFBundleVersion` 是废号 `1`）
- 安装路径: `/Library/Input Methods/DoubaoIme.app`
- Info.plist 关键位: `CHANNEL_NAME = release`、无 `SUFeedURL`、无 `KSChannelID`、无 `_MASReceipt`
- 自更新机制: 自研 in-app 更新器（读 `ime.doubao.com/api/v1/version/list`），无 Sparkle

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —¹      | —²       | —   | —      | ✓ ★         |

★ = 生效源。`duo check --all --json DoubaoIme` 实测 `"source":"Vendor"`。

1. bundle 里没有 Sparkle framework，也没有 `SUFeedURL`。
2. Homebrew 的 `doubao` cask 是**不相关的豆包 AI 聊天 app**（`doubao.app`），不是输入法；输入法没有 cask。

**接入前的状态**：`AppScanner` 会扫 `/Library/Input Methods`（为 WeType 加的），
所以 `duo list` 一直能看到 `DoubaoIme 0.9.6`，但优先链里没有任何源应答 → 常驻 `unknown`。
表现上像「一直是最新」，实际是**从来没检查过**。

## Channel 详情

| Channel | 说明 | 状态 |
|---------|------|------|
| `release` | 唯一面向用户的轨，装机 Info.plist `CHANNEL_NAME = release` | ✓ |
| `inhouse` | 版本 API 也应答（0.9.4 / 90407，change_log 是 `warmup v3`），ByteDance 内部灰度 | — 不接 |
| `test`    | 同上（0.9.4 / 90403，change_log 空），QA 轨 | — 不接 |

单 channel app，不需要 ChannelBinding。

## 更新检测

- 源: `VendorProbe`（`mode: .responseBody`）
- 端点: `https://ime.doubao.com/api/v1/app/download_url?platform=macos`
  （官网下载按钮读的同一个接口，`platform` ∈ `android|ios|macos|windows`）
- 真实响应（2026-08-21，183 字节）:
  ```json
  {"code":0,"data":{"url":"https://lf-wave.doubaocdn.com/obj/doubao-ime/app/macos/DoubaoImeInstaller_v90602_release.zip","version_code":1002007,"version_name":"V0.9.6"},"msg":"success"}
  ```
- `versionPattern`: `DoubaoImeInstaller_v([0-9]+)_release\.zip` → `90602`（`versionIsBuild: true`）
- `displayVersionPattern`: `"version_name"\s*:\s*"[Vv]?([0-9]+(?:\.[0-9]+)+)"` → `0.9.6`（行上显示的）

### ⚠️ 版本方案：一个响应里三个数字，只有一个有本地对应物

| 数字 | 来自 | 装机侧对应物 |
|------|------|-------------|
| 文件名里的 `v90602` | 厂商 version code | **Info.plist `Wave Build Version Number` = `90602`** ✓ 比这个 |
| `version_name` `"V0.9.6"` | 营销版本 | `CFBundleShortVersionString` = `0.9.6` → 只用来**显示** |
| `version_code` `1002007` | 第三套命名空间 | 无。永远不要比 |

`CFBundleVersion` 是**每个 build 都恒等于 `1`** 的废号——厂商把真号放进了自定义键
`Wave Build Version Number`（另有点分形式 `Wave Build Version = 0.9.6.2`，主 bundle 和
`DoubaoImeSettings.app` 子 bundle 里都有一份）。

所以 `AppScanner.buildVersionIsOverridden` 把这个 bundle id 也纳进来了（此前只有 Xcode），
`buildVersion` 用 `Wave Build Version Number` 顶掉 `CFBundleVersion`；recipe 走
`versionIsBuild: true` + `displayVersionPattern`，和 WeType 同形。

**没有 `?? CFBundleVersion` 兜底，是故意的**：厂商哪天丢掉那个键，`AppScanner` 报
**nil**，`evaluate()` 退回比营销版本（降级但安全）；若兜底成 `1`，就是 `90602 > 1` 的
永久幽灵更新。这条由 `doubaoImeBuildComesFromTheWaveKeyAndFallsBackToNothing` 和
`doubaoImeVerdictIsExactWithTheKeyAndSafeWithoutIt` 钉住。

> **修正记录**：本审计初版判定「`90602` 在本地没有对应物」，据此只比营销版本，并接受
> 「同营销版本内的重发（90601 → 90602）检测不到」这个盲区。那是**读漏了 Info.plist**
> —— `plutil -p` 的输出里那两个自定义键排在很后面。号是有的，盲区已消除。

### 内测包旁证（`DoubaoImeInstaller_v0.5.7.app`，构建于 2026-03-26）

**这是一份内测包。** 豆包输入法 Mac 版 2026 年 3 月底走微信公众号私下发内测包，
[2026-05-12/13 才正式上线官网](https://www.appinn.com/doubao-shurufa-macos/)；
0.5.7 的构建日期落在内测窗口内，且它的 `com.apple.quarantine` 只记到 Keka、
没有 `shurufa.doubao.com` 的 `kMDItemWhereFroms`（同目录下 90602 那份有）。

> **判据修正**：初次审计据「Developer ID 签名 + 已公证 + `ProvisionsAllDevices` 分发档」
> 判定它「不是内测包」。**这三条对内测包同样成立**——公众号发出去的包要能在别人机器上跑，
> 就必须这么签、这么公证。用一个对两种情况都为真的事实去否定其中一种，是无效推理。

因此这份包能佐证什么、不能佐证什么，要分清：

**能佐证**：一个不带本方案的 bundle 长什么样。它的 Info.plist 没有
`Wave Build Version` / `Wave Build Version Number`、没有 `CHANNEL_NAME`，
**连 `CFBundleVersion` 都没有**。对它跑 `channel-verify`：
`build version <none>` → 走营销分支 → `UPDATE 0.5.7 → 0.9.6`。降级路径在真包上成立。

**不能佐证**：「正式版里这些键可能消失」。那是**发布前的形态**，不是发布后的行为。
no-fallback 的设计不靠这个预测撑——它零成本、且严格更安全，两种情况下都该这么写。

**也不能佐证「下载文件名方案不稳」**（初版审计据此把 `versionPattern` 列为最脆一环，
现撤回）：`DoubaoImeInstaller_v0.5.7.app` 是**内测期**的命名。手上仅有的两个**公开**样本
——`DoubaoImeInstaller_v90602_release.zip`（官网）和
`DoubaoImeInstaller_v90601_release_20260814_120854_64003a2e.zip`（push feed）
——是同一形状 `_v<code>_release`。两个样本不足以证明"稳定"，但没有任何变更证据。
真变了 probe 会报「resolved no version」，`duo verify` 夜扫会响——失败方向是响的那边。

安装器做了什么（两代 `install.sh` 基本一致）：`unzip` → 杀 `OceanIme`/`DoubaoIme` 进程 →
`rm -rf "$INPUT_METHODS_DIR"/DoubaoIme*.app` → `mv` → 去 quarantine →
（新版多了 `sudo chown -R root:staff` + `chmod -R 775`）→ `killall SystemUIServer`。
**注册不在脚本里**：安装器二进制导入 `_TISRegisterInputSource` / `_TISEnableInputSource` /
`_TISSelectInputSource`，并带字面量 `Registered input source from `。
也就是说它不只是拷贝，还负责注册、启用、选中输入源——这正是覆盖安装会整个跳过的部分。
（`boe-gateway.byted.org` 两代安装器里都有，是 ByteDance 通用 SDK 的死配置，不是环境标记。）

## Channel 详情（补充：其他环境版本装在别的路径）

`install.sh` 的安装路径是 `"$INPUT_METHODS_DIR/$APP_NAME.app"`，**`APP_NAME` 来自环境变量**，
而且脚本会 `rm -rf "$INPUT_METHODS_DIR"/DoubaoIme*.app`，注释写的是
「移除可能存在的其他环境版本，防止系统设置中出现多个重复的输入法」。

意味着非 release 的构建（`inhouse` / `test`）装在**同一个 bundle id、不同的 .app 文件名**下。
今天不接那两个轨，所以没有影响；真要接，检测信号是 **bundle 文件名 + `CHANNEL_NAME`**
（后者 0.9.6 才有），和 Android Studio 那套同形。

## Changelog

- 来源: `ChangelogRecipe`（`mode: .json`）
- 端点: `https://ime.doubao.com/api/v1/version/list?channel=release&version_code=1&platform=macos`
- 官网**没有任何 release notes 页面**——notes 只存在于 app 自己的更新器读的这个接口里，
  所以 recipe 没有 `changelogURL` WebView 兜底（没有值得嵌的页面）。
- 接口语义是「一个跑在 `version_code=N` 上的客户端应该被推什么」：
  - 三个参数缺一个就 400（`渠道不能为空` / `当前版本不能为空` / `平台不能为空`）；
  - 调用方已是最新时返回 `[]`（实测 `version_code=90602` → 空，`≤90601` → 有）。
  - 所以我们固定传 **`version_code=1`**（假装是个远古客户端），无论读者装的什么版本都能拿到最新那条 notes。
- `change_log` 是一串 `- ` 开头、用转义 `\n` 连接的行；`push_message.title` 里还藏着**第二个** `0.9.6`，
  entry pattern 锚在 `"platform":"macOS"` + 按字段发出顺序走，够不到它。

### ⚠️ 抄 ChatWise 的 itemPattern 会吞掉最后一条

ChatWise recipe 的尾部 alternative 是 `\\n?$`——这在正则里是
「**一个字面反斜杠**，后面可选一个 `n`，然后到结尾」，要求正文以反斜杠结尾。
正文以文字结尾时它永远不成立，**最后一个 bullet 被静默丢掉**。
本 recipe 用 `|$)`。真实响应实测：6 条进，6 条出（`extractsAllDoubaoImeBulletsIncludingTheLast`）。

> ChatWise（`app.chatwise`）自己仍带着这个 bug，见「已知问题」。

## 一键安装

- 状态: **已接入（2026-08-28）**，走**输入法专用的 Contents 轮换**，不是整包覆盖。
- 此前是 detection-only，阻塞在 `UpdatePolicy.isInputMethod` 的整类闸
  （WeType 2026-08-16 一键上线当天因用户设置丢失而撤回）。整类闸已换成
  `UpdatePolicy.isContentsRotatable`：**按安装动作的形状**放行，而不是按位置一刀切。

### 为什么可以做了：厂商自己的更新就是 Contents 轮换

`install.sh` 是**首装**路径（`rm -rf` 整个 `.app` 再 `mv` 新的进去）。
豆包**自己的 in-app 更新器**不走这条——它保留外层 `DoubaoIme.app`，
用 `Contents` / `Contents_update` / `Contents_backup` 三个目录做近似原子切换。
WeType 同形（`.Contents.update` / `.Contents.old` / `.Contents.abandoned`，
其更新器二进制里还有 `will exchange Contents: previous=`）。

`InPlaceSwap.rotateContents` 复刻的就是这一条：外层 `.app` 的 inode、属主、模式全不动，
只换里面的 `Contents`，失败原地回滚。**被 `TISRegisterInputSource` 注册的是那个路径**，
所以保住它才是关键，而不是保住里面的代码。

### 产物：本 registry 里唯一一个「下载的不是 app」

`download_url` 给的是 `DoubaoImeInstaller_v<code>_release.zip`（约 190 MB），
解出来是 `DoubaoImeInstaller.app` 这个**安装器壳**，真包在它的
`Contents/Resources/DoubaoIme.zip`（170 MB）里。所以 recipe 用
`VendorInstallSpec.nestedArchivePath` 拆一层：

1. 先验**壳**的代码签名 + Team（`96L78H6LMH`，与装机 app 同 Team；
   **不钉 bundle id**——壳是 `…doubaoime.installer`，按构造就是兄弟）；
2. `Contents/Resources` 由壳自己的签名封存，所以「签名有效」是一句关于内层 zip 的陈述；
3. 拆出 `DoubaoIme.app` 后，签名 / Team / **bundle id** / 架构四道闸原样再跑一遍。

没有这一层，bundle id 闸会（正确地）拒绝 `…doubaoime.installer`，一键根本不可能成立。

### ⚠️ 提权在这里是**不可用**的，不是「不需要」

写**另一个 app 的 bundle 内部**受 App Management（`kTCCServiceSystemPolicyAppBundles`）
门控，而且**这道闸对 root 也生效**。同一个 root shell、同一个目录，2026-08-28 实测：

```
uid 0  ditto → /Library/Input Methods/.probe                 status 0
uid 0  ditto → /Library/Input Methods/DoubaoIme.app/.probe   Operation not permitted
```

`osascript … with administrator privileges` 起的子进程没有自己的 TCC 身份，
所以提权路线在这里**严格弱于**不提权：DuoUpdater 自己持有 App Management，
同一条 `ditto` 由它来跑就成功。第一版实现走了提权，实测报
`ditto: …/.Contents.duoupdater-new: Operation not permitted`。

推论有三条：
- 整包覆盖那条路不受影响——它写的 `.duoupdater-new` / `-old` 全在 bundle **旁边**；
- 轮换一律不提权，`InPlaceSwap.needsElevatedReplace` 对输入法只问 bundle 本身可写与否
  （否则行上会承诺一个永远不会出现的密码框）；
- 代价是 `Contents` 的属主从 `root:staff` 变成当前用户。**对这两个装机形态不改变任何人的写权限**
  ——两者都是 `775` + 组 `staff`，组权限本来就等同属主权限——厂商 installer 下次跑还会
  `chown -R root:staff` 改回去。这条变化会写进日志，不静默。

### ⚠️ bundle 根目录下**任何**残留都会让签名失效

实测（真 `DoubaoIme.app` 的副本）：在 bundle 根下建一个**空的隐藏目录**
`.Contents.duoupdater-new`，`codesign --verify --strict` 立刻从 `valid on disk`
变成 `unsealed contents present in the bundle root`，删掉又恢复。
（`.DS_Store` 由签名规则豁免，我们这个不是。）

所以轮换留下的暂存目录不是"整洁问题"：清不掉就等于一个过不了 Gatekeeper 的输入法。
两处应对——`replaceItemAt` 用**具名**备份（`.Contents.duoupdater-old`，成功时它自己删掉，
实测换完 bundle 里只剩 `Contents`），启动时的 sweep 现在也扫两个 Input Methods 目录
（此前只扫 `/Applications`，而轮换的残留在 bundle **里面**，永远扫不到）。

### 一键之外的一道闸：`requiresInstaller`

`isContentsRotatable` 只在 `canAutoInstall` 里。但每个调用方都是
`canAutoInstall || requiresInstaller`——**`||` 让第二个成立就绕过了第一个**。
今天两条 recipe 都是 `.zip`，够不到；但厂商换产物、或者 `kind:` 改一个词，
就会把 Contents 轮换变成"root 跑一个 vendor pkg 盖在已注册的输入源上"，
没有任何代码改动、没有任何闸响。所以 `requiresInstaller` 里也加了整类拒绝。
（`PackageInstaller` 的目的地检查兜不住：它只在 `/Applications` 里硬拒，
其他位置退回按 bundle 名匹配。）

### 用户数据安全网

一键之前先对输入法的**用户数据**打快照（`InputMethodDataBackup`），和 bundle 回滚点同一代、
同一个 key 目录、同样 retention=1，`duo backups` 还原时一起还原。
**它跟着 bundle 回滚点走**——用户关掉「保留回滚点」就同样没有快照（故意的：
对方说了不要备份，还偷偷把他的数据抄一份到磁盘上是错的）。本机实测捕获 4 处：

```
~/Library/Application Support/DoubaoIme            （含 EngineUserDict / EngineUserDictAccounts）
~/Library/Preferences/com.bytedance.inputmethod.doubaoime.plist
~/Library/Preferences/com.bytedance.inputmethod.doubaoime.settings.plist
~/Library/Preferences/com.bytedance.inputmethod.doubaoime.installer.plist
```

578 MB 的 Application Support 目录**克隆**过去只要 0.096 s、几乎不占空间（APFS，`ditto` 会 clone）。
轮换本身证明碰不到 bundle 以外的任何东西，这个快照防的是**换完之后 app 自己**
对用户数据做的迁移/降级——那是 app 的代码跑在用户数据上，我们没有闸能拦。

## 验证记录（2026-08-21）

| 检查 | 命令 | 结果 |
|------|------|------|
| 单元测试 | `cd DuoUpdaterCore && swift test --filter Doubao` | 5/5 ✓ |
| 全量 | `make test` | 821 + 119 全绿（2 个既有 known issue）|
| 活体端点 | `duo verify --only doubao` | vendor probe ✓1 / changelog ✓1 |
| 端到端（绿）| `duo check --all --json DoubaoIme` | `installedBuild: 90602` / `latestBuild: 90602` / `up-to-date` |
| 端到端（红）| `channel-verify` 打把 `Wave Build Version Number` 改成 90601 的副本 | `UPDATE 0.9.6 (90601) → 0.9.6 (90602)` |
| 未回归 | `channel-verify /Library/Input Methods/WeType.app` | `up to date`（同为 versionIsBuild）|
| 降级路径（真包）| `channel-verify` 打 0.5.7 的真实 payload（无任何 build 键）| `build version <none>` → `UPDATE 0.5.7 → 0.9.6` |

## 已知问题

- **ChatWise 的 changelog 最后一条被吞**（`app.chatwise`，`ChangelogRecipe.swift` 的
  `(?=\\n-\s|\\n?$)`）。本次审计顺带发现，未在本改动里修——属于另一个 app 的行为改动。
- **`channel-verify` 此前对所有 `versionIsBuild` recipe 判错字段**（本次顺手修）：它重新实现了
  一遍比较（`shortVersion` 存在就比营销版本），而 `versionIsBuild` 的 recipe 两个都带——
  build 用来比、营销串用来显示——引擎 `evaluate()` 优先比 build，harness 优先比营销串。
  结果是打降到 90601 的 bundle 在 harness 里显示「up to date」，而实际链路正确给出 90602。
  已改成直接调 `UpdateChecker.evaluate`。**重新实现一遍闸门，正是 harness 漏掉它本该抓的东西的方式。**

## 端到端实测（2026-08-28，真机真更新 90602 → 90703）

```
duo install com.bytedance.inputmethod.doubaoime --yes
→ backed up 0.9.6 → downloading… → extracting → verifyingCodeSignature → installing → done
1 installed, 0 failed.          （全程无密码框）
```

换完的磁盘状态：

| 检查 | 结果 |
|------|------|
| 外层 `.app` inode | `203661759` → `203661759`，**未变**（注册路径活着） |
| `Contents` inode | `203661761` → `213316313`，已换 |
| 版本 | `Wave Build Version Number` `90602` → `90703`，`0.9.6` → `0.9.7` |
| 外层属主/模式 | `root:staff` `drwxrwxr-x`，未变 |
| `Contents` 属主 | `bobby:staff`（不提权的已知代价，见上） |
| `Contents` 下无组写目录 | `find … -type d ! -perm -g+w` → 空 |
| 残留 | bundle 内只有 `Contents`，无 `.Contents.duoupdater-*` |
| 代码签名 | `valid on disk` + `satisfies its Designated Requirement` |
| 输入源注册 | `com.apple.HIToolbox` 里 bundle id + input mode 仍在 |
| 用户数据 | 原地未动，且快照 4 处齐全 |

失败路径也是真跑出来的：提权那一版在同一台机器上报
`ditto: …/.Contents.duoupdater-new: Operation not permitted`，
**bundle 一个字节没动**（inode 与版本都不变）——原子性顺序按设计成立。

## 建议下一步

1. 一键已接入并端到端验证。盯 `Contents_update` / `Contents_backup` 这两个名字：
   轮换在开工前会检查它们是否存在（存在＝厂商更新器正在飞，拒绝而不是抢），
   名字变了这道保护会静默失效。
2. 盯着 `Wave Build Version Number` 这个键会不会消失。它一没，检测自动降级成比营销版本
   （安全，但重发又看不见了）；`duo verify` 不会因此报错，因为端点那边没变。
   真要监控，判据是本机 `installedBuild` 从 `90602` 变回 `<nil>`。
3. `versionPattern` 锚在 `DoubaoImeInstaller_v<数字>_release.zip` 上。已知的两个公开样本
   同形，无变更证据（0.5.7 那个不同的命名是内测期的，不算）。真变了 probe 会报
   「resolved no version」，夜扫能抓到；届时要么跟新命名，要么退回只比 `version_name`
   （代价是丢掉同营销版本内的重发检测）。
