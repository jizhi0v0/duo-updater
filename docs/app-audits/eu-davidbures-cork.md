# Cork

Homebrew 的图形前端（David Bureš，源码在 `buresdv/Cork`）。app 自己**没有更新器**：
包内没有 Sparkle、没有 feed，二进制里的 "Updates available" 指的是 Homebrew 包的更新。
厂商把每个版本放在 `corkmac.app/RLS/<version>/Cork.zip`，Homebrew cask `cork` 指向同一个地址，
它的 livecheck 读的是目录索引 `corkmac.app/RLS/`。

## 基本信息
- Bundle ID: `eu.davidbures.cork`（1.6.0 起）；更早是 `com.davidbures.cork`（1.4.4.1–1.5.7）和 `com.davidbures.Cork`（≤ 1.4.4）
- Team ID: `ZSVA6DVZHM`（David Bures），抽查的每个版本都是这个 Team
- 观测版本: short `2.0.3`, build `146`（2026-10-16）
- 架构: universal（x86_64 + arm64）
- 系统下限: `LSMinimumSystemVersion` 14.0.0（1.6.0 起；之前是 13.0）
- 自更新机制: 无
- 开源: 是（`github.com/buresdv/Cork`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | ✗ 落后于官网 | ✓ 一键 zip（下载遇首页重下） |
| **beta**     | —       | —        | —   | ○ 目前没有在跑的 beta | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**

## 需要覆盖的副本（Coverage checklist）

| 副本 | 处理 |
|---|---|
| `eu.davidbures.cork`（1.6.0 及以后，含 `1.6.x+Sonoma`） | VendorProbe recipe，一键 |
| `com.davidbures.cork`（1.4.4.1–1.5.7，含 `macos-13/` 冻结版 1.5.6） | `BundleIDMigration` → 走 `eu.davidbures.cork` 的 recipe 和一键 |
| `com.davidbures.Cork`（≤ 1.4.4） | `BundleIDMigration` → 同上 |
| Public Beta（2.0.0 Beta 1–5，只发在 GitHub prerelease） | 不接，见 Channel 详情 |
| 架构 | 每个包都是 universal，无需拆分 |
| macOS 13 专用构建（`RLS/macos-13/`，1.5.6） | 低于 DuoUpdater 的下限（macOS 15）；这份副本在 15 上一样归入上面的迁移 |

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `eu.davidbures.cork` | — | — | 官网目录索引 | ✓ |
| beta | 与 stable 共享 | 共享 | `CFBundleVersion` 带 `_BETA_N`（`134_BETA_5`），short 是 `2.0.0` | 只有 GitHub prerelease | — |

beta：厂商只在 2.0.0 发布前发过 5 个 public beta（2026-06-20 到 08-09，GitHub prerelease + 博客文章），
官网 `RLS/` 里没有 beta 目录，2.0.0 正式版（2026-08-24）之后没有新的 beta。
beta 副本的 short 版本是 `2.0.0`，所以它会被当作 stable 2.0.0，收到 stable 2.0.3，这正是从 beta 毕业该走的路。
现在没有在跑的 beta 轨，所以不加 beta 规则；厂商再开 beta 时再看。

## 更新检测
- 源: `VendorProbeRecipe`，`mode: .responseBody`，`selectHighest`
- 端点: `https://corkmac.app/RLS/`（nginx autoindex，按字母排序）
- `versionPattern`: `href="([0-9]+(?:\.[0-9]+)+)/"`。只认全数字点分的目录名，`latest/`、`macos-13/`、
  `1.6.1%2BSonoma/` 都不匹配。目录名等于包内 `CFBundleShortVersionString`（`1.4`、`1.5`、`1.7.3.1`、`2.0.3` 都核对过）。
- 为什么不用 GitHub Releases：`v2.0.3` 只有 tag 没有 release（GitHub 最新 release 是 2.0.2，2026-09-14），
  官网 2.0.3 同日已上线；cask 也读官网。
