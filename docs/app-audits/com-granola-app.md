# Granola

审计 2026-10-08（重审；2026-08-17 那版只在一个真包上跑过 up-to-date，没有上一版 → 新版的实测，
没查渠道和 Granola 自己的更新请求，也没跑一键）。

## 基本信息
- Bundle ID: `com.granola.app`
- Team ID: `QZ7DHHLN25` — Developer ID Application: Granola Labs Ltd（7.626.2、7.626.3 相同，均
  `Notarized Developer ID`）
- 观测版本: `7.626.3`（short = build）、上一版 `7.626.2`。`LSMinimumSystemVersion` 13.0；universal
  （`x86_64 arm64`）
- 自更新机制: electron-updater。包里的 `app-update.yml` 写的是 `provider: github`、
  `granola-inc/granola-electron`，但运行时被覆盖：`autoUpdater.setFeedURL("https://api.granola.ai/v1/check-for-update")`
  （`app.asar` 字符串，见 Phase 3⅞）。`autoDownload = app.isPackaged`（即后台自动下载），
  `allowDowngrade = false`
- 包内还带一个**相机系统扩展**：`Contents/Library/SystemExtensions/com.granola.app.GranolaMacWebcam.Extension.systemextension`
  （`CMIOExtension`，1.53），以及负责激活 / 替换它的 `Contents/Helpers/GranolaMacWebcam.app`（`LSBackgroundOnly`，
  二进制里有 `activationRequestForExtension:queue:` / `request:actionForReplacingExtension:withExtension:`）
- Homebrew: cask `granola`，`auto_updates: true`，版本 `7.626.3`，URL 就是 recipe 装的那个 CloudFront dmg（2026-10-08）
- 不开源

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，让位） | — | — | ✓ 一键 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**（`VendorProbeSource`，recipe 在
`Recipes/com-granola-app.swift`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.granola.app` | — | — | `latest-mac.yml` 的 `version` | ✓ |

**有没有别的轨（实测 + 字符串，结论是「没找到」，不是「没有」）:**

- `app.asar` 里没有 `autoUpdater.channel` 赋值，没有 `beta-mac` / `alpha-mac`、`updateChannel` 一类字符串；
  `allowPrerelease` 只在 electron-updater 自己的构造函数里出现（默认 false）。
- 端点对**任何**文件名都 302 到当前版本目录：`beta-mac.yml`、`alpha-mac.yml`、`nightly-mac.yml` 都被重定向到
  `…/7.626.3/<同名>`，而这些文件在 CloudFront 上都是 403（S3 不存在）。也就是端点不按文件名分轨。
- Granola 自己的检查会带 `Authorization: Bearer <登录 token>`、`X-Granola-Platform: macOS`、
  `X-Granola-Device-Id`（字符串）。不带 token、带随机设备号、带无效 token，四种组合都 302 到 `7.626.3`。
  **带真实登录 token 时服务器会不会给内部 / 早期构建，没法验证**（要账号）。

## 更新检测
- 源: `VendorProbeSource`，端点 `https://api.granola.ai/v1/check-for-update/latest-mac.yml` → 302 →
  `https://dr2v7l5emb758.cloudfront.net/7.626.3/latest-mac.yml`
- manifest（2026-10-08）: `version: 7.626.3`、只列 `Granola-7.626.3-mac-universal.zip`（`sha512` + `size 297602155`）、
  `releaseDate: '2026-10-06T17:47:12.941Z'`；**没有** `stagingPercentage`、系统版本字段、release notes
- `version` 等于 Info.plist 两个版本字段；recipe 的 `publishedAtPattern` 读 `releaseDate`
- `feed-discover`（7.626.3）: `review    electronProviderNeedsConstruction`（包里的 github provider 是假地址，
  真地址在运行时设置，`feed-discover` 看不到），所以要 recipe
