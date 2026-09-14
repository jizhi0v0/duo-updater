# LibreWolf

## 基本信息
- Bundle ID: `net.librewolf.librewolf`  (⚠️ NOT `org.mozilla.librewolf`)
- 观测版本: `151.0.3-1` (build `15126.6.2`)
- 自更新机制: 无（LibreWolf 不带自更新；靠 brew 或手动下载）
- RemotingName: `librewolf` — 单 channel，无需用于检测

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓        | —   | —      | ✓ (Codeberg) |

当前生效源（brew 安装时）: **Homebrew**（cask 无 `auto_updates`，brew 优先链先于 VendorProbe 应答）。
直接下载安装（无 cask）时回落到 **VendorProbe**（Codeberg releases/latest）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.librewolf.librewolf` | 单一 | 默认(无后缀) | — | ✓ 真实 bundle 验证 |

LibreWolf 也有 alpha/nightly 上游构建，但无独立 macOS cask、无检测信号 → 不接（同
Firefox/Thunderbird 之外的单轨判定）。

## 更新检测
- 源: VendorProbe（fallback）+ Homebrew（brew 安装时优先）
- 端点: `https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest`
  （`tag_name` 字段；旧 GitLab `44042130` 已废弃，停在 147.0.4）
- versionPattern: `"tag_name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"` → 捕获 `151.0.3`，丢弃 `-1` 打包后缀
- 注意事项:
  - 版本同构: 端点 `151.0.3-1` vs 安装 `CFBundleShortVersionString` `151.0.3-1`；
    pattern 抽 `151.0.3`，引擎判定 not-newer → up to date，无幽灵更新。
  - bundle id 是 `net.librewolf.*`，不是 `org.mozilla.*`，所以 `AppScanner` 的
    Mozilla RemotingName 读取（gated on `org.mozilla` 前缀）不触发——单轨不需要。

## Changelog
- 来源: Codeberg releases 页 `https://codeberg.org/librewolf/bsys6/releases`（WebView）
- 跟随 channel: 单轨
- Recipe 状态: 不需要（无结构化 changelog recipe；releases 页可内嵌）

## 一键安装
- 状态: **仅检测（不可一键 — 已定论）**
- 阻塞（2026-07-03 实测）: Codeberg release 里确有 `librewolf-<ver>-macos-arm64-package.dmg`
  直链，但下载验证 → dmg 内 `LibreWolf.app` 是 **ad-hoc 签名**：`codesign` 显示
  `TeamIdentifier=not set`、无 `Developer ID` Authority，`spctl -a` 直接 fail
  （"code has no resources but signature indicates they must be present"）。LibreWolf
  作为隐私 fork **故意不做 Apple 公证**（用户装时需手动去隔离）。因此过不了
  `VendorInstaller` 的强制 Team 签名门（fail-closed 会正确拒绝）→ 永久留 detection-only。
- 教训: "JSON/release 带 mac dmg 直链" 只是必要非充分条件；接一键前必须真下包跑
  `codesign -dv` + `spctl -a` 确认有 Developer ID Team + Notarized。

## 已知问题
- 历史 bug（2026-06-04 修复）: 配方 bundle id 写成 `org.mozilla.librewolf`（永不匹配）
  + 版本端点指向废弃的 GitLab 仓库（停在 147.0.4）。两处均改正并加注释。

## 建议下一步
1. 已修复检测，无需额外动作。
2. ~~一键安装~~ — **已否决**（见上：dmg 未公证/无 Team ID，过不了签名门）。除非 LibreWolf
   上游开始公证 mac 构建，否则不再尝试。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --check net.librewolf.librewolf --expect stable
swift run --package-path application-test channel-verify "/Applications/LibreWolf.app" --expect stable
```

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/net-librewolf-librewolf.swift — VendorProbe（版本源在 Codeberg）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（旧 GitLab 项目停在当前线之前、会变成陈旧探针；cask 的 livecheck 读同一个 Codeberg `releases/latest`），147.0.4 / 151.x 和 2026-06-04 对照装机副本的那次核对搬到这里。唯一的改写：一处本机状态措辞（被核对的那份装机副本），按本目录的机器状态规则改成了针对那台被核对的机器的说法。

LibreWolf — release tags, newest first; tag is "<firefox-version>-<packaging>"
(e.g. "151.0.3-1") and we capture only the upstream Firefox version so it
compares equal to the installed app's `CFBundleShortVersionString` (keeping
"-1" would read as a perpetual update). No auto-updater — genuinely useful.
Real installed bundle id is `net.librewolf.librewolf` (NOT
`org.mozilla.librewolf` — LibreWolf re-brands the Mozilla source). Version
source is **Codeberg**, not GitLab: LibreWolf migrated, and the old GitLab
repos are abandoned (project 44042130/bsys6 caps at 147.0.4 while current
is 151.x → a stale probe). The brew cask's own livecheck reads this same
Codeberg `releases/latest`. Verified 2026-06-04 against the cask installed on the machine verified that day:
app reports `151.0.3-1`; `tag_name` is `151.0.3-1` → captures `151.0.3`.

### Recipes/net-librewolf-librewolf.swift — VendorProbe（为什么只检测）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论和日期（checked 2026-08-09 时 dmg 里的 app 是 ad-hoc 签名、Gatekeeper 直接拒绝），Gatekeeper 的原话搬到这里。

DETECTION ONLY, and not for lack of a URL — the release does publish
`librewolf-<ver>-macos-arm64-package.dmg`. Checked it on 2026-08-09: the
`LibreWolf.app` inside is ad-hoc signed (`TeamIdentifier=not set`) and
Gatekeeper rejects it outright ("code has no resources but signature
indicates they must be present"). `VendorInstaller`'s same-Team gate would
refuse it anyway, and rightly: there is no signing identity to compare the
installed copy against. Don't wire one-click here unless LibreWolf starts
shipping a Developer ID build.