- **服务器约一半请求回首页**：同一 URL 交替返回目录索引和完整的首页 HTML（都是 200），zip 地址也一样。
  本机单独顺序请求时严格交替（2026-10-16 连发 30 次 `HiHi…`，0 次连续两个 HTML）；同时有别的客户端在请求时（当时另一个 agent 也在测）
  见过 `HiHHii`。推测是服务端对所有来访者统一轮转，别人的请求会插进来，所以对单个客户端不保证交替（未验证）。
  recipe 的 `transientBodyPattern` 认出首页（HTML5 文档、`<title>Cork: …`；目录索引是裸 `<html>`、标题 `Index of /RLS/`），重试一次；
  通常拿到索引，碰上两次都是首页时这次检查报错（下次扫描再查）。重试次数是共用的 `versionFeedData` 定的一次，没为 Cork 单改。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | app 没有更新器 | 每个版本目录只有一个整包 `Cork.zip` | — |

## 已停放整包（自更新器下完、还没装的那份）
不适用：app 没有更新器。

## Changelog
- 来源: recipe，读厂商 Substack 博客的 RSS `https://blog.corkmac.app/feed`（每篇文章的 HTML 在 `<content:encoded>` 里）
- 只认标题形如 `Cork <version> (is) out` 的文章；beta 和 RC 文章（`Cork 2.0.0 Public Beta 4 is out!`、`… Release Candidate …`）不匹配
- 条目是每个 `<p>`（文章里列表层层嵌套，每行都包在 `<p>` 里），`<h2>` 作为分节标题（Additions / Fixes / Adjustments）；
  正文在厂商的结尾套话（`NO AI USED, EVER`、`Cork Community`）之前截断，Substack 订阅框的 `cta-caption` 段落跳过
- 结构化（`channel-verify` 生产链）: `recipe changelog:eu.davidbures.cork:-: 14 entries; newest 2.0.3: 8 items, headings ["Additions", "Fixes", "Adjustments"]`
- 缺口：2.0.2 没有文章（GitHub 说明写着它与 2.0.1 相同，只是换了 SDK 重新编译），所以没有 2.0.2 条目
- GitHub release body 不用：多数只有一条指向博客的链接
- 跟随 channel: 只有 stable

## 一键安装
- 状态: **一键**，下载到首页 HTML 时由 `VendorInstaller.fetchArchive` 重下（`VendorInstallSpec`，`.versionTemplate("https://corkmac.app/RLS/{version}/Cork.zip")`，`kind: .zip`）
- 包: zip 内只有 `Cork.app`，universal，`spctl` 显示 `Notarized Developer ID`，Team `ZSVA6DVZHM`
- 上一版的 Team：2.0.2、2.0.1、1.7.6、1.6.0 都是 `ZSVA6DVZHM`，`com.davidbures.*` 时代的 0.9、1.0.0、1.1、1.4–1.4.6、1.5、1.5.7 也一样
- 包内没有 helper、login item、XPC、launch agent；开机启动用的是 `SMAppService.mainApp`（`LaunchAtLogin-Modern`），也就是 app 自己，所以 `.zip` 换包即可
- 旧 bundle id 的副本：`BundleIDMigration` 让 `com.davidbures.cork` / `com.davidbures.Cork`（< 1.6.0，同一 Team）可以被 `eu.davidbures.cork` 替换。
  厂商 1.6.0 的文章说明了这次换 id：设置可能重置一次，可能要重新输入一次邮箱
