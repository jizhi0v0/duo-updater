# FlyEnv

## 基本信息
- App: FlyEnv — Electron 写的本地开发环境管理器（PHP/Node/本地站点/数据库），前身叫 PhpWebStudy
- Bundle ID: `phpstudy.xpfme.com`（沿用前身 phpstudy 的名字；cask 的 zap 清单里仍留着 `~/Library/PhpWebStudy` 等旧路径）
- 仓库: `xpf0000/FlyEnv`（开源）
- Team ID: `956BZQ2F2P`（Developer ID Application: pengfei xu）；spctl: Notarized Developer ID；`codesign` 的 `Identifier` 就是 `phpstudy.xpfme.com`
- 观测版本: 4.20.2（tag `v4.20.2`，资产 `FlyEnv-4.20.2-arm64-mac.zip`）；上一版 4.20.1；观测于 vmpal「macOS VM 1」（macOS 27.2）
- 自更新机制: **electron-updater**。`Contents/Resources/app-update.yml` 为 `provider: github`、`owner: xpf0000`、`repo: FlyEnv`、`updaterCacheDirName: flyenv-updater`
- 分发: GitHub Releases；Homebrew cask `flyenv`（cask 下的是 `-arm64-mac.zip`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|        | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------|---------|----------|-----|--------|-------------|
| stable | —       | —        | —   | ✓      | —           |

`ElectronManifestSource` 接不上：`provider: github` 只给 owner/repo，不给可读地址；构造出来的地址可能是别人的 bundle。故走 `GitHubReleaseRule`。

## 覆盖清单
- **bundle id**：只有 `phpstudy.xpfme.com`，改名成 FlyEnv 之后 id 没跟着换
- **Team**：4.20.1 与 4.20.2 都是 `956BZQ2F2P`
- **资产**：每个 release 有 20 个资产——`FlyEnv-<v>-arm64-mac.zip`、`-arm64-mac.zip.blockmap`（electron-updater 的两份）、`-arm64.dmg` + blockmap、`.deb`/`.rpm`、以及 windows 构建。rule 钉 `-arm64-mac.zip`，因为那是 app 自己的 updater 和 cask 都取的那份
- **tag 形状**：`v4.20.2`；release 名是 `v4.20.2: <一段说明>`，所以 `versionPattern` 必须整串锚定，不能只取前缀

## 更新检测
`GitHubReleaseRule`（`phpstudy-xpfme-com` family），`owner: xpf0000`、`repo: FlyEnv`，`versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`，`installAssetPattern` `^FlyEnv-[0-9]+(?:\.[0-9]+)+-arm64-mac\.zip$`。

`versionPattern` 的整串锚定是必要的：release 名里带冒号和说明，只锚前缀会把说明也算进 tag 形状。

## 一键安装
`installerKind: .zip`。Team 闸 = 已装副本的 `956BZQ2F2P`；GitHub 也为该资产发 `sha256` digest。

## Changelog
正文是一份写好的 release notes 文档：`# **FlyEnv v4.20.2 Update Release Notes**`，然后 `## **🚀 New Features**` / `## **🛠️ Improvements & Bug Fixes**`，再是编号的 `### **1. <标题>**` 子节加解释性正文，部分子节下面带 `- **要点**：说明` 的条目。`GitHubMarkdownParser` 的手写正文那半正好覆盖：标题不进条目，条目保留 `**…**` 内联语法（`itemSyntax: .markdown`，渲染时是粗体而不是星号）。v4.20.2 整篇解析出 14 条。

注意：**一份文档写全平台**，mac 读者会看到只有 Windows 的条目（Git Bash 集成、Windows PHP 扩展安装器）。按标题切不了平台——`## New Features` 不是平台名——所以保留原样。

## 已知问题
- **没有 changelog recipe**：release 正文是发版说明，还没结构化
- **为什么当初「暂缓」**：它有一个 root helper，用来改 `/etc/hosts` 做本地站点。实测（见下）启动本身不动 hosts
- **运行中换包后 `duo restart` 不生效**（复现过一次、不是偶发）：`duo install` 在 FlyEnv 运行时换掉 bundle 之后，`duo restart FlyEnv` 会退出但不换 pid，旧进程继续跑在已被移走的 bundle 上；同一份二进制对刚启动的 FlyEnv 是正常的（pid 13997 → 15292）。`kill -TERM` 对那个进程仍然有效，所以不是进程僵死，而是协作式退出（`AppRestarter` 只发 `terminate()`、从不 force-kill，以免丢失未保存内容）没有落地。按设计 duo 会把它留作 `.stillRunning` 而不是强杀。根因未查明，列为待办

## 实测（2026-10-30，vmpal「macOS VM 1」）
- `duo verify --only flyenv` → 1 条 rule ✓
- 未运行一轮：4.20.1 → **4.20.2** ✓
- 运行中一轮：`duo install` 换包成功，旧 pid 保持（stale）；`duo restart` 后 FlyEnv 仍是旧 pid（另两个 app 换了）
- **对系统的影响面（本项当初被暂缓的原因）**：
  - 启动前后 `scutil --proxy` 逐字相同
  - `/etc/hosts` sha1 不变（`9feb94ca…`），内容尾部无 FlyEnv 段落
  - `/Library/LaunchDaemons` 下没有 flyenv/phpstudy 条目；`launchctl list` 也没有
  - 启动后只有标准 Electron 助手进程（GPU/Utility/Renderer），没有常驻监听端口
- 也就是说：**装、检测、一键更新这条路径不碰 hosts**。改 hosts 发生在用户自己建站点、并同意装那个 helper 之后

## 如何复验
```sh
duo verify --only flyenv
# VM 里：装 4.20.1，duo check 应报 4.20.1 → 4.20.2
# 一键前后各跑一次：scutil --proxy、shasum /etc/hosts、ls /Library/LaunchDaemons
```
