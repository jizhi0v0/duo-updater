# Douchat

初次审计 2026-09-22；签名迁移复核 2026-11-15。

## 基本信息

- Bundle ID: `ai.thinkany.douchat`
- App 名: `Douchat.app`
- Team ID: `0.1.8`、`0.1.28` 为 `JU9K7W6T6W`（MinHua Tang）；`0.1.29` 为
  `8PL52G56V9`（ThinkAny, LLC）。`0.1.29` 的 zip / dmg 均严格验签通过、已公证。
- 观测版本: `0.1.8`、`0.1.28`、`0.1.29`（short == build），`LSMinimumSystemVersion` 12.0，arm64 包
- 分发: 官网 `douchat.ai`，按架构分 dmg / zip（`Douchat-<version>-mac-{arm64,x64}.{dmg,zip}`）
- 自更新机制: **electron-updater**（`Squirrel.framework` + `Electron Framework.framework`），bundle 自带
  `0.1.8` 的 `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://cdn.douchat.ai
  channel: latest
  updaterCacheDirName: douchat-updater
  ```

  `0.1.28`、`0.1.29` 的配置改为 `url: https://cdn.douchat.ai/thinkany`，其余上述字段相同。

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
其他渠道没查。`/thinkany` 是上述包声明的发布路径；没有证据表明它是另一条 beta 等发布轨道。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: 随 bundle 内的 `app-update.yml`：`0.1.8` 指向
  `https://cdn.douchat.ai/latest-mac.yml`；观测的 `0.1.28`、`0.1.29` 指向
  `https://cdn.douchat.ai/thinkany/latest-mac.yml`（实际请求带 `noCache` 查询串）。
  2026-11-15 前者仍发布 `0.1.28`，后者发布 `0.1.29`；通用源不改写旧包声明的路径。
- 版本方案: manifest 的 `version` == 包的 short == build（`0.1.8`、`0.1.29`）
- `releaseDate` 是完整 ISO8601（`0.1.29` 为 `2026-11-15T07:44:01.501Z`）
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

- 状态: 由 `ElectronManifestSource` 提供。它从 `files:` 里选出 arm64 zip
  （带 sha512 + size），走 `VendorInstaller` 的 zip 路线 + Team ID 闸。
  支持 `JU9K7W6T6W` → `8PL52G56V9` 的已授权迁移：仅 `ai.thinkany.douchat`，且下载包必须
  满足旧包原有的 designated requirement（指定要求）。两组 Team 各自的同 Team 更新继续走原校验。
- 格式: zip，顶层只有 `Douchat.app`
- **读的是**: 人人都能下载的 GA 版：manifest 里只有一个版本，就是 app 自己的更新器读的那份，和官网下载的是同一个构建
- 没有跑 `--install` 实装。

## 已知问题

- 版本线还早（0.x），发布路径约定改动的风险高于成熟产品。
- 修复前，`0.1.29` 改变签名主体会使旧 Team 的一键更新在替换前失败。迁移兼容要求旧包的
  签名已经授权新 Team；下载包哈希或 Apple 公证通过本身不代替这个授权。没有授权的旧包仍拒装。
- 仍声明根路径 feed 的旧包只能读到该路径发布的版本；2026-11-15 根路径为 `0.1.28`。

## 如何复验

```bash
# 1. manifest
curl -sS "https://cdn.douchat.ai/latest-mac.yml?noCache=$RANDOM"

# 2. 通用源对真包的判定（dmg 只读挂载，不安装）
swift run --package-path application-test feed-discover Douchat-<version>-mac-arm64.dmg

# 2b. 整条生产源链对真包的结论：应是 winning source Electron
swift run --package-path application-test channel-verify Douchat-<version>-mac-arm64.dmg

# 3. 一键装的那个 zip：sha512 与 manifest 一致、Team 与已装的一致
openssl dgst -sha512 -binary Douchat-<version>-mac-arm64.zip | base64
ditto -x -k Douchat-<version>-mac-arm64.zip out && codesign -dv out/Douchat.app 2>&1 | grep TeamIdentifier
```

## 建议下一步