- 发版很密：CloudFront 上 7.626.0 / .1 / .2 / .3 都在，后两个 releaseDate 同一天相隔 4.5 小时

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有，但受远端开关控制 | 有 blockmap | 不能 |
| 证据 | `app.asar`: `disableDifferentialDownload = !<feature flag>`（初始化时先设为 true） | `Granola-7.626.3-mac-universal.zip.blockmap`（307,017 B）与 `.dmg.blockmap`（316,076 B）都 200 | `DeltaApplier` 只吃 Sparkle binary delta；recipe 整包下载 dmg |

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 请求带登录 token 与设备号；electron-updater 也支持 `stagingPercentage` | 匿名请求：否（四种请求头组合同一答案；manifest 无 `stagingPercentage`）。登录后：未验证 | 不需要 |
| 按架构 / 按 OS 分轨 | — | 否：只有 universal；`arm64` / `x64` 单架构 dmg 403。下限 13.0 只在包里（cask 写 `macos >= 13`），manifest 不写 | — |
| 自更新器会不会和我们抢 | 会：`autoDownload` 在打包版上为 true，`autoInstallOnAppQuit` 默认 true（推断：后台下载、退出时装）；另有 MDM 关自动更新的分支（`managed-auto-update-disabled`） | 同一端点 | 第二轮未跑 |

## Changelog
- 来源: 无
- 结构化: `changelog pane  none — the pane says there are no release notes`（7.626.2 与 7.626.3 两个包同一行）
- manifest 不带说明；recipe 的 `downloadURL` 是官网首页，`changelogURL` 为 nil
- 官网 `https://www.granola.ai/updates`（`/docs/changelog` 也跳到这里）是功能公告博客：按日期的文章，
  不标版本号。每天几个版本、公告几周一篇，版本 → 条目对不上
- 跟随 channel: —
- Recipe 状态: 不需要（`ChangelogRecipe` 没有可对版本的页面；最多给面板一个网页链接，价值低）

## 一键安装
- 状态: 支持（`install: .versionTemplate("https://dr2v7l5emb758.cloudfront.net/{version}/Granola-{version}-mac-universal.dmg")`，`.dmg`）
- 端到端（2026-10-08，第一轮，不启动）: 7.626.2 → `duo check` `update 7.626.3`、`source Vendor`；`duo install /Applications/Granola.app --yes --json` → `installed`、`route vendor`、`bytesDownloaded 306974683`（dmg，只过 Team 闸），约 51 s。装后 7.626.3，strict 通过，`Notarized Developer ID`，Team `QZ7DHHLN25`；与厂商 7.626.3 dmg 逐文件比 SHA-256，503 个文件、14 个软链接全部相同。没有启动 app，相机系统扩展没有被激活
- 格式: dmg（universal，7.626.3 为 306,974,683 B）
- 校验: **不接**。manifest 的 `sha512` 描述的是 zip，不是 recipe 装的 dmg。实测 7.626.3：manifest
  `ebWkPvoSPQryOWIfzD70NjNWSOXvRzx9ISdhWnCVtrjLavJLExfKS1aMh4m7a2AzFNr21VxZGmGY5byqRBwIcQ==`（zip，297,602,155 B），
  dmg 的 SHA-512 是 `igilZJLz1cs8Fx538Uxn9JbNsmplRJq7QC/w2W21Am3YuatzXCon3XHPeNTmFy8cT657M41Rq5fAIpCc2LGLgQ==`
  （306,974,683 B）。只靠 Team 闸
- **读的是**: 匿名请求能拿到的 head（与 Homebrew cask 下的是同一个 dmg）。登录用户的请求带 token，
  服务器是否按人分配不同构建未验证；如果分配，duo 读的是公开 head，不会超前于公开可下载的版本
- Team: 7.626.2 / 7.626.3 同为 `QZ7DHHLN25`，`codesign --verify --deep --strict` 均退出 0
- 嵌套: `check-bundle.sh` 列出 4 个 Electron helper（`LSUIElement`）和 `Contents/Helpers/GranolaMacWebcam.app`
  （`LSBackgroundOnly`）。另有相机系统扩展（上文）。两版里扩展都是 1.53，但可执行文件哈希不同。
  原地换 bundle 后系统里已激活的扩展不会自动换新，要等 Granola 的 helper 发替换请求（推断，未验证）；
  扩展与 helper 都不是常驻 LoginItem
- 阻塞: 无已知硬阻塞

