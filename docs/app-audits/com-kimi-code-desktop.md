# Kimi Code

审计 2026-09-18。

## 基本信息

- Bundle ID: `com.kimi.code.desktop`
- App 名: `Kimi Code.app`（与 [Kimi](com-moonshot-kimichat.md) `com.moonshot.kimichat` 是两个产品，同一厂商）
- Team ID: `2J9472RW75` — Beijing Moonshot Technology Co., Ltd（Developer ID，已公证）
- 观测版本: `1.0.1`（`CFBundleShortVersionString` 与 `CFBundleVersion` 都是 `1.0.1`），
  `LSMinimumSystemVersion` 12.0，arm64 包的主程序只有 arm64
- 来源: 官网下载地址 `code.kimi.com/kimi-code/desktop/download/KimiCode-mac-arm64.dmg?download=1`
  302 到 `cdn.kimi.com` 的同名文件（142,988,263 字节，`Last-Modified: Thu, 17 Sep 2026 13:07:46 GMT`）。
  DMG 顶层直接是 `Kimi Code.app`，不是安装器（和 Kimi 不同）。
- 自更新机制: **electron-updater**（`Squirrel.framework` + `Electron Framework.framework`），bundle 自带
  `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://code.kimi.com/kimi-code/desktop/
  channel: latest
  updaterCacheDirName: kimi-code-app-updater
  ```

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** | — | — | 没查 | — | — | ✓ + changelog recipe |
| **canary** | — | — | — | ✗ | — | ✗ |
| **preview** | — | — | — | — | — | ✗ |

当前生效源：**Electron**（`ElectronManifestSource`）。不需要 VendorProbe recipe。

- **Sparkle** — 没有 `SUFeedURL`。
- **Homebrew** — `brew search --cask kimi` 只有 `kimi`（那是 Kimi）和无关的 `kimis`，没有 Kimi Code 的 cask。
- **GitHub** — 公开的发布不在 GitHub；canary 读的是私有仓库（见下）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.kimi.code.desktop` | — | — | — | ✓ |
| canary | 没查（没有公开包） | 没查 | 版本号含 `-canary.` | 私有 GitHub 仓库 + `gh auth token` | ✗ |
| preview | 没查（没有公开包） | 没查 | 版本号含 `-preview.` | 不自动更新 | ✗ |

以下读自 1.0.1 的 `app.asar`（主进程打包后的 JS，`src/main/release-channel.ts` /
`src/main/canary-updater.ts` 两个 region）：

- `isCanaryVersion(v)` = `v.includes("-canary.")`，`isPreviewVersion(v)` = `v.includes("-preview.")`；
  `updateChannelFromVersion` 取 `-` 后第一段，canary / preview 之外一律 `latest`。
- stable（`initAutoUpdater`）在版本是 canary 或 preview 时直接不启动。
- canary（`initCanaryGithubUpdater`）把 feed 换成 `provider: "github"`、`owner: "MoonshotAI"`、
  `repo: "kimi-code-app"`、`private: true`，token 取自本地 `gh auth token`，拿不到就记一句
  `canary auto-update unavailable` 然后放弃。这是内部轨道，外部用户拿不到包，也没有公开端点可读，
  所以不接。
- preview 没有任何更新器。

stable 目录下 `beta-mac.yml`、`alpha-mac.yml`、`nightly-mac.yml`、`canary-mac.yml`、
`latest-mac-arm64.yml`、`arm64-mac.yml` 都是 404（2026-09-18）。

**没验证的风险：** 如果真有 canary / preview 副本出现在用户机器上，而它的 `app-update.yml` 仍写着
`channel: latest`，`ElectronManifestSource` 会拿 stable 的 `version` 去和 `1.0.2-canary.3` 这种版本比。
手上没有这种包，这一点没法核实。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://code.kimi.com/kimi-code/desktop/latest-mac.yml`（302 到 `cdn.kimi.com`），
  实际请求带 `?noCache=<token>`
