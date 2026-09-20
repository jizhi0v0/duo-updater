# 搜狗输入法 (SogouInput)

> 审计于 2026-08-28，一键于 2026-09-20 接入。搜狗的输入法，官网 `shurufa.sogou.com` / `pinyin.sogou.com` 下载。
> 结论：**检测读厂商自己的条件更新接口**（不是官网更新日志）；**一键走 Contents 轮换**，
> 包由 `ContentsPayload` 从双层 zip 里装配出来，厂商的三个脚本一个都不跑。
>
> **⚠️ 本文 2026-08-28 版的 detection-only 结论有一条理由是错的**，见「一键安装」一节的更正。

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
| **stable** | —       | —        | —   | —      | ✓ ★ 一键     |

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

> **数法**：一个「位置」= 一次捕获，支持目录是整个抓走的，所以
> `Application Support/Sogou` 下面那四个子目录算 **1** 条不是 4 条。
> 全量是 **7** 条（1 个支持目录 + 6 个 plist），快照实测也是 7 条。
> 本文早前有几处写成「8」，那是把子目录混进来数的，已统一成 7。

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

- 状态: **已接入**（2026-09-20）。源 `VendorProbe` 的 `install`，`kind: .zip`，
  `urlSource: .bodyPattern(\nupdate_pack_url=(https?://[^\s]+\.zip))`，
  `contentsArchivePattern: ^Contents[0-9.]+\.zip$`。
- 路线：`ContentsPayload` 从双层 zip 里装配出 `<装机名>.app` → 走 Gate 2–6 →
  `InPlaceSwap.rotateContents`（和 WeType / 豆包同一条轮换）。
- 厂商的 `pre.sh` / `post.sh` / `switch.sh` **一个都不跑**，逐条理由见下。

### ⚠️ 更正：2026-08-28 版「不做一键」的主要理由读错了对象

初版写「Contents 轮换会漏掉两个 LaunchAgent、QuickLook 注册和用户目录迁移」。
**那些是官网安装器做的事，自更新包里一样都没有。** 这两个包是不同的东西，
而一次普通发版走的是后者。把安装器的动作算到更新头上，等于给「不做」找了一条
它撑不住的理由——这就是本文头部那条警告指的错误。

2026-09-20 拿真包（6.25.1.11973，183,534,090 bytes，MD5 `a171cf3d5cb42ef1d33a701555d5051c`
与接口声明一致）逐个脚本读完：

| 脚本 | 真实内容 | 为什么不跑 |
|------|----------|------------|
| `pre.sh` | 仅当 `! -w "/Library/Input Methods/SogouInput.app"` 时弹授权并 `chown -R root:staff` + `chmod -R 775` | 可写时是 no-op；不可写那一支 `InPlaceSwap.stageRotation` 本来就先拒，且给的是一句话而不是密码框。**行为等价** |
| `post.sh` | 整段包在 `if [ $SOGOU_INPUT_VERSION == "3.2.0.68597" ]` | 2019 年那一版的皮肤目录修复，现代安装上是死代码 |
| `switch.sh` | 见下 | 唯一有破坏性的，而且是参数门控的 |

`switch.sh` 的全部内容归纳：

- `killAll -9 SogouTaskManager` / `killAll -9 SogouServices` / `killAll SogouPreference`
  —— ⚠️ 写的是 `killAll`（大写 A），但 macOS 默认卷不区分大小写，PATH 查找**照样命中**
  `/usr/bin/killall`。**别把它当成拼错所以不执行**；
- 用户目录那段是 `$1` 门控的：`switch.sh 1` 会
  `rm -rf ~/Library/Application Support/Sogou/InputMethod`（学习词库，本机 17MB）
  再把 `~/Library/Input Methods/Sogou` 移过去；不传参只 `rm -rf ~/Library/Input Methods/Sogou`
  （本机该目录不存在）；
- 重启 `SogouCharacterViewer`；
- 结尾 `killall -KILL SystemUIServer`。

所以正确处置是**根本不调用它**，而不是「因为它带迁移分支所以不能做一键」。

### 装配后的包是真包（这决定了没有一道闸被放宽）

把内层 `Contents6.25.1.11973/` 改名 `Contents`、套进 `SogouInput.app/`：