## 已知问题
- manifest 的 `sha512` 是 zip 的，不能拿来校验 dmg（上文实测）
- 没有 changelog
- Granola 默认后台自动下载、退出时安装，和 duo 的一键可能撞车（第二轮未跑）
- 系统扩展在一键后由谁、何时替换没验证

## 建议下一步
1. 一键第一轮已过（见「一键安装」）；第二轮（app 运行中）未跑。第二轮重点看 Granola 退出时自己的安装会不会把 duo 装好的
   版本覆盖回去，以及扩展状态
2. 若想要摘要校验：recipe 改装 zip（manifest 的 `sha512` 对得上 zip），要先下载 zip 比对 SHA-512 再改；
   现在 dmg + Team 闸可用，不急
3. changelog 不做

## 如何复验

2026-10-08。包从 recipe 的 CloudFront 地址下载（`curl -fL --retry 5 -C -`），各放一个空目录；dmg 只读挂载、
`ditto` 拷出 .app，不安装、不启动。

```bash
curl -sSL -D - https://api.granola.ai/v1/check-for-update/latest-mac.yml
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' -H "X-Granola-Platform: macOS" \
  -H "X-Granola-Device-Id: $(uuidgen)" https://api.granola.ai/v1/check-for-update/latest-mac.yml
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://api.granola.ai/v1/check-for-update/beta-mac.yml
curl -sS -o /dev/null -w '%{http_code}\n' https://dr2v7l5emb758.cloudfront.net/7.626.3/beta-mac.yml        # 403
curl -sS https://dr2v7l5emb758.cloudfront.net/7.626.2/latest-mac.yml                                        # 上一版
curl -fL -o Granola-7.626.3-mac-universal.dmg https://dr2v7l5emb758.cloudfront.net/7.626.3/Granola-7.626.3-mac-universal.dmg
curl -fL -o Granola-7.626.2-mac-universal.dmg https://dr2v7l5emb758.cloudfront.net/7.626.2/Granola-7.626.2-mac-universal.dmg
swift run --package-path application-test channel-verify <Granola.app>   # 两个包各跑一次
openssl dgst -sha512 -binary Granola-7.626.3-mac-universal.dmg | base64
.claude/skills/coverage-discovery/scripts/check-bundle.sh Granola-7.626.3-mac-universal.dmg
```

| 包 | short / build | Team | detected | VendorProbe verdict | winning | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 7.626.2 | 7.626.2 / 7.626.2 | QZ7DHHLN25 | stable | UPDATE 7.626.2 → 7.626.3 | Vendor | **UPDATE → 7.626.3** | none |
| 7.626.3 | 7.626.3 / 7.626.3 | QZ7DHHLN25 | stable | up to date | Vendor | **up to date** | none |

两个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`（`source=Notarized Developer ID`）。
`download` 都是 `https://dr2v7l5emb758.cloudfront.net/7.626.3/Granola-7.626.3-mac-universal.dmg`。
下载 SHA-256：7.626.2 `766c1ba5…a8b4`（306,972,799 B，与 HEAD 的 `content-length` 相等）、7.626.3 `8a15a7e9…f0e4`。

**一键端到端预备（第一轮已用它跑通）:** 上一版用 7.626.2 的 dmg（上表第一行），解包出的 `Granola.app` 就是要 `ditto` 进
`/Applications` 的那个。预期 `duo check` 报 update 7.626.3，`duo install --yes --json` 走 `route vendor`
（dmg，仅 Team 闸，没有摘要）。Granola 发版很密，跑之前先看一眼 manifest 是否已经前进。

## 重审更正（相对 2026-08-17 版）
- 原文「Homebrew ✗」：cask 是有的（`granola`），只是 `auto_updates: true`，让位
- 原文没提包内的相机系统扩展和它的 helper
- 原文没说 Granola 自己的检查带登录 token 和设备号，也没说端点不按文件名分轨（本次实测）
- 原文「暂无公开、逐版本的 changelog」成立；补了面板实测行和 `/updates` 页面为什么不能用
- 原文「一键 ✓」只有挂载验证、没有端到端；本次第一轮端到端已跑通（见「一键安装」）
