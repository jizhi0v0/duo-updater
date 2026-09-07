# Windscribe

> ⚠️ **Homebrew 的 cask 写的 bundle id 是错的（或者说过时的）。** `windscribe` cask 的
> `uninstall quit:` 列的是 `com.windscribe.gui.macos`，而 2.24.12 的真实 app bundle
> 报的是 **`com.windscribe.client`**（从 dmg 里解出来读的 Info.plist，不是从 cask 抄的）。
> `com.windscribe.gui.macos` 在 2.24.12 的包里**一个 bundle 都不叫这个名字**——包里另外两个
> 是 `com.windscribe.launcher.macos`（登录项）和 `com.windscribe.helper.macos`（特权 helper）。
> 按 cask 写 recipe 会得到一条永远绑不上任何 app 的死 recipe。

## 基本信息
- Bundle ID: `com.windscribe.client`
- Team ID: `GYZJYS7XUG`（Developer ID Application: Windscribe Limited）
- 观测版本: `2.24.12`（`CFBundleShortVersionString` == `CFBundleVersion`，
  Info.plist 模板把同一个值写进两个 key，所以**不存在 marketing/build 分岔**）
- 架构: universal（x86_64 + arm64）
- `LSMinimumSystemVersion`: `13`（bundle 里写的）；feed 里同一条写 `min_version: "13.0"`
- 自更新机制: **厂商自研**（Qt 客户端）。**不是 Sparkle，不是 electron-builder**——
  真实 bundle 里没有 `SUFeedURL`，没有 `app-update.yml`，没有 `Sparkle.framework`。
- 分发: 官网 `windscribe.com/download` → `deploy.totallyacdn.com/desktop-apps/<version>/`
- Homebrew: 有 cask `windscribe`，但 `auto_updates true` → `HomebrewCaskSource` 直接放弃，
  **有 cask ≠ 有检测**
- 开源: `github.com/Windscribe/Desktop-App`（客户端源码；下面几条结论是读它得出的）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|----------------|---------|----------|-----|--------|-------------|
| **stable**     | — (无 feed) | — (auto_updates) | — | ○ (可行，见下) | ✓ |
| **beta**       | —       | —        | —   | ○      | ✗ (无法检测 channel) |
| **guinea pig** | —       | —        | —   | ○      | ✗ (无法检测 channel) |

当前生效源: **VendorProbe**（`vendor:com.windscribe.client:stable`）。
changelog 正文另走 GitHub（`changelog:com.windscribe.client:stable`），见下。

### GitHub 是可行的，这条要说清楚，因为第一版审计把它写成 ✗ 了

> ⚠️ **更正（2026-09-07 当天）。** 初版写的是「release 的 asset 只有 Linux CLI 包，
> 一个 macOS 产物都没有」。**错的。** 121 个 release 里有 **118 个 `.dmg`**，
> 最新那个就带 `Windscribe_2.24.12_universal.dmg`。错因很平淡：第一次列 asset 时
> 每个 release 只打印了前 6 个，而 GitHub 按字母序返回，`.deb` / `gnupg_key.pub`
> 把前 6 格占满了，`.dmg` 排在后面被截掉。**列表被截断和列表为空长得一样。**

所以 `GitHubReleaseRule` 是真能用的，而且它有一个 VendorProbe 给不了的优点：
`usePrereleases: false` 走 `/releases/latest`，**GitHub 定义上就不返回 prerelease**，
选 stable 轨这件事不再依赖任何我们要自己论证的东西。而 Windscribe 的发布习惯正好对上
——实测 2026-09-07，2024 年以来：

- 厂商 API 认定在 **release 轨**的 19 个版本，GitHub 上**全部** `prerelease: false`
- 厂商 API 认定在 **beta / guinea pig 轨**的 51 个版本，GitHub 上**没有一个**是
  `prerelease: false`（即不会漏进 `/releases/latest`）

**那为什么版本源仍然是 VendorProbe。** 同一次实测里那 19 个 release 轨版本，有 1 个
（**2.15.9**，2025-06-02）**GitHub 上根本没有对应的 release**。厂商 API 有它。
`/releases/latest` 在那段时间会一直答 2.15.8，直到 7 周后 2.16.11 发布为止——
也就是「有更新却自信地报『已是最新』」，这个仓库最不想要的那种失败，而且这是个 VPN，
错过的那一版很可能带着安全修复（它的 changelog 就长这样）。**19 分之 1，约 5%。**
厂商的 `release_full_version` 按定义不会漏。

代价是 VendorProbe 这边要自己扛住三件事（`Authorization` 头、整 key、不跨条目边界），
都在下面写了，也都有变异测试钉着。**这是一个可以翻的决定**：想换成通用机制而不是
bespoke recipe，把版本源换成 `GitHubReleaseRule(usePrereleases: false,
installAssetPattern: ^Windscribe_[0-9.]+_universal\.dmg$)` 即可，代价就是上面那 5%。
⚠️ **换的时候必须把 VendorProbe recipe 删掉**：`SourceStack` 里 GitHub 排在
VendorProbe **前面**，两条都留会让 recipe 变成永远不被调用的死代码
（Bartender / ImageOptim / Vivaldi Snapshot 三条就是这么死了几个月没人发现的）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable (release) | `com.windscribe.client` | 共享 | — | — | ✓ |
| beta | `com.windscribe.client` | **共享** | `engineSettings.updateChannel`（三分，需真机验证）／`WS_ASSERT` 残留（二分，已验证） | — | ✗ 未接 |
| guinea pig | `com.windscribe.client` | **共享** | 同上 | — | ✗ 未接 |

⚠️ **这张表 2026-09-07 一天里改了两次，两次都是"我断言没有、结果有"。**
第一版：检测信号「无」、状态 `✗ BLOCKED`（依据只有两份构建）。
第二版：拿到四份不同渠道的真实构建，发现二进制里有 `WS_ASSERT` 残留，能二分。
第三版（当前）：去读开源仓库，发现那个"加密的"偏好里就存着 channel，而且密钥是
仓库里的明文常量、字段排在第 4 位。**两次都是同一个毛病：断言"没有 X"之前没量够。**

### 三条轨道是编译期烙进去的，磁盘上却看不出来

