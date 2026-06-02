# Duo Updater — 覆盖状态总览

> 本机实测(bobby's Mac,2026-06-01),共扫描 **62** 个 app。
> 核心原则:**安装渠道 = 更新渠道,绝不混用。**

## 一句话结论

62 个 app 全部有明确归属:**48 个可检测/可更新**、**9 个托管渠道自理**(App Store / Toolbox)、**5 个真无解**。没有一个落在"不知道怎么办"的灰区。

---

## 五大更新源(48 个 app 被解析)

| 源 | 命中数 | 机制 | 能否一键装 |
|---|---|---|---|
| **App Store** | 17 | iTunes lookup + 登录 storefront(区域锁检测) | 深链跳 App Store |
| **Vendor**(官网探测) | 14 | 逐 app 配方:GET 端点 + 正则抠版本 | 仅检测,手动装 |
| **Sparkle** | 8 | appcast.xml + EdDSA 签名 | ✅ 原地装 |
| **GitHub** | 6 | Releases API(gh token→5000/h) | 仅检测,跳 releases 页 |
| **Homebrew** | 3 | Caskroom 实地验证 provenance | ✅ `brew upgrade` |

### 当前有更新的 9 个
- ChatWise 26.3.36 → 26.5.3 `[Vendor]`
- VS Code 1.119.0 → 1.122.1 `[Vendor]`
- Conductor 0.57.0 → 0.61.1 `[Vendor]`
- Google Chrome 148 → 149 `[Vendor]`
- LM Studio 0.4.12 → 0.4.15 `[Vendor]`
- QQ 6.9.95 → 6.9.96 `[App Store]`
- TablePlus 6.9.1 → 7.1.0 `[Sparkle]`
- TablePro 0.43.0 → 0.47.0 `[Sparkle]`
- Warp …04.29 → …05.27 `[GitHub]`

---

## 托管渠道自理(9 个 — 我们只标记,不插手)

### JetBrains Toolbox 托管(4)
按 `state.json` 的 `installLocation` **路径**识别(两个 AS 共享 bundleID,只有路径能区分):
- IntelliJ IDEA 2026.1.2
- Android Studio Otter 2025.2.3(channel `version_filter` 锁 2025.2 线 → 不报 2025.3)
- Android Studio Koala 2024.1.2(channel `version_filter` 锁 2024.1 线 → 旧副本不催升级)
- Air / Fleet 261.474 → 261.584.13(Public Preview / `eap` 频道 Sparkle feed)

显示版本一律取 Toolbox `state.json` 的 `displayVersion`(抠数字核):磁盘
`CFBundleShortVersionString` 对这几个不可信(AS 截成 "2025.2"、Air 报的是 SHIP
runtime "261.617")。"keep version" = channel `version_filter`:存在即按 build 分支号
(252==2025.2)闸住跨线更新,同线 patch 仍照常提示。

**Air/Fleet 的两条版本线**(查更新的坑):
- **Public Preview(`eap`)安装线**:261.398.29 → 261.474.25 → 261.584.13(三段号)。
  Toolbox 装的、官网 dmg、`AIR/eap` feed 都是这条。**这才是我们要比的线。**
- **SHIP runtime**:app 自更新模块后 `CFBundleShortVersionString` 报 261.617(两段号),
  feed 指向 `nightly`(262.x);MacUpdater 跟的是这条。**不能拿来跟 eap feed 比。**

做法:`productCode == nil` 时,把 app 自带 SUFeedURL 的频道段从 `nightly` 换成 Toolbox
实际订阅的 `channelType`(EAP→`eap`),拉 `AIR/eap` feed 得 261.584.13,再跟 Toolbox
**安装基线** `localLatestBuild`(261.474.25,同三段命名空间)比 → `261.474 → 261.584.13`,
和 Toolbox UI、官网 dmg 完全一致。曾经误报的 `262.6` 是错用了 nightly 频道。

→ UI 显示灰色 **"Toolbox"** 徽标。

### Mac App Store 托管(5)
MAS app 取不到可信 Mac 版本(lookup 返回 iOS track),标为商店托管而非 unknown:
- WhatsApp、TestFlight、Developer(WWDC)、LocalSend、Paste

→ UI 显示灰色 **"App Store"** 徽标。

---

## 真无解(5 — 故意不配,免误报)

| App | 原因 |
|---|---|
| Spotify | 版本 API 需账号 token |
| ToDesk | appcast 被腾讯 EdgeOne JS challenge 挡 |
| WeMeeting(华为 WeLink) | Zoom SDK 私有更新器 |
| RunnerNotify | ad-hoc 内测,无稳定源 |
| STCM Editor | ad-hoc 内测,无稳定源 |

均为国产/专有自更新 app,curl 实证拿不到稳定带版本的链接 → 安静停在 unknown(正确默认)。

---

## 关键架构决策(踩过的坑)

1. **provenance = 路径/实地验证**,不靠文件名猜:Homebrew 查 Caskroom 实地、Toolbox 查 state.json 路径。
2. **MAS `kind==mac-software` 守卫不可放松**:lookup 对 `kind:software` 返回 iOS 版本(超前于 Mac 构建),放松会报幻影更新。
3. **firstMatch vs selectHighest**:默认取首个匹配;只有升序 appcast(VLC)才开 highest——宽正则+highest 会撞上插件/min-OS 版本(HBuilderX 教训)。
4. **Toolbox 全源短路**:不止拦探测源,Air 自带 Sparkle 也要拦,否则跨渠道误报。

测试:**30 个全绿**。
