# Douchat

审计 2026-09-22。

## 基本信息

- Bundle ID: `ai.thinkany.douchat`
- App 名: `Douchat.app`
- Team ID: `JU9K7W6T6W` — Developer ID Application: MinHua Tang（已公证）
- 观测版本: `0.1.8`（short == build），`LSMinimumSystemVersion` 12.0，`lipo -archs` = `arm64`（arm64 包）
- 分发: 官网 `douchat.ai`，按架构分 dmg / zip（`Douchat-<version>-mac-{arm64,x64}.{dmg,zip}`）
- 自更新机制: **electron-updater**（`Squirrel.framework` + `Electron Framework.framework`），bundle 自带
  `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://cdn.douchat.ai
  channel: latest
  updaterCacheDirName: douchat-updater
  ```

- Homebrew: 无 cask（`formulae.brew.sh/api/cask/douchat.json` → 404，2026-09-22）
- Sparkle: 没有 `SUFeedURL`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** | — | — | 没查 | 没查 | — | ✓ |

当前生效源：**Electron**（`ElectronManifestSource`）。不需要 VendorProbe recipe，也没有 changelog recipe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `ai.thinkany.douchat` | 单一渠道 | — | — | ✓ |

`app-update.yml` 写的是 `channel: latest`，也就是 electron-updater 默认读的 `latest-mac.yml`，
所以通用源拿到的地址和 app 自己的一致（对照：Memoh 写的是 `channel: 1`，通用源因此读不到）。
其他渠道没查。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://cdn.douchat.ai/latest-mac.yml`（实际请求带 `noCache` 查询串）；Cloudflare，
  响应头 `cache-control: no-store, max-age=0`
- 版本方案: manifest 的 `version` == 包的 short == build（`0.1.8`）
- `releaseDate` 是完整 ISO8601（`2026-09-22T07:33:16.656Z`）
- manifest 没有 `minimumSystemVersion` 之类的字段，不按 OS 分轨
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 支持 blockmap） | 无 | 不适用 |
| 证据 | electron-updater | `latest-mac.yml` 里没有 `blockMapSize` / `differential` 字段（2026-09-22） | `DeltaApplier` 只吃 Sparkle binary delta |

## Changelog

- 来源: 无
- 官网是单页应用：`/changelog`、`/releases`、`/release-notes`、`/docs` 都是 404，`/blog` 里没有版本条目；
  manifest 不带 `releaseNotes`（2026-09-22）
- Recipe 状态: 不需要，等厂商出更新日志页再说

## 一键安装

- 状态: 由 `ElectronManifestSource` 提供。它从 `files:` 里选出 `Douchat-0.1.8-mac-arm64.zip`
  （带 sha512 + size），走 `VendorInstaller` 的 zip 路线 + Team ID 闸。
- 格式: zip，顶层只有 `Douchat.app`
- **读的是**: 人人都能下载的 GA 版：manifest 里只有一个版本，就是 app 自己的更新器读的那份，和官网下载的是同一个构建
- 没有跑 `--install` 实装。

## 已知问题

- 版本线还早（0.x），发布路径约定改动的风险高于成熟产品。

## 如何复验

```bash
# 1. manifest
curl -sS "https://cdn.douchat.ai/latest-mac.yml?noCache=$RANDOM"

# 2. 通用源对真包的判定（dmg 只读挂载，不安装）
swift run --package-path application-test feed-discover Douchat-<version>-mac-arm64.dmg

# 3. 一键装的那个 zip：sha512 与 manifest 一致、Team 与已装的一致
openssl dgst -sha512 -binary Douchat-<version>-mac-arm64.zip | base64
ditto -x -k Douchat-<version>-mac-arm64.zip out && codesign -dv out/Douchat.app 2>&1 | grep TeamIdentifier
```

## 建议下一步

- 无。厂商出了更新日志页再加 changelog recipe。

## 历史与实测

### 2026-09-22 接入时的测量

**包身份。** 官网下载的 `Douchat-0.1.8-mac-arm64.dmg` 的 sha512 与 `latest-mac.yml` 里同名条目一致
（`HmaiKkzr…q4eA==`）。挂载后是 `Douchat.app`：`ai.thinkany.douchat`，`0.1.8` / `0.1.8`，
`codesign --verify --deep --strict` 通过，`spctl` accepted（Notarized Developer ID，
MinHua Tang (JU9K7W6T6W)），`lipo -archs` = `arm64`。

**feed-discover。** `ADOPT https://cdn.douchat.ai/latest-mac.yml`（electron-builder manifest）。

**生产源。** 用一次性测试对这个 bundle 调 `AppScanner().scan(bundlesAt:)` +
`ElectronManifestSource().latestVersion(for:)`：

```
electronUpdate: provider "generic", url "https://cdn.douchat.ai", channel "latest"
manifest: https://cdn.douchat.ai/latest-mac.yml
resolved: shortVersion 0.1.8, vendorInstallerKind zip, downloadSize 115128989
downloadURL: https://cdn.douchat.ai/Douchat-0.1.8-mac-arm64.zip
expectedSHA512: vNhzUs36…psEow==, publishedAt 2026-09-22 07:33:16 +0000
```

**一键装的 zip。** 下载 `Douchat-0.1.8-mac-arm64.zip`：HTTP 200，115,128,989 字节，sha512 与 manifest
一致；解出的 `Douchat.app` 是 `ai.thinkany.douchat` `0.1.8`，Team `JU9K7W6T6W`，strict 验签通过，
`spctl` accepted。
