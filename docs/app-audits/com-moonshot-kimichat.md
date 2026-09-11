# Kimi

审计 2026-09-11。

## 基本信息

- Bundle ID: `com.moonshot.kimichat`
- App 名: `Kimi.app`（产品名 Kimi Work，更新说明页在 `kimi.com/en/help/kimi-work/release-notes`）
- Team ID: `2J9472RW75` — Beijing Moonshot Technology Co., Ltd
- 观测版本: `3.2.7`（`CFBundleShortVersionString` 与 `CFBundleVersion` 都是 `3.2.7`），
  `LSMinimumSystemVersion` 12.0，主程序只有 arm64
- 自更新机制: **electron-updater**（`Contents/Frameworks/` 下有 `Squirrel.framework` +
  `Electron Framework.framework`），bundle 自带 `Contents/Resources/app-update.yml`：

  ```yaml
  provider: generic
  url: https://kimi-img.moonshot.cn/app/upgrade/
  updaterCacheDirName: kimi-desktop-updater
  ```

**官网 DMG 里装的不是 app，是安装器。** `kimi_3.2.7.dmg` 顶层只有 `Kimi Installer.app`
（`com.moonshot.kimichat.installer`，同 Team，3.2.7）；真正的 `Kimi.app` 在它的
`Contents/Helpers/Kimi.app`（`codesign --verify --deep --strict` 通过，同 Team、同版本）。
安装器二进制的字符串显示它做的是：要求先退出 Kimi、以 `.Kimi.app.installing` /
`.Kimi.app.backup` 原子替换 `/Applications/Kimi.app`、顺带升级
`~/.kimi-webbridge/bin/kimi-webbridge`。Homebrew cask `kimi` 的 `app` 也是直接取
`Kimi Installer.app/Contents/Helpers/Kimi.app`。所以 `feed-discover` 对这个 DMG 报的
`noKnownUpdater` 说的是**安装器**，不是 Kimi。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** | — | 未验证 | 没查 | 没查 | — | ✓ + changelog recipe |

当前生效源：**Electron**（`ElectronManifestSource`，读 bundle 自带的 `app-update.yml`）。
不需要 VendorProbe recipe。

- **Sparkle** — 没有 `SUFeedURL`。
- **Homebrew** — cask `kimi` 存在、没有 `auto_updates`，`livecheck` 用 `header_match` 读
  `appsupport.moonshot.cn/api/app/pkg/latest/macos/download` 的 302。但 `HomebrewCaskSource`
  只对 Caskroom 里真有这个 cask 的副本生效，官网装的副本它不答；brew 装的副本（artifact 是
  上面那条嵌套路径）会不会被它匹配上，没验证。
- **MAS / GitHub** — 没查。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.moonshot.kimichat` | 独立 | — | — | ✓ |

`app-update.yml` 没写 `channel`（即 `latest`）。同目录的 `beta-mac.yml`、`alpha-mac.yml`、
`latest-mac-arm64.yml` 在 2026-09-11 都是 404。没发现别的轨道。

## 更新检测

- 源: `ElectronManifestSource`
- 端点: `https://kimi-img.moonshot.cn/app/upgrade/latest-mac.yml`（electron-updater generic
  provider 的默认 manifest），实际请求带 `?noCache=<token>`
- 版本方案: manifest 只有一个 `version`，与 `CFBundleShortVersionString` 同构（`3.2.7`）

### ⚠️ CDN 边缘缓存：不带查询串读到的是旧版本

2026-09-11 同一时段、同一出口的实测：

| 请求 | 回答 | `Age` | `Last-Modified` |
|---|---|---|---|
| 裸地址 | `version: 3.2.5` | 384307 | Fri, 04 Sep 2026 15:04:47 GMT |
| 裸地址 + `Cache-Control: no-cache` / `max-age=0` / `Pragma: no-cache` | `3.2.5` | ~384381 | 同上 |
| 裸地址 + 旧 `If-None-Match` | 304 | ~384382 | — |
| `?noCache=<随机>` | `version: 3.2.7`（`releaseDate: 2026-09-10T15:39:50.574Z`） | 0 | Fri, 11 Sep 2026 06:11:26 GMT |

请求头一律无效，只有查询串能穿过边缘副本。electron-updater 每次都带
`noCache=<Date.now().toString(32)>`：`GenericProvider.getLatestVersion` 调
`newUrlFromBase(channelFile, baseUrl, isAddNoCacheQuery)`，而 `AppUpdater.isAddNoCacheQuery`
在请求头里没有 `authorization` / `private-token` 时恒为 true（electron-builder 源码，
issue #3021）。所以 Kimi 自己的更新器读到的是源站——它的日志
（`~/Library/Logs/kimi-desktop/main.log`）同一晚记的是
`Update for version 3.2.7 is not available (latest version: 3.2.7, downgrade is disallowed)`。

修之前 `ElectronManifestSource` 读的是裸地址：`duo check Kimi --all --json` 给出
`"latestVersion":"3.2.5","source":"Electron","status":"up-to-date"`。3.2.7 的副本被对着
3.2.5 判成"最新"，而 3.2.5 / 3.2.6 的副本在边缘副本存活期间看不到任何更新。现在
`ElectronUpdateConfig.manifestRequestURL` 照 electron-updater 的做法加 `noCache`
（地址本身已带查询串时不动），所有走 generic provider 的 Electron app 一起受益；artifact
URL 仍对裸地址解析，token 不会进下载地址。`FeedDiscovery` 的 manifest 读取走同一个函数，
所以它对 Kimi 报的 `electronVersionMismatch` 也是这个缓存造成的假信号。

