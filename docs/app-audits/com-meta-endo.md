# Muse

## 基本信息
- Bundle ID: `com.meta.endo`
- Team ID: `V9WTTPBFK9`（Developer ID Application: Meta Platforms, Inc.）
- 已验证版本: short `2.2`, build `1074644564`
- 自更新机制: Sparkle 2.7.0-beta.1，`SUFeedURL` = `https://www.facebook.com/endo/release/appcast.xml?channel=production`

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ◐ 登录墙 | ✗ auto_updates | — | — | ✓ |

当前生效源: **Sparkle**（拿到真 appcast 时）/ **VendorProbe**（Sparkle 撞登录墙抛 `notAFeed` 时）。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.meta.endo` | appcast `?channel=production`；latest 下载链接 | ✓ |

## 更新检测
- Sparkle feed 被 facebook.com 登录墙：匿名请求大多 302 到 `/login`，成段出现（几十秒到一分钟以上）。
  `SparkleAppcastSource` 对"HTML 且零 item"抛 `SparkleError.notAFeed`，交给后面的源。
- VendorProbe: `https://muse.ai/api/hatch/app-download/mac` HEAD → 307 → fbcdn `…/Muse-<marketing>.dmg`，
  取文件名里的 marketing 版本。与 Homebrew cask `muse` 的 `url` 同一个链接。
- 只比 marketing：文件名不带 build；同 marketing 的重打包只有 Sparkle feed 能看到。

## Changelog
- 未发现公开的逐版本页面；appcast item 无 `<description>`。

## 一键安装
- 状态: **已启用**，`.redirect` 指向同一 latest 链接（下载时解析，fbcdn URL 带签名 `oh=`/`oe=`）。
- dmg 内是自包含的 `Muse.app`：`Contents` 下只有 Frameworks（Sparkle）/MacOS/Resources 等，
  无 LaunchDaemons / LoginItems / 系统扩展 → `kind: .dmg`。

## 已知问题
- Sparkle feed 的登录墙在厂商侧，机制从外部不可见。

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