- 真机端到端（2026-10-16，集成分支 `make cli`，加 HTML 重试**之前**）：**失败，4/4 次**。每次都是 `failed: ditto -x -k failed (1): ditto: Couldn't read PKZip signature`，停在 extracting，旧版 2.0.2 原样、签名完好。原因（推断）：corkmac.app 约一半请求回首页 HTML，多数时候严格交替（同日实测 10 次，代理内外一致），一次安装里探针在前、下载紧随其后，下载落在 HTML 上；真机上不是「约一半失败」。同日后来用 cookie jar 连发 6 次是 HTML/目录/HTML/HTML/目录/目录，**并非总是严格交替**；HTML 那次是直接 200（`x-powered-by: PHP`），没有 `Location`、没有 `Set-Cookie`，禁止重定向或带 cookie 都无用。一键要等下载器认出 HTML 并重试，或改成只检测
- 包 URL：最新 `https://corkmac.app/RLS/2.0.3/Cork.zip`，上一版 `https://corkmac.app/RLS/2.0.2/Cork.zip`

## 已知问题
- **下载会抽到首页（已加重试）**：服务器约一半请求回首页（见更新检测），下载不走 `transientBodyPattern` 的重试；
  加重试前真机 4/4 次都抽到首页（解包失败、安装失败，app 不受影响）。现在 `VendorInstaller.fetchArchive` 认出下载到的是 HTML
  文档（开头 `<!DOCTYPE html` / `<html`）就删掉重下，最多 4 次（各约 1/2 时全败约 1/16）；加重试后的真机端到端（2026-10-16，集成分支 `make cli`）：2.0.2 → 2.0.3 成功，`backed up … verifyingCodeSignature … installed.`；日志 `download ok: 15038 bytes … (attempt 1)` 后接 `download ok: 7843012 bytes … (attempt 1)`，即第一次拿到首页、重下拿到 zip；装后 Team `ZSVA6DVZHM`、`codesign --verify --deep --strict` 0、`spctl` Notarized Developer ID，`duo check` 报 up to date。同一轮里装前的 `duo check` 报 `check failed: the vendor answered with an error, not a version (15038-byte body)`：探针两次都抽到首页，检测偶发失败是实测到的（下次扫描再查即可；探针重试次数是共用的一次，没为 Cork 改）。
  `duo verify-install`（`ArtifactInspection.inspect`）原来只下一次，夜扫因此连报 `install.unpack`（#1372）；现在走同一个 `fetchArchive`。2026-10-17 本机 `make cli` 后连跑 3 次，每次日志都是 `download was a web page, not an archive: retry 1/3`，结果 ✓ 2.0.3 / `ZSVA6DVZHM`。
- 那个 HTML 是什么：与 `https://corkmac.app/` 首页逐字节相同（15038 B，同 SHA）；不存在的路径（`/RLS/no-such-file.zip`、
  `/definitely-missing`）也一半回它、一半回真 404。官网首页的 Download 按钮指向 `https://corkmac.app/RLS/latest/Cork.zip`，同样 5/10 是首页。
  **厂商说明（buresdv/Cork#687，2026-10-16）**：这是有意的反 LLM 抓取措施；列版本的「正式」方式是 GitHub releases API
  （Cork 自己降级时也用它），以后会出一个返回版本列表的 JSON 端点，做好会在 issue 里通知。
  实测（2026-10-17）：措施不看 User-Agent，curl 默认 / Homebrew / Safari 的 UA 各 8 次请求 zip，都严格交替 zip 与首页；
  `brew fetch --cask cork --force` 15 次里 1 次报 `Cask reports different checksum`（下到的文件 SHA-256 `940291111dd32c34…` 即首页）。
  已在 issue 里回复这两点，并说明 duo 现在读 `/RLS/`、遇首页重试一次，JSON 端点出来就换过去。
- 博客 RSS 只保留最近 20 篇文章，更早的版本没有条目。

