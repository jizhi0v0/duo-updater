# 搜狗输入法 (SogouInput)

> 审计于 2026-08-28。搜狗的输入法，官网 `shurufa.sogou.com` / `pinyin.sogou.com` 下载。
> 结论：**接入检测（VendorProbe，读官网更新日志）；一键不做，而且这次不是policy 保守，是厂商的更新确实不止拷贝**。

## 头条：**它自己的更新检查是坏的**

从运行中的 `SogouServices` 抓到的真实请求（Surge，2026-08-28）：

```
GET http://macime.sogou.com/macversion.txt?h=<md5>&v=6.24.1.11676&r=1111&sv=27.0&s=0
User-Agent: SogouServices (unknown version) CFNetwork/3896.100.1.1.1 Darwin/27.0.0

→ 200
[product0]
version=1.0.0.1
url=http://pinyin.sogou.com/mac/
pkg_url=http://pro.cdn2.ime.sogou.com/SogouInput_V1.0.0.1.ins
```

**带着真实设备 hash、真实在装版本原样重放，服务端答的还是 `1.0.0.1`** ——低于任何真实构建，
所以客户端每次都认为自己是最新的。**搜狗输入法 Mac 版目前根本不会自更新。**

这不是"我们多此一举"，恰恰相反：这个 app 的用户今天拿不到任何更新提示。

## 基本信息
- Bundle ID: `com.sogou.inputmethod.sogou`
- Team ID: `DFD88F82SU`（Developer ID Application: Beijing Sogou Technology Development Co.,Ltd.）
- 已安装: `6.24.1.11676`（`CFBundleShortVersionString`，**四段**）/ build `11676`（`CFBundleVersion`）
- 安装路径: `/Library/Input Methods/SogouInput.app`（`root:staff` 775，与 WeType / 豆包同形）
- 无 `SUFeedURL`、无 MAS receipt、无 Homebrew cask
- 装机附带：`/Library/LaunchAgents/com.sogou.Sogou{Services,TaskManager}.plist`、
  `/Library/QuickLook/SogouSkinFileQuickLook.qlgenerator`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓ ★         |

**接入前的状态**：`AppScanner` 扫 `/Library/Input Methods`，所以 `duo list` 能看到
`SogouInput 6.24.1.11676`，但优先链里没有源应答 → 常驻 `unknown`。和豆包接入前一样，
「看着像最新」其实是**从来没检查过**——只是这次连它自己也没在检查。

## 三个厂商端点，为什么都不能用

`SogouServices` 二进制里有三个，全部实测过：

| 端点 | 实测响应 | 为什么不能用 |
|------|----------|--------------|
| `macime.sogou.com/macversion.txt?h&v&r&sv&s` | `version=1.0.0.1` | 客户端真正读的那个，永远答占位版本 |
| `macime.sogou.com/macversionOfficial.php?h&v&r&os` | 给全四个参数一律 `{"stat":"0"}` | 裸请求时报的 `6.16.0.9770` 是**默认值**，不是当前发布；带参数就是"没更新" |
| `macime.sogou.com/sgupdate.php` | `{"version":999,...}` | 组件（增量资源）通道，不是 app 版本 |

> **判据修正记录**：初次只做裸请求，看到 `macversionOfficial.php` 报 6.16.0.9770，
> 判成"滞后 8 个小版本的镜像"。补齐真实四参数后才知道它对**任何**版本都答 `stat:0`——
> 那个 6.16 是缺省，不是它对"当前版本是什么"的回答。**用一个残缺请求的响应去给端点定性是错的。**

`pinyin.sogou.com/mac/` 也没有 changelog：`changelog.php` / `update.php` / `history.php` 全 404。

## 更新检测：读官网更新日志

- 源: `VendorProbe`（`mode: .responseBody`）
- 端点: `https://pinyin.sogou.com/mac/update_log.php`（页面自称 `charset=gbk`）
- 真实结构：

