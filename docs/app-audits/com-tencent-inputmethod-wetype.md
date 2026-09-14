# 微信输入法 (WeType)

> 审计于 2026-08-28。腾讯的输入法，官网 `z.weixin.qq.com` 下载。
> 结论：**检测 + changelog 早已接入；一键 2026-08-28 重新接入**，走输入法专用的
> Contents 轮换，并带用户数据快照。真机红→绿（656 → 657）与回滚均已实测。

这份文档是补写的——WeType 的 recipe 早在 2026-08 就在跑了，但它的知识一直只散在
`VendorProbeRecipe.swift` 的注释和一条 memory 里。2026-08-16 的一键撤回事件也在那里，
下一个人要重新拼一遍才能读懂，所以补上。

## 基本信息
- Bundle ID: `com.tencent.inputmethod.wetype`
- Team ID: `88L2Q4487U`
- 观测版本: `2.2.3`（`CFBundleShortVersionString`），build `657`（`CFBundleVersion`）
- 安装路径: `/Library/Input Methods/WeType.app`（`root:staff`，**每一级都是 775**）
- Info.plist 关键位: **无 `SUFeedURL`**（bundle 里有 Sparkle.framework，feed 在运行时才设）
- 自更新机制: 自带 `Contents/Helpers/WeTypeUpdater.app`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✗¹      | —        | —   | —      | ✓ ★         |

1. 有 Sparkle framework，但 `Info.plist` 里没有 `SUFeedURL`（运行时设），
   而写死在二进制里的那份公开 appcast **停在 1.4.1（2025-07）**，2.x 走微信内推送通道。
   所以 Sparkle 这条路对我们是死的。

## 更新检测

- 源: `VendorProbe`（`mode: .responseBody`）
- 端点: `https://z.weixin.qq.com/web/mac/download?channel=InstallInfo`
  ——**厂商自己的安装器读的那个接口**，302 到一份 per-build 的 JSON manifest。
- 真实响应（2026-08-28）:
  ```json
  {
    "zip_download_url": "https://download.weread.qq.com/app/wxkb/mac/2.2.3/WeType_2.2.3_657.zip",
    "zip_download_md5": "001fb418c7974c112bfc7ebbf47d483e",
    "zip_version": "2.2.3.657",
    "package_type": ""
  }
  ```
- `versionPattern` 取第 4 段 → `657`（`versionIsBuild: true`，与装机 `CFBundleVersion` 同 namespace）
- `displayVersionPattern` 取前 3 段 → `2.2.3`（行上显示）

### ⚠️ 上一版 recipe 读的是**安装器壳自己的版本**

此前的 recipe 从 `z.weixin.qq.com/web/change-log/macos` 上抓
`WeTypeInstaller_<x.y.z>_<build>_<letter>.zip` 文件名。那串数字是**安装器 stub 的版本，
不是 app 的**——手上的 stub 是 2.2.0 (643)，它装出来的是 2.2.3 (657)。
两者长期贴得很近，所以看起来一直是对的：**一个用错 namespace 的 recipe 不会失败，
它只是拿另一个命名空间的号来回答你**。最后是夜扫里的
`remote is BEHIND the installed copy` 把它抓出来的。

那个页面本身也滞后（内嵌 per-platform JSON 还写着 Mac 2.2.2 时 2.2.3 已经在发），
所以**它的文件名和它的 notes 都不是版本源**。

## Changelog

- `changelogURL`: `https://z.weixin.qq.com/web/change-log/macos`（Next.js 页面，
  数据是服务端渲染进 `__next_f` 的 RSC blob，不需要跑 JS）
- 该页是**全平台混排**的扁平列表，`"platform":1`=iOS、`2`=Android、`3`=macOS、`4`=Windows。
  entry pattern 锚在 `version` 先于 `platform` 出现这个字段顺序上，把版本绑在**它自己那个对象**的
  `"platform":3` 上；`[^"]*` 跨不过结构性引号，所以够不到相邻的 iOS 对象。
  没有这道锚，一个「取最高版本」的写法会抓到 iOS 的 3.4.0 → 幽灵更新。

## 一键安装

- 状态: **已接入（2026-08-28）**，走**Contents 轮换**，不是整包覆盖。
- 历史：一键 0.3.25 上线，**当天撤回**（2026-08-16），因为用户的输入法设置丢了。

### 撤回那次的证据链（如实记，它并不构成定论）

- `/Library/Input Methods/WeType.app` 的 mtime 当时仍是厂商安装那天、版本没变 →
  **提权替换那条路从来没真跑过**；