## 建议下一步
1. 真机：装 2.0.2，一键到 2.0.3；再装一份 `com.davidbures.cork` 1.5.7，确认迁移一键。
2. 厂商再开 beta 时，按 `CFBundleVersion` 的 `_BETA_` 后缀评估 beta 轨。
3. 跟踪 buresdv/Cork#687：厂商的版本 JSON 端点上线后，把检测（以及能的话下载地址）换过去，不再抓 `/RLS/`。在那之前不加大对
   corkmac.app 的重试次数。若厂商要求不碰 corkmac.app，改读 GitHub releases（代价：GitHub 上 release 晚于官网，如 2.0.3 只有 tag）。

## 如何复验

```bash
# 1. 目录索引与交替回答（size 9491 = 索引，15038 = 首页）
for i in 1 2 3 4; do curl -sS -o /dev/null -w "%{size_download}\n" https://corkmac.app/RLS/; done

# 2. 生产检测 + changelog
swift run --package-path application-test channel-verify <解包后的 Cork.app> --expect stable

# 3. 签名
codesign -dv <Cork.app> 2>&1 | grep TeamIdentifier
spctl -a -vv -t exec <Cork.app>
```

## 历史与实测

### 2026-10-16 · 接入

- 交替回答：`curl https://corkmac.app/RLS/` 连打 12 次，经代理 `..H.H.H.H.H.`、直连（`--noproxy '*'`，源站 157.180.30.119）`H.H.H.H.H.H.`
  （`.` = 目录索引 9491 bytes，`H` = 首页 15038 bytes）；同一连接上连发 6 次也是严格交替。zip 地址同样交替（下载 2.0.2、1.7.6 时第一次拿到 15038 bytes 的 HTML）。
- 6 次 `channel-verify`（1.4.4 副本）全部 `UPDATE → 2.0.3`：transient 重试生效。
- 真包核对（解包读 `Info.plist`、`codesign`、`spctl`）：

  | 版本 | bundle id | short / build | 下限 | Team |
  |---|---|---|---|---|
  | 0.9 | `com.davidbures.Cork` | 0.9 / 33 | 13.0 | ZSVA6DVZHM |
  | 1.0.0 | `com.davidbures.Cork` | 1.0.0 / 38 | 13.0 | ZSVA6DVZHM |
  | 1.4.4 | `com.davidbures.Cork` | 1.4.4 | 13.0 | ZSVA6DVZHM |
  | 1.4.4.1 | `com.davidbures.cork` | 1.4.4.1 | 13.0 | ZSVA6DVZHM |
  | 1.5.7 | `com.davidbures.cork` | 1.5.7 / 97 | 13.0 | ZSVA6DVZHM |
  | macos-13 | `com.davidbures.cork` | 1.5.6 / 96 | 13.0 | ZSVA6DVZHM |
  | 1.6.0 | `eu.davidbures.cork` | 1.6.0 / 100 | 14.0.0 | ZSVA6DVZHM |
  | 1.6.1+Sonoma | `eu.davidbures.cork` | 1.6.1+Sonoma / 101_S | 14.0.0 | ZSVA6DVZHM |
  | 2.0.0 Beta 5（GitHub） | `eu.davidbures.cork` | 2.0.0 / 134_BETA_5 | 14.0.0 | ZSVA6DVZHM |
  | 2.0.2 | `eu.davidbures.cork` | 2.0.2 / 145 | 14.0.0 | ZSVA6DVZHM |
  | 2.0.3 | `eu.davidbures.cork` | 2.0.3 / 146 | 14.0.0 | ZSVA6DVZHM |

  1.4.1–1.4.4 是 `com.davidbures.Cork`，1.4.4.1、1.4.4.2、1.4.5、1.4.5.2、1.4.6、1.4.6.1、1.5 是 `com.davidbures.cork`。全部 Notarized Developer ID、universal。
- GitHub：`v2.0.3` 有 tag 无 release；release 资产 `Cork.zip` 与官网同版本字节数相同（2.0.2：7,838,933）。
- 博客 RSS：20 篇，14 篇是正式版文章（2.0.3 到 1.4.5），其余是 beta/RC 和一篇非发布文章。