```
codesign -dv    → TeamIdentifier=DFD88F82SU   Identifier=com.sogou.inputmethod.sogou
codesign --verify --deep --strict → valid on disk / satisfies its Designated Requirement
spctl -a -t install               → accepted, source=Notarized Developer ID
```

Gate 2/3/4 原样通过。与豆包那条 `nestedArchivePath` 的**区别要写清楚**：豆包在拆包前
先验了 stub 的签名，搜狗外层是裸 zip，**没有 stub 可验**——信任完全落在装配后的
Gate 2–6 上（豆包最终也落在那里，stub 那一次是额外的一道）。`ContentsPayload` 补的是
形状守卫：内层必须恰好一个 `^Contents[0-9.]*$` 目录、不能是符号链接或文件、
外层匹配必须唯一。

### `SGQuDao` 不保留（初版的开放问题，已闭环）

装机副本 `Info.plist` 有 `SGQuDao = 1111`，**payload 的没有**，
`pre/post/switch.sh` 三个脚本也**没有任何一处重新注入**。
2026-09-20 真机验证：更新后该键消失；`launchctl kickstart -k gui/<uid>/com.sogou.SogouServices`
重启厂商服务后再读，**仍然没有**，`Info.plist` 的 sha1 一字未变。
结论：**厂商自己更新一次同样会丢**，这是行为对齐，不是我们弄坏的。
反过来注入才是错的——`Info.plist` 被 code directory 封签，写它会当场作废刚验过的签名。
（回滚会把带 `SGQuDao` 的旧 `Contents` 原样放回，已验。）

### 用户数据：一般规则在搜狗身上几乎全空（必须先修的那一项）

`InputMethodDataBackup` 的两条通用规则在这里只命中 **1/7**——
`Application Support/SogouInput` 根本不存在，名字规则 `contains("SogouInput")`
也够不到 `com.sogou.SogouPreference`（设置面板，和 WeType 的 `com.tencent.WeTypeSettings`
同一形状）。所以加了 `declaredDataNames["com.sogou.inputmethod.sogou"] = ["Sogou"]`，
两条规则共用这个名字。

被否决的做法是**从 bundle id 推厂商 token**（`com.sogou.…` → `Sogou`）：
同一条规则会把 WeType 读成 `Tencent`，从而把 `~/Library/Application Support/Tencent`
（多个腾讯 app 共用）整个快照进去。

真机快照实测 7 条全中：`Application Support/Sogou` +
`SogouServices.plist`、`com.sogou.{SGInputStatPanel,SogouInstaller,SogouPreference,SogouTaskManager}.plist`、
`com.sogou.inputmethod.sogou.plist`。

### 仍然不做的事

- 不跑厂商脚本（上表）；
- 不重启 `SogouServices` / `SogouTaskManager`——旧进程继续跑在被换掉的二进制上，
  实测输入法可用、输入源注册未掉；真需要时正确做法是 `launchctl kickstart -k`
  那两个 agent（有界、可解释），不是把 `switch.sh` 请回来；
- 不做 `killall -KILL SystemUIServer`；
- `update_pack_md5` 是 MD5 而 `checksumPattern` 是 SHA-512/base64，**故意不接**而不是错声明
  （和 WeType 的 `zip_download_md5` 同一处置）。

### 下载 URL 用的是 pin 了 `v=0.0.0.1` 的那次响应

这与初版「建议下一步 4」相反（那条说要带真实版本号另发一次动态请求）。改判据是两条实测：
接口**不做分段升级**（所以 pin 的那次拿到的就是最新包），而 `sv` **做 OS 门控**
（macOS 28 上带真实 OS 去问会拿到 2023 年的旧包）。
用同一次响应还顺带消掉「比较的版本」与「下载的包」指向不同发布的漂移面。

### 旧记录（2026-08-28 写的，保留）

它的 `install.sh` 在**已安装**分支上确实是 Contents 轮换（第三家同形）：

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

> **以上三段已被 2026-09-20 取代**，两处结论改了：`SGQuDao` 不保留（厂商自己也不保留，已实测），
> 而 MD5 故意不接。上面那段「未来的一键路径」里唯一照做的是双层解包 + 切换 Contents。
> 真正落地的样子见本文「一键安装」一节。

