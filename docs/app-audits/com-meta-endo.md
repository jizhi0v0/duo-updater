# Muse

## 基本信息
- Bundle ID: `com.meta.endo`
- Team ID: `V9WTTPBFK9`（Developer ID Application: Meta Platforms, Inc.）
- 已验证版本: short `2.2`, build `1074644564`
- 自更新机制: Sparkle 2.7.0-beta.1，`SUFeedURL` = `https://www.facebook.com/endo/release/appcast.xml?channel=production`

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ◐ 登录墙 | ✗ auto_updates（版本号由 VendorProbe 读） | — | — | ✓ 只检测 |

当前生效源: **Sparkle**（拿到真 appcast 时，可一键）/ **VendorProbe**（Sparkle 撞登录墙抛 `notAFeed` 时，读 Homebrew cask API 的版本号，只检测）。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.meta.endo` | appcast `?channel=production`；latest 下载链接 | ✓ |

## 更新检测
- Sparkle feed 被 facebook.com 登录墙：匿名请求大多 302 到 `/login`，成段出现（几十秒到一分钟以上）。
  `SparkleAppcastSource` 对"HTML 且零 item"抛 `SparkleError.notAFeed`，交给后面的源。
- 换请求形状逃不出撞墙时段：www / web / m / 裸域、Sparkle UA、`Accept: application/rss+xml` 交替各 10 轮，
  同一窗口里全部 302（2026-09-25）。放行时各 host 也不一致：同一轮 www、m 200 而 web 302（同日稍后）。
- VendorProbe: `https://formulae.brew.sh/api/cask/muse.json` 的顶层 `"version"`。cask 的 `livecheck`
  读的也是这个带墙的 appcast，但 autobump 周期性地反复跑，任何一次穿过就够；`sha256 :no_check`
  使 bump 不下载任何东西，所以版本号能前进，只是有滞后：4.0 从 appcast `pubDate`（02:10Z）到
  cask 合并（04:15Z）约 2 小时；3.0（夜扫基线 02:20Z 从旧端点读到）根本没进 cask（2.2 → 4.0）。
- 只比 marketing：cask 不带 build；同 marketing 的重打包只有 Sparkle feed 能看到。
- 曾用 `muse.ai/api/hatch/app-download/mac` 的 307 文件名，2026-09-25 起需登录，见历史。

## Changelog
- 未发现公开的逐版本页面；appcast item 无 `<description>`。

## 一键安装
- 状态: **仅在 Sparkle 源答复的轮次可用**，装的是 appcast 的 enclosure（fbcdn 签名 URL，匿名可下；
  `oe=` 实测约 4.5 天后过期）。撞墙的轮次由 VendorProbe 答复，只检测、无安装；Muse 自带 Sparkle 自动更新。
- 不再有稳定的安装链接：cask 的 `url` 即 `muse.ai/api/hatch/app-download/mac`，未登录一律 403。
- 只检测时行上的「打开页面」是 `https://muse.ai/`：登录后可下载，未登录先跳 `auth.muse.ai`。
- dmg 内是自包含的 `Muse.app`：`Contents` 下只有 Frameworks（Sparkle）/MacOS/Resources 等，
  无 LaunchDaemons / LoginItems / 系统扩展 → `kind: .dmg`。

## 已知问题
- Sparkle feed 的登录墙在厂商侧，机制从外部不可见。
- Homebrew cask 的 `url` 已对匿名失效；若 Homebrew 改 url 或停用 cask，版本号源随之失效（`duo verify` 会报）。

## 建议下一步
1. 若 Meta 解除 appcast 登录墙，VendorProbe 仍可保留作兜底。

## 历史与实测

### 2026-09-23 · 登录墙与 latest 链接（本机，经 Surge `Hysteria-native` 出口）

- 菜单栏 app 的请求账本（2026-09-22 12:43Z → 09-23 04:16Z）: appcast 13 × 200、176 × 302→`/login`。
- 同一出口、同一请求每 3 秒一次共 60 次: 4 × 302 → ~20 × 200 → 18 × 302 → ~17 × 200 → 5 × 302。
  换 UA（DuoUpdater / `Muse/1.0 Sparkle/2.7.0-beta.1` / 浏览器）各 15 次，当时全 302。
- 200 的 appcast: 单 item，`2.2` / `1074644564`，enclosure 为 fbcdn 签名 URL，`length="34332337"`；
  两种响应体长度（1192/1213 B）只差 CDN 机房（lax3 / sjc6）。
- `muse.ai/api/hatch/app-download/mac`: 20/20 次 307 → `…/818743816_…_n.dmg/Muse-2.2.dmg`（与 appcast
  enclosure 同一文件 id）；HEAD 跟随后 200、`content-length: 34332337`。
- 真包（跟随重定向下载 34,332,337 B）: `com.meta.endo` 2.2 / 1074644564，LSMinimumSystemVersion 14.0，
  `Developer ID Application: Meta Platforms, Inc. (V9WTTPBFK9)`，spctl `Notarized Developer ID`。
- Homebrew cask `muse`: 2026-09-19 新建（同名旧 cask 属另一个 app，2026-07-28 删除），
  至 09-22 经 1.0 → 2.2，`url` 始终是这个 latest 链接；`livecheck` 读的是同一个 facebook appcast。

### 2026-09-25 · latest 链接改为需登录，VendorProbe 改读 Homebrew

- 本机请求账本：`muse.ai/api/hatch/app-download/mac` 至 12:39:20 CST 全为 307，12:40:04 起全为 403，此后未恢复。
  11:00–12:40 调试期间请求量约 40 次/小时（平时约 7 次/小时）。
- 403 体为 `{"error":"not_eligible"}`（`server: Vercel`，应用路由返回，非 WAF）。三个互不相关的出口
  （DMIT 洛杉矶、AWS 俄勒冈、Anthropic 的 WebFetch）全部 403；换 UA / 加 Referer 同样 403。
  浏览器无痕窗口 `not_eligible`，登录 muse.ai 的正常窗口能拿到 fbcdn 链接 → 是登录门槛，不是封 IP。
- 同日 Homebrew cask `muse` 12:15 CST 升到 4.0；appcast 放行轮次中 4.0 / 1076735096，
  enclosure `…/820479897_…_n.dmg`，35,687,468 B，匿名 HEAD 200。
- `duo check Muse` 默认输出曾显示 "Everything is up to date."，实为 `status: error: HTTP 403`
  被过滤掉；同批修改让默认输出列出失败行。
- 本机 appcast 命中率（账本，05–14 点）：真 appcast 请求 204 次、拿到 60 次（约 29%），每小时至少 2 次。
