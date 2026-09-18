# 千问输入法 (QianwenIME)

> 审计于 2026-09-18。阿里的输入法，官网 `ime.qianwen.com` 下载，装到
> `/Library/Input Methods`。结论：**检测 + 一键都接**。版本读官网下载按钮自己读的那个接口
> （app 自己的更新检查是加密 protobuf，读不了）；一键走 `nestedArchivePath` 解包 +
> 输入法 `Contents` 轮换，与厂商 `update.sh` 同型。

## 头条：它自己的更新检查是加密的，所以我们读的是官网的下载接口

`QianwenIMEService` 的更新检查走 Quark PUDS：

```
POST https://puds.qianwen.com/upgrade/index.xhtml?from=pb_query
```

请求体是 protobuf（`quattro_puds_update.pb.cc`），再整体用 WSG 加密，响应同样加密后解密。
二进制里的日志串把这条链写得很明白：

```
build PUDS request
failed to encrypt Quark PUDS request with WSG
failed to decrypt Quark PUDS response with WSG
official update PUDS encrypted payload
official update response missing upd_rst / url / version / checksum
```

没有任何明文形状可以正则，要构造请求等于重新实现阿里的安全组件。**这条端点同时也是按设备
灰度的分配通道**——我们读的不是它（见下面「读的是什么」）。

于是探针改读官网下载按钮读的那条。官网 `ime.qianwen.com/download/mac` 是个 SPA，真正发请求的是
buwang SDK 那个 chunk，拼出来的地址是：

```
GET https://download.qianwen.com/pcdownload/qwenimemac?ch=pcqwenime@homepage_official&platform=mac

→ 200 application/json
{"success":true,"code":"OK","data":{
   "fp":"dapi-<uuid>",
   "url":"https://umcdn.qianwen.com/download/37317/qwenimemac/pcqwenime@homepage_official/QwenimeMac_V1.2.26.41_mac_pf8002_(zh-cn)_release_(Build3192975).dmg"},
 "msg":"","timestamp":…,"traceId":…}
```

`fp` 是每次请求现签的一次性下载指纹（连发三次得到三个不同 uuid），探针不读它，也**不许**把任何
一个写进 recipe 或 fixture。

## `ch` 决定答案，而且回落是静默的

同一分钟内，只改 `ch` 的实测（2026-09-18）：

| `ch` | 应答的包 |
|------|----------|
| `pcqwenime@homepage_official` | `QwenimeMac_V1.2.26.41_…(Build3192975).dmg` |
| 省略 `ch` | `QwenimeMac_V1.2.2.32_…(Build3134283).dmg`（落到 `pcqwenime@default`） |
| `pcqwenime@beta` | 同上，`V1.2.2.32` |
| `pcqwenime@inner` | 同上，`V1.2.2.32` |

两个结论：

1. **`@beta` / `@inner` 不是真轨道**，只是不认识的值回落到 `@default`。这个 app 没有可发现的
   非 stable 发布轨道（Info.plist 里确实有 `QianwenUpdateChannel = stable` 和
   `QianwenSubVersion = release` 两个键，但公开面上没有第二个值可取）。
2. **回落不报错**。如果厂商哪天下掉 `@homepage_official`，探针照样 200，只是答一个远低于任何
   真实安装的版本号——那会被 `duo verify` 报成 `remote is BEHIND the installed copy`，
   是响的失败不是哑的。

钉住的 `ch` 不是从某台机器上抄来的：它就是官网首页那条发布渠道，凡是从那页下载的包，Info.plist
里的 `QianwenChannelId` / `QianwenPackageChannelId` 都是这个值。

## 别去读 `ime.qianwen.com/api/download-config`

这个接口看起来才像“版本源”，它是个坑，三条都实测于 2026-09-18：

```json
"mac":{"enabled":true,
       "url":"https://pdds.qianwen.com/download/stfile/…/QianwenIMEInstaller_V1.2.2.32.zip",
       "version":"1.2.2.33","size":98304000,"updatedAt":"2026-08-14T21:45:00Z"}
```