- 同一时间窗里，做那个一键的 agent 把**旧版 2.2.1** 摆进 `~/Applications` 装了一遍、
  并两次重启运行中的输入法，而 `~/Library/Application Support/WeType/{userDict,mmkv}`
  正好在那个窗口被改写；
- 用户「我的设备」里出现**两个同名 Mac** → 第二份副本以新设备身份注册了。

所以更像"身份被顶掉"，而不是"文件被删"。**swap 没有被定罪，一份更旧的副本自行注册了才是。**
无论哪种，波及面都是用户的词库和设置，这类 app 不适合拿来学习。

### 为什么现在可以做了

`WeTypeInstaller.app` 的 `install.sh` 是**首装**路径：`rm -rf` 整个 `WeType.app`、
`mv` 新的进去、`chown -R root:staff` + `chmod -R 775`、去 quarantine、
`killall System Preferences` / `SystemUIServer`；安装器**二进制**还额外做输入源注册
（字面量 `Registered input source from /Library/Input Methods/WeType.app, result: `，
以及 `killall -9 TextInputMenuAgent / TextInputSwitcher / pboard`）。

但**每一次普通版本更新**跑的不是它，是 bundle 里的 `WeTypeUpdater.app`，
而它保留外层 `.app`、只轮换 `Contents`：

```
/Library/Input Methods/WeType.app/.Contents.update
/Library/Input Methods/WeType.app/.Contents.old
/Library/Input Methods/WeType.app/.Contents.abandoned
"will exchange Contents: previous="   "old Contents removed: "   "cleanup old Contents failed: "
```

（本机更新日志里也有 `stage successful: …/.Contents.update` 和
`install committed: previous=2.2.3(655), target=2.2.3(656)`；更新器运行期间自己就位于
`…/.Contents.old/Helpers/WeTypeUpdater.app`。）

被 `TISRegisterInputSource` 注册的是**那个路径**，所以要保的是外层目录，不是里面的代码。
`InPlaceSwap.rotateContents` 复刻的就是这条：外层 `.app` 的 inode、属主、模式全不动。

### `chmod -R 775` 是承重的，不是洁癖

两家 installer 结尾都是 `chown -R root:staff && chmod -R 775`，**递归**。
本机实测 `WeType.app` 里每一个目录都是 775，而厂商 payload zip 解出来是 755/644。
组写位在他们更新的**收尾**那一步才用上：轮换完要 `rm -rf` 被换下的那份 Contents，
而删一棵 root 拥有的树需要树里每一层目录都可写——更新器二进制里那句
`cleanup old Contents failed:` 就是为这个准备的。

所以**轮换**把组写位一路带到底（`chmod -R g+w`，而不是照抄 `-R 775`：后者会把普通文件也变成可执行）。
只保外两层的话，"能预备、不能清理"，每次厂商自更新在 app 里留一份全尺寸残留。

**这条递归只在轮换里，不在整包覆盖那条路上**：输入法已经不走整包覆盖了，
而那条路上真有组可写根目录的 app（本机 137 个 bundle 里 5 个 g+w 根，其中
Microsoft Word 和 Excel 走提权路径，`root:wheel` 775），拿输入法量出来的规则去
放宽它们的整个内部，是没人要求过的改动。整包覆盖那条路的保证因此**恰好是两层**。

### 产物

`zip_download_url` 直接就是**真包**（notarized `WeType.app`，Team 88L2Q4487U），
不是官网页面上那个 ~3 MB 的 stub，所以不需要 DoubaoIme 那样的 `nestedArchivePath`。
响应里的 `zip_download_md5` 没有接——`checksumPattern` 是 SHA-512 base64，
**宁可不声明也不要错声明**；真正的闸是签名 + Team + bundle id + 架构那四道。

### 提权在这里不可用

