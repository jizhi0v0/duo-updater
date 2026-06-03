# Plan: CleanShot X 4.x 检测修复（legit 个性化 feed via ChannelBinding feedOverride）

> 自包含 plan，供新 session 直接执行。涉及读取 CleanShot 的 license key（明文），**绝不把 key 写进代码/日志/这个文件**——运行时从 defaults 读。

## 1. 目标

让 duo-updater 正确检测 CleanShot X 4.x 的更新（当前是瞎的），并顺带消掉那个 `4.8.8 ↓ 3.7.1` 的降级提示。

## 2. 背景与已证实的事实（2026-06-03 实测）

- CleanShot X（`pl.maketheweb.cleanshotx`）是 **Sparkle 应用**。它 Info.plist 的 `SUFeedURL` = `https://updates.getcleanshot.com/v3/appcast.xml`，但这是**遗留的 v3 feed，只到 3.7.1**（实拉确认；v2 feed=1.2.1..2.7.6，按大版本分桶且冻结）。装的是 4.8.8。
- CleanShot 4.x 的**真实更新**走母公司 maketheweb 的 Legit 授权服务，**按 license key 个性化**：
  - `GET https://legit.maketheweb.io/api/v1/check-for-updates?version=<installed>&key=<KEY>` → `{"new_version_available":bool}`（实测 4.8.8 → false）。
  - `GET https://legit.maketheweb.io/api/v1/appcast?key=<KEY>` → **一个标准 Sparkle appcast XML**，按订阅 entitlement 过滤，顶部就是用户授权内的最新版（实测顶部 `sparkle:shortVersionString="4.8.8"`，pubDate 2026-03-23，往下 4.8.7/4.8.6…；正文无显式授权字段——门槛纯服务端按 key 判）。
- **license key 明文可读**：`CFPreferencesCopyAppValue("activationKey", "pl.maketheweb.cleanshotx")`（= `defaults read pl.maketheweb.cleanshotx activationKey`，形如 `XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX`）。非 keychain，非沙盒的 DuoUpdater 直接可读。还有个 `lastLegitVersionNumber`。
- **为什么不能简单加个 VendorProbeRecipe**：`VendorProbeSource` 是 checker 的**最后兜底**，只在前面源都 miss 时才跑。CleanShot 有 Sparkle feed → `SparkleAppcastSource` 会**先**用 v3 feed 答出 3.7.1（不 miss）→ VendorProbe 永远轮不到。所以必须从**喂给 Sparkle 的 feed URL** 这一层下手。

## 3. 选定方案：复用 `ChannelBinding.feedOverride`（最干净）

`ChannelBinding`（`DuoUpdaterCore/.../Sources/ChannelBinding.swift`）已有一套"读 app 自己的偏好 → 返回 `ResolvedChannel(channel, feedOverride: URL?)`"机制，AppScanner 用 `feedOverride` **替换** Sparkle 的 SUFeedURL（Fork/Surge 在用，见 `ForkChannel.swift` 模板）。

把 CleanShot 接进去：读 `activationKey` → `feedOverride = https://legit.maketheweb.io/api/v1/appcast?key=<activationKey>`。然后 **`SparkleAppcastSource` 照常 fetch+解析这个 legit appcast**（它本就是标准 Sparkle appcast）→ 拿到 4.8.8 → 和已装比 → 正确。**全程复用现有 Sparkle 机器**（解析、版本比较、甚至若 enclosure 带 EdDSA 签名 + 有 SUPublicEDKey 还能走一键安装）。

订阅语义自动正确：legit appcast 是 entitlement 过滤过的，顶部就是"你授权内的最新"。订阅过期时服务端把 appcast 截到最后授权版 → 我们不会越权多报。**绕过了 [[duo-updater-subscription-detection]] 的死结。**

### 为什么不用 VendorProbeRecipe + 新"读 defaults key"能力
也能做（recipe 加凭证插值 + 抑制 CleanShot 的 Sparkle 源），但要新增能力、要解决源顺序、还得用正则重新解析 appcast（不如 Sparkle 解析器稳）。feedOverride 方案零新增源逻辑、自动抑制 v3、复用解析+安装，明显更优。

## 4. 实现步骤

### Step 1 — 新建 `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/CleanShotChannel.swift`
镜像 `ForkChannel.swift` 的结构：
```swift
import Foundation

/// CleanShot X (pl.maketheweb.cleanshotx) — Sparkle app whose baked-in SUFeedURL
/// points at the LEGACY v3 appcast (frozen at 3.7.1). The real 4.x updates come
/// from the maketheweb "Legit" licensing service, which serves a per-license,
/// subscription-filtered Sparkle appcast. We read the user's license key from
/// CleanShot's own prefs and swap the feed to the personalized legit endpoint, so
/// the existing Sparkle source parses the correct (entitlement-aware) latest.
enum CleanShotChannel {
    static let bundleID = "pl.maketheweb.cleanshotx"

    /// Build the personalized legit appcast feed from a license key.
    static func feed(forKey key: String) -> URL? {
        var c = URLComponents(string: "https://legit.maketheweb.io/api/v1/appcast")
        c?.queryItems = [URLQueryItem(name: "key", value: key)]
        return c?.url
    }

    static func resolveCurrent() -> ResolvedChannel? {
        guard let key = readActivationKey(), !key.isEmpty,
              let feed = feed(forKey: key) else { return nil }   // no license → fall back to v3 (current behavior)
        return ResolvedChannel(channel: .stable, feedOverride: feed)
    }

    /// Read `activationKey` from CleanShot's own defaults (plaintext). nil if absent.
    static func readActivationKey() -> String? {
        guard let raw = CFPreferencesCopyAppValue(
            "activationKey" as CFString, bundleID as CFString) else { return nil }
        return raw as? String
    }
}
```
注意：`resolveCurrent` 返回 `ResolvedChannel?`（nil = 没授权 → 不 override → 走原 v3 feed = 现状，优雅降级）。**Fork/Surge 的 `resolveCurrent` 返回非 optional**，所以 Step 2 要处理 optional。

