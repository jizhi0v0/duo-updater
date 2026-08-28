# 搜狗输入法 (SogouInput)

> 审计于 2026-08-28。搜狗的输入法，官网 `shurufa.sogou.com` / `pinyin.sogou.com` 下载。
> 结论：**接入检测，版本读厂商自己的更新接口**（不是官网更新日志）；payload 已确认，
> 但一键安装仍需专用适配，不能交给通用整包替换。

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

## 更新检测：读厂商自己的更新接口

- 源: `VendorProbe`（`mode: .responseBody`）
- 端点: `https://macime.sogou.com/macversion.txt?v=0.0.0.1&sv=27.0&s=0`
- `versionPattern`: `\nversion=([0-9]+(?:\.[0-9]+)+)[\s\S]*?\nupdate_pack_url=`
- 无 `publishedAtPattern`（接口不带日期）；notes 仍指向更新日志页

**做法就是"装成一个很旧的客户端去问"。** 接口是条件式的，pin `v=0.0.0.1`——比厂商能发的任何
版本都旧，所以这个请求永远落在"有更新"那一支，不会随着发版漂进哨兵分支。

**它不做分段升级**（这是 pin 旧版本能代表"最新"的前提，必须验）。实测 `6.23.0.0`、
`6.16.1.0`、`2.0.0.26481`、`1.5.1.21442`、`1.0.0.2`、`0.0.0.1` 六个值，答案**全部**是
同一个最新版 `6.24.1.11676`，没有中间跳板；`>=` 最新版（`6.24.1.11677`、`9.9.9.9`）则一律哨兵。

### ⚠️ 版本就是 bundle 自己那一串——四段全中

| | 值 |
|---|---|
| 接口 | `6.24.1.11676` |
| bundle `CFBundleShortVersionString` | `6.24.1.11676` ← **完全一致** |

**这就是它比更新日志页强的地方**：日志页只发三段（`6.24.1`），要比就得把装机侧裁到三段，
而裁完之后"只改第四段的重发"就永远看不见了。走接口不需要任何推导、任何裁剪，
命名空间天然对齐，重发也照样能发现。

> 早先那版 recipe 读的是更新日志页，并为此在 `AppScanner` 里加了 `firstThreeSegments` 裁剪。
> 改到接口之后那段裁剪**已经删掉**——不是留着不用，是根本不需要了。

### 参数：哪些是必需的（逐个实测，不是照抄抓包）

| 参数 | 结论 |
|------|------|
| `sv` | **唯一真正必需的**。缺了就是哨兵。**而且它做 OS 门控**，见下 |
| `v` | 可省（缺失/乱填都按"很旧"处理），但**显式 pin**：把意图写出来，不靠默认行为。`v=6.24.1.11676` 会得到哨兵，说明它确实被解析 |
| `s` | 可省（`s=`、`s=abc` 都能过），但**显式写 0**：它按整数解析，`s=1`/`2`/`3`/`-1` 一律走到哨兵分支 |
| `r` | **可省**。不带 `r`、`r=1111`、`r=9999` 答案一致，服务端忽略它。不发——那是某台机器安装副本的渠道码，代表不了别人 |
| `h` | **不发**。不需要它也能拿到答案，而我们的 probe 没有理由把一个每机唯一的标识送给厂商 |
| `cpu` / `r0` | 二进制里另有两套模板带这两个参数，`cpu` 是架构选择器。**今天是惰性的**（`arm64` / `x86_64` / `intel` 答案一致），但厂商哪天真拆架构，就是它决定我们被告知哪一个 |

HTTPS 可用（抓包里客户端走的是 http）。同一 URL 连打五次**版本**稳定
（`update_pack_url` 的主机在 `pro.cdn` / `pro.cdn2` 之间轮询，body 本身不是逐字节稳定的）。

### ⚠️⚠️ `sv` 是做 OS 门控的——第一版审计在这里判错了

初版写"`sv` 不门控"，依据是 `10.14` / `13.0` / `15.0` / `26.0` / `27.0` 答案一致。
**那五个值全落在同一个桶里。** 细扫之后是三个桶：

| `sv` | 返回 |
|------|------|
| `< 10.10` | 哨兵 |
| `10.10` – `10.13` | **`6.14.1.9298`**（2023-06 的包，冻了三年） |
| `10.14` – `27.6` | `6.24.1.11676` ← 当前 |
| `27.61` 及以上 | **`6.14.1.9298`**，又回到旧包 |

边界卡在 `27.6` 与 `27.61` 之间。**这条对厂商自己的用户有直接后果**：macOS 28 上的搜狗客户端
会带 `sv=28.x` 去问，拿回一个低于自己安装版本的 2023 年包，然后安静地不再更新。

对我们：pin 成常量恰恰是对的——**不管宿主什么系统，我们都拿当前桶的答案**；
真去发宿主的真实 OS，反而会在 macOS 28 的机器上把检测搞坏。

**代价是这条 recipe 唯一的静默失效面**：如果搜狗把 `10.14–27.6` 这个桶再拆开、只往上面发新包，
我们 pin 的请求会一直答 `6.24.1.11676`，而且不报错。
多数边界移动是**响**的（pin 掉进旧桶 → 报 `6.14.1.9298` → 低于所有安装版 →
夜扫 `remote is BEHIND the installed copy`）。静默那一种的判据是**更新日志页**：
下次发版它会前进，这里也必须跟着前进。

### 哨兵不能被读成版本

响应两种形态的差别只在**有没有 `update_pack_url`**——`version=` 这一行两边都有。
所以 pattern 要求 `update_pack_url` 出现在 version **之后**，哨兵响应直接匹配不上（实测 0 命中）。