- 版本方案: manifest 只有一个 `version`，与 `CFBundleShortVersionString` 同构（`1.0.1`）
- `releaseDate` 是完整的 ISO8601 时间戳（`2026-09-17T12:13:48.537Z`）
- 按区域换 feed：app 登录后按 `serverRegionProfile` 在运行时 `setFeedURL`，`mainland-cn` 用
  `code.kimi.com/kimi-code`，`global` 用 `code.kimi.ai/kimi-code`，后面都接 `/desktop/`。我们只读
  bundle 里写死的 `.com`。两边的 manifest 和 changelog 在 2026-09-18 完全相同（见「历史与实测」）；
  以后要是分叉，`.ai` 区的用户看到的会是 `.com` 的版本。
- 没有 `stagingPercentage`（2026-09-18），所以不存在「轨道最新」和「本机分到的版本」的区别。
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（blockmap 分块下载） | 有 blockmap | 不能 |
| 证据 | `app.asar` 里是 electron-updater，canary 分支还专门重写了 `getBlockMapFiles` | `binaries/1.0.1/KimiCode-1.0.1-mac-arm64.zip.blockmap` 对 Range 请求回 206（2026-09-18） | `DeltaApplier` 只吃 Sparkle binary delta |

- 格式: electron-builder blockmap（不是二进制补丁）
- 阻塞项: 需要新机制，而收益只是省下载量

## Changelog

- 来源: recipe（`Recipes/com-kimi-code-desktop.swift`），`sourceTemplate`
  `https://code.kimi.com/kimi-code/desktop/binaries/{version}/changelog.en.md`
- 由来：app 自己的更新器在 `update-available` 之后调 `fetchReleaseNotes(version)`，并发拉
  `${cdnBase}/desktop/binaries/${version}/changelog.{zh,en}.md`。每个版本一个文件，没有索引，也没有 latest 别名。
- 文件内容**就只有说明**：以 `### Polish` / `### Features` / `### Bug Fixes` 开头，下面是单行的 `- …`，
  全文不出现版本号。所以加了 `ChangelogRecipe.versionFromTemplate`：条目的版本取 URL 模板里代入的那个
  版本；没有版本就什么都不解析（不会出现没有版本号的条目）。约束（模板必须带 `{version}`、
  `maxEntries: 1`、entryPattern 不带 `version` / `title` 组、不走 structured / 两段式 / feed page）
  由 `versionFromTemplateOnlyLandsOnAOneReleasePerVersionPage` 对整个注册表检查。
- `###` 分组标题通过 `headingPattern` 作为标题渲染。
- 语言：用 en。app 自己两种都拉，按界面语言显示；我们这边没有语言选择可以跟它对齐，和 Kimi 一样用英文。
- `source`（没有版本时的兜底）是 manifest 本身：`versionFromTemplate` 在没有版本时本来就解析不出东西，
  兜底页只需要是个能展示的地址。
- `duo verify` 会跳过这条：模板化 recipe 需要版本，而这个 app 的版本来自 `ElectronManifestSource`，
  扫描拿不到（`CLI/Sources/DuoKit/Verify.swift` 的 `sourceTemplate != nil, version == nil` 分支，
  读代码得出，没有跑 `duo verify` 看）。
- 跟随 channel: 只有 stable 一条公开轨。

## 一键安装

- 状态: 由 `ElectronManifestSource` 提供。manifest 的 `files:` 里按架构选
  `binaries/1.0.1/KimiCode-1.0.1-mac-arm64.zip`（带 sha512 + size），走 `VendorInstaller` 的 zip 路线 +
  Team ID 闸。
- 格式: zip
- **读的是**: 厂商更新器给每个已装副本的同一份 manifest，没有 `stagingPercentage`，也就是人人都能手动下到的 GA 版本
  （官网 DMG 链接 2026-09-18 给的也是 1.0.1）。
- zip 已下载实测，见「历史与实测」：sha512 与 manifest 一致，顶层就是 `Kimi Code.app`，签名和公证都通过。
- 没有跑 `--install` 实装。

## 已知问题

- 按区域的 feed（`.com` / `.ai`）目前内容相同，分叉了也没东西能发现。
- canary / preview 副本在用户机器上会被怎么判定，没验证（见 Channel 详情）。

## 如何复验

