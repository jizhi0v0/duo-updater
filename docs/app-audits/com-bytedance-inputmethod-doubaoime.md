# 豆包输入法 (DoubaoIme)

> 审计于 2026-08-21。ByteDance 的输入法，官网 `shurufa.doubao.com` 下载。
> 结论：**已接入检测 + changelog；一键按输入法整类闸不做**。

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

- 状态: **仅检测（detection-only）**
- 阻塞：`UpdatePolicy.isInputMethod` 对 `/Library/Input Methods` 下的一切**整类**拒绝一键
  （WeType 2026-08-16 一键上线当天因用户设置丢失、设备列表出现两个同名 Mac 而撤回）。
- **不是因为没有产物**：`download_url` 直接给了安装包地址。实际下载到的
  `DoubaoImeInstaller_v90602.app` 是 202 MB 的**带 payload 安装器**，
  `Contents/Resources/` 里是 `DoubaoIme.zip` + `install.sh`——
  也就是说厂商自己也走「安装器注册 input source」，不是单纯拷贝 bundle。覆盖安装会整个跳过这一步。

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

## 建议下一步

1. 无。检测 + changelog 均已接入并验证；一键按整类闸永久不做。
2. 盯着 `Wave Build Version Number` 这个键会不会消失。它一没，检测自动降级成比营销版本
   （安全，但重发又看不见了）；`duo verify` 不会因此报错，因为端点那边没变。
   真要监控，判据是本机 `installedBuild` 从 `90602` 变回 `<nil>`。
3. `versionPattern` 锚在 `DoubaoImeInstaller_v<数字>_release.zip` 上。已知的两个公开样本
   同形，无变更证据（0.5.7 那个不同的命名是内测期的，不算）。真变了 probe 会报
   「resolved no version」，夜扫能抓到；届时要么跟新命名，要么退回只比 `version_name`
   （代价是丢掉同营销版本内的重发检测）。