`CMakeLists.txt` 按 `WS_BUILD_TYPE` 定义 `WINDSCRIBE_IS_BETA` / `WINDSCRIBE_IS_GUINEA_PIG`，
`AppVersion` 的 `buildChannel_` 就是这两个宏 `#ifdef` 出来的。产物文件名带 token
（`Windscribe_2.24.10_beta_universal.dmg` / `..._guinea_pig_universal.dmg`），
但**文件名不进 bundle**。

实测（2026-09-07，两份真实 bundle：stable 2.24.12 与 beta 2.24.10，各自从官方 dmg 里
解出 `Contents/Resources/windscribe.tar.lzma` 得到，全程未安装）：

- bundle id 一模一样：`com.windscribe.client`
- `CFBundleName` / `CFBundleDisplayName` 一模一样：`Windscribe`
- 版本串**不带任何后缀**：`2.24.12` / `2.24.10`
- 两份 payload 的**文件清单逐条相同**（24 个文件，无增无减）；24 个里 15 个内容不同，
  而那 15 个**全是二进制加 Info.plist**——没有任何一个文本/plist 文件写着 channel

所以 `ReleaseChannel.detect()` 拿不到任何信号，这是量出来的，不是推的
（`channel-verify` 拿真实 beta bundle 跑生产实现：`detected channel → stable`）。
两个主二进制的 `strings` 也逐条比过，**没有任何一边独有的 `beta` / `guinea` /
`channel` / `staging` 字样** —— `fullVersionString()` 里那些 `(Beta)` 字面量三种构建都有，
因为那是运行期 `if`，只有 `buildChannel_` 的初始化是 `#ifdef` 的。

> ⚠️ **更正：不要写「磁盘上没有任何 channel 痕迹」。** 那句话我写过，它太强了。
> 准确的说法是「**bundle 里没有，可读的偏好里也读不出来**」。整台机器上是有一处的：
> app 每次启动都往 `paths::clientLogFolder()`（`QStandardPaths::AppLocalDataLocation`，
> macOS 上即 `~/Library/Application Support/…`）下的 `log_gui.txt` 写一行
> ```
> App version: v2.24.10 (Beta)
> ```
> —— 直接来自 `fullVersionString()`，`(Beta)` / `(Guinea Pig)` / 无后缀三选一
> （`src/client/frontend/gui/main.cpp` 启动序列，紧跟 `=== Started ===`）。
> 这是**目前已知唯一**的本机 channel 信号。为什么仍然没用它，见下。

### 阶梯语义下，"该给谁什么"长这样（真实 feed 回放）

六份构建（四份不同渠道 + 一份对照 + 已安装的那份）**bundle id 和显示名逐字相同**：
`com.windscribe.client` / `Windscribe`，版本串不带任何后缀。所以"装的是哪条轨"
在文件系统层面完全看不出来，而"该比对哪条轨"只由偏好决定。

把真实 feed 按日期回放，同一份安装在不同档位下的结果：

| 场景 | 档位 | 比对目标 | 结果 |
|---|---|---|---|
| 装了 beta 包 2.24.10，as of 08-26（release 轨还在 2.23.11） | Release | 2.23.11 | 比装机版本旧 → **什么都不给** |
| 同上 | Beta | 2.24.10 | 已是最新 |
| 同上 | Guinea Pig | 2.24.10 | 已是最新 |
| 同一台，as of 09-07（2.24.12 已落地） | 任意档 | 2.24.12 | 升级 → 2.24.12 |
| 装了 guinea pig 包 2.24.6，as of 08-01 | Guinea Pig | 2.24.6 | 已是最新 |
| 同上 | Release / Beta | 2.23.11 | 比装机版本旧 → **什么都不给** |

两条可以直接回答用户会问的问题：

- **装了 beta 包但没动设置（默认 Release），是不是只能等下次 stable？** 是。
  比对目标是 release 轨的最新，它可能比你手上的 prerelease 还旧，那就一直没有更新，
  直到下一个 release 落地。（现在 2.24.12 已落地，所以这台会拿到升级。）
- **切换档位就是换比对目标吗？** 是，而且**只**由档位决定。往更稳定的档切，
  可能直接变成"这一轨还没追上你"——不会被降级，但会**搁浅**在那儿。

### ⚠️ 所以我们今天错在哪——和我上一版写的方向是**反的**

上一版写的是"把 beta 拷贝推上 stable"，当成跨渠道推送要修。**阶梯语义下那不是违规**，
那正是厂商自己的行为（Release 档就该拿 release 轨的最新，哪怕手上是 beta 构建）。

真正的缺陷是**反方向的漏报**。我们把每一份拷贝都判成 stable，于是永远拿 release 轨去比：

| as of | 装机 | 偏好 | 正确答案 | 我们会答 | |
|---|---|---|---|---|---|
| 2026-08-01 | 2.23.11 | Guinea Pig | 升级 → 2.24.6 | 已是最新 | ❌ 漏报 |
| 2026-08-12 | 2.23.11 | Guinea Pig | 升级 → 2.24.8 | 已是最新 | ❌ 漏报 |
| 2026-08-26 | 2.23.11 | Beta | 升级 → 2.24.10 | 已是最新 | ❌ 漏报 |
| 2026-08-26 | 2.24.10 | Beta | 已是最新 | 已是最新 | 一致 |
| 2026-09-07 | 2.24.10 | Release | 升级 → 2.24.12 | 升级 → 2.24.12 | 一致 |

**我们从不误报，只会漏报。** 给出的答案总是不高于正确答案，降级由既有的守卫挡住。
所以这是**完整性缺口，不是安全缺陷**——非 Release 档的用户在每个周期约 75% 的时间里
看到"已是最新"，而实际上他们那一轨有新构建。这也把优先级放对了位置。

### （旧标题保留）后果不是"什么都不做"

这一节存在的原因：上面那张表写 `✗ BLOCKED`，容易被读成"那两轨我们不碰"。**不是。**
检测不出来的直接结果是 beta 拷贝被当成 stable，然后照常提供 stable 更新。
生产全链实测（`channel-verify`，真实 2.24.10 beta bundle）：

```
detected channel  → stable
UpdateChecker.check() — winning source Vendor
  status          UPDATE → 2.24.12          ← 一份 beta 拷贝被提供了 stable 更新
```