## 验证记录（2026-09-20，一键）

装机 `6.24.1.11676` → 线上 `6.25.1.11973`，这是 2026-08-28 那次欠下的真机红→绿。

| 检查 | 命令 / 做法 | 结果 |
|------|-------------|------|
| 单元测试 | `swift test --filter SogouInputTests` | 7/7 ✓ |
| 装配器 | `swift test --filter ContentsPayloadTests` | 9/9 ✓ |
| 数据快照 | `swift test --filter InputMethodDataBackupTests` | 11/11 ✓ |
| 变异测试（数据快照） | 声明表置空 / 名字只驱动支持目录 / 只驱动 preferences | 3/3 **都变红** ✓ |
| 变异测试（装配器） | 去锚点 / 去唯一性 / 去多匹配拒绝 / 去符号链接拒绝 / 去类型检查 / 用归档名命名 bundle | 6/6 **都变红** ✓（去 containment 那条**空过**，已在代码里写明它是 backstop） |
| 全量 | `make test` | Core 3531 / CLI 378 / App 51 全绿（1 条既有 known issue） |
| payload 完整性 | `md5 -q autosetup6.25.1.11973...zip` | `a171cf3d5cb42ef1d33a701555d5051c`，与接口声明一致 ✓ |
| 装配后签名 | `codesign --verify --deep --strict` / `spctl -a -t install` | valid / `accepted, source=Notarized Developer ID` ✓ |
| 计划 | `duo install SogouInput --dry-run` | `SogouInput 6.24.1.11676 → 6.25.1.11973 [vendor]` |
| **真机红→绿** | `duo install SogouInput --yes --json` | `outcome=installed, applied=true`，183,534,090 B，**12.7s** ✓ |
| 外层 bundle 身份 | `ls -id` 前后对比 | `213390184` **不变**；`Contents` 由 `213390185` → `256854106` ✓ 正是轮换 |
| 属主 / 权限 | `stat` | 外层仍 `root:staff` 775；`Contents` 变 `bobby:staff` 775 —— 不提权的已知代价 |
| 签名（更新后） | `codesign --verify --deep --strict` | **exit 0**（更新前是 `a sealed resource is missing or invalid`，app 自己运行时往 bundle 里写出来的）|
| `SGQuDao` | 更新后读 / `kickstart` 重启 SogouServices 后再读 | 两次都没有，`Info.plist` sha1 未变 ✓ |
| 输入源注册 | `defaults read com.apple.HIToolbox` | `com.sogou.inputmethod.sogou` 仍在 ✓ |
| 用户数据快照 | 看 `Backups/<key>/UserData/userdata.json` | **7 条全中**（通用规则只会命中 1 条）✓ |
| 回滚 | 先在词库目录里放一个 marker，再 `duo backups restore SogouInput --yes` | 回到 `6.24.1.11676`、`SGQuDao=1111` 回来了、marker 消失（快照早于它）、外层 inode 不变、输入源仍在 ✓ |
| 复装 | 再 `duo install` 一次 | 再次 `applied=true`，`duo check` → `up-to-date` ✓ |
| CDN 的 HTTPS | `curl -r 0-15` 打两个轮询主机 | `pro.cdn` / `pro.cdn2` **都** 206 + `application/zip` + `PK\x03\x04` ✓ —— 接口给的是 `http`，`VendorProbeSource.preferHTTPS` 会无条件改写成 `https`，所以这条必须真打过才算数 |

**人工复核（同日，用户在键盘前）**：更新 → 回滚 → 再更新走了一整圈，中文输入正常、
**账号登录态保住了**、关于面板读数正确。两条只有人能看见的现象：

- **关于面板会显示陈旧版本**，因为轮换只换磁盘上的代码、不打断已映射的进程
  （`SogouPreference` 那个进程比回滚早一小时起的）。重选一次输入源、面板重开就对了。
  `duo backups restore` 结尾那句 `SogouInput is running — restart it to use the restored version`
  说的就是这件事。**这不是 bug，是这个 app 从不强杀换来的**。
- 面板上的「已是最新」也会缓存：回到 6.24 之后它仍写「已是最新」，而同一时刻厂商接口对
  `v=6.24.1.11676` 明确返回 6.25.1.11973。