- `version` 写 `1.2.2.33`，`url` 里却是 `V1.2.2.32`，**自己跟自己不一致**；
- `updatedAt` 停在 2026-08-14，早已不动；
- **官网自己不用它**：页面 JS 的 `normalizePlatformConfig` 对 mac/windows 在
  `buwang.enabled` 为真时直接返回空 url（当前就是真），按钮走 `/download/<platform>`，
  再走上面那条 `pcdownload` 接口。

拿它做 recipe 会报出一个低于所有真实安装的版本。

## 基本信息
- Bundle ID: `com.qianwen.inputmethod.desktopime`
- Team ID: `8T9NQJXDU3`（Developer ID Application: Shanghai Zhixin Puhui Technology Co., Ltd.）
- 观测版本: `1.2.26`（`CFBundleShortVersionString`）/ `1.2.26.41`（`CFBundleVersion`）
- 安装路径: `/Library/Input Methods/QianwenIME.app`
- 自更新机制: 自研（Quark PUDS + WSG 加密），随包的
  `Contents/Helpers/{QianwenIMEUpdater, QianwenIMEAtomicSwap, QianwenIMERelaunch, QianwenIMEService.app}`
- OS 下限: `LSMinimumSystemVersion = 13.0`，安装器 metadata 的 `MinimumSystemVersion` 同为 `13.0`。
  端点本身**不声明任何 OS 窗口**，所以没有写进 `hostRequirement`（那是给按代冻结的下限用的，
  这里是纯检测，装不装由用户决定）
- 无 `SUFeedURL`、无 MAS receipt；`feed-discover` 判 `no Sparkle and no electron-builder update config`
- **Homebrew 陷阱**：`brew search --cask qianwen` 命中的 `qianwen` cask 装的是 `Qianwen.app`，
  阿里的 Qwen 聊天客户端，和输入法无关——和豆包那边 `doubao` cask 的坑同形

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**

**接入前的状态**：`AppScanner` 扫 `/Library/Input Methods`，所以 `duo list` 看得见它，
但优先链里没有源应答 → 常驻 `unknown`。和搜狗、豆包接入前一样，“看着像最新”其实是
**从来没检查过**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.qianwen.inputmethod.desktopime` | — | — | — | ✓ |

未发现第二条公开发布轨道（见上面的 `ch` 实测表）。Info.plist 的 `QianwenUpdateChannel` 键
留了口子，但公开面上取不到 `stable` 以外的值，所以不进 `CHANNEL_COVERAGE_TODO`。

## 更新检测
- 源: VendorProbe (`.responseBody`)
- 端点: `https://download.qianwen.com/pcdownload/qwenimemac?ch=pcqwenime@homepage_official&platform=mac`
- 版本方案（三个号，比哪个是整条 recipe 的关键）：

  | 来源 | 值 | 用途 |
  |------|-----|------|
  | 包名 `QwenimeMac_V…` | `1.2.26.41` | **比这个**，等于装机侧 `CFBundleVersion` → `versionIsBuild: true` |
  | 装机 `CFBundleShortVersionString` | `1.2.26` | 行里**显示**这个 → `displayVersionPattern` 取前三段 |
  | 包名里的 `(Build3192975)` | `3192975` | 第三个 namespace，本地没有对应，**永远别比** |

- pattern 要求四段齐全 + `_release_`：方案一变或者拿到非 release 产物，解析不出任何版本
  （响的失败），而不是答半个号。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查到 | 没查（端点加密，问不了） | 不能 |
| 证据 | `QianwenIMEUpdater` / `QianwenIMEService` 里只有整包路径：`--payload-zip`、`QianwenIME.zip`、`PayloadSHA256`、`PayloadArchiveBytes`；没有 bspatch/hdiff/xdelta/delta 一类串 | PUDS 请求与响应都被 WSG 加密，拿不到任何真实响应体 | 无 patch URL 可取；`DeltaApplier` 只会应用 Sparkle binary delta |

- 格式: 未知（未见迹象）
- 阻塞项: 服务端一栏要真实响应才能填，而真实响应是加密的

