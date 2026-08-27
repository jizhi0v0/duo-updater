# Raycast

审计日期：2026-08-27（本机 macOS 27 / Darwin 27.0.0，arm64）

## 基本信息

- Bundle ID: `com.raycast.macos`
- Team ID: `SY64MV22J9`
- 已安装版本: `CFBundleShortVersionString = 2.0.6.0`（`CFBundleVersion = 0`，不可用作比较）
- 自更新机制: 自研（无 `SUFeedURL`，非 Sparkle / 非 Electron Squirrel）

## 两条 train（本次审计的核心发现）

Raycast 现在同时开着两条发布线，**归属由机器决定，不是用户偏好**，所以这不是 channel 问题：

| train | 端点 | 产物 | 面向 |
|---|---|---|---|
| v1 | `releases.raycast.com/releases/latest?build=universal` | universal dmg（预签名 R2） | 不满足 v2 要求的所有 Mac |
| v2 | `x.raycast-releases.com/releases/latest?platform=macos&architecture=arm64` | arm64-only dmg（明文 R2 URL） | macOS Tahoe(26)+ 且 Apple Silicon |

v2 要求见官方 https://www.raycast.com/new：「macOS Tahoe and Apple Silicon required」，
FAQ 另称「Raycast v2 is built for macOS Tahoe. If you are still on Sequoia or earlier,
you need to upgrade macOS before installing v2.」
`/releases/latest` 返回的 `builds` 数组里 macOS 只有一条 `arm64`，与之吻合。

**两个端点都不做门控**（2026-08-27 实测）：把 UA 换成
`Raycast/1.104.25 (x-macOS-x86_64 24.0.0)`、Sequoia、或普通浏览器 UA，
`x.raycast-releases.com` 一律 200 返回 `2.0.6.0`。所以闸只能记在我们这边。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓ ×2（v1 + v2）|

当前生效源: **Vendor**。本机 `duo check raycast --all --json` →
`{"source":"Vendor","installedVersion":"2.0.6.0","latestVersion":"2.0.6.0","status":"up-to-date"}`
（`latestVersion` 是 2.0.6.0 而非 v1 的 1.104.25，即 `best(of:)` 选中了 v2 recipe）。

## Channel 详情

两条都是 `channel: .stable`，靠新增的 `VendorHostRequirement` 而非 `channel` 区分。

| recipe | recipeID | hostRequirement | 状态 |
|---|---|---|---|
| v1 | `vendor:com.raycast.macos:stable:v1` | 无 | ✓ |
| v2 | `vendor:com.raycast.macos:stable:v2` | `minimumSystemVersion: "26.0"`, `architectures: [.arm64]` | ✓ |

为什么用 hostRequirement 而不是 channel：channel 表达的是「用户选了哪条质量轨」，
这里用户没得选 —— 能不能用 v2 是硬件和系统版本决定的。放进 channel 会让不满足条件的机器
**完全查不到更新**（channel gate 会整个跳过），而不是回落到 v1。

`VendorProbeSource.probeDiagnostic(for:)` 在 channel gate 之后加了 host gate，
位置在多端点合并 **之前** —— `best(of:)` 的前置条件原文是「every endpoint listed for one
channel must serve a build this machine may legitimately install」，先滤掉跑不了的
recipe 正是在维护这条前置条件，而不是绕过它。

## 更新检测

- v2 响应形状：
  ```
  {"id":2275,"version":"2.0.6.0","title":…,"changelog":"<markdown>","commit_sha":…,
   "created_at":"2026-08-25T07:34:17.976Z","updated_at":…,
   "builds":[{"platform":"macos","architecture":"arm64","url":"…arm64.dmg"},
             {"platform":"windows",…".msix"}],
   "download_url":"https://x-r2.raycast-releases.com/Raycast_2.0.6.0_c3450ccdc9_arm64.dmg",
   "checksum":"f09c22aa30a45e17c346c2b1051cf4c3"}
  ```
- **版本方案已核对**：`version` = `2.0.6.0` = 已装 bundle 的 `CFBundleShortVersionString`，
  逐字相同 → 不需要 `versionIsBuild`。（`CFBundleVersion` 是 `0`，本来也不能比。）