**外层 bundle 的 inode `213390184` 在三次安装 + 两次回滚里一次都没变。** 这是输入源注册
不掉的根据，也是「是谁换的」最好用的判据：我们留下 `Contents` 属主 `bobby:staff`，
厂商那条路径结尾是 `chown -R root:staff`，而 `switch.sh` 只要跑过就会写
`~/Library/Caches/com.sogou.installType`（全程不存在 → 厂商自己一次都没装成）。

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

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。以下各段原句没写日期的，都来自引入它们的提交 `6c09268b`（2026-08-28）。

### Recipes/com-sogou-inputmethod-sogou.swift — stable VendorProbe（条件端点、pin 旧版本）

转引自 recipe 注释，未复测。四段整段原文（第二段里的表格是原注释里缩进的摘录）。代码里留下的是结论：不做分段升级；`sv` 按系统分三档，档位边界保留、各档对应的版本号搬到这里；静默失效那一种的说法改成了不带版本号的；changelog 页与接口在写这句时（2026-08-28，引入它的提交 `6c09268b` 的日期；原句没写核对日期）一致，2026-09-14 复测仍一致。

So the probe pins `v` at `0.0.0.1` — below anything the vendor can ever
ship, so the request can never drift into sentinel territory. It does
NOT stage: measured at `6.23.0.0`, `6.16.1.0`, `2.0.0.26481`,
`1.5.1.21442`, `1.0.0.2` and `0.0.0.1`, every one is answered with the
same newest build rather than an intermediate hop, which is the property
that makes a pinned-old-version probe mean "latest".

WARNING: `sv` DOES gate by OS. The first version of this comment said it
did not, from five values that all sat inside one bucket. Swept finely
there are three answers:

```
    sv < 10.10             sentinel
    sv 10.10 – 10.13       6.14.1.9298   (frozen since June 2023)
    sv 10.14 – 27.6        6.24.1.11676  ← current
    sv 27.61 and above     6.14.1.9298   again
```

The residual risk is narrow, and it is this recipe's one quiet failure:
if Sogou splits the 10.14–27.6 bucket and ships a newer build only above
it, the pinned request keeps answering 6.24.1.11676 and nothing fails.
Most boundary moves are loud instead — a pin landing in the legacy
bucket reports 6.14.1.9298, below every real install, which the sweep
flags as `remote is BEHIND the installed copy`. The check for the quiet
case is the changelog page: at the next release it advances and so must
this.

`changelogURL` stays on the update-log page: it is the only place the
release notes exist, and the two agree (`6.24.1`, 2026-07-17, matching
this bundle's own build date).

复测 2026-09-14（约 07:25 UTC，只读 GET `macime.sogou.com/macversion.txt?v=0.0.0.1&sv=27.0&s=0`，另加 `cpu=arm64` / `x86_64` / `intel` 各一次）：四次都是 `version=6.24.1.11676`，`update_pack_url` 相同。代码里 "`cpu` is inert today" 因此原样保留。没有重扫 `sv` 的档位。约 09:47 UTC 另读 `pinyin.sogou.com/mac/update_log.php`（53,446 B）：最上面的条目是 `6.24.1`、`2026-07-17`；同时 `macversion.txt` 仍回 `version=6.24.1.11676`，两者一致。

### Recipes/com-sogou-inputmethod-sogou.swift — stable VendorProbe（安装脚本与 LaunchAgent）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（两个脚本都只 `bootout` 并删掉那个用户级 LaunchAgent，并不安装它）。唯一的改写：括号末句一处本机状态措辞（某个文件在不在；原文把一台机器上的观察写成了普遍情况），按本目录的机器状态规则改成了针对那台被核对的机器的说法。

(An earlier version of this comment said the installer *installs* a
per-user LaunchAgent. It does the opposite: both scripts only `bootout`
and `rm -rf` `~/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`,
and no such file existed on the machine checked, which had Sogou installed.) The self-update payload
above is a narrower shape again (a double zip carrying
`Contents<version>.zip` plus `pre.sh`/`post.sh`/`switch.sh`, whose
switch script has its own migration branches), so a one-click here needs
a Sogou-specific path, not the generic archive install.