**这是接受，不是疏漏。** 三条理由：版本是往前走的；Windscribe 自己的客户端在 Beta 档
也会提供 2.24.12（它的 API 答的是"本轨或更新"）；而且我们这条是纯检测，用户点了是跳到
厂商下载页，装什么由他自己决定。也**没法**加闸——闸需要的正是那个读不出来的 channel。
反方向（把 stable 推上 prerelease）则是被结构性挡住的，见下面的 key 选择。

### ✅✅ 用户选的 channel 也是能读的——加密不是障碍，因为 app 是开源的

> ⚠️ **这一节推翻了本文档自己的前一版。** 前一版写的是「要读出 channel 就得复刻
> SimpleCrypt 和一份带版本号、字段会随版本增删的 `QDataStream` 布局……每次厂商 bump
> `versionForSerialization_` 我们就会静默读错一个数。**不做。**」
> **两条腿都是错的**，而且错因是同一个：我看到"加密"两个字就停了，没去读源码。
> 这个 app 是开源的，所以这不是逆向，是读规范。

`EngineSettings::saveToSettings()` 确实把全部引擎设置串成 `QDataStream`、过 `SimpleCrypt`
加密、写进 `com.windscribe.Windscribe2.plist` 的单个 `engineSettings` key
（QSettings org/app = `Windscribe` / `Windscribe2`）。但：

**1. 密钥是仓库里的一个明文常量。**
`src/client/client-common/types/global_consts.h`：
```cpp
static constexpr unsigned long long SIMPLE_CRYPT_KEY = 0x4572A4ACF31A31BA;
```
`SimpleCrypt` 本身是 Andre Somers 2011 年那份公开代码（BSD，`utils/simplecrypt.cpp`
原样收录）：版本字节 `0x03`、flags 字节，然后逐字节
`out[i] = in[i] ^ keyPart[i%8] ^ 前一个密文字节`。**解密是三十行。**
flags：`0x01` = qCompress（4 字节 BE 原长 + zlib）、`0x02` = qChecksum（CRC-16/CCITT，
在前）、`0x04` = SHA-1。

**2. `updateChannel` 是流里的第 4 个字段，排在每一个 version 分支前面。**
`enginesettings.cpp` 的读写两侧一致：
```
quint32  magic          = 0x7745C2AE
qint32   version        （今天 13；`version > 13` 才拒绝，老流一律接受）
QString  language       （quint32 字节长度 + UTF-16BE；0xFFFFFFFF = null）
enum     updateChannel  （4 字节：0=RELEASE 1=BETA 2=GUINEA_PIG 3=INTERNAL）
```
所有 `if (version < 12)` / `if (version >= 2)` 这类分支**全在它后面**。
所以"厂商 bump 序列化版本我们就会读错"这句话是错的——bump 只会在后面增删字段，
前四个从 v1 到 v13 没动过（厂商自己的 reader 也是无条件按这个顺序读的）。

**3. 读错不会是静默的。** SimpleCrypt 默认带 `qChecksum` 完整性校验，`magic` 还要对上
`0x7745C2AE`。两道都过了才可能是误读。

**已写了一份原型解码器并跑过**（Python，约 60 行，不依赖 Qt）：4 个枚举值 × 压缩/不压缩
× 3 种 language 值全部往返正确；单字节翻转**每一处**都被 checksum 抓到；
v1 / v11 / v12 / v13 四种流版本都能取到同一个 channel。

**✅ 已在真实 `com.windscribe.Windscribe2.plist` 上对齐（2026-09-07）。**
往返测试只能证明自洽，真 blob 才能证明和 Qt 对齐 —— 而它当场抓出了一个 bug：

> `qChecksum` 我照 **Qt 4** 的实现写了，末尾多做了一次字节交换。真 blob 里存的是
> `0x63b8`，我算出 `0xb863` —— **正好是字节反序**。Qt 5 之后
> `Qt::ChecksumIso3309` 去掉了那次 swap。去掉之后 checksum 通过。
> 往返测试**永远抓不到这个**：编码器和解码器用的是同一个错函数。

对齐后，真 blob 上**每一个字段都落在该落的地方**：

| 字段 | 读到 | 判据 |
|---|---|---|
| `magic` | `0x7745C2AE` | 与源码常量逐位相同 |
| `version` | `13` | 等于厂商的 `versionForSerialization_` |
| `language` | 4 字节 → `"en"` | 是个合法语言标签，说明偏移正确 |
| `updateChannel` | `1` = **beta** | —— |
| 下一个字段 | `01 …` | `isTerminateSockets` 是 bool，取值合理 |
| `qChecksum` | **通过** | —— |

**关键在于这不是调参调出来的**：checksum 的修法是从 blob 的第 1–3 字节推出来的，
而 `updateChannel` 在解压之后、完全不同的偏移上。修完 checksum 之后那个字段读出什么，
是一个**没有被拟合过的预测**——它读出的值与偏好里选中的那一项一致。

同一份安装上，**三条互相独立的信号一致**：

| 信号 | 读到 | 量的是什么 |
|---|---|---|
| `engineSettings.updateChannel` | `1` = beta | 用户**声明**要接哪条轨 |
| 二进制里的 `WS_ASSERT` 残留 | 2 处 | 这个**构建**是 prerelease |
| `client.log` 的 `App version:` | `"v2.24.10 (Beta)"` | 同上，人可读 |

三条来自三个完全不同的地方（加密偏好 / Mach-O 字符串 / 日志文本），结论相同。

#### ⚠️ 然后它们**分岔了**——而这正是最有用的一次观测

把偏好换到 Guinea Pig 之后，同一时刻三条信号是这样的：

| 信号 | 读到 | 量的是什么 |
|---|---|---|
| `engineSettings.updateChannel` | **`2` = guinea_pig** | 用户**从现在起想接**哪条轨 |
| `WS_ASSERT` 残留 | 2 处 = prerelease 构建 | 这个**二进制**是怎么编的 |
| `client.log` | `App version: "v2.24.10 (**Beta**)"` | 同上 |

**偏好说 guinea pig，构建说 beta。这不是矛盾，是两个不同的事实**——一份 beta 构建的
拷贝，被要求从下一次开始跟 Guinea Pig 轨。