见 [豆包输入法的同一节](com-bytedance-inputmethod-doubaoime.md#️-提权在这里是不可用的不是不需要)：
App Management 对 root 同样生效，写 bundle **内部**一律 EPERM，写 bundle **旁边**没问题。
轮换因此一律不提权，`needsElevatedReplace` 对输入法只问 bundle 本身可写与否。

### 用户数据安全网

撤回那次丢的东西全部在 bundle 之外：

```
~/Library/Application Support/WeType/userDict     词库
~/Library/Application Support/WeType/mmkv         设置与状态
~/Library/Preferences/com.tencent.inputmethod.wetype.plist
~/Library/Preferences/com.tencent.WeTypeSettings.plist      ← 注意：不共享 bundle id 前缀
```

`InputMethodDataBackup` 跟着 bundle 回滚点一起打快照（APFS clone，103 MB 的
Application Support 目录几乎零成本），`duo backups` 还原时一起还原。
**关掉「保留回滚点」就没有快照**——不绕过用户的选择，代价是那种配置下没有安全网。

**发现的一条：`com.tencent.WeTypeSettings` 和 bundle id 没有公共前缀**，
只按 bundle id 前缀找 plist 会漏掉设置面板的偏好；只按 app 名字找又会漏掉 DoubaoIme 的
`…doubaoime.settings` / `.installer`（那三个都在 bundle id 前缀下）。
所以 `locations()` 两条规则都要：**bundle id 前缀 OR 名字包含**。两家各证一条。

## 验证记录（2026-08-28）

| 检查 | 命令 | 结果 |
|------|------|------|
| 全量测试 | `make test` | Core 1359 / CLI 161 全绿 |
| 活体端点 | `duo verify --samples`（全量 270） | ✗ 0；WeType vendor probe `ok` |
| 正则独立复算 | Python 打真实响应体 | 3 个 pattern 各命中**恰好 1 次** |
| 端到端 红→绿 | 见下 | ✓ 656 → 657 真机真更新 |
| 回滚 | `duo backups restore WeType --yes` | ✓ 回到 656，4 处用户数据一并还原 |

### 端到端实测（2026-08-28）

657 就是最新，本机本来没有可验的更新——所以**造了一个真的红**：
厂商历史 payload 仍然可取（`download.weread.qq.com/app/wxkb/mac/2.2.3/WeType_2.2.3_656.zip`，
实测 200，307 MB，公证过、Team `88L2Q4487U`、`CFBundleVersion 656`）。
用**厂商自己那套手法**（ditto 进 bundle → 两次 rename）把 656 的 Contents 摆成在装版本，
再跑我们的一键。夹具那步刻意不用我们的代码，免得测试自证。

```
duo check   → installedBuild 656 / latestBuild 657 / route in-place
duo install → backed up → downloading → extracting → verifyingCodeSignature → installing → done
```

| 检查 | 结果 |
|------|------|
| 外层 `.app` inode | `212955694` → `212955694`，**未变** |
| 版本 | 656 → **657** |
| 残留 | bundle 内只有 `Contents` |
| `Contents` 下无组写目录 | `find … ! -perm -g+w` → 空 |
| 代码签名 | `valid on disk` + `satisfies its Designated Requirement` |
| 用户数据快照 | 4 处，含只能靠名字命中的 `com.tencent.WeTypeSettings.plist` |
| 回滚 | `duo backups restore` → 657 → 656，4 处用户数据还原，日志带"运行中的输入法要重启才会用上" |
| 再更新 | 656 → 657，机器留在当前版本 |

全程**没有密码框**。

## 建议下一步

1. 盯 `.Contents.update` / `.Contents.old` / `.Contents.abandoned` 这三个名字：
   轮换开工前会检查它们存在与否（存在＝厂商更新器正在飞，拒绝而不是抢它）。
   名字变了这道保护会**静默失效**——判据是这三个字符串还在不在 `WeTypeUpdater` 二进制里。
3. `zip_download_url` 与 `zip_version` 出自同一份 manifest、同一次响应，
   不存在"版本和产物指向不同发布"的漂移面。这条是这个 recipe 比多数 recipe 更稳的地方。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（开头三段：版本从 changelog 页读的那一版）

转引自 recipe 注释，未复测。三段整段原文，迁移时都已不成立（描述的是被替换掉的读页面的 recipe），见下面的更正。代码里第一段只留下了到 appcast 冻结为止的那部分，并改成指向现在的 manifest；后两段删了。

WeType (微信输入法) — Tencent's input method. Installs under
`/Library/Input Methods` (not /Applications), now scanned by AppScanner.
No standard source resolves it: its bundled Sparkle has NO SUFeedURL in
Info.plist (set at runtime), and the hardcoded public appcast froze at
1.4.1 (2025-07) while 2.x updates ride an in-app WeChat push channel — so
the only public "what's the latest macOS version" surface is the official
changelog page. It's a Next.js page but the data is server-rendered inline
(an `__next_f` RSC blob, no JS needed): a flat list of release objects for
ALL platforms — `"platform":1`=iOS, `2`=Android, `3`=macOS, `4`=Windows.
CRUCIAL anchor: `version` precedes `platform` in each object, so the
pattern ties the captured version to its OWN object's `"platform":3` —
`[^"]*` can't cross a structural quote, so it can't span into an adjacent
(e.g. iOS) object. Without that gate, a bare/highest version pattern would
grab a higher non-macOS version (iOS is at 3.4.0) → a phantom update.
`content_html` carries no raw `"` (quotes are `&quot;`-encoded), so the
`[^"]*` field bounds hold.

We compare BUILDS, not the marketing version: the page names the current
installer as `WeTypeInstaller_2.2.2_647_<letter>.zip`, and the installed
bundle's `CFBundleVersion` is that same `647`, so both sides speak the
same scheme. Those installer links exist only for the CURRENT release
(verified 2026-08-16: the whole page yields exactly one version/build
pair). `displayVersionPattern` keeps the row reading `2.2.2` rather than a
bare `647`, and it reads that string out of the SAME filename — which
matters twice over: display extraction is first-match with no
`selectHighest`, and this page lists releases oldest-first, so the
`"platform":3`-gated object pattern would have shown the very first
macOS release ever published beside the current build.

If a future page ever drops the installer links, the build pattern misses
and the probe degrades to "unknown" — never to a wrong version.

更正 2026-09-14：这三段描述的是 `2c9e99a4`（2026-08-20）之前的 VendorProbe——从 `z.weixin.qq.com/web/change-log/macos` 读版本。现在的 VendorProbe 读 `?channel=InstallInfo` manifest（`versionPattern` 取 `zip_version` 的第 4 段、`displayVersionPattern` 取前 3 段，`Recipes/com-tencent-inputmethod-wetype.swift` 的 `VendorProbeRecipe`），所以这三段对当前代码不成立。页面按 `"platform":3` 锚定的那部分说明对 ChangelogRecipe 仍然成立，它自己的注释里有。

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（2026-08-16 一键撤回）

转引自 recipe 注释，未复测。整段原文，从代码里删了：开头的「DETECTION ONLY」迁移时已不成立（见下面的更正），其余是撤回那次的证据。代码里留下的是一键段里的「withdrawn 2026-08-16 after a user lost their WeType settings; History has the evidence」。唯一的改写：三处本机状态措辞（那台机器上被观测到的文件时间与版本、提权替换没跑过的那台机器、一键工作所在的机器），按本目录的机器状态规则改成了针对那台被检查的机器的说法。

DETECTION ONLY — the one-click was built, shipped in 0.3.25, and then
WITHDRAWN on 2026-08-16 after a user lost their WeType settings during
that work. State the evidence plainly, because it does not add up to a
proof and the decision does not depend on one:
```
  * `/Library/Input Methods/WeType.app` was never replaced by us — on the
    machine checked that day its mtime is still the vendor install's (Aug 6) and it is 2.2.2/647.
    The elevated swap never actually ran on that machine.
  * What DID run, during the one-click work on that machine, was a staged OLDER copy
    (2.2.1) placed in `~/Applications`, installed over, and the running
    input method restarted twice. `~/Library/Application Support/WeType/`
    `userDict` and `mmkv` were rewritten inside that window.
```
So the swap is not convicted; a second, older copy of an input method
registering itself is. Either way the blast radius is the user's own
dictionary and settings, and this class of app is not one to learn on.

更正 2026-09-14：「DETECTION ONLY」不成立——`489b3921`（2026-08-28）重新接入了一键（`install: VendorInstallSpec(… kind: .zip)`，输入法走 `InPlaceSwap.rotateContents` 的 Contents 轮换并带 `InputMethodDataBackup` 快照）；代码里的一键段说明了为什么。

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（留给以后再看的真实 payload）

转引自 recipe 注释，未复测。整段原文，迁移时已不成立，从代码里删了，见下面的更正。

Kept for whoever revisits this: the real payload (not the ~3 MB stub the
page links) is `download.weread.qq.com/app/wxkb/mac/<ver>/WeType_<ver>_<build>.zip`,
constructible from the version+build this recipe already extracts, and
verified in 2026-08 to be a notarized `WeType.app`, Team 88L2Q4487U.
The missing piece is not the URL — it is doing the vendor installer's
registration/migration, which nothing here does.

更正 2026-09-14：「which nothing here does」不成立——`489b3921`（2026-08-28）起一键走 Contents 轮换，保留已注册的 `.app` 路径，不需要复刻安装器的注册；payload 也不再由版本+build 拼出，而是直接读 manifest 的 `zip_download_url`。代码里现有的「`zip_download_url` is the real payload」一段说的是现状。

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（读厂商安装器读的接口）

转引自 recipe 注释，未复测。整段原文；代码里只把「an 8 MB stub」换成了「a stub」。原句没写日期，引入它的提交是 `2c9e99a4`（2026-08-20）。

Read the endpoint the vendor's OWN installer reads, not the marketing
page. `WeTypeInstaller.app` is an 8 MB stub that ships no payload — it
GETs `?channel=InstallInfo`, which 302s to a per-build JSON manifest:

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（上一版读的是安装器壳的版本）

转引自 recipe 注释，未复测。整段原文；代码里留下的是警告（那些文件名里的数字是安装器 stub 自己的版本，不是 app 的；用错 namespace 的 recipe 不会失败，只会答错号），手上 stub 与它装出的版本、以及夜扫抓到它的经过搬到这里。原句没写日期，引入它的提交是 `2c9e99a4`（2026-08-20）。

The previous recipe read `WeTypeInstaller_<x.y.z>_<build>_<letter>.zip`
filenames off `z.weixin.qq.com/web/change-log/macos`. Those numbers are
**the installer stub's own version, not the app's** — the stub in hand
is 2.2.0 (643) and installs 2.2.3 (657). The two tracked each other
closely enough for a while to look right, which is exactly how a
wrong-scheme recipe survives: it never fails, it just answers with a
number from the wrong namespace. `remote is BEHIND the installed copy`
in the nightly sweep is what finally caught it.

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（那个页面自己也滞后）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（页面自己也滞后，所以文件名和 notes 都不是版本源），当时 Mac 2.2.2 / 在发 2.2.3 这个例子搬到这里。原句没写日期，引入它的提交是 `2c9e99a4`（2026-08-20）。

That page also lags on its own account — its embedded per-platform JSON
still listed Mac at 2.2.2 while 2.2.3 was shipping — so neither the
filenames nor the notes on it are a version source.

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（一键在 2026-08-28 恢复）

转引自 recipe 注释，未复测。整段原文；代码里只把「— see above」换成了撤回原因和指向这里的说明（「see above」指的那段已搬到这里）。

ONE-CLICK, restored 2026-08-28 (withdrawn 2026-08-16 — see above), and
the reason it is back is that the install now has the same SHAPE as the
vendor's own update rather than the shape of its installer.

### Recipes/com-tencent-inputmethod-wetype.swift — VendorProbe（`zip_download_url` 是真包）

转引自 recipe 注释，未复测。整段原文；代码里只把「the ~3 MB stub」换成了「the small stub」。原句没写日期，引入它的提交是 `489b3921`（2026-08-28），更早的 `a982671f`（2026-08-16）里已有「~3 MB stub」。

`zip_download_url` is the real payload, not the ~3 MB stub the marketing
page links: a notarized `WeType.app`, Team 88L2Q4487U, which the code
signature + Team + bundle-id gates check before anything moves. The
response also carries `zip_download_md5`; `checksumPattern` is SHA-512
base64, so it is deliberately NOT wired up rather than mis-declared.

### Recipes/com-tencent-inputmethod-wetype.swift — ChangelogRecipe（与 VendorProbe 同一个页面）

转引自 recipe 注释，未复测。整段原文；开头一句迁移时已不准确，代码里改写了，见下面的更正；其余原样。

WeType (微信输入法) — same official changelog page as its VendorProbe.
Next.js page with the data server-rendered inline (an `__next_f` RSC blob,
no JS needed): a flat list of release objects for ALL platforms, tagged
`"platform":1`=iOS / `2`=Android / `3`=macOS / `4`=Windows. The entry
pattern ties the captured version/body to its OWN object's `"platform":3`
(version precedes platform; `[^"]*` can't cross a structural quote, so it
can't bleed into an adjacent platform's object) — so only macOS releases
become entries. The notes live in `content_html`, where each line is its
own tag — usually `<h2>` (including the dash-bulleted lines), sometimes
`<ul><li>` or `<p>` — so itemPatterns try all three. No human per-entry
date is published (only a unix `release_date`), so `date` is omitted
rather than shown as a raw epoch. CRUCIAL: the list runs oldest→newest, so
`newestLast` flips it to newest-first before the cap. Quotes inside notes
are `&quot;`-encoded (no raw `"`), so the `[^"]*` field bounds hold and the
default HTML entity decode renders them. A parse miss falls back to
embedding this same page (the VendorProbe's changelogURL).

更正 2026-09-14：自 `2c9e99a4`（2026-08-20）起 VendorProbe 不再读这个页面（读 `?channel=InstallInfo`），这个页面只是它的 `changelogURL`。代码里改成「the official changelog page its VendorProbe names as `changelogURL`」。