## Changelog
- 来源: **无**。`ime.qianwen.com` 上 `/changelog`、`/release-notes`、`/updatelog`、`/help`
  一律 404（2026-09-18）；发布说明随加密的 PUDS payload 下发，只以 app 自己的“已更新”通知露面
- 跟随 channel: 不适用
- Recipe 状态: 不需要。`changelogURL` 留空而不是指向营销页——与豆包同一个判断

## 一键安装
- 状态: **支持**
- 格式: dmg（外层是安装器壳，真 app 在内层 zip → `nestedArchivePath`）
- **读的是**: 轨道最新 —— 准确说是**官网首页下载渠道当前发布的那一个包**，
  和人点 `ime.qianwen.com` 上的「下载」拿到的字节完全一致（实测两处下载同为
  200,356,907 bytes）。不是本机被分配的构建（那是 PUDS，读不了）。属于 Claude `/latest`
  那类「有人工下载路径的 GA」，不是 CapCut beta 那类「只有知道 URL 才拿得到」

### 判据：厂商有两个脚本，UPDATE 是做 Contents 轮换的那个

这一条是整个一键决策的支点，**只读安装器那份会得出相反的结论**：

| 脚本 | 在哪 | 干什么 | 是哪条路径 |
|------|------|--------|-----------|
| `macos_install_core.sh` | 安装器壳的 Resources | `rm -rf "$INSTALL_ROOT"/QianwenIME*.app` → `chown -R root:staff` → `chmod -R 775` → `mv -f` → 去隔离 → 逼文本输入子系统重扫注册 | **首装** |
| `update.sh` | **装机 bundle 自己**的 `Contents/Resources/`，并列在 `QianwenIMEService` 的完整性检查清单里 | `Contents` 原子轮换，见下 | **自更新** |

`update.sh` 的核心（非 root 分支 `update_normally`）：

```bash
CONTENTS_UPDATE="$DESTINATION/Contents_update"
mv "$PAYLOAD_APP/Contents" "$CONTENTS_UPDATE"
xattr -d -r com.apple.quarantine "$CONTENTS_UPDATE"
"$ATOMIC_SWAP_HELPER" --current "$DESTINATION/Contents" --next "$CONTENTS_UPDATE"
chown -R root:staff "$DESTINATION"; chmod -R 775 "$DESTINATION"
```

`QianwenIMEAtomicSwap` 的导入符号里与文件系统相关的只有一个 `_renameatx_np`，
它收 `--current` / `--next` 两个目录做 `RENAME_SWAP` 交换，自己不构造任何路径。
**外层 `.app`、它的 inode、输入源注册全程没动**——`update.sh` 里根本没有 TIS 那一步。
暂存目录叫 `Contents_update`，与豆包自更新同名。

所以 `InPlaceSwap.rotateContents`（按 `/Library/Input Methods` 自动生效）**与厂商自更新同型**，
不是替代品。root 分支只是先修一次属主再走同一段轮换。

### 包型与闸

DMG 根只有一个 app：安装器壳 `com.qianwen.inputmethod.desktopime.installer`
（Team `8T9NQJXDU3`，与装机侧同 Team），真 `QianwenIME.app` 在它的
`Contents/Resources/QianwenIME.zip`。壳的签名封着 `Contents/Resources`，`VendorInstaller`
先验壳（签名 + Team，**不**钉 bundle id——壳的 id 按构造就是 app 的兄弟）再取 payload，
之后签名/Team/bundle id/架构每一道闸在 payload 上重跑一遍。

不设 `checksumPattern`：响应里没有任何摘要，壳的 `QianwenInstallerMetadata.plist` 里的
`PayloadSHA256` 既是错的哈希类型（SHA-256，不是 base64 SHA-512）也描述错了对象
（内层 zip 而非下载物）。刻意留空而不是错填——与 WeType 的 `zip_download_md5` 同一个处理。

### 用户数据

不在 bundle 里，`InputMethodDataBackup` 按 bundle 名和 bundle id 前缀通用发现，**无需登记**：

```
~/Library/Application Support/QianwenIME/
~/Library/Preferences/com.qianwen.inputmethod.desktopime.plist
~/Library/Preferences/com.qianwen.inputmethod.desktopime.service.plist
~/Library/Preferences/com.qianwen.inputmethod.desktopime.installer.plist
```

