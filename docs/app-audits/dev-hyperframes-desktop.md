# HyperFrames

HeyGen 的 HyperFrames 有两样东西：桌面 app（本文主体）和 npm 上的 `hyperframes` CLI
（末节）。项目开源在 `heygen-com/hyperframes`，但桌面 app 的源码不在那个仓库里
（CLI 的 `packages/cli/src/utils/desktopApp.ts` 只引用它的 bundle id 和下载页），
下面关于 app 内部的结论都读自 dmg 里 app 的 `Contents/Resources/app.asar`。

## 基本信息
- Bundle ID: `dev.hyperframes.desktop`（Canary: `dev.hyperframes.desktop.canary`）
- Team ID: `2VW993BDT8`（HeyGen Technology Inc.）
- 观测版本: b271（stable）、b272（Canary），2026-10-06
- 自更新机制: 自研（Electron 壳，带 Squirrel.framework 但不用它的 feed，也没有 `app-update.yml`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | —      | ✓           |
| **canary**   | —       | —        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**。`feed-discover` 对 b271 的
app 给出 `noKnownUpdater`；没有 Homebrew cask（`brew search hyperframes` 无结果），不上 MAS，
GitHub releases 只发 agent 插件 zip。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `dev.hyperframes.desktop` | 独立 | — | 独立端点 `desktop/latest.json` | ✓ |
| canary  | `dev.hyperframes.desktop.canary` | 独立 | bundle id 后缀 `.canary` | 独立端点 `desktop/canary/latest.json` | ✓ |

两个 channel 的身份由 app 自己的 `shared/channel.mjs` 定义（`bundleId`、`releases` 文件夹、
`installerBundleId`、下载页），是 pattern A。

## 更新检测
- 源: `VendorProbeRecipe`，读 app 自己的更新器读的同一个文件（`main/releaseUpdates.mjs` 的 `readLatest`）。
- 端点: `https://static.heygen.ai/hyperframes-oss/desktop/latest.json`，Canary 在 `…/desktop/canary/latest.json`。
  `cache-control: no-cache, max-age=0`，不带任何设备标识。
- **版本方案陷阱**：每个构建的 `CFBundleShortVersionString` 和 `CFBundleVersion` 都是 `0.1.0`。
  区分构建的只有 Info.plist 自定义键 `HFBuildLabel`（`b271`，旁边还有 `HFBuildSha`、`HFBuiltAt`）。
  app 的 About 面板显示的就是它，它自己的更新器按其中的数字排序（`verifiedInstall.mjs` 的 `buildNumber`）。
  所以 `AppScanner` 对这两个 bundle id 把 `HFBuildLabel` 的数字读进 `vendorBuildVersion`，行上的
  版本显示成 `b271`；recipe 是 `versionIsBuild` + `buildNamespace: .vendor`。缺这个键的拷贝在
  vendor 命名空间里是「判断不了」，不会拿 `271` 去比 `0.1.0`。`CFBundleVersion` 原样保留：
  重启检查用它和 `lsappinfo` 比，两边都是 `0.1.0`，不会出现假的 Restart。
- `latest.json` 的 `linux`、`deb` 块各带一个 `build`，app 注释说它可能比所在 release 旧
  （恢复发布时）。pattern 只认后面紧跟 `"sha"` 的顶层 `build`。
- 读的是：轨道上每台机器都拿到的同一个构建（一个文件、无灰度键），也就是下载页发的那个。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 不能 |
| 证据 | `main/deltaInstall.mjs`（`assemble`） | `latest.json` 的 `delta: {url: delta/manifest-b271.json, blobs: …/blobs}`，各架构各一份（2026-10-06） | 厂商自有格式（manifest + blobs），不是 Sparkle 的 BinaryDelta，`DeltaApplier` 用不上 |

- 格式: 厂商自有
- 阻塞项: 要接得写一个新的 applier，目前没做

## Changelog
- 来源: app 自己 What's New 对话框读的文件，`whats-new-<build>.json`，和 `latest.json` 在同一个文件夹，
  每个构建一份（`{schema: 1, build, date, title, summary, new[], improved[], fixed[], scenes[]}`）。
  新加 `StructuredFormat.hyperFramesWhatsNew` 解码：先 summary，再 New / Improved / Fixed 三个标题
  （空列表不出标题），`title` 和 `scenes` 是对话框的插图头部，不收。
- 跟随 channel: 是（Canary 有自己的 `canary/whats-new-<build>.json`）。
- Recipe 状态: 已有，`sourceTemplate` 按目标构建（`b272`）取文件。stable 的文件只在该构建发布到 stable 后
  才有（2026-10-06 时 `whats-new-b272.json` 在 stable 文件夹是 403，在 canary 文件夹是 200）。

