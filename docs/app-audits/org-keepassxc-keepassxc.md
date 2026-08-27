# KeePassXC

## 基本信息
- Bundle ID: `org.keepassxc.keepassxc`（stable / snapshot **共享同一 id**）
- 已验证版本: stable 由 GitHub Releases 覆盖（Team `G2S7P7J672`，公证）；snapshot
  `2.8.0-snapshot`（build `290601`，2026-08-24，**x86_64-only**）
- 自更新机制: 无内嵌自更新，本仓库靠 GitHub Releases 检测

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查、**永久**不可行  — = 不适用

|              | Homebrew | GitHub Releases |
|--------------|----------|------------------|
| **stable**   | (cask `keepassxc`) | ✓ 检测 + 一键（`org.keepassxc.keepassxc`，Team `G2S7P7J672`，arm64 dmg）|
| **snapshot** | (cask `keepassxc@snapshot`，Homebrew 已标记 deprecated，计划 2026-09-01 停用) | ○ 检测已可行（#93 已解决），尚未接 recipe；✗ 一键**永久**不可（未签名）|

`keepassxc@beta` 不是独立预发轨——指向的就是 stable 那个包（2.7.12），是别名，不是候选
（见 `CHANNEL_COVERAGE_TODO.md` §2c）。真正的预发轨是 `keepassxc@snapshot`。

## Channel 详情

| Channel  | Bundle ID | 独立/共享 | 本地渠道标记 | 签名 | 判定 |
|----------|-----------|----------|-------------|------|------|
| stable   | `org.keepassxc.keepassxc` | 共享 | — | Team `G2S7P7J672`，公证 | ✓ 已接入 |
| snapshot | `org.keepassxc.keepassxc` | 共享 | 版本串带 `-snapshot`（`ReleaseChannel.detect()` 已识别，#93 已解决）| **完全无签名** | 检测已可行，尚未接 recipe；**一键永久不可**（见下）|

## 为什么 snapshot 只能是 detection-only（issue #95）

来源：#95（2026-08-27 channel sweep §2c 之后单独立项），本次 PR 重新下载真机验证。

### 重新验证：签名（本次实测，非转抄 issue）

下载当日（2026-08-27）最新 snapshot build `KeePassXC-2.8.0-snapshot.dmg`
（`https://snapshot.keepassxc.org/build-290601/`），SHA-256 与官方 `.DIGEST` 文件
（`d840649…ca8344`）逐字节核对一致，也与 Homebrew cask 记录的 sha256 一致。挂载后对
`KeePassXC.app` 跑：

```
$ codesign -dv --verbose=4 KeePassXC.app
KeePassXC.app: code object is not signed at all

$ spctl -a -vv KeePassXC.app
KeePassXC.app: rejected
source=no usable signature
```

比 issue 原文更精确一步：这不是"某种弱签名验不过"，是**完全没有签名**
（`code object is not signed at all`）。`VendorInstaller` 的 gate 2
（`SignatureVerifier.verifyCodeSignature`，
`DuoUpdaterCore/Sources/DuoUpdaterCore/Install/VendorInstaller.swift`）第一步就会拒——
连 Team ID 比对都轮不到。跟 VLC nightly 的 ad-hoc 签名比,这个连"有签名但不认"的阶段
都没到,拒绝理由更直接。

Homebrew 自己也独立标记了同一结论：`keepassxc@snapshot` cask 被标
`Deprecated because it does not pass the macOS Gatekeeper check!`，计划 2026-09-01
停用（本次核查 2026-08-27 的 cask 源码，供佐证，非本仓库验证的替代）。

### 松散尾 —— snapshot 的 x86_64-only dmg：核实为真，无 arm64 替代路径

`lipo -info` 确认这不是 universal 构建：

```
$ lipo -info KeePassXC.app/Contents/MacOS/KeePassXC
Non-fat file: …/KeePassXC is architecture: x86_64
```

Homebrew cask 本身的 `caveats` 也写着 `requires_rosetta`，与这个结果一致。

issue 提的疑点——"`@snapshot` cask 这条 URL 是 x86_64，但**另有路径**存在 arm64 build
吗"——本次实测排除了：`snapshot.keepassxc.org` 每个 build 目录下**只发布一个 macOS
产物**（`KeePassXC-2.8.0-snapshot.dmg`），Windows/Linux 侧倒是分了
`x64.msi`/`x64.zip`/`x86_64.AppImage`，唯独 macOS 没有按架构区分的第二个文件。核了
当前 build（`build-290601`，2026-08-24）和一个更早的 build（`build-289983`，
2026-08-09），目录结构一致，没有 arm64 变体。`README.md`（服务器根目录）也只说这是
"most recent development branch" 的快照，没提多架构。

结论：**arm64 Mac 上想跑 snapshot 只能靠 Rosetta，没有原生 arm64 snapshot 可选**。这
对检测层的含义（#93 已解决，若真要接检测）：不需要 `hostRequirement` 去"选对架构"——
因为只有一种架构；但**在 arm64 Mac 上做检测本身要不要有意义**，取决于用户装的到底是
不是这份 x86_64-only 包在 Rosetta 下跑的（`Info.plist` 不会说"这是 Rosetta 转译的"，
只会显示 `KernelArchitecture`/`CFBundleExecutable` 都是 x86_64 二进制，AppScanner 现有
逻辑读的是 bundle 本身的架构，不区分是否在转译层下运行）——这不影响"能不能检测"，
只是提醒：如果将来做，检测出的版本号对 arm64 用户和 x86_64 用户是同一份东西，不需要
按 host arch 分流。反正一键不可行，这条对本 issue 没有阻塞意义,只是记下来避免下一个人
重新查一遍。

## 结论

- **检测**：已解决（#93）。`detect()` 现在能从版本串里的 `-snapshot` 后缀识别
  snapshot（注意 `ReleaseChannel` 已经把*单词* `snapshot` 映射到 `.preview`,但只在
  `channelWord`(读 display name)里生效——KeePassXC 的 display name 是干净的
  "KeePassXC",这条映射对它不触发,是版本串专属信号)，但仓库尚未为它接一条 recipe。
- **一键**：**永远不做**。完全无签名，`VendorInstaller` 的签名 gate 第一步就拒。如果
  有人想给 snapshot 接 channel-gated recipe，**不要带 `install:`**——保持
  detection-only。
- 详见 issue #95、`CHANNEL_COVERAGE_TODO.md` §2c。

## 建议下一步
1. 若决定接 snapshot 检测（`detect()` 已支持 `-snapshot` 后缀，#93 已解决）：只加
   `channel: .preview`（或对应枚举）的 GitHubReleaseRule 或 VendorProbeRecipe，
   **省略 `installAssetPattern`/`install:`**。
2. 不必现在做——这不是本 issue 的范围，本 issue 只是把"一键必拒"这条写下来存档。