## 已知问题
- `ch` 回落静默（上面「回落是静默的」一节）——失败方向是安全的，但值得在 verify 报表里认出来
- 增量那栏的“服务端实际下发”永远填不上，除非有人能解开 WSG

## 如何复验

```bash
# 1. 端点还在答，而且答的是四段版本号
curl -sS 'https://download.qianwen.com/pcdownload/qwenimemac?ch=pcqwenime@homepage_official&platform=mac'
#    → {"success":true,…,"data":{"fp":"dapi-…","url":"…/QwenimeMac_V<四段>_mac_…_release_(Build…).dmg"}}

# 2. 真实 bundle 上跑生产的 detect() + 探针
swift run --package-path application-test channel-verify \
  '/Library/Input Methods/QianwenIME.app' --expect stable

# 3. 注册表扫一遍这条
make cli && duo verify --only qianwen --vendor
```

2026-09-18 的结果：

- `channel-verify`：`detected channel → stable`、`✓ detection matches --expect stable`、
  `VendorProbe ✓ recipe answered for channel 'stable'`，`latest 1.2.26` /
  `version(build) 1.2.26.41` / `verdict up to date`；`UpdateChecker.check()` 的
  `winning source` 为 `Vendor`
- `duo verify --only qianwen --vendor`：`vendor probe ✓ 1 ⚠ 0 ✗ 0`
- `swift test --package-path DuoUpdaterCore`：3360 tests / 291 suites 全绿

## 历史与实测

### 2026-09-18 — 接入（检测）

`ch` 的逐值实测，同一分钟内只改这一个参数：

| `ch` | 应答的包 |
|------|----------|
| `pcqwenime@homepage_official` | `QwenimeMac_V1.2.26.41_mac_pf8002_(zh-cn)_release_(Build3192975).dmg` |
| 省略 | `QwenimeMac_V1.2.2.32_mac_pf8002_(zh-cn)_release_(Build3134283).dmg`（`pcqwenime@default`） |
| `pcqwenime@beta` | 同省略，`V1.2.2.32` |
| `pcqwenime@inner` | 同省略，`V1.2.2.32` |

`fp` 三次请求三个不同 uuid，确认是一次性下载指纹。

`ime.qianwen.com/api/download-config` 当时的 `mac` 条目原文：

```json
"mac":{"enabled":true,
       "url":"https://pdds.qianwen.com/download/stfile/…/QianwenIMEInstaller_V1.2.2.32.zip",
       "version":"1.2.2.33","size":98304000,"updatedAt":"2026-08-14T21:45:00Z"}
```

`version` 与 `url` 里的版本号不一致（`.33` vs `V…​.32`），`updatedAt` 停在 2026-08-14。
同日官网页面 JS 的 `normalizePlatformConfig` 对 mac/windows 在 `buwang.enabled` 为真时
返回空 url，实测该字段未被页面使用。

changelog 页排查：`ime.qianwen.com` 上 `/changelog`、`/release-notes`、`/updatelog`、
`/help` 四条全部 404。

验收（命令与结果见上面「如何复验」）：`channel-verify` 检测 stable + 探针 `up to date`、
`duo verify --only qianwen --vendor` 1 ✓ 0 ✗、`swift test --package-path DuoUpdaterCore`
3360 tests 全绿。

### 一键安装 —— 真包闸链实测（2026-09-18）

按 recipe 解析出的 URL 实时下载，跑生产会跑的每一道闸：

```
下载              200,356,907 bytes（与官网手动下载的包同字节数）
DMG 根            只有 千问输入法.app 一个 app
壳 codesign       --verify --deep --strict OK
壳 Identifier     com.qianwen.inputmethod.desktopime.installer
壳 TeamIdentifier 8T9NQJXDU3（= 装机侧 Team）
内层 zip          Contents/Resources/QianwenIME.zip，196,982,756 bytes → QianwenIME.app
payload codesign  --verify --deep --strict OK
payload spctl     accepted / source=Notarized Developer ID
                  origin=Developer ID Application: Shanghai Zhixin Puhui Technology Co., Ltd. (8T9NQJXDU3)
payload Identifier com.qianwen.inputmethod.desktopime（= 装机侧）
payload 版本      short=1.2.26 build=1.2.26.41（= recipe 解析出的号）
payload 架构      x86_64 arm64
payload 自带      Contents/Resources/update.sh + Contents/Helpers/QianwenIMEAtomicSwap
                  （轮换进去的 Contents 把厂商自己的更新器一并带上）
```

