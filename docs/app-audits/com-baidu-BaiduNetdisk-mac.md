# 百度网盘 (BaiduNetdisk_mac)

审计 2026-08-29。

## 基本信息

- Bundle ID: `com.baidu.BaiduNetdisk-mac`
- App 名: `BaiduNetdisk_mac.app`（`CFBundleDisplayName` 也是这个；卷标/中文名是「百度网盘」）
- URL scheme: `com.baidu.BaiduNetdisk_mac`
- 官网下载页: https://pan.baidu.com/download
- 观测版本: `CFBundleShortVersionString` = `8.7.9`，`CFBundleVersion` = `473`
- `LSMinimumSystemVersion` = `10.13`（feed 里的 `system` 字段写的也是 `Mac OS X 10.13+`）
- Team ID: `738UU3Y57V` — Baidu (China) Co., Ltd；`spctl -a -t install` 判定
  "Notarized Developer ID"，`Notarization Ticket=stapled`
- 架构: `lipo -archs` = `arm64`（这一份包是 arm64 thin；厂商同时另发 x64 和 universal）
- 壳: Electron（`Contents/Frameworks/` 有 `Electron Framework.framework` +
  `Squirrel.framework`，业务在 `Resources/app.asar` / `core.asar`，另有一堆自研 dylib：
  `libkernel.dylib`、`libnetbase.dylib`、`libsyncengine.dylib` …）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Changelog |
|---|---|---|---|---|---|---|
| **stable** | ✗ | ✗ | — | — | ✓ 一键 | ✓ 原生结构化 |

当前生效源：**VendorProbe**。其余四条源为什么都不答：

- **Sparkle** — bundle 里没有 `SUFeedURL`。`Squirrel.framework` 是 Electron 自带的，
  不是 Sparkle，`SparkleAppcastSource` 不会有任何入口。
- **Homebrew** — 本机这份是手动装的，`HomebrewCaskSource` 的 provenance 闸只认
  brew 自己装过的 app，按设计不答。
- **MAS** — 非 MAS 分发，`Contents/_MASReceipt` 不存在。
- **GitHub** — 无公开发布仓库。

## 更新检测

### 厂商自己的两条更新通道，都用不了

1. **electron-updater（generic provider）——死的。**
   `Contents/Resources/app-update.yml` 明写：

   ```yaml
   provider: generic
   url: https://netdisk-pc.cdn.bcebos.com/update/
   updaterCacheDirName: baidunetdisk-updater
   ```

   但这个 feed 已经不存在：`latest-mac.yml`、`latest-mac-arm64.yml`、以及目录本身
   **全部 404**（2026-08-29 实测）。即 Electron 那半套自更新是留着没接的。

2. **原生自更新 —— 参数不明文。**
   `libkernel.dylib` 里有 `http://update.pan.baidu.com/autoupdate`（另有
   `update.pan.baidu.com/statistics` 出现在 `libbrowserengine` / `libbtsdk` /
   `libminosagent`）。直接 GET 该端点得到 **200 + 0 字节**；它要哪些 query/POST 参数
   在二进制里拼不出来，而且是明文 HTTP。**没有采纳。**

### 采纳的端点：官网下载页背后的 CMS API

```
https://pan.baidu.com/disk/cmsdata?do=client
```

怎么找到的：`pan.baidu.com/download` 是 Vue SPA，HTML 里没有版本；页面 JS
（`nd-static.bdstatic.com/m-static/wp-brand/js/chunk-common.*.js`）里
`getDownloadClientInfo` / `getMacDownloadInfo` 打的就是 `/disk/cmsdata`，`do=client`。

响应是 `application/json; charset=UTF-8`，约 4 KB，**匿名可取**：不需要 cookie、
不需要 Referer，用 `VendorProbeSource` 默认的 Safari UA 直接 200。每个产品线一个对象：

```json
"mac":{"title":"百度网盘Mac电脑客户端V8.7.9","version":"百度网盘Mac电脑客户端V8.7.9",
"url":"…/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_x64.dmg",
"url_1":"…/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg",
"url_2":"…/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_universal.dmg",
"publish":"2026-08-28 14:39:00","size":"444.2M","system":"Mac OS X 10.13+","feature_tips":""}
```

### 三个必须绕开的陷阱

