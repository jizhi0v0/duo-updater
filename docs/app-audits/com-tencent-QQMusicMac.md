# QQ音乐 (QQMusic Mac)

审计 2026-08-29。

## 基本信息

- Bundle ID: `com.tencent.QQMusicMac`
- App 名: `QQMusic.app`
- URL scheme: `qqmusicmac`
- 官网下载页: https://y.qq.com/download/index.html
- 观测版本: `CFBundleShortVersionString` = `11.8.1`，`CFBundleVersion` = `73276`
- `LSMinimumSystemVersion` = `10.11`
- Team ID: `FN2V63AD2J` — Tencent Technology (Shanghai) Company Limited；
  `spctl -a -t install` 判定 "Notarized Developer ID"
- 架构: `lipo -archs` = `x86_64 arm64`（universal）
- 壳: 原生 AppKit + Swift（`Contents/Frameworks/` 是 `TekEngineLib.framework`、
  `libpag.framework`、`SVGKit`、`Masonry`、`libMNN.dylib` 加一整套
  `libswift*.dylib`）。**不是 Electron，也没有 Sparkle。**
- 体积: 194 MB（安装后）；dmg 97 MB

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Changelog |
|---|---|---|---|---|---|---|
| **stable** | ✗ | ✗ | — | — | ✓ 一键 | ✓ 原生结构化 |

当前生效源：**VendorProbe**。其余四条源为什么都不答：

- **Sparkle** — bundle 里没有 `SUFeedURL`，`Contents/Frameworks` 里也没有
  `Sparkle.framework`。`SparkleAppcastSource` 不会有任何入口。
- **Homebrew** — cask `qqmusic` 存在，但标了 `auto_updates`，按仓库既有决策
  （`duo-updater-brew-autoupdates`）不当作 brew 源。
- **MAS** — 非 MAS 分发，`Contents/_MASReceipt` 不存在。中国区 App Store 里的
  「QQ音乐」是 iOS app，不是这一份。
- **GitHub** — 无公开发布仓库。

## 更新检测

### 厂商自己的更新通道 —— 用不了

主二进制里的更新端点是 `https://c.y.qq.com/fcgi-bin/fcg_unite_update`
（`UpdateHostToIP` + `c.y.qq.com` 拼出来的）。**GET 和 POST 都返回 200 + 0 字节**
（2026-08-29 实测），它要哪些参数在二进制里拼不出来。**没有采纳** —— 一个恒空的
响应和"端点坏了"无法区分。

### 采纳的端点：官网下载页背后的数据文件

```
https://y.qq.com/download/download.js
```

`y.qq.com/download/index.html` 是 JS 壳：**发下来的 HTML 里没有任何版本号、也没有
任何更新说明文字**（实测 grep 不到 `AI声景疗愈`），版本和说明都是页面在客户端从
`download.js` 取的。

响应是 `application/x-javascript`，约 9.6 KB，JSONP 包裹：

```
MusicJsonCallback({"data":[ …每个平台一个对象… ]})
```

**匿名可取**：不需要 cookie、不需要 Referer，`VendorProbeSource` 默认 UA 直接 200。

#### query 参数全部无效

用户给的链接带一长串参数（`cv` / `ct` / `format` / `inCharset` / `platform` /
`needNewCode` / `g_tk` / `g_tk_new_20200303` / `jsonpCallback` …）。2026-08-29 实测：
**裸路径、站点原样的完整 query、以及只留 `format=json&platform=yqq.json` 的最小
query，三者返回的 body 逐字节相同**，`Last-Modified` 和
`Cache-Control: max-age=600` 也相同；回调名恒为 `MusicJsonCallback`，与
`jsonpCallback=` 传什么无关。CDN（`Server: nws_static_mid`）显然忽略整个 query。

所以 registry 里登记的是**裸路径**：能坏的 token 更少，答案一样。

#### 表里有两条 Mac 记录（关键陷阱）

`Ftype == 2` / `Ftitle == "Mac"` 的对象有**两个**：

| ID | Fversion | Flink1 | 说明 |
|---|---|---|---|
| 2 | `最新版:11.8.1` | `…QQMusicMac11.8.1Build01.dmg&sign=…` | 在售客户端 |
| 15 | `最新版:7.0.0` | `…/mac/QQMusicMac_Mgr.dmg` | 2020-05-19 的遗留记录 |

只按 `Ftitle` / `Ftype` 锚定会命中哪个纯看顺序。两条规则因此都锚在
**带版本号的 Mac dmg 文件名** `QQMusicMac<ver>Build<nn>.dmg` 上：遗留记录的链接是
`QQMusicMac_Mgr.dmg`，没有版本段，`QQMusicMac[0-9]` 结构性地排除它 —— 而不是锚一个
`"ID":2` 字面量（表一改号就漂）。

Windows / Android / iOS 的链接文件名词干不同（`QQMusic_Setup_*.exe`、
`QQMusic*.apk`、`QQMusicIPhone*.ipa`），同样被排除。

#### 版本粒度：只有 marketing，没有 build

文件名里的 `Build01` 是该 marketing 版本的**重切序号**，不是 app 的
`CFBundleVersion`（装好的 11.8.1 报 `73276`）。拿它当 build 比是**跨命名空间**，所以
recipe 保持 `versionIsBuild: false`：