```html
<span class="post_type">搜狗输入法 for Mac 6.24.1</span>
<span class="post_time">2026-07-17</span>
```

`6.24.1` / `2026-07-17` 与在装副本**完全对上**，连 bundle 自己的构建日期都是 7-17。

- `versionPattern`: `\sfor Mac ([0-9]+(?:\.[0-9]+){1,2})</span>`
- `publishedAtPattern`: `post_time">([0-9]{4}-[0-9]{2}-[0-9]{2})`
- `entryStartPattern`: `<span class="post_type">`

### ⚠️ `for` 前面那个空格是承重的

**同一个页面上还有搜狗五笔**：`搜狗五笔输入法for Mac 1.4.0` ——产品名直接顶着 `for`，没有空格；
而每一条拼音都是 `搜狗输入法 for Mac 6.24.1`，有空格。全页 96 条带版本的条目实测：
拼音（major 1 到 6 都有）前面一律是空格，五笔前面是汉字。

这个判据能用，是因为它**纯 ASCII**：页面是 GBK，而 probe 按 UTF-8 解码，汉字会变成
替换字符（不是空白），所以 `\s` 依然排得掉五笔；反过来，想直接锚"五笔"两个字是做不到的。

**五笔只有 1.x、比不过 6.x，那是兜底不是理由。**今天赢不了的量级不构成规则，
所以规则写成空格，并由 `theWuBiFamilyOnTheSamePageIsNeverSelected` 钉住。

### 为什么用 `entryStartPattern` 而不是相信文档顺序

页面今天是新→旧，first-match 和 highest-version 结论一致。但版本和日期本来是**两次独立的
first-match**，而这份文档里混着两个产品线。切片之后，两者按构造来自同一条发布。

### ⚠️ 版本方案：页面三段，bundle 四段

| | 值 |
|---|---|
| 页面（厂商发布的） | `6.24.1` |
| bundle `CFBundleShortVersionString` | `6.24.1.11676` ← **多一段** |
| bundle `CFBundleVersion` | `11676` |

`VersionComparator` 把缺失段当 `0`，所以 `6.24.1` **输给** `6.24.1.11676` ——
不处理的话，行上永远是"remote 比在装的还旧"。

处理方式是**在本地侧裁到三段**（`AppScanner.firstThreeSegments`，只对全数字、超过三段的版本生效），
不是在 recipe 里补第四段。理由：三段是**两边都能说**的形式，也是厂商公开发布的形式，
行上显示 `6.24.1` 正好和更新日志一致；第四段是 build，仍然留在 `buildVersion` 里，没有丢。

**盲区（如实记）**：只改第四段的重发看不见。这是"漏"，不是"幻影"。

**换形状时的失败方向**：
- 厂商改成三段 → 裁剪变成 no-op，仍然正确；
- 改成两段（`6.25`）→ 比较器缺失段补 0，`6.25` 与 `6.25.0` 相等，仍然正确；
- **改回四段**（2018 年以前就是四段，页面上还留着 `2.0.0.26481` / `1.5.1.21442`）→
  `{1,2}` 让最新条目不再匹配，选择退回更旧的三段条目 → 下一次发布时夜扫报
  `remote is BEHIND the installed copy`。**响，而不是静默给个陈旧答案。**

## 下载文件名不是版本（实测排除）

考虑过直接用官网下载链接的 token（`sogou_mac_624d_new_guanwang.zip`）当版本源。
逐个探测（`curl -r 0-15` 看 zip magic，避免被 catch-all 200 骗；实测该 CDN 对乱名确实 404）：

| 线 | 真实存在的文件 | 更新日志里的发布 |
|----|----------------|------------------|
| 6.24 | `624a` `624b` `624c` `624d` | 6.24.0、6.24.1 |
| 6.23 | `623a` | 6.23.0 |
| 6.22 | `622a` | 6.22.0 |

