# Qoder CN（国内版桌面 app）

审计 2026-09-22。

> ⚠️ 先读这段：「Qoder」这个名字下至少有四个 macOS app，bundle id 各不相同：
>
> | 产品 | bundle id | Team | 审计 |
> |---|---|---|---|
> | Qoder IDE | `com.qoder.ide` | `T27K5A5ZWD` | [com-qoder-ide.md](com-qoder-ide.md) |
> | Qoder（国际版桌面 app） | `com.qoder.app` | `B6U242QL73` | [com-qoder-app.md](com-qoder-app.md) |
> | **Qoder CN**（这份） | `com.qodercn.app` | `9DFNGU9AK5` | — |
> | Qoder CN IDE | `com.aliyun.lingma.ide` | `9DFNGU9AK5` | [com-aliyun-lingma-ide.md](com-aliyun-lingma-ide.md) |
>
> 后两个的 bundle id 和 Team 出自 CN 安装器壳自己的 `installer-manifest.json`
> （`expectedIdeTeamIdentifier` / `expectedQoderTeamIdentifier` 都是 `9DFNGU9AK5`，
> `ideArtifact.expectedApplicationId` 是 `com.aliyun.lingma.ide`）。Qoder CN 不是
> `com.qoder.app` 的国内下载镜像：bundle id、app 名、Team、下载主机、发布说明页都分开，
> 两个可以装在同一台 Mac 上。

## 基本信息

- Bundle ID: `com.qodercn.app`
- App 名: `Qoder CN.app`
- Team ID: `9DFNGU9AK5` — Developer ID Application: Hangzhou Yundian Technology Company Limited（已公证）
- 观测版本: `0.3.4`（short == build），`LSMinimumSystemVersion` 12.0，`lipo -archs` = `arm64`
- 分发: 下载页给 `qoder-app.oss-cn-beijing.aliyuncs.com/qoder-app/releases/latest/Qoder-CN-Installer-mac-arm64.zip`，
  是安装器壳（`Qoder CN Installer.app`，`com.qodercn.installer`），真 app 在
  `Contents/Resources/payload/Qoder-CN-<version>-mac-arm64.zip`。同一个 release 另有不套壳的
  `static.qoder.com.cn/qoder-app/releases/<version>/Qoder-CN-mac-arm64.zip`。
- 自更新机制: **electron-updater**（`Squirrel.framework` + `Electron Framework.framework`），bundle 自带
  `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://static.qoder.com.cn/qoder-app/releases
  updaterCacheDirName: qoder-cn-updater
  ```

- Homebrew: 无 cask（`formulae.brew.sh/api/cask/qoder-cn.json` → 404，2026-09-22）
- Sparkle: 没有 `SUFeedURL`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** | — | — | 没查 | — | — | ✓ + changelog recipe |

当前生效源：**Electron**（`ElectronManifestSource`）。不需要 VendorProbe recipe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.qodercn.app` | 单一渠道 | — | — | ✓ |

`app-update.yml` 没写 `channel`，electron-updater 默认读 `latest-mac.yml`。其他渠道没查。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://static.qoder.com.cn/qoder-app/releases/latest-mac.yml`（实际请求带 `noCache` 查询串）
- 版本方案: manifest 的 `version` == 包的 short == build（`0.3.4`）
- `releaseDate` 是完整 ISO8601（`2026-09-19T08:53:03.284Z`）
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）

### 其他版本面（没用）

- 网页安装器读的 `…/qoder-app/releases/latest/manifest.json`：`oss-cn-beijing` 和
  `static.qoder.com.cn` 两个主机都有，格式同 `com.qoder.app` 那份（`schemaVersion` + `version` +
  按平台的 `artifacts`，sha256 hex）。它和 `latest-mac.yml` 指向同一个 zip、同一个 sha256，
  但 `latest-mac.yml` 是 app 自己的更新器读的，还带 base64 sha512，所以用后者。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（blockmap 分块下载） | 有 blockmap | 不能 |
| 证据 | electron-updater | `latest-mac.yml` 的 `differential.blockmapUrl` 指向 `…/0.3.4/Qoder-CN-mac-arm64.zip.blockmap`（2026-09-22） | `DeltaApplier` 只吃 Sparkle binary delta |