- 同 marketing 重切（11.8.1 Build01 → Build02）在这里**看不见**；
- 但绝不会凭空报更新 —— marketing 打平 + 远端无 build ⇒ `VersionComparator`
  答 "not newer"。

腾讯确实会动 marketing 版本（同一份 body 里 Windows 是 22.5.2、iPhone 是 20.7.5），
所以这是**粒度上限，不是失效判据**。

#### 发布日期没有采纳

日期写在 `Fdesc` 结尾：`发布时间：2026-08-03` —— 裸日历日，无时间无时区，
`ReleaseDate` 解析不了，写 `publishedAtPattern` 会是个静默 no-op。
它还是个 first-match 陷阱：Windows 对象排在 Mac 前面，不锚定的日期正则会把
Windows 的日期盖到 Mac 的发布上。

changelog 那边按**原样字符串**显示这个日期（display-only），这才是裸日历日该待的地方。

## 一键安装

`Flink1` 是 `c.y.qq.com/cgi-bin/file_redirect.fcg?bid=dldir&file=<路径>&sign=<token>`，
302 到 `dldir.y.qq.com/…/QQMusicMac11.8.1Build01.dmg?sign=<另一个 token>`。
body 里那个 `sign` 是**跳转器自己的 token**，最终下载链接上的 `sign` 由跳转在请求时
现签 —— 所以 install spec 用 `.bodyPattern` 抓整条 `file_redirect.fcg` URL（含
`&sign=`，截到 `.dmg` 就会拿到一条 CDN 拒绝的链接），apply 时从实时 body 现读。

2026-08-29 实拉验证（97 MB）：

- 镜像里**只有 `QQMusic.app`，没有别的** —— 没有 pkg、没有 daemon，本机
  `/Library/LaunchDaemons`、`/Library/LaunchAgents`、`~/Library/LaunchAgents`、
  `/Library/PrivilegedHelperTools` 也都没有腾讯音乐的条目。这就是 `kind: .dmg`
  （只换 bundle）正确、不需要 `.pkg` 的依据。
- Bundle ID `com.tencent.QQMusicMac`，`CFBundleShortVersionString` 11.8.1 /
  `CFBundleVersion` 73276（与已装副本完全一致）
- Team `FN2V63AD2J`（= 已装副本的 Team，`VendorInstaller` 的签名闸就是卡这个）
- `spctl -a -t install` → "Notarized Developer ID"
- `lipo -archs` → `x86_64 arm64`

厂商不发 SHA-512，所以 `checksumPattern` 为空。

## 更新说明（changelog）

**腾讯没有任何人能读的发布说明页**：没有 blog、没有 appcast、没有 per-version 页；
下载页本身是 JS 壳（见上）。说明只作为 Mac 对象的 `Fdesc` 字符串存在于同一份
`download.js` 里 —— 所以 changelog recipe 读的是**同一个端点**。

`Fdesc` 原样（2026-08-29）：

```
「AI声景疗愈」新增AI声景疗愈模式，可在设置-疗愈模式开启\n|「AI伴听」新增AI伴听模式，在左侧自定义功能栏可开启\n|「其他」其他体验优化\n|\n\n|发布时间：2026-08-03
```

要点：

- 分隔符是 **JSON 转义的 `\n` 再跟一个 `|`**，正则路径上是 `\` `n` 两个字符，
  item pattern 必须写 `\\n`；
- 结尾 `\n|\n\n|发布时间：…` 那一串必须由 entry pattern 吃掉，否则会变成一条 bullet；
- item 主体是 `(?:[^\\]|\\(?!n))+?` 而不是 `[^\\]+?`：一条说明要能**穿过转义引号
  `\"`** 但仍在 `\n` 处停下。朴素的否定字符类分不清这两者 —— 它在每个反斜杠处都停，
  于是带引号的那条说明**被丢掉而不是被切开**（其它 bullet 匹配到了，
  `firstNonEmptyItemHits` 就满足了，没人会报错）。当前线上没有带引号的说明，
  回归测试是唯一的守卫。
- 只有一个 item pattern，没有惯例上的冗余兜底：`(?:^|\\n)` 能匹配 body 开头，
  所以将来 `Fdesc` 若完全不带分隔符，整串会作为一条说明出现，而不是什么都没有。
  第二条 pattern 在这里永远不会被用到。

`maxEntries: 1` —— 这份文件每个平台只登记**当前**一个版本，没有历史可翻。

`VendorProbeRecipe.changelogURL` 仍然指向 `y.qq.com/download/index.html`，只作为
recipe 万一失配时的人肉兜底（那个页面在真浏览器里跑 JS 后是能显示说明的）。

## 验证

```
$ duo verify --only qqmusic
  vendor probe  ✓ 1  ⚠ 0  ✗ 0  ~ 0  - 0
  changelog     ✓ 1  ⚠ 0  ✗ 0  ~ 0  - 0

$ duo check --json --all | grep qqmusic
{"bundleID":"com.tencent.QQMusicMac","hasUpdate":false,"installedBuild":"73276",
 "installedVersion":"11.8.1","latestVersion":"11.8.1","source":"Vendor",
 "status":"up-to-date"}
```

回归测试：`DuoUpdaterCore/Tests/DuoUpdaterCoreTests/QQMusicProbeRecipeTests.swift`
（14 例，fixture 保留 Windows / iPhone / 遗留 Mac 三个诱饵对象）。