- **`version=` 参数是陷阱**：这是一个「我该不该更新」端点，不是「最新是什么」端点。
  传入已是最新的版本 → **204 No Content**（抓包里最常看到的就是这个，容易误判成鉴权失败）；
  传 v1 的三段版本 `1.104.25` → **400 FST_ERR_VALIDATION**（只收四段）。
  所以 recipe **不带** `version`，裸 `/releases/latest?platform=macos&architecture=arm64`
  恒定 200 返回最新版。
- `architecture` 只影响 Windows：`x64` 同样 200 且 `download_url` 仍是 macOS 的 arm64 dmg，
  `x86_64` 则 404。
- 不需要鉴权，无 OAuth。**别把 TLS 握手失败读成鉴权**：经中间人代理探测该端点时会看到
  `SSLV3_ALERT_HANDSHAKE_FAILURE`，那是端点拒绝被拦截，与 auth 无关；直连即 200。

## Changelog

- 来源: `https://www.raycast.com/changelog` — ChangelogRecipe（HTML 正则），服务端渲染。
- **路径是反直觉的**：v2 上线后 `/changelog` 就是 **v2** 的 macOS changelog，
  v1 存档移到了 `/changelog/macos`（页面标题 "Raycast - macOS V1 Changelog"）。
  v1 recipe 的 `changelogURL` 已相应改指 `/changelog/macos`。
- 版本标签是厂商自己的 **minor 训**（"2.0"、"0.71"），app 报的是四段 build（2.0.6.0）。
  这不是要修的错位：Raycast 一个 minor 出一份 notes、下面挂多个 build。
  JSON API 从另一侧印证了这点 —— `/releases` 列表里 2.0.6.0 / 2.0.5.0 / 2.0.4.0 / 2.0.3.0
  的 `changelog` 字段**字节相同**。
- **没有用旁边那个 JSON API**，尽管它直接给 markdown：
  - `/releases` 列表**无视自己的 `platform` 参数** —— `platform=macos` 与 `platform=windows`
    返回**逐字节相同**的 body（2026-08-27 三次复测稳定），且给的是某条 release 的
    **Windows 版**文案，而它的 macOS 双胞胎内容不同。
  - `/releases/latest?platform=macos` 平台是对的，但只有一条 release，没有历史。
- 已知局限：ChangelogRecipe 按 bundleID 索引，两条 train 共用一个 id 且同为 `.stable`，
  所以**没法给 v1 用户单独挂 v1 存档页的解析**；v1 用户会看到 v2 的 notes 列表
  （`changelogURL` 指向对了，正文解析仍走 /changelog）。v1 人群随时间收缩，暂不为此加机制。

## 一键安装

- 状态: 两条 train 都支持。
- 格式: dmg。
- v2 的 `download_url` 是**明文、不过期**的 R2 对象（v1 是 1 小时过期的预签名 URL，
  靠每次探测重新解析规避过期）。
- install pattern 钉死 `\.dmg` 结尾：同一个 host 上 `builds` 还挂着 Windows 的 `.msix`。
- `checksum` 是 **MD5 hex**，`VendorInstallSpec.checksumPattern` 只吃 base64 的 SHA-512，
  用不上，留空；签名闸仍由 Team `SY64MV22J9` 把守。
- 架构安全网：即使 host gate 失效，`SignatureVerifier` 第 5 道闸（`verifyRunnableArchitecture`）
  会读真实 Mach-O，在 Intel 机上拒绝 arm64-only 包。**但 OS 下限没有安装期闸**
  —— 这正是 host gate 必须存在于检测期的原因。

## 已知问题

- v2 的 `title` 在多个 build 之间重复（"🎉Raycast 2.0 is out of Beta!"），
  因为一份 notes 覆盖一整条 minor 训。
- `/releases` 列表端点的 platform 参数无效，见上。别拿它当 changelog 源。

## 建议下一步

1. 无。检测（两 train）、changelog、一键安装均已接入并对真实端点验证通过：
   `duo verify --only raycast` → vendor ✓2 / changelog ✓1 / ✗0 ⚠0。
2. 观察点：v1 train 停更那天，`vendor:com.raycast.macos:stable:v1` 会开始报
   `remoteBehindInstalled` 之类的 advisory —— 那是把 v1 recipe 退役的信号，不是故障。