- 使用含迁移兼容的 DuoUpdater；缺少签名授权的旧包仍需从[官网](https://douchat.ai/)手动安装新版。
- 厂商出了更新日志页再加 changelog recipe。

## 接入时的实测（2026-09-22）

没有 recipe 文件，所以这里不用 `## 历史与实测`（那个标题要和 recipe 里的 `// History:` 指针成对出现）。

**包身份。** 官网下载的 `Douchat-0.1.8-mac-arm64.dmg` 的 sha512 与 `latest-mac.yml` 里同名条目一致
（`HmaiKkzr…q4eA==`）。挂载后是 `Douchat.app`：`ai.thinkany.douchat`，`0.1.8` / `0.1.8`，
`codesign --verify --deep --strict` 通过，`spctl` accepted（Notarized Developer ID，
MinHua Tang (JU9K7W6T6W)），`lipo -archs` = `arm64`。

**feed-discover。** `ADOPT https://cdn.douchat.ai/latest-mac.yml`（electron-builder manifest）。

**生产源。** 用一次性测试对这个 bundle 调 `AppScanner().scan(bundlesAt:)` +
`ElectronManifestSource().latestVersion(for:)`（当时 `channel-verify` 的源链是手抄的、漏了 Electron 源，
答不了这类 app；2026-10-04 起它直接用 `SourceStack.make`，对 0.1.22 真包给出 `winning source Electron`）：

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

## 签名迁移复核（2026-11-15）

**修复前的触发条件。** `ai.thinkany.douchat` `0.1.28` 的代码签名为
`Developer ID Application: MinHua Tang (JU9K7W6T6W)`，其声明的
`https://cdn.douchat.ai/thinkany/latest-mac.yml` 发布 `0.1.29`。安装事件记录显示下载的正是
`/thinkany/Douchat-0.1.29-mac-arm64.zip`，随后报告：

```text
Team Identifier mismatch: installed “JU9K7W6T6W” vs downloaded “8PL52G56V9”. Refusing to install.
```

**独立下载复核。** 从上述 manifest 下载 arm64 zip，并从[官网](https://douchat.ai/)列出的地址
下载 arm64 dmg。两者的大小、SHA-512 均与 manifest 相等：

```text
Douchat-0.1.29-mac-arm64.zip: 123001804 bytes
SHA-512: A544FUqTt17Osk05tsr5kWdxjIdtr7IhVmu8Vy10KWUoTzgprKjFj4rs2hMOjMet/JjkME1wrXZuHXGhI1JpFA==
Douchat-0.1.29-mac-arm64.dmg: 123235602 bytes
SHA-512: 14kYWlOGFPh9ds1fTVGitFB4dhcpshdx8U1rUkIAyq9+WuDpYTK9i/mPksIjB+TjEznlgPTQawSHe4WWOl1jHQ==
```

zip 解包与 dmg 只读挂载后均为 `ai.thinkany.douchat` `0.1.29` / `0.1.29`、arm64，
`LSMinimumSystemVersion=12.0`，更新配置均为 `/thinkany`。两份 bundle 的结果相同：

```text
codesign -dvv Douchat.app
Authority=Developer ID Application: ThinkAny, LLC (8PL52G56V9)
TeamIdentifier=8PL52G56V9
Notarization Ticket=stapled

codesign --verify --deep --strict Douchat.app
exit 0

spctl --assess --type execute --verbose=2 Douchat.app
accepted
source=Notarized Developer ID
```

`0.1.28` 的严格验签也通过。这是官方当前发布包改变签名主体触发的拒装，未发现源选择或解包选错包。

**旧包已签名授权。** `codesign -d -r- Douchat.app` 读取 `0.1.28` 的指定要求如下；它已经包含
两个 Team，而 `0.1.29` 只包含新 Team：

```text
identifier "ai.thinkany.douchat" and anchor apple generic
and certificate 1[field.1.2.840.113635.100.6.2.6] exists
and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
and (certificate leaf[subject.OU] = JU9K7W6T6W or certificate leaf[subject.OU] = "8PL52G56V9")
```

**兼容范围。** `SignatureVerifier.verifyTeamIdentifierMatch` 允许上述 bundle 的旧 Team → 新 Team，
前提是 `verifySatisfiesDesignatedRequirement` 按旧包原有、未改写的指定要求验证下载包通过。
不是仅凭两个 Team 字符串放行，也没有把新包自己的指定要求当作信任依据。
同 Team 的路径不变；未登记的 Team、其他 bundle、逆向迁移与缺少旧签名授权的包仍拒绝。
后续严格代码签名、bundle ID、架构、OS 校验和 privileged staging 的指定要求 + cdhash 复验保持不变。
新包的指定要求不授权旧 Team，跨 Team 回滚仍会被备份的真实性校验拒绝。
未核实厂商改变签名主体的具体原因，也未测试 Douchat 自更新器是否支持跨 Team 迁移。

复验使用 `https://cdn.douchat.ai/thinkany/latest-mac.yml`、
`https://cdn.douchat.ai/thinkany/Douchat-0.1.29-mac-arm64.zip` 和
`https://cdn.douchat.ai/thinkany/Douchat-0.1.29-mac-arm64.dmg`，按上方「如何复验」的哈希、解包、
签名命令检查；dmg 应只读挂载，完成后卸载。