**四个文件对两条公告**，而且 `624a…624d` 分不出 6.24.0 和 6.24.1。所以那个 token 是**构建重发计数**，
不是版本；也无法向前预测（新 minor 大概率是 `a`，但 6.24 证明了同一线内会有不带公告的重发）。
更新日志严格更好。

顺带一条：`624b/c/d` 这类**没有公告的重发**，正好就是上面"只改第四段看不见"的那个盲区的实物。

## 一键安装

- 状态: **不做**，而且理由与 WeType / 豆包不同——不是保守，是它的更新确实不止拷贝。

它的 `install.sh` 在**已安装**分支上确实是 Contents 轮换（第三家同形）：

```sh
if [ -d "$SOGOU_INPUT_APP_PATH" ]; then
    chmod 755 "$SOGOU_INPUT_APP_PATH"
    mv "$CUR_DIR/SogouInput.app/Contents" "$SOGOU_INPUT_APP_PATH/"   # 保留外层 .app
else
    mv "$CUR_DIR/SogouInput.app" "$SYSTEM_INPUTMETHOD_DIR"           # 首装才换整个
fi
```

**但它同时往 bundle 外面装四样东西**，轮换会把它们全留在旧版本：

- `/Library/LaunchAgents/com.sogou.SogouServices.plist`（`launchctl bootout` → `bootstrap` → `kickstart`）
- `/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`（同上）
- 用户级 LaunchAgent（`~/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`）
- `/Library/QuickLook/SogouSkinFileQuickLook.qlgenerator`（+ `qlmanage -r`）

外加**用户目录迁移**（`~/Library/Input Methods/Sogou` → `~/Library/Application Support/Sogou/InputMethod`，
按 `$1` 分支）、十来个 `killall`、以及 `chmod -R 777 "$SOGOU_INPUT_APP_PATH/Contents/Resources"`。

这才是 2026-08 撤回时担心的那种「安装器不止拷贝」——WeType 和豆包查下来不是，这个是。

产物形状本身和豆包一样（安装器壳 `com.sogou.SogouInstaller` → `Contents/Resources/SogouInput.zip`
→ `SogouInput.app`），真要做一键，`nestedArchivePath` 那一层是现成的；缺的是上面那四样和迁移。

## 验证记录（2026-08-28）

| 检查 | 命令 | 结果 |
|------|------|------|
| 单元测试 | `swift test --filter SogouInputTests` | 6/6 ✓ |
| 全量 | `make test` | Core 1347 / CLI 161 全绿 |
| 活体端点 | `duo verify --only sogou` | vendor probe ✓ 1 / ✗ 0 |
| 正则独立复算 | Python 打真实页面（101 条切片 / 96 条带版本） | 最高版本条目 = `6.24.1` / `2026-07-17` |
| 端到端 | `duo check --all --json SogouInput` | `installedVersion 6.24.1` / `installedBuild 11676` / `latestVersion 6.24.1` / `up-to-date` |
| 抓包 | Surge `dump recent`，`launchctl kickstart` 触发 | 见头条 |

**没有红→绿实测**：装的就是最新版，且厂商历史 payload 的 URL 无法从版本前推
（letter 不可预测），所以造不出像 WeType 那样的真实红。下一次搜狗发版时应当补上。

## 建议下一步

1. 搜狗发 6.25 时补一次真机红→绿，把上面那条空缺补掉。
2. 盯 `for` 前那个空格。判据是：全页拼音条目前面是否仍**全部**为空白字符。
   真变了，五笔可能被选中——但五笔在 1.x，量级兜底还在，所以是"响一次"而不是"错一片"。
3. 盯页面是否改回四段版本号。判据是夜扫出现 `remote is BEHIND the installed copy`。
4. 如果哪天 `macversion.txt` 开始返回真实版本，说明厂商修好了自更新——那时可以考虑
   把版本源换到端点（更稳），并重新评估一键。