这条观测**直接决定接的时候该读哪一个**：channel gate 要回答的是「该给这一行提供哪条轨的
更新」，那就是**偏好**（厂商自己的客户端也是拿 `updateChannel` 去问 API 的）。
二进制/日志那两条量的是来源，适合当**一致性旁证**（偏好说 release 而二进制带着 assert
残留，就该怀疑而不是照做），**不能拿来代替偏好**。
上一版文档把这两件事并列成"两条候选信号"，是不准确的。

**✅ 已钉死：这个字段跟着下拉框走。** 把下拉框换到另一个值之后重读（**跨两级**，
排除"偏移差一位"这类解释），磁盘上的 blob 变了，解出来是**预测的那个值**，
checksum / magic / language 全部照旧：

| | 换之前 | 换之后 |
|---|---|---|
| `updateChannel` | `1` = beta | **`2` = guinea_pig**（= 预测值） |
| `qChecksum` | 通过 | 通过 |
| `magic` / `version` / `language` | `0x7745C2AE` / 13 / `"en"` | 同左 |

再换回第三个值又读了一次，**枚举里三个真实取值全部观察到**
（`1` beta → `2` guinea_pig → `0` release），每次 checksum 都通过。
所以它不是"恰好等于 1"，是**这个控件的持久化形式**。

⚠️ 顺带一条对接入方式有直接影响的观测：**偏好的默认值是 `UPDATE_CHANNEL_RELEASE`，
装 beta 包不会改它**（见下节）。所以「偏好 = release」**不等于**「这是个 stable 构建」,
一份刚装好、没动过设置的 beta 拷贝读出来就是 release。

**这条信号比 `WS_ASSERT` 那条好在哪：**

| | `WS_ASSERT` 残留 | `engineSettings.updateChannel` |
|---|---|---|
| 分辨力 | 二分（stable / 非 stable） | **三分**（release / beta / guinea pig） |
| 性质 | 调试宏的**副作用** | 厂商**声明**的状态 |
| 读什么 | 另一个 app 的二进制（12.9 MB 扫描） | 一个偏好键，和 OrbStack / Fork 同形状 |
| 误读 | 静默 | magic + checksum 双重把关 |
| 已验证 | ✅ 五份真实构建 | ✅ 真实 plist 对齐（当场抓出一个 Qt4/Qt6 的 checksum 差异）；⚠️ 只观察过一个取值 |

⚠️ **两者量的不是同一件事，别混用。** `WS_ASSERT` 残留说的是**这个二进制是按哪条轨编译的**；
`updateChannel` 说的是**用户想接哪条轨的更新**。两者可以不一致（beta 构建 + 偏好选 Release）。
对"该给这一行提供哪条轨"这个问题，**偏好才是答案**（厂商自己的客户端也是拿它去问 API 的），
`WS_ASSERT` 那条适合当旁证：偏好说 beta 而二进制没有 assert 残留，就该怀疑而不是照做。

### ✅ 找到了一条二进制里的信号：prerelease 构建带 `WS_ASSERT` 的残留

**2026-09-07，五份真实构建实测。** 起因是回头去数「到底哪些东西是编译期分叉的」——
`WINDSCRIBE_IS_BETA` / `WINDSCRIBE_IS_GUINEA_PIG` 全仓库只有 **5 个使用点**，
其中一个是 `src/client/client-common/utils/ws_assert.h`：

```cpp
#if defined(WINDSCRIBE_IS_BETA) || defined(WINDSCRIBE_IS_GUINEA_PIG)
#define WS_ASSERT(b) { if (!(b)) { qCritical(LOG_ASSERT)
    << "Assertion failed! (" << __FILE__ << ":" << __LINE__ << ")"; } Q_ASSERT(b); }
#else
#define WS_ASSERT(b)          // ← stable 构建里展开成空
#endif
```

stable 里这个宏**展开成空**，所以 `"Assertion failed! ("` 这个字面量和每个调用点的
`__FILE__` 路径**根本不会被编译进去**。prerelease 里会。实测：

| 构建 | 发布日 | 轨道 | GUI `Assertion failed!` | GUI 内嵌 `__FILE__` 路径 | cli |
|---|---|---|---|---|---|
| 2.23.11 | 2026-07-06 | release | **0** | **0** | 0 |
| 2.24.4  | ~2026-07   | guinea pig | **2** | **194** | 2 |
| 2.24.10 | 2026-08-25 | beta | **2** | **194** | 2 |
| 2.24.11 | ~2026-08-26 | （feed 里没有） | **0** | **0** | 0 |
| 2.24.12 | 2026-09-02 | release | **0** | **0** | 0 |

**2.23.11 是刻意加的对照组**：它比两个 prerelease 都**早**，仍然是 0。所以这个分组
跟着**渠道**走，不是跟着**时间**走——按日期排是 0 / 2 / 2 / 0 / 0，不单调。
GUI 二进制大小也跟着分组（prerelease 大约 87.2 MB，两个 stable 都是 **86,459,232 字节**，
一模一样），但那只是旁证，判据是字符串。

内嵌的路径长这样（厂商 CI 的构建机路径，原样烤进 prerelease 二进制）：
`.../client-desktop/src/client/frontend/gui/mainwindow.cpp`

**顺带解开了 2.24.11 这个谜。** 它在 GitHub 上被标 `prerelease: true`、文件名却不带
channel token、厂商 API 三条轨道也都不认它——**它是按 stable 编译的**。所以 GitHub 那个
`prerelease` 标记在这里是**发布流程的状态**（压着没放的构建），不是渠道。

#### 但这条信号只能二分，不能三分

`WS_ASSERT` 那个 `#if` 是 `BETA || GUINEA_PIG`，两轨共用。唯一 guinea-pig-only 的使用点
（`cli/main.cpp` 的 staging 开关）实测不产生可区分的字符串——四份构建的 cli 里
staging 相关字符串都是 2 个。想分辨 beta 和 guinea pig，需要**同一个版本号**的两份不同渠道
构建来做对照，而厂商从不这么发。

#### 拿 feed 补成三分？不行，feed 是残缺的