## Changelog

- 来源: recipe（`Recipes/com-qodercn-app.swift`），
  `https://docs.qoder.cn/product-overview/qoder-update-log`（页面标题「Qoder CN 更新日志」）
- 与 `docs.qoder.com` 是同一套 docs 构建，共用 `ChangelogRecipeRegistry.qoderEntryPattern`；
  版本写成 `Qoder 0.3.4`，日期是中文 `2026年09月20日`，按文本原样显示。
- ⚠️ 这个站的 slug 和产品名对不上：`/product-overview/qoder-cn-update-log` 是所有 CN 产品的
  更新日志**索引页**，里面一条条目都没有；Qoder CN 自己的是 `/qoder-update-log`。

## 一键安装

- 状态: 由 `ElectronManifestSource` 提供。`latest-mac.yml` 的 `files:` 里是
  `0.3.4/Qoder-CN-mac-arm64.zip`（带 sha512 + size），走 `VendorInstaller` 的 zip 路线 + Team ID 闸。
- 格式: zip，顶层只有 `Qoder CN.app`
- 没有跑 `--install` 实装。

## 已知问题

- 版本线还早（0.x），和国际版一样发布密，路径约定改动的风险高于成熟产品。
- 只在 `latest-mac.yml` 里看到 arm64 一个文件；x64 用户会拿到什么没查（DuoUpdater 本身只跑 arm64）。

## 如何复验

```bash
# 1. manifest
curl -sS "https://static.qoder.com.cn/qoder-app/releases/latest-mac.yml?noCache=$RANDOM" | head -8

# 2. 真包身份（解开安装器壳里的 payload，或直接下 manifest 指的 zip）
ditto -x -k Qoder-CN-mac-arm64.zip out && codesign -dv "out/Qoder CN.app" 2>&1 | grep TeamIdentifier

# 3. recipe 的 fixture
swift test --package-path DuoUpdaterCore --filter QoderRecipeTests
```

## 建议下一步

- 无。Qoder CN IDE 已另行接入（[com-aliyun-lingma-ide.md](com-aliyun-lingma-ide.md)）。

## 历史与实测

### 2026-09-22 接入时的测量

**包身份。** 用户从下载页下的 `Qoder-CN-Installer-mac-arm64.zip`（255,375,751 字节）解开是
`Qoder CN Installer.app`（`com.qodercn.installer`，Team `9DFNGU9AK5`）。它的 payload
`Qoder-CN-0.3.4-mac-arm64.zip` 是 255,505,455 字节：sha256 `c6a93ef6…6679` 与两份
`manifest.json` 和 `latest-mac.yml` 的 sha256 一致，`openssl dgst -sha512 -binary | base64` 与
`latest-mac.yml` 的 sha512 一致；`static.qoder.com.cn/…/0.3.4/Qoder-CN-mac-arm64.zip` 的 HEAD 也是
255,505,455 字节。解出 `Qoder CN.app`：`com.qodercn.app`，`0.3.4` / `0.3.4`，
`codesign --verify --deep --strict` 通过，`spctl` accepted（Notarized Developer ID，
Hangzhou Yundian Technology Company Limited (9DFNGU9AK5)），`lipo -archs` = `arm64`。

**生产源。** 用一次性测试对解出的 bundle 调 `AppScanner().scan(bundlesAt:)` +
`ElectronManifestSource().latestVersion(for:)`：

```
app: Qoder CN com.qodercn.app 0.3.4
manifest: https://static.qoder.com.cn/qoder-app/releases/latest-mac.yml
resolved: 0.3.4 kind: zip sha512: true size: 255505455
artifact: https://static.qoder.com.cn/qoder-app/releases/0.3.4/Qoder-CN-mac-arm64.zip published: 2026-09-19 08:53:03 +0000
```

**changelog。** `docs.qoder.cn/product-overview/qoder-update-log` 752 KB，13 个
`data-component-part="update-label"`，共享 pattern 匹配 13 条（`0.3.4` → `0.1.0`）；`0.3.4` 1 条
item，`0.3.3` 13 条。`docs.qoder.cn/release-notes/qoder` 是 404。
