# Capy

审计 2026-10-04。

## 基本信息

- Bundle ID: `ai.capy.desktop`（stable）· `ai.capy.desktop.nightly`（nightly，`Capy Nightly.app`）
- Team ID: `9YWUN5FK23` — Developer ID Application: Yingting Sun（两个渠道相同，均已公证）
- 观测版本: stable `0.4.3`（short == build）· nightly `0.4.3-nightly.20261003.226`（short == build）；
  `LSMinimumSystemVersion` 13.0；arm64 包 `lipo -archs` = `arm64`
- 分发: 官网 `capy.ai/download`，按架构分 dmg。`/download/mac/arm64` 302 到
  `downloads.capy.ai/stable/Capy-<version>-arm64.dmg`，`/download/mac/x64` 同理
- 自更新机制: **electron-updater**（`Squirrel.framework` + `Electron Framework.framework`），
  bundle 自带 `Contents/Resources/app-update.yml`：

  ```yaml
  # Capy.app
  provider: generic
  url: https://d1lfowv2t69uz0.cloudfront.net/stable/
  updaterCacheDirName: '@capydesktop-updater'
  # Capy Nightly.app：同上，url 换成 …/nightly/
  ```

  没写 `channel:`，electron-updater 默认读 `latest-mac.yml`。
- Homebrew: 无 cask（`brew search --cask capy` 无结果，2026-10-04）
- Sparkle: 两个包都没有 `SUFeedURL`
- 不开源（`github.com/capy-ai` 下没有公开仓库）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** | — | — | 没查 | — | — | ✓ |
| **nightly** | — | — | — | — | — | ✓ |

当前生效源：**Electron**（`ElectronManifestSource`），两个渠道都是。没有 VendorProbe recipe；
stable 有 changelog recipe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `ai.capy.desktop` | 独立 | — | 各自 `app-update.yml` 的 `url` | ✓ |
| nightly | `ai.capy.desktop.nightly` | 独立 | bundle id 后缀 `.nightly` | 同上 | ✓ |

Pattern A：每个渠道一个 bundle id、一个 manifest 目录（`/stable/`、`/nightly/`），通用源读的就是
各自包里写的那个地址，不会跨渠道。`downloads.capy.ai/beta/`、`/canary/` 下的 `latest-mac.yml`
都是 403（2026-10-04），没有别的渠道。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://d1lfowv2t69uz0.cloudfront.net/{stable,nightly}/latest-mac.yml`（实际请求带
  `noCache` 查询串）。`downloads.capy.ai/{stable,nightly}/latest-mac.yml` 返回同一份内容
- 版本方案: manifest 的 `version` == 包的 short == build。nightly 是
  `0.4.3-nightly.<yyyymmdd>.<n>`；把 `.226` 的副本改成 `.20261002.225` 时判为有更新（见历史与实测）
- `releaseDate` 是完整 ISO8601（`2026-10-03T01:00:04.703Z`）
- manifest 没有 `minimumSystemVersion` 之类的字段，不按 OS 分轨（包里写的下限是 13.0）
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 支持 blockmap） | 无 | 不适用 |
| 证据 | electron-updater | 两份 `latest-mac.yml` 都没有 `blockMapSize` 字段（2026-10-04） | `DeltaApplier` 只吃 Sparkle binary delta |

## Changelog

- 来源: recipe（`ai-capy-desktop.swift`），读 `https://capy.ai/changelog`
- 页面: 服务端渲染，newest first，每版一个 `<article id="v0-4-3">`：`<time>` 显示日期、
  `<h2>Capy 0.4.3</h2>`、一行副标题 `<p>`，然后是 `<h3>` 分节下的 `<p class="font-inter …">`
  段落，中间夹截图
- 结构化: 版本 / 日期 / 副标题作 title / 段落作条目，`<h3>` 保留为分节标题，截图按位置插在条目之间
  （`headingPattern` + `imagePattern`）。页面底部有一篇没有版本号的 `Capy Beta`（`id="vbeta"`，
  桌面端之前的 web 版首发），被版本号要求数字的正则跳过
- 跟随 channel: 否。页面只记 stable 版本；nightly 没有 recipe，面板显示无更新日志
- manifest 不带 `releaseNotes`
- Recipe 状态: 已有

## 一键安装

- 状态: 两个渠道都由 `ElectronManifestSource` 提供。它从 `files:` 里选 arm64 zip（带 sha512 +
  size），走 `VendorInstaller` 的 zip 路线 + Team ID 闸