修之后（`make cli` 之后，同一晚）：`duo check Kimi --all --json` 给出
`"latestVersion":"3.2.7","source":"Electron","status":"up-to-date"`；`feed-discover` 对已装
bundle 的判定从 `review electronVersionMismatch` 变成 `ADOPT
https://kimi-img.moonshot.cn/app/upgrade/latest-mac.yml`。

### 不是版本源的两样东西

- **官网下载端点** `appsupport.moonshot.cn/api/app/pkg/latest/macos/download`：302 到
  `kimi-img.moonshot.cn/app/download/mac/kimi_3.2.7.dmg`，响应不带 `Age`（动态）。
  Homebrew 的 livecheck 读它。我们不用：它给的是安装器 DMG（见上），而 manifest 已经给出
  版本和带 sha512 的 zip。
- **`UpgradePolicyService`**：日志反复出现 `fetchUpgradePolicy: target=3.2.5 strategy=force
  hasDownloadUrl=true`。看起来是"低于 3.2.5 强制升级"的下限，不是"最新版本"（推断，
  端点没抓）。

### 为什么 app 里找不到「检查更新」

日志里更新器在启动后几秒自己跑 `Checking for update`，状态 `status=hidden`，没有 UI。主进程
代码里 autoUpdater 旁边有一个 `4 * 60 * 60 * 1e3` 的常量——推断是 4 小时一次的定时检查；
代码是混淆过的，没有逐行确认。没找到菜单项。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（differential download） | 没查 | 不能 |
| 证据 | 主进程里是 electron-updater 的 `isUseMultipleRangeRequest` / `isUrlProbablySupportMultiRangeRequests`（blockmap 分块下载） | 没查 `*.zip.blockmap` 是否存在 | `DeltaApplier` 只吃 Sparkle binary delta，没有 blockmap 机制 |

- 格式: electron-builder blockmap（不是二进制补丁）
- 阻塞项: 需要新机制，而收益只是下载量

## Changelog

- 来源: recipe（`ChangelogRecipeRegistry`，`com.moonshot.kimichat`）→
  `https://www.kimi.com/en/help/kimi-work/release-notes`
- 结构: 服务端渲染，每个版本一个 `<h2 id="327-2026-09-11">3.2.7 (2026-09-11)</h2>`，新的在前，
  下面是 `<p><strong>New|Changed|Fixed</strong></p>` + `<ul>` 分组。2026-09-11 页面上 13 个版本
  （3.2.7 … 3.1.6），recipe 在真实页面上 13/13 命中、每条都有条目；`duo verify --only moonshot`
  （2026-09-11）changelog ✓。
- 分组标签不保留：`Changelog.Entry` 只有 version/date/items，New/Changed/Fixed 按文档顺序拍平。
- 两个坑都在真实页面上：
  - 3.2.1 有一个嵌套在 `<li>` 里的 `<ul>`。惰性 `<li>(.*?)</li>` 会停在子项的 `</li>`，把父行和
    第一个子项粘成一行（9 行而不是 10 行）；item 改为停在下一个 `<li`/`</li>`。
  - 最后一个版本后面是 `</ul></div>` + 反馈组件 + 目录（13 个 `<li>`，每个的文字就是
    `3.2.7 (2026-09-11)` 这种）。body 停在下一个 `<h2` **或** `</div>`，否则最后一个版本会把目录
    吞成条目。
- manifest 的 `releaseNotes` 只有一句中文摘要（3.2.7：`新增滚动截图与插件推荐`），而且
  `ElectronManifestSource` 本来就不带 notes，所以 recipe 是唯一的结构化来源。
- 跟随 channel: 只有一条轨道。

## 一键安装

- 状态: 由 `ElectronManifestSource` 提供——manifest 的 `files:` 里有
  `Kimi-3.2.7-arm64-mac.zip`（sha512 + size），走 `VendorInstaller` 的 zip 路线 + Team ID 闸。
  **这次没下载 zip 验内部结构**（electron-builder 的 mac zip 顶层就是 `.app` 是惯例，未验证）。
  zip 本身 2026-09-11 HEAD 200、`application/zip`、430688879 字节。
- 格式: zip
- **读的是**: 厂商更新器给每个已装副本的同一份 manifest。manifest 里没有
  `stagingPercentage`（2026-09-11），所以没有"轨道最新 vs 本机被分配"的分别（electron-updater
  在没有 `stagingPercentage` 时不分桶——推断，没读那段源码确认）。
- 官网 DMG 路线不适用：它装的是安装器，不是 app。

## 已知问题

- `ElectronManifestSource` 不在 `duo verify` 的扫描范围里（它没有表，地址在 bundle 里），
  这个 app 的检测只能靠 `duo check` / `electron-verify` 复验。
- Kimi 自己不提供手动检查更新的入口（见上）。

## 如何复验

```bash
# 1. 边缘副本 vs 源站：两行应当给出不同的 version（边缘副本还没过期时）
python3 - <<'PY'
import urllib.request, uuid
u = "https://kimi-img.moonshot.cn/app/upgrade/latest-mac.yml"
for q in ["", "?noCache=" + uuid.uuid4().hex[:10]]:
    r = urllib.request.urlopen(urllib.request.Request(u + q, headers={"User-Agent": "Mozilla/5.0"}))
    print(repr(q), r.read().decode().splitlines()[0], "Age:", r.headers.get("Age"))
PY

# 2. 生产源读到的版本（make cli 之后）
duo check Kimi --all --json

# 3. changelog recipe 对真实页面
duo verify --only moonshot
```