没有这道守卫的话，哨兵会被报成 `1.0.0.1`，那读起来是"所有人都该降级"——夜扫会响，
但**明确拒绝**好过"响一声然后报一个我们明知不是版本的数"。

## 更新日志页：现在只当 notes 源

`https://pinyin.sogou.com/mac/update_log.php`（`charset=gbk`）仍然是 `changelogURL`，
因为 notes 只存在于这里，而且它和接口**互相印证**：页面最新条目 `搜狗输入法 for Mac 6.24.1` /
`2026-07-17`，与接口的 `6.24.1.11676` 以及 bundle 自己的构建日期都对得上。

真要拿它当版本源（现在不是了），有两个坑，记在这里免得下次重新踩：

- **同页混着另外两个产品线**（初版审计只数出一个，而且条目数也数错了）。实测 **101** 条
  `post_type` 条目，全部带版本号，按产品名分：`搜狗输入法 for Mac` ×94、
  **`搜狗输入法 for Mac touchbar` ×3**、`搜狗五笔输入法for Mac` ×4。
  - 五笔的 `for` 前面**没有空格**，拼音一律有（97 有 / 4 无），所以空格判据对五笔成立，
    而且它**纯 ASCII**：页面 GBK 而 probe 按 UTF-8 解，汉字变替换字符，锚"五笔"两个字做不到。
  - **touchbar 那三条不是被空格排除的**，是碰巧——它们的版本号写在 `touchbar` 这个词后面
    （`touchbar3.0`），恰好不匹配。**碰巧排除掉的东西不算被规则挡住。**
  - 五笔在 1.x 比不过 6.x 同样只是兜底，不是理由。
- **只发三段**，见上。

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
- `/Library/QuickLook/SogouSkinFileQuickLook.qlgenerator`（+ `qlmanage -r` + `qlmanage -r cache`）

> **更正**：初版写"还装一个用户级 LaunchAgent"。**方向反了**——两份脚本对
> `~/Library/LaunchAgents/com.sogou.SogouTaskManager.plist` 只做 `bootout` + `rm -rf`，
> payload 里也只有那两个 `/Library/LaunchAgents` plist；装好搜狗的机器上那个用户级文件
> 根本不存在。是运行时才创建的。这条错在"让 detection-only 的理由听起来比证据更强"的方向上。

另外两条初版**说轻了**的：那个 Contents 轮换是 `rm -rf` 之后再 `mv`，**不是原子交换**；
脚本结尾是 `killall -9 SogouInput` + `killall -KILL SystemUIServer`——
**强杀，这个 app 对谁都不做的事**。两条都让 detection-only 更站得住。

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
| 正则独立复算 | Python 打两种真实响应 | 有更新 → `6.24.1.11676`（命中 1 次）；哨兵 → **不匹配** |
| 端到端 | `duo check --all --json SogouInput` | `installedVersion 6.24.1.11676` / `latestVersion 6.24.1.11676` / `up-to-date` |
| 条件接口 old → new | `v` 取 6 个历史值，从 `6.23.0.0` 到 `0.0.0.1` | 全部返回同一个 `6.24.1.11676`，**无分段升级** |
| 条件接口 >= latest | `v=6.24.1.11677`、`v=9.9.9.9` | 一律哨兵 `1.0.0.1` |
| 参数必需性 | 逐参数删/改 | **只有 `sv` 必需**；`v`/`s`/`r`/`h` 皆可省，`s∈{1,2,3,-1}` → 哨兵 |
| `sv` OS 门控 | 细扫 `10.9`→`30.0`，边界二分 | **三个桶**；`10.14–27.6` 是当前，`27.61+` 回落到 2023 年的包 |
| 跨块配对 | 哨兵块 + 更新块拼接、异产品块在前 | 均返回 `6.24.1.11676`（未加守卫时会返回 `1.0.0.1` / `9.9.9.9`）|
| fixture 逐字节 | 与活体响应比对 | 188 / 252 bytes，**逐字节一致**（含混用的 LF/CRLF）|
| 稳定性 | 同 URL 连打 5 次 | 5 次一致 |
| payload | 下载 + MD5 + 双层 ZIP 静态检查 | `654bd...77b` ✓；内层为 `Contents6.24.1.11676/`，0775 |

**没有红→绿实测**：装的就是最新版。不过这次红侧不是空白——服务端 old → new 已经验过，
`v` 取六个历史值都拿到真实新版本和 payload URL。缺的是"在本机把旧副本真的更上来"，
下次搜狗发版时补。

## 建议下一步

1. 搜狗发 6.25 时补一次真机红→绿，并保存新 payload 的脚本与目录差异。
2. 盯厂商是否改哨兵语义。判据：`v=0.0.0.1` 那个请求什么时候开始不返回 `update_pack_url`——
   pattern 会直接不匹配 → probe 报 "resolved no version" → 夜扫响。**这是设计成响的那一侧。**
3. 盯 `s` / `sv` 的必需性是否变化。它们不是抓包里抄来的装饰，是让接口开口的必要条件；
   哪天多一个必填参数，症状同样是不匹配 → 响。
4. 若实现专用安装源，直接复用这个接口拿 `update_pack_url` + `update_pack_md5`（**动态**请求，
   带真实版本号；不要把 pin 了 `v=0.0.0.1` 的探测 URL 拿去下包），并且仍然不要发设备 hash。
5. 一键前补齐 `SGQuDao` 保留、脚本版本门控、回滚和登录/词库回归测试。
