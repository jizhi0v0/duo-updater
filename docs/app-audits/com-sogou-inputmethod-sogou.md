# 搜狗输入法 (SogouInput)

> 审计于 2026-08-28。搜狗的输入法，官网 `shurufa.sogou.com` / `pinyin.sogou.com` 下载。
> 结论：**接入检测（VendorProbe，读官网更新日志）；自更新候选接口与 payload 已确认，
> 但一键安装仍需专用适配，不能交给通用整包替换。**

## 头条：自更新接口不是“latest API”，但它没有坏

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

这里的 `1.0.0.1` 是**无可用更新时的哨兵**，不是服务端所认为的最新版本。用相同端点、相同
渠道 `r=1111`，只把 `v` 模拟为较旧的 `6.23.0.0`，服务端立即返回：

```ini
[product0]
version=6.24.1.11676
update_pack_url=http://pro.cdn.ime.sogou.com/autosetup6.24.1.11676_V10003_20260715_223833.zip
update_pack_md5=654bd06d7df44e2237e0c61fab08477b
update_notice=0
```

该请求不需要设备 hash（省略 `h` 仍返回相同结果），HTTPS 也可用。下载后实测大小
`135226164` bytes，MD5 与响应完全一致。因此它的语义是“**给定当前客户端版本，返回候选更新**”，
而不是“无上下文地告诉我最新版本”。对已经是最新的客户端返回旧哨兵，正好让客户端保持不更新。

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
「看着像最新」其实是 DuoUpdater **从来没检查过**；搜狗自己的条件更新检查是另一条独立路径。

## 三个厂商端点及其职责

`SogouServices` 二进制里有三个，全部实测过：

| 端点 | 实测响应 | 结论 |
|------|----------|------|
| `macime.sogou.com/macversion.txt?h&v&r&sv&s` | 当前版本 → `1.0.0.1`；旧版本 → `6.24.1.11676` + `update_pack_url` + MD5 | 自更新候选接口，可用于动态取包；不是无上下文 latest API |
| `macime.sogou.com/macversionOfficial.php?h&v&r&os` | 当前版本 → `{"stat":"0"}` | 官网安装器的条件更新接口；裸请求里的 6.16 是缺省，不是当前发布 |
| `macime.sogou.com/sgupdate.php` | `{"version":999,...}` | 组件（增量资源）通道，不是 app 版本 |

> **判据修正记录**：第一次只重放了“已安装 = 最新版”的请求，把 `1.0.0.1` 错判为坏接口；
> 补测旧版本后才确认它是候选更新接口。`macversionOfficial.php` 裸请求里的 6.16 同样只是缺省。
> **条件更新端点必须至少验证一次 old → new，不能只看 latest → sentinel。**

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

- 状态: **暂不做**；已经拿到厂商自更新 payload，但需要搜狗专用适配，不能复用通用整包替换。

它的 `install.sh` 在**已安装**分支上确实是 Contents 轮换（第三家同形）：

```sh
if [ -d "$SOGOU_INPUT_APP_PATH" ]; then
    chmod 755 "$SOGOU_INPUT_APP_PATH"
    mv "$CUR_DIR/SogouInput.app/Contents" "$SOGOU_INPUT_APP_PATH/"   # 保留外层 .app
else
    mv "$CUR_DIR/SogouInput.app" "$SYSTEM_INPUTMETHOD_DIR"           # 首装才换整个
fi
```

完整官网安装器还会往 bundle 外面装四样东西：

- `/Library/LaunchAgents/com.sogou.SogouServices.plist`（`launchctl bootout` → `bootstrap` → `kickstart`）
- `/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`（同上）
- 用户级 LaunchAgent（`~/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`）
- `/Library/QuickLook/SogouSkinFileQuickLook.qlgenerator`（+ `qlmanage -r`）

完整安装器还包含**用户目录迁移**、进程重启以及权限处理。现有通用安装 recipe 不能安全重放这些动作。

另一方面，真正的自更新包已经确认是另一种、更窄的形状：

```text
autosetup6.24.1.11676_....zip
├── Contents6.24.1.11676.zip   # 解开后是新的 Contents
├── pre.sh
├── post.sh
└── switch.sh
```

- 内层目录权限为 `0775`，版本为 `6.24.1.11676`；
- `pre.sh` 会把外层 app 修成 `root:staff` / `0775`；
- `switch.sh` 带有旧用户目录的删除/迁移分支，不能由通用 updater 盲目执行；
- 内层 `Info.plist` **没有**安装副本中的 `SGQuDao=1111`；尚未确认厂商流程会重新注入渠道，还是
  有意回落到默认渠道。可以确定的是，直接把内层目录改名成 `Contents` 会丢这个值。

所以未来的一键路径应当是专用的“候选接口 → 校验 MD5 → 解双层 ZIP → 保留渠道和权限 → 原子切换
Contents”，并为迁移脚本建立明确版本门控；不是把官网安装器或自更新 ZIP 当普通 `.app` 覆盖。

## 验证记录（2026-08-28）

| 检查 | 命令 | 结果 |
|------|------|------|
| 单元测试 | `swift test --filter SogouInputTests` | 6/6 ✓ |
| 全量 | `make test` | Core 1347 / CLI 161 全绿 |
| 活体端点 | `duo verify --only sogou` | vendor probe ✓ 1 / ✗ 0 |
| 正则独立复算 | Python 打真实页面（101 条切片 / 96 条带版本） | 最高版本条目 = `6.24.1` / `2026-07-17` |
| 端到端 | `duo check --all --json SogouInput` | `installedVersion 6.24.1` / `installedBuild 11676` / `latestVersion 6.24.1` / `up-to-date` |
| 抓包 | Surge `dump recent`，`launchctl kickstart` 触发 | 确认真实请求形状；当前版本返回无更新哨兵 |
| 候选接口 old → new | `v=6.23.0.0&r=1111&sv=27.0&s=0`（省略设备 hash） | 返回 `6.24.1.11676`、payload URL 和 MD5 |
| payload | 下载 + MD5 + 双层 ZIP 静态检查 | `654bd...77b` ✓；内层为 `Contents6.24.1.11676/`，0775 |

已完成服务端 old → new 的红侧模拟，但没有在本机执行 payload 或进行真实版本降级；安装安全仍保持
未验证。下一次搜狗发版时应补一次真实旧副本的端到端更新。

## 建议下一步

1. 搜狗发 6.25 时补一次真机红→绿，并保存新 payload 的脚本与目录差异。
2. 盯 `for` 前那个空格。判据是：全页拼音条目前面是否仍**全部**为空白字符。
   真变了，五笔可能被选中——但五笔在 1.x，量级兜底还在，所以是"响一次"而不是"错一片"。
3. 盯页面是否改回四段版本号。判据是夜扫出现 `remote is BEHIND the installed copy`。
4. 若实现专用安装源，动态请求 `macversion.txt`；不要把它当静态 latest probe，也不要记录设备 hash。
5. 一键前补齐 `SGQuDao` 保留、脚本版本门控、回滚和登录/词库回归测试。