### Step 2 — 接进 `ChannelBinding.resolve`（同文件 switch）
```swift
case CleanShotChannel.bundleID: return CleanShotChannel.resolveCurrent()
```
`resolve` 已返回 `ResolvedChannel?`，CleanShot 的 `resolveCurrent()` 也是 optional，直接 return 即可。

### Step 3 — 日志脱敏（**关键安全步骤**）
feed URL 现在带 `?key=<licensekey>`，会进 `InstalledApp.sparkleFeedURL`。审计所有可能打印 feed URL 的地方并脱敏 `key` query：
- `grep -rn "sparkleFeedURL\|feedURL\|SUFeedURL\|feed" DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/SparkleAppcastSource.swift App/Sources` —— 找出任何 `Log.*` 把 feed URL 带进去的。
- 现已知 `AppListModel` 的 check 日志打的是 `name → version`（不含 URL），应安全；但 `SparkleAppcastSource` 内部若有 `Log.source.*("...\(feedURL)...")` 必须脱敏。
- 做法：加一个 `URL.redactedForLog`（去掉 query 或把 key value 换成 `***`）的小工具，所有打印 feed URL 处统一用它。**ChangelogCache / RecipeHealth 等若以 URL 为 key 落盘，确认 key 不会写盘**（CleanShot 的 changelog 走独立 ChangelogRecipe→cleanshot.com/changelog，不是这个 feed，应无关，确认即可）。

### Step 4（可选，stretch）— 一键安装
若 legit appcast 的 `<enclosure>` 带 `sparkle:edSignature` 且 CleanShot bundle 有 `SUPublicEDKey`，现有 `SparkleInstaller` 路径可能直接支持一键更新。**先只做检测（Step 1-3）**；确认 appcast 有签名 enclosure 后再评估。

## 5. 验证

1. **手动确认 feed 正确**（本机，运行时读 key，别硬编码）：
   ```bash
   KEY=$(defaults read pl.maketheweb.cleanshotx activationKey)
   curl -sS "https://legit.maketheweb.io/api/v1/appcast?key=$KEY" | grep -oE 'sparkle:shortVersionString="[^"]*"' | head -3
   # 顶部应是当前最新（实测 4.8.8）
   ```
2. **单测**：给 `CleanShotChannel.feed(forKey:)` 写纯函数测试（key→URL 拼接正确、含 query）。`readActivationKey` 依赖机器状态，不强测。可选：把保存的 legit appcast XML 喂给 `SparkleAppcastSource` 的解析路径，断言解析出 4.8.8（参考现有 SparkleSmokeTests / AppcastMarkdownParserTests 风格）。
3. **构建**：`cd App && xcodebuild -scheme DuoUpdater -configuration Debug build`（core 改动也会被带进去；`cd DuoUpdaterCore && swift test` 跑核心测试）。
4. **实跑**：部署 debug build，`log stream --predicate 'subsystem == "com.duoupdater.app"' --info`，触发刷新，确认 CleanShot 那行从 `Sparkle → 3.7.1 [upToDate]` 变成 `Sparkle → 4.8.8 [upToDate]`（或有真更新时报出来），且**日志里不出现 license key**。
5. **降级提示自动消失**：feed 修正后 `downgradeNote` 不再命中（4.8.8 vs 4.8.8），CleanShot 行不再显示 `↓ 3.7.1`。

## 6. 边界 & 决策

- **没授权/没装 key** → `resolveCurrent` 返回 nil → 走原 v3 feed → 现状（3.7.1 + 降级提示）。不退化、不报错。
- **订阅过期** → legit 服务端把 appcast 截到最后授权版 → 我们报的"最新"就是你授权内的最新，不会诱导越权更新。符合 [[duo-updater-install-safety]] 的安全取向。
- **channelIsAuthoritative**：binding 命中会设为 true（stable），无害。
- **UA**：实测 legit appcast 用 Sparkle UA 和浏览器 UA 都 200；`SparkleAppcastSource` 的默认请求应可用，验证时确认不被 403 即可。

## 7. 可泛化

这套"读 app 明文凭证 → 拼个性化 feed → 复用 Sparkle"对**任何把 license/key 明文存 defaults 且更新走 key-bound Sparkle appcast 的订阅 app** 都适用。反例：**TablePlus** 的 license 存**加密** `.licensemac`、auth 是运行时派生的 bcrypt sign → **够不着，不做**（硬搞＝绕授权）。TablePlus 检测本身靠公开 Sparkle feed 正常（6.9.1→7.1.0），且 6→7 已被 `isMajorUpgrade` 门兜住。详见 [[duo-updater-subscription-detection]]。

## 8. 记忆指针
- [[duo-updater-subscription-detection]] —— CleanShot/TablePlus 抓包全过程、"replay key-bound 请求"绕过订阅检测的结论、两者凭证明文/加密的对比。
- [[duo-updater-claude-staged-rollout]] —— 降级提示 `downgradeNote` 的实现（本 plan 完成后该提示对 CleanShot 自动消失）。
- [[duo-updater-vendor-probe-plan]] / `fragile-recipe` skill —— 通用 recipe 调试 loop（本 plan 用的是 ChannelBinding 路线，不是 VendorProbe，但实测/验证的纪律一致）。