```bash
# 1. manifest（带 noCache，与 ElectronManifestSource 相同）
curl -sSL "https://code.kimi.com/kimi-code/desktop/latest-mac.yml?noCache=$RANDOM" | head -3

# 2. 当前版本的说明（把版本换成 manifest 里的）
curl -sSL "https://code.kimi.com/kimi-code/desktop/binaries/1.0.1/changelog.en.md"

# 3. recipe 的 fixture 与注册表约束
swift test --package-path DuoUpdaterCore --filter 'KimiCode|versionFromTemplate'
```

## 历史与实测

### 2026-09-18 接入时的测量

**DMG 身份。** 只读挂载 `KimiCode-mac-arm64.dmg`：`Kimi Code.app`，`CFBundleIdentifier`
`com.kimi.code.desktop`，`1.0.1` / `1.0.1`，`codesign` Authority
`Developer ID Application: Beijing Moonshot Technology Co., Ltd (2J9472RW75)`，`spctl`
`accepted, source=Notarized Developer ID`。`feed-discover` 对这个 bundle 的判定：
`ADOPT https://code.kimi.com/kimi-code/desktop/latest-mac.yml`。

**生产源。** 用一次性程序对挂载的 bundle 调 `AppScanner().scan(bundlesAt:)` +
`ElectronManifestSource().latestVersion(for:)`：

```
Kimi Code com.kimi.code.desktop 1.0.1
manifest: https://code.kimi.com/kimi-code/desktop/latest-mac.yml
resolved: 1.0.1 kind: zip sha512: true size: 142010925
artifact: https://code.kimi.com/kimi-code/desktop/binaries/1.0.1/KimiCode-1.0.1-mac-arm64.zip published: 2026-09-17 12:13:48 +0000
```

**manifest 缓存。** `cdn.kimi.com` 回 `cache-control: no-cache, max-age=0, must-revalidate`，
`x-response-cache: miss`。裸地址和带 `noCache` 的地址都给出 `version: 1.0.1`。没有 Kimi 那种边缘副本滞后。

**区域。** `code.kimi.com/kimi-code/desktop/latest-mac.yml` 与 `code.kimi.ai/kimi-code/desktop/latest-mac.yml`
（302 到 `cdn.kimi.ai`）都是 `version: 1.0.1`、`releaseDate: '2026-09-17T12:13:48.537Z'`；两边的
`binaries/1.0.1/changelog.{en,zh}.md` 内容相同。

**zip。** 下载 `binaries/1.0.1/KimiCode-1.0.1-mac-arm64.zip`：142,010,925 字节，`openssl dgst -sha512 -binary | base64`
与 manifest 的 `sha512` 一致；1386 个条目全部在 `Kimi Code.app/` 下；`ditto -x -k` 解出后
`codesign --verify --deep --strict` 通过，Team `2J9472RW75`，`1.0.1` / `1.0.1`，`LSMinimumSystemVersion` 12.0，
`spctl` accepted（Notarized Developer ID），`lipo -archs` = `arm64`。

**changelog。** `binaries/1.0.0/changelog.en.md` 964 字节（`### Features` 8 条 + `### Bug Fixes` 3 条），
`binaries/1.0.1/changelog.en.md` 911 字节（`### Polish` 5 条 + `### Bug Fixes` 5 条）；两份都以 `###` 开头、
LF 换行、UTF-8。`0.9.9`、`0.9.0`、`1.0.2` 是 404，响应体是 `application/json`。用
`ChangelogService.loadDiagnostic` 跑注册表里的 recipe：

```
1.0.1 status: 200 entries: 1 version: 1.0.1 items: 10 blocks: 12  headings: ["Polish", "Bug Fixes"]
1.0.0 status: 200 entries: 1 version: 1.0.0 items: 11 blocks: 13  headings: ["Features", "Bug Fixes"]
9.9.9 status: 404 entries: 0
```

`ChangelogService.load(recipe, version: "1.0.1", …)` 同样给出 1 条、版本 `1.0.1`。

**变异。** 删掉 extractor 里「没有版本就直接返回 nil」的判断，测试照样全过：已有的
「版本和标题都为空的条目丢弃」那条 guard 已经覆盖了，所以那段删了，改成在注册表检查里禁止 `title` 组。
让 extractor 忽略请求的版本，或者让 `ChangelogService.parse` 不往下传版本，
`theEntryIsNamedByTheRequestedVersion` 都会失败。