- 格式: zip，顶层只有一个 `.app`（`Capy.app` / `Capy Nightly.app`），无 LoginItems / 常驻 helper，
  `Contents/Frameworks` 下只有 Electron 的 4 个 Helper app
- **读的是**: 人人都能下载的 GA 版。每份 manifest 只有一个版本，就是 app 自己的更新器读的那份；
  stable 的 zip 与官网 dmg 是同一版本（`/download/mac/arm64` 302 到同一目录）。nightly 没有官网入口，
  但 manifest 就是 Capy Nightly 自己的更新器读的地址，装的是它自己也会装的那个构建
- 端到端: 未跑（`duo install` 需要先装上一版并串行执行）；zip 的 sha512 / Team / 验签见下
- 旧版仍可下载（`0.4.2` 的 arm64 zip 和 dmg、`0.4.0` 的 arm64 zip 都是 HTTP 200），可用来做端到端

## 已知问题

- 版本线还早（0.x），发布路径约定改动的风险高于成熟产品。
- 正文以段落为主、没有列表；如果厂商以后改用 `<ul>`，第二条 item pattern（`<li>`）接住。

## 如何复验

```bash
# 1. manifest
curl -sS "https://d1lfowv2t69uz0.cloudfront.net/stable/latest-mac.yml?noCache=$RANDOM"
curl -sS "https://d1lfowv2t69uz0.cloudfront.net/nightly/latest-mac.yml?noCache=$RANDOM"

# 2. 通用源对真包的判定（dmg 只读挂载，不安装）
swift run --package-path application-test feed-discover Capy-<version>-arm64.dmg

# 3. 一键装的那个 zip：sha512 与 manifest 一致、Team 与已装的一致
openssl dgst -sha512 -binary Capy-<version>-arm64.zip | base64
ditto -x -k Capy-<version>-arm64.zip out && codesign -dv out/Capy.app 2>&1 | grep TeamIdentifier

# 4. changelog recipe
duo verify --only capy
```

## 建议下一步

- 跑一次 stable 的端到端 `duo install`（0.4.2 → 最新）。

## 历史与实测

### 接入时的实测（2026-10-04）

**包身份。** 官网 `Capy-0.4.3-arm64.dmg` 与 `Capy Nightly-0.4.3-nightly.20261003.226-arm64.dmg`
只读挂载：`ai.capy.desktop` `0.4.3` / `ai.capy.desktop.nightly` `0.4.3-nightly.20261003.226`，
short == build，`spctl` 都是 Notarized Developer ID，Yingting Sun (9YWUN5FK23)。

**feed-discover。** 两个 dmg 都是
`ADOPT https://d1lfowv2t69uz0.cloudfront.net/{stable,nightly}/latest-mac.yml`（electron-builder
manifest）。`channel-verify` 的 `detected channel` 分别是 stable / nightly；它的全链路不读 dmg 里的
`app-update.yml`，所以那里 `winning source <none>`，由下面的生产源调用代替。

**生产源。** 用一次性测试对这两个 bundle 调 `AppScanner().scan(bundlesAt:)` +
`UpdateChecker(sources: SourceStack.make(githubToken: nil))`，再各加一份把
`CFBundleShortVersionString` 改低的副本：

```
ai.capy.desktop 0.4.3          → upToDate, source Electron
ai.capy.desktop 0.4.2(改)       → updateAvailable 0.4.3
  download …/stable/Capy-0.4.3-arm64.zip, zip, sha512 fXje8guS…, publishedAt 2026-10-03 01:00:04Z
ai.capy.desktop.nightly .226    → upToDate, source Electron
ai.capy.desktop.nightly .225(改) → updateAvailable 0.4.3-nightly.20261003.226
  download …/nightly/Capy%20Nightly-0.4.3-nightly.20261003.226-arm64.zip, zip, sha512 Vf3nboOZ…
```

**一键装的 zip。** 两个 arm64 zip：HTTP 200，149,975,308 / 150,039,032 字节，sha512 与各自 manifest
一致；解出的 `.app` Team `9YWUN5FK23`，`codesign --verify --deep --strict` 通过，`spctl` accepted，
`lipo -archs` = `arm64`。

**changelog 页。** recipe 的正则对 `capy.ai/changelog` 的原始 HTML 匹配到 8 条（0.4.3 到 0.2.0），
每条都有日期、副标题和 ≥1 条段落；0.4.3 有 10 条段落、8 个分节、3 张图。`Capy Beta` 那篇未被匹配。