版本号在 `/ChangeLogs?platform=osx` 里确实唯一对应一个 `beta` 轨道号（149 条、149 个不同
版本，是个函数）。但**用户下的这四份里有两份根本不在那份 feed 里**：

- `2.24.11` —— NOT IN FEED
- `2.24.4`（guinea pig）—— NOT IN FEED

CDN 和 GitHub 上都有、能装、能跑的构建，厂商自己的 changelog feed 里没有。
所以「装了什么版本 → 查 feed → 得轨道」对真实可安装的构建**答不出来**，
这正是「feed 不是 app」那条规矩的一个干净实例。

#### 这条信号能买到什么

**能把现在那个跨渠道推送关掉。** 今天 beta 拷贝被判成 stable、照常被提供 stable 更新
（上一节写了，是接受的）。有了这条判据就能识别出「这是个 prerelease 构建」并停止向它
提供 release 轨——把一个"接受但没论证"的行为换成一道真闸。

**代价和风险**（还没实现，先记下来）：

1. **要读另一个 app 的二进制内容**，`AppScanner` 现在不干这事，`ChannelBinding` 现有
   resolver 也全是读偏好的。扫 `Contents/MacOS/windscribe-cli`（约 12.9 MB）比扫 GUI
   （约 86 MB）便宜得多，两者标记一致。
2. **判据是调试宏的副作用，不是厂商声明的渠道。** 厂商把 `ws_assert.h` 改一下（比如
   stable 也开 assert、或换个宏），标记就没了。⚠️ **两个失效方向不对称**：标记消失 →
   prerelease 被判成 stable → 退回今天的行为（不更糟）；stable 开了 assert → stable
   被判成 prerelease → **我们会扣住 stable 用户的更新**，这个方向才要防。
3. 只有二分。guinea pig 用户会被当成 beta 用户对待（或者当成"某种 prerelease"）。

### ⚠️ 接 channel recipe 之前必须先解决的一件事（比检测信号更棘手）

**Windscribe 的三条轨不是平行列车，是一架成熟度梯子。** 而且偏好的默认值是
`UPDATE_CHANNEL_RELEASE`（`enginesettings.h:27`），**装 beta 包不会把它设成 Beta**
——全仓库只有偏好界面那一处会写它（`generalwindowitem.cpp`），安装器和首次启动都不碰。
所以「装的是 beta 包、channel 却显示 Release」是设计如此。

这带来一个 recipe 设计问题。假设照搬 stable 那条、只把 key 换掉：

| 轨道 | 天真写法读到 | 装了 2.24.10 的人会看到 |
|---|---|---|
| release | `release_full_version` → 2.24.12 | 提示升级 ✓ |
| beta | `beta_full_version` → **2.24.10** | **"已是最新"**（而厂商会给他 2.24.12） |
| guinea pig | `guinea_pig_full_version` → **2.24.6** | 比装机版本还旧 |

厂商这边实测（2026-09-07）：`beta=0/1/2` **三档都返回 2.24.12**。所以看起来正确的写法是
「取你那一轨和更成熟的轨里最新的那个」。

**但两件事拦着，都得写下来：**

1. **这个语义证不出来。** 三档返回同一个值，既符合「取本轨或更新的」也符合「参数被忽略」
   ——因为 release 轨（2.24.12）当前领先另外两轨。和上面 `CheckUpdate` 那节是同一个盲区。
2. **⚠️ 我第一次想到的写法是错的，实测才发现。** 想用
   `"(?:release|beta)_full_version"` 并集配 `selectHighest` 取 max。**它只会匹配一次**：
   `"platform"\s*:\s*"osx"` 这个锚在第一次匹配时就被消费掉了，正则引擎从匹配点之后
   继续扫，而文档里只有一个 `"platform": "osx"`。实测 `findall` 返回 `['2.24.12']`，
   一条。今天答案碰巧是对的（release 排在最前**又**恰好最高），
   **beta 哪天领先 release，它就会继续报 release**——又一个"看起来在工作"的错法。
   要真取到 max，得走 `entryStartPattern` 把 osx 那段切出来再在段内 `selectHighest`，
   而那条路的**条目选择**本身也用 `versionPattern`，不带 `"osx"` 限定就会在 28 个平台里
   选中版本号最大的那个（android 是 `3.98.2061`）。这个组合还没设计出来。

#### ✅ 官方文档 + 数据回放，把语义定下来了

厂商自己的 `windscribe.com/features/update-channels`（2026-09-07 读）：

- **Release** —— 最稳定的版本，发布**最不频繁**
- **Beta** —— 新版本的预发布构建，发布更频繁
- **Guinea Pig** —— 新功能和修复的"抢先看"，可能不稳定
- 关键那句：报的 bug 和新功能**先进 Guinea Pig**；想尽量少碰 bug 就留在 Release

**数据完全对上这条阶梯**，而且 build 号**跨轨单调递增**（从 `ChangeLogs?platform=osx` 回放）：

```
2.24 周期   07-21  2.24.3   guinea pig
            07-30  2.24.6   guinea pig
            08-10  2.24.8   beta
            08-25  2.24.10  beta
            09-02  2.24.12  release      ← 落地，此时 release 反超所有轨
2.23 周期   06-08  2.23.5 gp → 07-02  2.23.10 beta → 07-06  2.23.11 release
```

所以「prerelease 领先 release 占 75% 的天数」不是巧合，是**周期的大部分时间都花在
GP/Beta 阶段**。而**现在正处在刚落地、release 反超的那 25%**——这也是为什么
`beta=0/1/2` 三档今天返回同一个值。

**并且"每档只给自己那一轨"已经被排除掉了**：如果 `beta=2` 是"只给 guinea pig 轨"，
它应该返回 `2.24.6`（那一轨的最新）。实测返回 `2.24.12`。
结合官网那句"想少碰 bug 就留在 Release"，唯一自洽的读法是：
**一个选了第 N 档的用户，拿到轨道 0..N 里最新的那个构建。**

#### 于是 recipe 该怎么写——已经测过了

不能用 `ChangeLogs/summary`（三个字段在同一个对象里，`"platform": "osx"` 这个锚一次就被
消费掉，见上）。用 **`ChangeLogs?platform=osx`**，它每条带 `"beta"` 轨道号：