`QianwenIMEAtomicSwap` 的文件系统相关导入符号只有 `_renameatx_np`（`nm -u`），
确认它就是 `RENAME_SWAP` 原子交换而非拷贝。

### 真机红→绿（2026-09-18）

**造红用厂商自己的机制**：跑装机 bundle 的 `Contents/Resources/update.sh --payload-zip <1.2.2.32 的
QianwenIME.zip>`（旧包从 `pcqwenime@default` 那条取）。它自己打印
`atomic swap succeeded current=…/Contents next=…/Contents_update`，外层 inode 不变。
跑完要删掉它留在 bundle 根的 `Contents_update`（692 MB，且 bundle 根有残留就破坏签名）。

> 旧包的安装器壳叫 `QianwenIMEInstaller.app`，新包叫 `千问输入法.app`——**壳名在版本间变过**。
> recipe 不依赖壳名（`nestedArchivePath` 是相对路径），但任何按名字找壳的做法都会碎。

红：`duo check` → `QianwenIME 1.2.2 → 1.2.26 [Vendor, in-place]`

绿：`duo install QianwenIME --yes` → `backed up 1.2.2` / `downloading…` / `extracting` /
`verifyingCodeSignature` / `installing` / `installed.`（约 80 秒），末尾提示
`Still running the old code: QianwenIME → duo restart QianwenIME`——**没有强杀正在运行的输入法**。

| 核对项 | 结果 |
|--------|------|
| 版本 | 1.2.26 / 1.2.26.41 ✓ |
| **外层 `.app` inode** | 253890560，与测试前**逐位相同** ✓（TIS 注册的就是这个身份） |
| `Contents` inode | 每轮都变（轮换确实发生） |
| bundle 根 | 只有 `Contents`，无残留 ✓ |
| 签名 / spctl | `--verify --deep --strict` OK；`accepted` ✓ |
| 用户数据 | 1.2M / 48 files，与测试前一致 ✓ |
| 输入源注册 | `defaults read com.apple.HIToolbox` 与测试前**逐字节相同** ✓ |
| 回滚点 | `QianwenIME 1.2.2 575.3 MB`，随带 `UserData/` 快照 52 个文件（三个 prefs plist + Application Support 树）✓ |

### 一个未解的观察：轮换后 `Contents` 顶层权限是 755

厂商基线是 `root:staff 775`。duo 轮换之后是 `bobby:staff`，**属主变成用户是
`rotateContents` 写明的取舍**；但 mode 顶层是 `755`，而 `Contents` 内部每一级都是 `775`。
也就是说 `InPlaceSwap` 那句 `chmod -R g+w staged` 跑了（内层是证据），顶层却没带上。

查到哪一步、以及哪些是**推断而非实测**：

- 独立探针（本机 macOS 27.0）：`replaceItemAt` **总是取被替换方（live）的 mode**，
  775/755 两个方向都验过。按这条，结果应当等于 replace 那一刻 live 的 mode。
- 第二轮特意把红的 `Contents` 调成 775 再跑，绿出来仍是 755。
- 把 `Contents` 置 775 后静置 90 秒不变，所以不是有后台进程在被动改它。
- **没查清**：install 流程内部是什么把它变回 755 的。需要给 `InPlaceSwap` 加日志才能定位。

**功能影响：目前没有。** 属主已是用户，厂商自己的非 root 更新路径要的
「重命名 `Contents`」只需要 bundle 根（`root:staff 775`）的写权限，
「`rm -rf Contents_update`」的条目属主也是用户，两者都仍然成立。
这条与本 app 的 recipe 无关，`InPlaceSwap` 对豆包和 WeType 同样适用。