1. **同一份 body 里有第二个 `_arm64.dmg`，而且排在前面。**
   key 是字典序，`genflow-pro-pc-mac`（库库 GenFlow，另一个百度产品）排在 `mac` 之前，
   它的包是 `…/MACGenFlowPro/1.3.6/KukuAI_1.3.6_arm64.dmg` —— 同一个 CDN、同一个
   `/issue/netdisk/` 前缀。所有 pattern 都是 first-match，所以裸的 `_arm64\.dmg`
   会先命中 KukuAI（已在真实 body 上实测确认）。**version 和 install 两条 pattern
   都钉了产品路径 `MACguanjia/` + 架构。**

2. **同版本号下 x64 / arm64 / universal 并排。** install pattern 必须钉 `_arm64.dmg`，
   不能取第一个。

3. **Windows 线的版本号是四段且前三段与 mac 相同**（`guanjia` = `8.7.9.102`），
   linux 线是 `8.7.0`。不锚定就会拿错产品线的版本。

### 版本 pattern 用了反向引用

```
/MACguanjia/([0-9]+(?:\.[0-9]+)+)/BaiduNetdisk_mac_\1_arm64\.dmg
```

`\1` 要求**目录里的版本和文件名里的版本必须是同一个**。这样「报出来的版本」按构造
就是「install spec 会下载的那个文件的版本」，两者不可能漂开。对不上就整体不匹配 →
降级成 unknown，是安全方向。

## 版本比较：只有 marketing，没有 build

feed 只给 `8.7.9`，bundle 还有一个 feed 从不提及的 `CFBundleVersion` = `473`。
`VersionComparator.isNewer(VersionSide, than:)` 在 marketing 打平后找不到 remote build，
返回 `false` —— 所以：

- **只涨 build 的重出包在这里是看不见的**（漏报，安全方向）；
- **永远不会因此产生幻影更新**（不会误报）。

百度的 mac 线 marketing 是会动的（同一份 body 里 Windows 8.7.9.102、linux 8.7.0），
所以这是**分辨率上限，不是判据失效**。

## Changelog

**已接，走 `ChangelogRecipe`（`mode: .json`），145 条历史。**

> 更正：本文初稿写的是「百度不为 Mac 客户端发布公开的更新日志页」，**这是错的**。
> 得出那个结论只查了 `feature_tips` 字段和客户端 bundle，没去查官网 —— 正是
> CLAUDE.md 里「断言『没有 X』之前先量一遍」那一条。

页面在 `https://pan.baidu.com/disk/version`（标题「百度网盘 版本更新」），有 8 个平台
tab，其中一个就是 **Mac版**。但**页面自己的 HTML 里一条 note 都没有**：8 个
`<section class="hp-section …">` 全是空的，内容由 `changelog.js` 填。

那支 JS 里 `disk.util.Versions.getData()` 打的是：

```
GET https://pan.baidu.com/disk/cmsdata?platform=mac&page=1&num=<n>
```

—— 和版本探测用的是**同一个 `/disk/cmsdata` 端点，另一套调用约定**（`do=client`
给「各平台最新一个」，`platform=<tab>` 给「某平台的完整历史」）。`total: 145`，
newest-first。取 `num=40` 与 `maxEntries` 对齐，24 KB（`num=100` 是 58 KB）。

条目形状（原样，厂商输出无空格）：

```json
{"detail":[{"more":["【团队空间】空间布局全新改版…"],"stable":true,"title":"百度网盘全新升级"}],
 "publish":"2026-08-28 14:39:00","size":"444.2M","system":"Mac OS X 10.13+",
 "title":"百度网盘Mac电脑客户端V8.7.9","url":"…_x64.dmg","url_1":"…_arm64.dmg",
 "version":"百度网盘Mac电脑客户端V8.7.9"}
```

### 真实数据里的三个形状（量过 100 条，不是猜的）

1. **11/100 条 `more` 是空数组，真正的更新说明跑到了 `detail.title` 里。**
   这些不是「没有更新说明的版本」—— 4.54.9 的 title 就是
   「百度网盘优化了一些已知的体验问题，欢迎升级体验~」，那就是全文。
   所以 `body` 捕获**整个 detail 对象**，`itemPatterns` 有序：先取 `more` 的元素，
   一条都没有时才回落到 `title`。只捕 `more` 数组的话，会有 11 条渲染成空条目。
2. **`detail` 里的 key 顺序不固定** —— 97 条是 `more, stable, title`，
   3 条是 `feature_tips, more, title`。任何「`more` 是第一个 key」的假设都会漏。
3. **版本串的写法变过三次** —— 近期 `百度网盘Mac电脑客户端V8.7.9`，
   较早 `百度网盘Mac电脑客户端 V4.15.0`（多一个空格），最早 `Mac版 V3.9.5`。
   锚 `V` + 数字而不是锚那串中文，三种都过。