```
entryStartPattern : "id"\s*:\s*[0-9]+                     ← 每条以 id 开头
versionPattern    : "beta"\s*:\s*<轨道集合>\s*,[\s\S]*?Windscribe_([0-9]+(?:\.[0-9]+)+)_
selectHighest     : true                                    ← 在匹配到的条目里取版本最高
轨道集合          : release → 0    beta → [01]    guinea pig → [0-2]
```

真实 body（250,371 字节）上模拟 `highestVersionEntry` + `selectHighest` 的结果：

| recipe | 匹配到的条目数 | 今天读到 |
|---|---|---|
| release（`0`） | 13 | 2.24.12 |
| beta（`[01]`） | 36 | 2.24.12 |
| guinea pig（`[0-2]`） | 97 | 2.24.12 |

⚠️ **今天三条给出同一个答案,所以只拿今天的数据写测试是分不出对错的。**
把 feed 按发布日期回放，就有真实的判别用例：

| as of | release(≤0) | beta(≤1) | guinea(≤2) |
|---|---|---|---|
| 2026-07-25 | 2.23.11 | 2.23.11 | **2.24.3** |
| 2026-08-01 | 2.23.11 | 2.23.11 | **2.24.6** |
| 2026-08-12 | 2.23.11 | **2.24.8** | **2.24.8** |
| 2026-08-26 | 2.23.11 | **2.24.10** | **2.24.10** |
| 2026-09-07 | 2.24.12 | 2.24.12 | 2.24.12 |（今天，三者相同）

**这几个时点就是回归测试该用的 fixture** ——「有没有一份输入能让正确实现和错三条实现
给出不同答案」这个问题，回放给出了肯定的答案。

⚠️ 两条要记的：
- 那个文件名 pattern **匹配不到古早条目**（`Windscribe_2_3_build11_beta.dmg`、
  `windscribe_mac_1_83_build17_beta.dmg` 这类）——40 条 release 里只匹配到 13 条。
  因为走 `selectHighest`，漏掉的都是低版本，无害；但别把"匹配到 13 条"读成"feed 里只有 13 条"。
- 代价：每次检查 250 KB（stable 现在走的 summary 只有 14 KB）。所以合理的做法是
  **stable 继续用 summary，beta / guinea pig 用这条**——两个端点各自做自己对的事。

### 那条启动日志信号（较弱，作为对照留着）

`log_gui.txt` 里那行确实能区分三轨。没接，四条理由，按分量排：

1. **它是日志，不是状态。** 每次启动重写，满了会轮转到 `prev_log_gui.txt`，
   app 从没启动过就根本不存在。偏好键（OrbStack 的 `updates_optinChannel`、
   Fork 的 `sparkleIncludePrereleases`）是**声明**，日志行是**副产物**——
   厂商改一句 `qCInfo` 的措辞不算 breaking change，而我们会静默读错。
2. **`ChannelBinding` 现有的 resolver 全是读偏好的**，没有一个读文件内容。
   加这条等于给 `ChannelBinding` 长一类新能力，为一个 app。
3. **那是 VPN 的日志。** 里面有网络活动记录。只读一行也是打开了它。
4. ~~本机验证不了~~ **已复核，而且路径我读源码读错了。**
   我从 `paths.cpp` 推的是 `<AppLocalDataLocation>/log_gui.txt`。真实安装上是
   **`~/Library/Application Support/Windscribe/Windscribe2/client.log`**
   （同目录还有 `installer.log`）。那一行确实在，内容是：
   ```
   App version: "v2.24.10 (Beta)"
   ```
   —— 后缀跟着渠道走，和 `fullVersionString()` 一致。**这正是"读源码推出来的路径"
   和"真实安装上的路径"会分岔的那种地方**，也是这个仓库要求「转引未复核的实测要标出来」
   的理由：标了，然后它真的错了。

前三条理由仍然成立，所以这条信号仍然只当**旁证**用（它和 `WS_ASSERT` 一样量的是
"二进制按哪条轨编译"，不是"用户想接哪条轨"）。

→ 现状：**明确不是 Pattern D。** 有两条独立信号，一条三分一条二分，形状分别对应
`ChannelBinding`（读偏好，和 OrbStack / Fork 同类）和一道旁证。
`CHANNEL_COVERAGE_TODO.md` § 3 那条已相应改写。

**解码器已经在真实 plist 上对齐**（见上）。剩下的是常规工作量：把那 30 行
SimpleCrypt + 4 个字段的解析写成 Swift，挂成一条 `ChannelBinding` resolver，
再加两条 recipe（beta / guinea pig 各一条，端点就是
`ChangeLogs/summary` 的 `beta_full_version` / `guinea_pig_full_version`）。

**接之前必须先做的一件事**：真实安装上现在的行为是
`detected channel → stable`、`UPDATE 2.24.10 → 2.24.12` —— 一份 beta 拷贝
（偏好也选着 Beta）被提供了 release 轨的构建。这就是要修的东西，也是接完之后
该拿来做红→绿验证的那个用例。

## 更新检测

- 源: `https://api.windscribe.com/ChangeLogs/summary`（14,280 字节，2026-09-07）
- **必须带 `Authorization` 头**，否则 403：
  ```
  {"errorCode":500,"errorMessage":"Missing client authentication values.",
   "errorDescription":"Invalid auth hash","logStatus":null}
  ```
  这个头是**存在性检查，不是凭证**：2026-09-07 实测 `Bearer 9999` 和 `Bearer 1234`
  返回同一份 200 body，不带头才 403。recipe 送的是 `Bearer 1234`——厂商自己的官网 JS
  bundle 里硬编码的就是这个值，是唯一一个每天都在生产里被跑的组合。
- 文档形状：`data.<kind>.<platform>` → 一个对象数组，全文 **28 个 platform 条目**
  （desktop / extension / mobile / tv），macOS 那条长这样：
  ```json
  "platform": "osx",
  "release_version": "2.24", "release_build": 12,
  "release_date": "2026-09-02",
  "release_full_version": "2.24.12",
  "beta_full_version": "2.24.10",
  "guinea_pig_full_version": "2.24.6"
  ```