## 一键安装
- 状态: 支持，stable 和 Canary 都已在真实拷贝上跑通（见下）
- 格式: zip，`latest.json` 顶层的 universal 包（`HyperFrames-b271-<sha9>.zip`），里面只有本 channel 的 app。
  `arm64`/`x64` 块是同一构建的瘦包，没用。
- **读的是**: 轨道上人人拿到的同一个构建（无按设备分配），等于下载页提供的构建
- 校验: Team ID 闸。`latest.json` 给了 zip 的 sha256，但是 hex；`checksumPattern` 只接 base64 SHA-512，没接
- Canary 的 channel proof: 下载 URL 必须匹配 `/hyperframes-oss/desktop/canary/HyperFrames-b`
- 与自更新器的关系: app 的更新器在运行时把新 app 放进 `dest` 旁边的新文件夹，两次 rename 换进来，然后自己重启；
  不在退出时留暂存包，没有 Sparkle/Squirrel 那种「我们一退出它就装旧包」的碰撞面。

## 如何复验

```bash
# 真实 bundle：dmg 里是安装器 stub（dev.hyperframes.installer），app 在 Contents/Helpers/ 下
hdiutil attach -readonly -nobrowse -mountpoint <mnt> Install-HyperFrames-arm64-b270.dmg
swift run --package-path application-test channel-verify "<mnt>/Install HyperFrames.app/Contents/Helpers/HyperFrames.app" --expect stable
```

2026-10-06 的结果：

| 拷贝 | bundle id | HFBuildLabel | 判定 channel | 对 live 端点 |
|---|---|---|---|---|
| stable dmg b271 | `dev.hyperframes.desktop` | b271 | stable | up to date，winning=Vendor，changelog 1 条 10 项 |
| Canary dmg b272 | `dev.hyperframes.desktop.canary` | b272 | canary | up to date，下载 URL 在 `canary/` 下，changelog 只有 Fixed |
| stable b270（放进 /Applications） | 同上 | b270 | stable | `duo check`: `b270 → b271 [Vendor, in-place]` |

一键（`duo install`，`make cli` 构建的 duo）：

- stable b270 → b271，app 未运行：34 s，之后 `spctl` accepted、Notarized Developer ID、Team 2VW993BDT8，再 check 为 up to date。
- stable b270 → b271，app 运行中：换包成功，CLI 提示 `duo restart HyperFrames`，restart 后新进程起在 b271 上。
  运行期间 app 没有改 Claude Code / Codex / Claude Desktop 的 MCP 配置（三个文件里都没有 hyperframes 条目，后两个 mtime 不变）。
- Canary b271 → b272：成功，Team 与公证同上，再 check 为 up to date。

## 已知问题
- sha256 校验没接（见一键安装）。

## 建议下一步
1. 如果要给 zip 加摘要校验：`VendorInstallSpec` 增加 hex sha256（`RemoteVersion.expectedSHA256` 和
   `VendorInstaller` 里已经有 GitHub 那条路用的 SHA-256 校验）。
2. 增量包是厂商自有格式，暂不接。

## CLI（npm `hyperframes`）

不需要专门的 recipe：通用的 npm 全局包 provider（`NpmProvider`）已经覆盖。2026-10-06 在临时 prefix 里装
`hyperframes@0.8.135`，用生产代码跑：检测为 `0.8.135 → 0.8.137`（`latest` dist-tag）；release notes 取自
安装包 `package.json` 的 `repository`（`heygen-com/hyperframes`），tag 是 `v<version>`，得到 0.8.137 和
0.8.136 两条结构化条目。临时 prefix 没有自己的 node，所以那次一键是 withheld（`noOwnNpm`）；带 node 的
真实 prefix 上一键就是 `npm install -g`，这一点没有针对 hyperframes 单独跑过。

CLI 自带静默自更新（`packages/cli/src/utils/autoUpdate.ts`）：某次运行发现新版本，就拉起一个 detached
的 `node -e` 进程，等所有 hyperframes 进程退出后执行 `npm install -g hyperframes@<v>`（bun/pnpm 同理）。
不跨 major，`npx` 不触发，`HYPERFRAMES_NO_AUTO_INSTALL=1` 可关。等待期间这个进程不是 npm，
`NpmActivity` 看不出它在排队，所以它和我们的一键理论上可能在同一个 prefix 里前后脚跑 npm；没有观测到，也没处理。