第一条 item pattern 靠**标点**认 JSON 数组元素 —— 由 `[` 或 `,` 起、由 `,` 或 `]`
收的字符串。这正好把 `more` 的元素与同一对象里的 key（后面跟 `:`）和 `title` 的值
（前面是 `:`）分开。

### 验证

2026-08-29 对真实 40 条响应跑：**40 条全部匹配**，每条的 version / date / item 列表
与 `json.loads` 出来的真值**逐字节一致**，包括 7 条回落到 title 的。

### `changelogURL`

探针那边设成 `https://pan.baidu.com/disk/version`（人看的兜底页，过
`ChangelogURLPolicy`）。注意它是 JS 壳，只能当 fallback；结构化的 note 由上面的
`ChangelogRecipe` 出。`do=client` 响应里那个 `feature_tips` 对 `mac` 是空串，
**不是**更新说明的来源。

## 发布时间：故意不接

`publish` 字段是 `"2026-08-28 14:39:00"` —— 空格分隔、无时区，`ReleaseDate.parse`
不认这个形状（它只认 ISO8601 / 带 `T` 的无时区 / RFC822 / 纯 epoch），写了也是静默返回 nil。

它是 **Asia/Shanghai**，这条是量出来的不是猜的：同一个 artifact 的
`Last-Modified: Fri, 28 Aug 2026 06:41:09 GMT` = 14:41 CST，比 `publish` 的 14:39 晚两分钟。
按 UTC 读会让每个百度发布在 timeline 上早 8 小时 —— 正是 `ReleaseDate` 无时区分支
注释里警告的那种情况。所以 `publishedAtPattern: nil`。

## 一键安装

**已接，`.dmg`。** 闸门逐条核过（2026-08-29）：

| 闸 | 结果 |
|---|---|
| 同 bundle id | `com.baidu.BaiduNetdisk-mac` == 已装那份 |
| 同 Team ID | `738UU3Y57V` == 已装那份 |
| 公证 | `spctl -a -vvv -t install` → `accepted / source=Notarized Developer ID` |
| 架构 | `lipo -archs` → `arm64`，本机可跑 |

**并且这不是「看着像同一个文件」——是同一份字节。**
`https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg`
的 CDN ETag 是 `23bfa249b059597234bfd396bf631300`，本地下载的
`BaiduNetdisk_mac_8.7.9_arm64.dmg` 的 `md5 -q` 完全相同，`Content-Range` 报的
`415643425` 字节也与本地文件一致。上表验的就是这份包里的 `BaiduNetdisk_mac.app`。

### ⚠️ install 必须是 `.bodyPattern`，不能改成 `.redirect`

那个 CDN（`pkg-ant.baidu.com`，实际由 `antpcdn.com` 回源）**对 HEAD 返回 405
Method Not Allowed**。`VendorInstallSpec.URLSource.redirect` 是唯一会自己发请求的
install 源，它发的正是 HEAD —— 换成 `.redirect` 会直接解析不出 URL。
GET 正常（Range GET 返回 206，`Accept-Ranges: bytes`，断点续传可用）。

### checksum

厂商不发 SHA-512，只有 CDN 的 MD5-形状 ETag，而 `checksumPattern` 吃的是 base64 SHA-512。
故 `checksumPattern: nil`，靠签名闸兜底。

## 已知问题

- **只涨 build 的重出包检测不到**（见上，漏报方向）。
- **hostRequirement 留空**：本 recipe 钉的是 arm64 端点，与 registry 全局做法一致。
  厂商同时发 x64 / universal，所以如果将来真的出现 Intel 宿主，正确做法是加一条
  universal 的 variant recipe，而不是加架构闸把检测也一起关掉。按 `App/project.yml`
  (`ARCHS: arm64`) DuoUpdater 本身就没有 Intel 宿主，今天两种写法等价。
- **端点是网页 CMS，不是发布系统。** `do=client` 服务的是官网下载页，理论上百度改版
  官网就可能改这个接口。真挂了是响亮失败（pattern 不匹配 → unknown），不是静默错答。

## 建议下一步

- 让 `duo verify` 的夜扫覆盖它（已随 registry 自动纳入），基线里记一次 `8.7.9`。
- `/disk/cmsdata?platform=<tab>` 对 `guanjia`(Windows) / `linux` / `android` 等 tab
  同样有效，将来若接入别的百度客户端可以直接复用这套 pattern。