- `versionPattern`（读 release 轨）与 `publishedAtPattern`（读发布日）都锚在
  `"platform": "osx"` 上，并且都带 `(?:(?!"platform")[\s\S])*?` 这个**不许跨条目**的边界。

### 为什么不是 `/CheckUpdate`——这是这条 recipe 唯一真正的设计选择

`CheckUpdate?platform=osx&beta=<n>` 只有 395 字节，直接给一条 `update_url`
（`.../Windscribe_2.24.12_universal.dmg`），从文件名上就能把版本读出来，看着是更好的选择。
**它有一个证不出来的前提。**

2026-09-07 实测：`beta=0` / `1` / `2` / `3` 返回**逐字节相同**的 body。也就是说
「参数选择轨道」和「参数被忽略」两种解释**分不开**——当天 beta 轨（2.24.10）恰好落后于
stable（2.24.12），所以无论哪种解释，正确答案都一样。

而这个歧义的危险分支，正是这个厂商的**常态**。数 `/ChangeLogs?platform=osx` 里 149 条
macOS 记录的发布日期：**近 819 天里有 618 天（75%）最新的 prerelease 压过最新的 release**，
分成 14 个窗口，每个 27~75 天。如果参数是被忽略的，那么这些窗口里 `CheckUpdate` 给的就是
`..._beta_universal.dmg`，靠文件名读版本的 recipe 会 `versionPatternNoMatch` ——
app 变 `.unknown`，`duo verify` 报红，一次报几周、一天四次。
（实测过这个终局：把 pattern 改成打不中真实 body，
`✗ BROKEN … versionPatternNoMatch — no match in 395-byte body`。）

`/ChangeLogs/summary` 不去赌这个前提：它把三条轨道写成**三个各自具名的字段**，
选 release 轨靠的是 key，不是一个语义观察不到的请求参数。
代价是每次扫描 14 KB 而不是 395 B；换来的除了这个确定性，还有 `release_date` ——
`CheckUpdate` 根本不给日期，所以 Release Log 之前只能给一个估算的 "≈" 窗口。

### 两个 pattern 细节，都是量出来的

**1. `_full_` 是双重承重的。**
- 隔壁 `beta_full_version` / `guinea_pig_full_version` 就在下面两行。
  但**今天真正挡住它们的是字段顺序**（惰性匹配停在第一个 `…_full_version`，而
  `release_full_version` 排在前面）—— 把 key 放宽成 `[a-z_]*full_version` 读到的也是
  2.24.12，看起来完全健康。整 key 买的是**答案不再依赖厂商的字段顺序**，
  而顺序被调换正是唯一能让 stable 用户吃到 prerelease 的形状。
  `theAdjacentPrereleaseFieldsAreNotWhatIsRead` 就是拿真实 excerpt 做这个调换的
  —— 一个分辨不出来的变异不算测试。
- 同一个对象里 `release_version` 是另一个陷阱：它只有 `"2.24"`，三段里的两段，
  第三段在 `release_build`。拿它比装机的 `2.24.12` 是**永久降级**，这一行从此不再提示更新。

**2. `(?:(?!"platform")…)` 边界不是装饰。** macOS 那条夹在 28 个同形状条目中间。
把它换成朴素的 `[\s\S]*?`，在 macOS 条目哪天不再带 `release_full_version` 时，
惰性匹配会一路跑进**下一个 platform** 的同名 key，把 Windows 的版本当成 Mac 的报上来。
拿真实 body 删掉 osx 那一行实测：带边界的匹配不到（正确），不带边界的返回 `2.24.12`
—— **今天恰好是对的答案**，因为 Windows 和 macOS 同步发版，所以这个 bug 看起来像通过。

### feed 里的 OS 下限会动，所以没冻进 `hostRequirement`

`min_version` 是**逐条**给的，跨 `/ChangeLogs?platform=osx` 的 149 条 macOS 记录取值为
10.8 / 10.11 / 10.12 / 10.13 / 10.14 / 11.0 / 12.0 / 13.0——**它随版本移动**。
按 Phase 3⅞ 的规矩，会动的下限只能每次从 feed 读，不能写进 `hostRequirement`。
今天不写也不丢东西：DuoUpdater 自己的 deployment target 是 macOS 14.0
（`App/project.yml`），任何跑得动这次检查的宿主都已经越过 13.0 了。
（`VendorProbeSource` 本来也不看 `min`/`max` 任何一个，这半边不会漂。）

### 读的是「轨道最新」还是「本机被分配的那个」

**都不是——读的是人人都能手动下载的 GA 构建。** `ChangeLogs/summary` 的
`release_full_version` 就是官网 `windscribe.com/download` 发给所有人的那一版。
和 Claude `/latest` 同一类，跟 CapCut beta 那种「轨道最新但官网不给手动下载」**不是**一回事。
Windscribe 也没有任何灰度机制：请求里没有 device id、没有 identity，
换 UA / 换 token 值返回同一份。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | **无** | **无** | 不适用 |
| 证据 | `src/client/engine/engine/autoupdater/` 整个目录（`autoupdaterhelper_mac.cpp` + `downloadhelper.cpp`）grep `delta\|bspatch\|hdiff\|binarypatch\|incremental` **零命中**；没有 Sparkle.framework，也就没有 `BinaryDelta`/`Autoupdate` | 真实响应体全文扫过（`CheckUpdate` 395 B、`ChangeLogs` 250 KB / 149 条、`summary` 14 KB）：字段只有下载 URL + `sha256`，**没有任何 diff/delta/patch 形状的 key，也没有任何 `.delta`/`.patch` URL** | — |

- 格式: 无。每次都是整包 dmg（约 73 MB）。
- 阻塞项: 无——不是"做不了"，是厂商压根没发。

## Changelog

- 发布**日期**由 probe 拿到（`publishedAtPattern` 读 `release_date`），所以 Release Log
  能精确定位这个 app，不落到估算窗口。
- **正文已接**：`changelog:com.windscribe.client:stable`，读
  `https://api.github.com/repos/Windscribe/Desktop-App/releases?per_page=40`，
  `structuredFormat: .gitHubReleases`。实测 2026-09-07 `duo verify`：
  `entryCount 9`、顶条版本 `2.24.12`，与 probe 报的完全一致。
  （40 个 release 里 9 个非 prerelease —— `.gitHubReleases` 只保留 stable，
  正好是这家的发布习惯，见上面那两条计数。）
- **为什么不用厂商自己的结构化 changelog。** `api.windscribe.com/ChangeLogs?platform=osx`
  更好——149 条，每条带 markdown 正文、`release_date`、`sha256`、`min_version`，还有
  `beta` 轨道号（0=release / 1=beta / 2=guinea pig）。但它**够不着**：那个端点不带
  `Authorization` 头就 403，而 `ChangelogRecipe` **没有 `requestHeaders` 字段**
  （`VendorProbeRecipe` 有，它没有）。GitHub 那份是同样的文字（v2.24.12 的 body
  有 11,480 字符），不要头，而且落在这个 registry 已经会解码的格式里。
  要接厂商那份，得先给 `ChangelogRecipe` 加 header 字段——单独一个 PR 的事。
- ⚠️ **GitHub 这份是厂商的 release notes，但不能当成「全部」。** 2.15.9 在 GitHub 上
  没有 release（厂商 API 有），所以历史列表会缺一条。
- ⚠️ **那份 149 条的厂商 feed 不是按版本序排的，是按发布日期/id 排的**（记给将来用它的人）：
  里面有一处倒挂，`2.20.7`（2026-02-23，stable）排在 `2.21.1`（2026-02-17，guinea pig）
  **前面**，谁拿它做版本源，`selectHighest` 会选中那条 guinea pig。

## 一键安装

- 状态: **✗ 不支持，而且是结构性拒绝，不是待办**
- 格式: dmg（约 73 MB），但**里面没有可拖拽的 app**
- **读的是**: 人人可手动下载的 GA（见上）——这一栏为真也救不了下面三条
- 阻塞（前两条可修，第三条不可）：
  1. **dmg 里只有 `WindscribeInstaller.app`**（`com.windscribe.installer.macos`），
     真身在它的 `Contents/Resources/windscribe.tar.lzma` 里。`ArchiveExtractor.extractApp`
     **按扩展名分派**（`dmg`/`zip`/`gz`/`bz2`/`xz`/`tar`/`tbz`/`tgz`），`lzma` 不在其中。
  2. 就算解开了，那个 tar 解出来是**光秃秃的 `Contents/`，没有 `.app` 外壳**，
     `firstApp`（只认顶层 `.app` 目录）找不到东西 → `noAppFound`。
  3. **装这个 app 不是换一个 bundle。** 它还要写
     `/Library/LaunchDaemons/com.windscribe.helper.macos.plist`、
     `/Library/PrivilegedHelperTools/com.windscribe.helper.macos`、
     一个 system extension（`com.windscribe.client.splittunnelextension`）、
     一个登录项、以及 `/usr/local/bin/windscribe-cli`。只换 bundle 会留下一个
     **和 root helper 版本对不上的 VPN**。厂商自己的更新走
     `WindscribeInstaller.app/Contents/MacOS/installer -q <appdir>`——那是以 root 跑
     厂商二进制，DuoUpdater 没有这种安装路线，也不该为一个 app 长出来：
     Windscribe 光 2026-08 一个月的 changelog 里，**四条**本地提权修复长在安装/更新
     这条路径上——两条逐字写着 "staged updater bundle"（2.24.12 #1987 竞态、
     2.24.10 #1964 继承的 SUID/SGID 位），另两条在安装器归档和引导解压流程上
     （2.24.8 #1949、#1816）。（同月另有几条提权修复在 OpenVPN 参数处理等别的路径上，
     不算在这四条里。）

> ⚠️ **`duo verify` 的 `oneClickCandidate` 提示对这条 recipe 是哑的，别把沉默当证据。**
> 现在这个端点根本不给下载 URL，所以它一个 artifact 都匹配不到。就算换回
> `/CheckUpdate` 也一样哑：那个探测器要求 body 里出现字面量 `https://`
> （`RecipeSanity.firstArtifactURL` 的正则起手就是 `https?://`），而它把 URL 写成
> JSON 转义的 `https:\/\/…`。拒绝一键的理由写在上面三条里，不在那条提示的有无里。

## 已知问题

- Homebrew cask `windscribe` 的 `livecheck` 目前是坏的：它对
  `https://windscribe.com/install/desktop/osx` 用 `strategy :header_match`，
  而那个 URL 现在返回的是 **200 + `text/html`**（Next.js 页面，客户端渲染，
  HTML 里连版本号都没有），不是带版本的重定向。换 UA（Homebrew / curl / 默认）结果相同。
  这是 Homebrew 那边的事，不影响我们——记在这里是免得下一个人拿 cask 的 livecheck
  当"厂商的版本端点"去抄。
- beta / guinea pig 无法检测，因此那两轨的用户会被提供 stable 更新（见 Channel 详情，
  已接受并说明理由）。

## 建议下一步

1. ~~加 stable 检测~~ **已完成**：`vendor:com.windscribe.client:stable`，
   2026-09-07 `duo verify --only windscribe` 实跑 `status: ok`，`version: 2.24.12`，
   468 ms，**零 warning**（说明 `publishedAtPattern` 也匹配上并解析成功了）。
   两份真实 bundle 过 `channel-verify` 生产全链：stable 判 `up to date`，
   beta 判 `UPDATE 2.24.10 → 2.24.12`。
   回归测试 `WindscribeProbeRecipeTests`（9 条，五个变异实测变红：放宽 key、
   去掉 `_full`、去掉 `osx` 锚、去掉不跨条目边界、删掉 `publishedAtPattern`）。
2. ~~结构化 changelog 正文~~ **已完成**：走 GitHub releases（`.gitHubReleases`），
   `duo verify` 实跑 `entryCount 9`、顶条 `2.24.12`。要升级成厂商那份 149 条的
   （带 `beta` 轨道号、`sha256`、`min_version`），前置条件是给 `ChangelogRecipe`
   加 `requestHeaders`——单独一个 PR。
3. beta / guinea pig 检测：BLOCKED，无代码改动。已写进 `CHANNEL_COVERAGE_TODO.md` § 3。
   要解锁需要厂商在 bundle 里留一个可读的 channel 标记，或者把 `updateChannel`
   写进一个不加密的 key——两件事都不在我们手里。
