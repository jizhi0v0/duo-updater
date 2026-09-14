# App Audit Index

Per-app audit checklist. Run `/app-audit <App>` for each, then check off.

> `P` = VendorProbe, `G` = GitHub, `C` = Changelog, `B` = ChannelBinding, `S` = Sparkle(auto)

## 从 recipe 注释迁出的历史

`DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/<family>.swift` 的注释只留**当前契约**；
带日期的验证记录、事故经过、实测、否决过的方案搬进该 family 的审计文档。步骤与
[`docs/engine-notes/README.md`](../engine-notes/README.md) 的
「Checklist for migrating a comment here」相同——(a)/(b)/(c) 三类、搬之前复核、
留回链、grep 副本、跑检查——**照那份清单走**，这里只写 recipe 这边的约定。

- **留下（a）**：pattern 为什么这样锚、版本方案的坑、为什么不跟重定向、某个字段是什么意思、
  下一个改它的人不知道就会改坏的东西。**搬走（b）**：带日期的验证记录（"Verified 2026-08-09
  by mounting the dmg…"）、事故时间线、实测数字、否决方案和它的实验、"2026-xx 查过：没有
  changelog 页"。**（c）**：对照**当前代码**（不是对照日期）已经不成立的——改正或删掉，
  理由写进 PR，**不许当成真话搬进历史**。
- **以句子为单位。** 以实测为主语的句子（"Measured …"、"Verified …"）整句搬走；契约和实测
  缠在同一句、拆开就得改写的，整句留下。**含日期或数字不等于该搬**——下面五条先于它：
  - **结论留下，只搬测量。** CapCut 的 "only the beta recipe is exposed to this"、Windscribe 的
    "`duo verify` pays all three" 留在代码；桶的表格、字节数、日期进历史。拆出结论需要改几个字
    时可以改（记账 diff 里逐条可见），历史里保留原段落全文（见下面补充第 3 条）；整段原样留在
    代码里、一句都没搬也没改的段落，不进历史。
  - **更正跟着它更正的说法走。** 注释写着"X 以前成立、现在不成立"时，在同一个 PR 里把代码里
    （以及复述它的测试注释里）的旧说法改掉，不许只把更正搬走、把旧说法留下。反例：第一版把
    CapCut「`capcutpc_beta` 的坑已不存在」那段搬进历史，代码和 `CapCutProbeRecipeTests` 里剩下的
    却是 "TRAP" 和 "returns NOTHING here"。
  - **"错改今天也能过"的警告留下。** Windscribe 的 "Adding an alternation there looks like it
    works — today it returns 2.24.12"、"so the bug would look like a pass"。
  - **（c）类改写是新断言。** 它要的证据和任何新断言一样：注释里点出让它成立的符号，PR 里给
    file:line，并写明成立条件。反例：第一版 Windscribe 写"`duo verify` files an installed copy
    under its resolved channel"，没写读不到偏好时（文件缺失、解不出、resolver 超时）那份拷贝仍按
    stable 归档。
  - **没写日期的数字，先分示例还是现状。** 用来展示格式或形状的（示例）留在代码里、标成示例
    （"e.g."），比如 Canva 注释里说明 feed 与 bundle 是同一个字符串的 `1.124.0`；断言“现在是怎样”的
    （现状：条数、“最新是 X”、“N 个条目”）连同引入它的日期搬进历史，代码只留结论，比如 1Password
    的 "item 1 of 89"。现状数字而契约又依赖它仍然成立的，按（c）处理：复测，或改写成不依赖具体值
    的说法。
- **搬完单独重读 Swift 文件。** 不看历史、只读留下的注释：每句仍为真（留下的 "today"、"which it
  is today" 也要核——CapCut 那句 "stable is 9.3.0 — which it is today" 在重读时已经不成立），
  没有悬空的 "see below"、"that"、"the question"。
- **接收位置**：`docs/app-audits/<family>.md` 末尾的固定标题 `## 历史与实测`（逐字，
  `scripts/check_app_audits.py` 认这一整行）。`<family>` 是 recipe 文件名去掉 `.swift`，
  一个 family 一份——family 里另一个 app 有自己的审计时也一样，历史进 family 那份，
  需要时再链过去。
- **格式**：每组搬出的注释前一行来源 `### Recipes/<family>.swift — <哪条 recipe / channel>`，
  下一行按 engine-notes 清单第 2 步标注 `转引自 recipe 注释，未复测。`（真复测过的写复测日期和
  结果，与转引分开写）。正文**逐字、保留原语言**（翻译就是改写）：每行去掉行首 `// `，保留原
  换行；原注释里缩进的摘录用 ```` ``` ```` 围起来。历史是注释当时的带日期快照，不跟代码同步：
  它和代码里留下的结论重复是无害的，代码以后变了而历史没跟着变也是预期的，不算漂移。
- **机器状态**：本目录的 `MACHINE_STATE` 规则同样管搬过来的句子。描述"那台机器装了/没有什么"
  的句子改成针对那份拷贝的说法（"the machine measured on 2026-08-27 had …"），不加豁免。这是
  历史正文里唯一允许的改写，PR 里逐条列出。
- **代码里的回链**：恰好一行 `// History: docs/app-audits/<family>.md#历史与实测`，放在 family
  第一个注释块的开头，或它关心的那条 entry 正上方。
- **还没有审计的 family**：新建仅含历史的文档——标题、一句"这不是审计，覆盖情况未审"、
  `## 历史与实测`。登记在下面索引的「仅迁出历史（未审计）」一节，**永远不打勾**；日后真审计了
  再挪到对应分类。
- **检查**：`check_app_audits.py` 要求每个回链指向 git 跟踪的文件、文件里有那一行标题、
  `Recipes/` 里的回链文件名等于所在 family，并且每个带 `## 历史与实测` 的文档至少被一个回链
  指着。它不判断搬的对不对——那是 PR 里的逐块分类表和注释行数记账（迁移前/后注释行数、
  审计新增行数）要回答的。
- **补充七条**（#615 三轮复审的教训，上面各条没有覆盖到的）：
  1. **机器状态怎么划**：拿身份、Team 或 bundle 和"被更新的那个 app"比较的措辞原样保留
     （"matching the install"、"the installed copy's team"、"same Team as the installed app"）。
     某一台机器上的**具体值**——版本号、build、路径、某个文件在或不在——是机器状态，要改写，
     哪怕它挂在 "installed" 这个词上（"the installed 1.27.0 commit"、"the installed version"）。
     这条管的是某台机器被观测到有什么：假设场景里的泛称（"an update against an installed 2.9.x"）、
     引用的工具输出（"remote is BEHIND the installed copy"）、同一版本每份拷贝都一样的属性
     （"this bundle's own build date"）都不是机器状态，原样保留。
     **来源标注只说改了哪一类**（例如「改写了一处本机状态措辞：具体版本号」），不以任何语言复述
     被替换掉的短语——翻译过来的引用也算引用。
  2. **从厂商现状句里删掉日期或 "when checked"，就造出了一句无时间的断言，按（c）处理**：先复测，
     或者把日期留着。反例：#615 第一版从 Gemini 的 "(302 → /sorry, observed 2026-08-16)" 里删掉
     日期，剩下 "the download page answers a plain fetch with Google's bot challenge (302 → /sorry)"，
     而那页复测时回的是 404。
  3. **一段里只要有一句被搬走或被改写，历史里就放这一段的整段原文**，不是只放那一句；同一段里
     仍原样留在代码的句子也跟着出现在历史里——历史是带日期的快照，这种重复是有意的。只有整段
     原样留在代码里的段落不进历史。只加一个 "e.g." 标记不算改写，不进历史；任何改写或任何（c）更正
     都把整段原文送进历史，后面另起一行写复测或更正说明。
  4. **grep 副本的范围是整个仓库**，只排除各审计文档里的 `## 历史与实测` 一节、`CHANGELOG.md`、
     `changelog/`、`verify/baseline.json`，以及测试 fixture 和抓下来的响应体——它们是历史记录或数据，
     不是断言。（以前列过一份目录清单，漏了 `Recipes/` 以外的 `Sources/`、`CLI/` 和别的 family
     的审计文档。）
  5. **改索引、台账或 skill 的某一行时，核这一行其余的说法**：在本批范围内的一起改，不在的列进 PR
     的 Found in passing。
  6. **改写里的量词**（"a few"、"ONE"、"all"、"never"）必须和历史里记下的计数一致。
  7. **改过的注释行按周围行的宽度重新折行。**

---

## Multi-channel families (audit covers all channels)

- [x] [**Chrome**](com-google-Chrome.md) · `com.google.Chrome` — P(stable/beta/dev/canary) · 4 channels, independent bundle IDs · 审计 2026-06-04 ✓
- [x] [**Firefox**](org-mozilla-firefox.md) · `org.mozilla.firefox` — P(stable/beta/esr/nightly/dev-edition) · 5 channels · RemotingName 检测（修复 beta/esr 误判）· 5 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Thunderbird**](org-mozilla-thunderbird.md) · `org.mozilla.thunderbird` — P(stable/beta/esr/nightly) · 4 channels · RemotingName 检测（修复 beta bundle id + esr 跨 channel 误推）· 4 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Edge**](com-microsoft-edgemac.md) · `com.microsoft.edgemac` — P(stable/beta/dev) · 3 channels, independent bundle IDs · **全 channel 一键 ✓**（beta/dev 一键接入 2026-07-03，pkg 取 enterprise API `Artifacts[].Location`，Team UBF8T346G9）· **三 channel 真实 bundle 验证 ✓**（pkg 展开取 app）· 版本方案核对通过 · 2026-06-04
- [x] [**Discord**](com-hnc-Discord.md) · `com.hnc.Discord` — P(stable/ptb/canary) · 3 channels, independent bundle IDs · **三 channel 官方 dmg 验证 ✓** · 2026-06-04
- [x] [**微信开发者工具**](com-tencent-wechatdevtools.md) · `com.tencent.wechatdevtools`（登记 id，磁盘上 2.02 是 `com.github.Electron`）— P(stable/rc/nightly) C · 3 channels · 真身份读 app 自带 `package.json`（`versionType`）· 一键 pkg ✓ · **三个渠道真实 pkg + 已装 2.01 全部 channel-verify ✓** · 2026-08-18
- [x] [**Warp**](dev-warp-Warp-Stable.md) · `dev.warp.Warp-Stable` — P(stable/preview/dev) C · 3 active channels, beta/canary 轨道废弃 · stable 一键 ✓ · **stable(scan)+preview+dev(dmg) 验证 ✓** · 2026-06-04
- [x] [**OrbStack**](dev-kdrag0n-MacVirt.md) · `dev.kdrag0n.MacVirt` — P(stable/beta/canary) C B · 3 channels, shared ID + ChannelBinding · 全 channel 一键 ✓ · **stable/beta/canary 三 channel 本机验证 ✓**（beta/canary 经 `updates_optinChannel` 取值验证，改动已还原）· 2026-06-04
- [x] [**Signal**](org-whispersystems-signal-desktop.md) · `org.whispersystems.signal-desktop` — P(stable/beta) · 2 channels, independent bundle IDs · **两 channel 官方 zip 验证 ✓** · 2026-06-04
- [x] [**Element**](im-riot-app.md) · `im.riot.app` — P(stable/nightly) · 2 channels, independent bundle IDs · **两 channel 验证 ✓ + 修复已发布 bug**（nightly id `io.element.nightly`→`im.riot.nightly`）· 2026-06-04
- [x] [**HBuilderX**](io-dcloud-HBuilderX.md) · `io.dcloud.HBuilderX` — P(stable/alpha) C · 2 channels, independent bundle IDs（alpha=`io.dcloud.HBuilderXAlpha`）· **全 channel 一键 ✓**（stable 一键接入 2026-07-03：版本源改 DCloud `release.json` + arm64 dmg，Team YQM5H857L5；alpha 早有一键）· **两 channel 本机验证 ✓**（stable channel-verify 复验 UPDATE 5.07→5.14）· 2026-06-04
- [x] [**Zed**](dev-zed-Zed.md) · `dev.zed.Zed` — G(stable+preview) C(stable+preview) · **两 channel 均经 GitHub 检测 ✓**（收尾补 stable rule 填上原缺口 + 修 Preview channel-gate 回归；`--check dev.zed.Zed-Preview` 全链 winning=GitHub/up-to-date）· 2026-06-04
- [x] [**Vorssaint**](com-vorssaint-utils.md) · `com.vorssaint.utils` — G(stable+beta，**两轨一键 dmg**) · 共享 bundle id **和 app 名**，beta 由真实版本后缀 `-beta.N` 分流 · cask `auto_updates true`，原通用 Homebrew 源会跳过 · beta 轨已在 `ChannelProofRegistry` 登记 artifact proof · **beta 端到端验过**：装 3.3.3-beta.1 → 收到 3.3.3-beta.3（不是 stable 3.3.2）→ 一键装绿 ✓ · 原「严格签名验证失败」结论复测未复现（没签名的是 dmg 容器，闸开在 .app 上）· 2026-09-03
- [x] [**Tailscale**](io-tailscale-ipn-macsys.md) · `io.tailscale.ipn.macsys` — P(stable) C · stable 一键 ✓ · unstable 未覆盖 · **stable 本机验证 ✓** · 2026-06-04
- [x] [**Fork**](com-DanPristupov-Fork.md) · `com.DanPristupov.Fork` — B(stable/beta) C · 2 channels, shared ID + feed-swap ChannelBinding · **beta（Fork 默认 Developer 渠道）+ stable 两 channel 真机验证 ✓**（stable 经 `applicationUpdateChannel=2` 验证，改动已还原）· 2026-06-04
- [x] [**Surge**](com-nssurge-surge-mac.md) · `com.nssurge.surge-mac` — B(stable/beta) · 2 channels, shared ID + feed-swap ChannelBinding · **beta（IncludeBetaBuilds=true）+ stable 两 channel 真机验证 ✓**（stable 经逐字节备份/还原验证，无需退出进程）· 2026-06-04
- [x] [**TablePlus**](com-tinyapp-tableplus.md) · `com.tinyapp.TablePlus` — B(stable/beta) C · 2 channels, shared ID + header-keyed ChannelBinding · **beta（IsReceiveBetaBuild=1）+ stable 两 channel 真机验证 ✓ + header 翻 710↔711 实证**（stable 经嵌套 pref 取值验证，改动已还原）· 2026-06-04
- [x] [**DuoPaste**](io-duopaste-daemon.md) · `io.duopaste.daemon` — B(stable/beta) · 2 channels, shared ID + channel-tag ChannelBinding · **beta + stable 两 channel 真机验证 ✓**（beta 用 `…-beta` 构建；stable 经 `sparkleIncludePrereleases` 取值验证，改动已还原）· 2026-06-04
- [x] [**CleanShot X**](pl-maketheweb-cleanshotx.md) · `pl.maketheweb.cleanshotx` — C B(license feed) · license-keyed Sparkle feed · **stable 本机验证 ✓**（legit feed head=4.8.8=installed）· 2026-06-04
- [x] [**CapCut**](com-lemon-lvoverseas.md) · `com.lemon.lvoverseas` — P(stable/beta) B · 2 channels, shared ID + ChannelBinding（`joinBeta` 在容器外的 INI）· **全 channel 一键 ✓**（Team 22MMUN2RN5，两轨真实 dmg 挂载核对）· **两轨版本字段是反的**（beta 的 short=`9.3.4531` / version=`9.4.0-beta4`，故 beta `versionIsBuild:true`）· 同 id 有 MAS 副本（19.2.0），靠 `_MASReceipt` 分流 · 2026-08-27
- [x] [**Termius**](com-termius-dmg-mac.md) · 三个独立 bundle id：`com.termius.mac`（MAS，`MacAppStoreSource` 通用覆盖，无 registry）/ `com.termius-dmg.mac`（官网 dmg，P stable，既有）/ `com.termius-beta.mac`（P beta，本次新增）— **全 channel 一键 ✓**（beta 用 universal dmg，Team 6KN952WR85）· stable 既有 recipe 的 arm64-only 一键是刻意的 arm64-pin（DuoUpdater 自身 arm64-only），不是 bug；真正待修的是 `changelogURL` 404，已拆分为独立任务 · issue #91、#102 · 2026-08-27
- [x] [**UTM**](com-utmapp-UTM.md) · `com.utmapp.UTM` — G(stable+beta，一键) C + MAS/TestFlight 通用托管 · 包内无 channel 标记；用观测版本的 exact GitHub release `prerelease` 位判轨（判"这份拷贝是什么"），候选则按 `max(装机大版本线, 最新正式版)` 取 —— **UTM 的预览是每条线的前半段、会转正，不是平行轨** · 双渠道 changelog 隔离，beta 侧含转正条目 · 真实 v5.0.5 DMG 签名/公证验证 ✓ · 2026-09-03
- [x] [**Mac Mouse Fix**](com-nuebling-mac-mouse-fix.md) · `com.nuebling.mac-mouse-fix` — B(stable/beta) · 2 channels, shared ID + feed-swap ChannelBinding · **stable 端到端本机验证 ✓**（`channel-verify --check` 走生产 AppScanner→ChannelBinding→Sparkle，实时命中 stable feed，判定 up to date）· beta 侧 resolver 映射与真实 preview bundle 已核对，未在本机翻转该 app 自身的偏好文件 · 2026-09-12

## Microsoft Office family

> Word/Excel are installed via **MAS** → resolve via App Store (receipt wins the
> chain before VendorProbe). So the `versionIsBuild` VendorProbe path is NOT
> exercised by a MAS install and stays **needs-verify** for a non-MAS Office.
> PowerPoint/Outlook/OneDrive/Teams = `.pkg` casks → skipped (need sudo).

- [~] **Word** · `com.microsoft.Word` — P(stable, versionIsBuild, one-click) · ✓ install detected via **App Store** (VendorProbe path needs-verify)
- [~] **Excel** · `com.microsoft.Excel` — P(stable, versionIsBuild, one-click) · ✓ install detected via **App Store** (VendorProbe path needs-verify)
- [ ] **PowerPoint** · `com.microsoft.Powerpoint` — P(stable, versionIsBuild, one-click) · ⏭ pkg/sudo
- [ ] **Outlook** · `com.microsoft.Outlook` — P(stable, versionIsBuild, one-click) · ⏭ pkg/sudo
- [ ] **OneDrive** · `com.microsoft.OneDrive` — P(stable, one-click) · ⏭ pkg/sudo
- [ ] **Teams** · `com.microsoft.teams2` — P(stable, one-click) · ⏭ pkg/sudo

## Single-channel — VendorProbe + optional Changelog

> ✓ marks = on-machine verified 2026-06-04 via `channel-verify` against a real
> installed bundle (full production chain). The sweep's raw output is an
> installed-app inventory, so it stays local (`application-test/records/`,
> gitignored) — per-app conclusions live in each app's audit instead.

- [x] **VS Code** · `com.microsoft.VSCode` — P C (one-click) · ✓ src=Vendor
- [x] **Claude Desktop** · `com.anthropic.claudefordesktop` — P (one-click) · ✓ src=Vendor
- [x] [**super.engineering**](com-zarifpour-superconductor.md) · `com.zarifpour.superconductor` — P C B (one-click) · ✓ src=Vendor · 版本是 commit hash，按 `changelog.json` 的发布顺序比较 · 审计 2026-09-11
- [x] **Codex → ChatGPT** · `com.openai.codex` — P C (one-click) · ✓ src=Vendor · 独立 Codex 桌面端 2026-07 并入 ChatGPT app（cask `codex-app` 已 `deprecate! … replacement_cask: "chatgpt"`），**bundle id 未变**——真包核实 ChatGPT.app 仍登记 `com.openai.codex` / `26.825.51511`，既有 recipe 全链 ✓（2026-08-30 复验）
- [x] **Cursor** · `com.todesktop.230313mzl4w4u92` — P · ✓ src=Vendor
- [x] [**Notion**](notion-id.md) · `notion.id` — P C · ✓ src=Vendor · **三个产物版本互不同步**（官网 307 universal / `latest-mac.yml` 纯 x64 / `arm64-mac.yml` 是独立轨）· `arm64-mac.yml` 不是另一个架构而是 `channel: arm64` 的另一条轨，故 ElectronManifestSource 不应接管 · 2026-09-01
- [x] **Obsidian** · `md.obsidian` — P C · ✓ src=Vendor
- [x] [**Figma**](com-figma-Desktop.md) · `com.figma.Desktop` (+beta `com.figma.DesktopBeta`) — P(stable/beta) C (one-click) · 2 独立 bundle, Pattern A · 真机验证 2026-06-06 ✓
- [x] **Slack** · `com.tinyspeck.slackmacgap` — P C · ✓ src=Vendor
- [x] **1Password** · `com.1password.1password` — P C · ✓ src=Vendor
- [x] **Sublime Text** · `com.sublimetext.4` — P C · ✓ src=Vendor
- [x] **Sublime Merge** · `com.sublimemerge` — P · ✓ src=Vendor
- [x] **LM Studio** · `ai.elementlabs.lmstudio` — P C · ✓ src=Vendor
- [x] **ChatWise** · `app.chatwise` — P C · ✓ src=Vendor
- [x] **Conductor** · `com.conductor.app` — P C · ✓ src=Vendor
- [x] **Postman** · `com.postmanlabs.mac` — P C (one-click) · ✓ src=Vendor
- [x] **AweSun** · `com.oray.sunlogin.macclient` — P C (one-click, WAF) · ✓ src=Vendor
- [x] [**VLC**](org-videolan-vlc.md) · `org.videolan.vlc` — P C (one-click, two-stage changelog) · ✓ src=Vendor · nightly 共享 bundle id，未签名 → **一键永久不可**，检测已可行（#93 已解决），尚未接 recipe（issue #95）
- [x] [**Docker**](com-docker-docker.md) · `com.docker.docker` — P C (one-click dmg) · ✓ src=Vendor · 外层 backend 拥有更新流程；嵌套 GUI 的 Squirrel 是闲置框架，不借给扫描器 · 2026-09-02
- [x] **Raycast** · `com.raycast.macos` — P · ✓ src=Vendor
- [x] **Alfred** · `com.runningwithcrayons.Alfred` — P · ✓ src=Vendor
- [x] **Shottr** · `cc.ffitch.shottr` — P · ✓ src=Vendor
- [x] **The Unarchiver** · `com.macpaw.site.theunarchiver` — P · ✓ src=Vendor
- [x] **Orion** · `com.kagi.kagimacOS` — P · ✓ src=Vendor
- [x] [**Dropbox**](com-getdropbox-dropbox.md) · `com.getdropbox.dropbox` — P (one-click dmg) · ✓ src=Vendor · **一键改取 `arch=arm64` 包**：不带参数的 dmg 是 x86_64-only，Apple silicon 上被架构闸拒 · 2026-09-14
- [x] **Plex** · `tv.plex.desktop` — P · ✓ src=Vendor
- [x] **Bartender** · `com.surteesstudios.Bartender` — P · ✓ src=Sparkle
- [x] **ImageOptim** · `net.pornel.ImageOptim` — P · ✓ src=Sparkle
- [x] [**LibreWolf**](net-librewolf-librewolf.md) · `net.librewolf.librewolf` — P · ✓ **修复 bundle id + 端点(GitLab→Codeberg)** · **detection-only（不可一键）**：dmg ad-hoc 签名/无 Developer ID/未公证，过不了签名闸（2026-07-03 实测）
- [x] **MacUpdater** · `com.corecode.MacUpdater` — P C · ✓ src=Vendor (upstream discontinued)
- [x] **IntelliJ IDEA** · `com.jetbrains.intellij` — P C (EAP via Toolbox) · ✓ src=Toolbox(managed)
- [x] **JetBrains Toolbox** · `com.jetbrains.toolbox` — P C (one-click) · ✓ src=Vendor · **一键接入 2026-07-03**（macM1 dmg 取 releases API，Team 2ZEFAR8TH3）· channel-verify 复验 ✓
- [x] **Android Studio** · `com.google.android.studio` — P · ✓ src=Toolbox(managed)
- [x] [**WeChat (微信 官网版)**](com-tencent-xinWeChat.md) · `com.tencent.xinWeChat` — P C (one-click dmg) · ✓ src=Vendor · 检测=公开 Sparkle appcast 截 3 段 marketing（4.1.10.53→4.1.10，不比 build）· changelog=官网 per-version 页 sourceTemplate · live smoke=up to date · 2026-06-16
- [x] [**Wispr Flow**](com-electron-wispr-flow.md) · `com.electron.wispr-flow` — P (one-click zip via `.versionTemplate`) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Granola**](com-granola-app.md) · `com.granola.app` — P (one-click universal dmg) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Longbridge Desktop（长桥桌面版）**](com-longbridge-app-desktop.md) · `com.longbridge.app.desktop` — P+C (stable + preview, one-click arm64 dmg) · changelog 读英文逐版本页 · stable + preview real DMGs verified ✓（preview 不是退役轨：独立 bundle `…desktop.preview`，recipe 活着，2026-09-14 复测 `1.0.0-preview.1`）· 2026-08-25
- [x] [**Comet**](ai-perplexity-comet.md) · `ai.perplexity.comet` — P (detection-only) · redirect version avoids stale rollout API · real DMG + live probe ✓ · 2026-08-17
- [x] [**Devin Desktop**](com-exafunction-windsurf.md) · `com.exafunction.windsurf` — P (one-click dmg via `.bodyPattern`) · former Windsurf bundle · real DMG + live probe ✓ · 2026-08-17
- [x] [**AionUi**](com-aionui-app.md) · `com.aionui.app` — P (detection-only) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Msty Studio**](MstyStudio.md) · `MstyStudio` — P (detection-only) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Grok Bot**](com-anysphere-sand.md) · `com.anysphere.sand` — P (one-click arm64 dmg, Team DCNK4UB866) · xAI 的产品但由 Anysphere 构建，走 Cursor 的更新基建（`api2.cursor.sh` / `downloads.cursor.com`），接口上的 app name 是 `sand` · asar 里的 nightly/dogfood 两轨客户端与服务端都不可达，故单 channel · 官网按钮那条无版本号、cask livecheck 那条最新时回 204，都不用 · 真实 DMG + live probe ✓ · 2026-08-29
- [x] [**TimeMachineEditor**](com-tclementdev-timemachineeditor-application.md) · `com.tclementdev.timemachineeditor.application` — P (one-click pkg, Team 68GTH78H6S) · cask `auto_updates:true` 被跳过，故 vendor 主页是唯一版本源 · 无 JSON API，读首页下载链接文字里的版本号，与 Homebrew 自己的 livecheck 独立印证 · pkg 装了 LaunchDaemon，故一键必须走 `.pkg` 而非 dmg/zip · 真实 pkg 展开验证 + live probe ✓ · 2026-08-29

- [x] [**搜狗输入法 (SogouInput)**](com-sogou-inputmethod-sogou.md) · `com.sogou.inputmethod.sogou` — P · 版本读**厂商自己的条件更新接口**（pin `v=0.0.0.1` 装成很旧的客户端去问；已验证不做分段升级，六个历史版本都答同一个最新版）· 返回的版本与 `CFBundleShortVersionString` 四段完全一致，无需任何裁剪 · 哨兵 `1.0.0.1` 由 `update_pack_url` 守卫挡掉 · 不发设备 hash · notes 走更新日志页 · detection-only（装机附带两个 LaunchAgent + QuickLook + 用户目录迁移；自更新 payload 另有 pre/post/switch 脚本）· 2026-08-28
- [x] [**豆包输入法 (DoubaoIme)**](com-bytedance-inputmethod-doubaoime.md) · `com.bytedance.inputmethod.doubaoime` — P+C · 比厂商 version code（装机侧在自定义键 `Wave Build Version Number`，CFBundleVersion 是废号 1）· changelog 走 app 自己的更新接口 · detection-only（输入法整类闸）· channel-verify ✓ · 2026-08-21
- [x] [**微信输入法 (WeType)**](com-tencent-inputmethod-wetype.md) · `com.tencent.inputmethod.wetype` — P+C · 读厂商安装器自己读的 InstallInfo manifest（此前抓的是**安装器壳的版本**，用错 namespace 不会失败、只会答错号）· **一键 ✓（2026-08-28 重新接入，Contents 轮换 + 用户数据快照）**——0.3.25 上线当天撤回的那条，证据链与复活理由都在文档里 · 真机红→绿 656→657 + 回滚实测 ✓（历史 payload 仍可取，用来造红）· 2026-08-28

- [x] [**WorkBuddy（国内站）**](com-workbuddy-workbuddy.md) · `com.workbuddy.workbuddy` — P (one-click) · 与国际站是两个独立 app，非 channel · 按架构分两条 recipe · 两站共用的端点/陷阱/一键闸写在这份 · 真实 DMG channel-verify ✓ · 2026-08-27
- [x] [**WorkBuddy AI（国际站）**](com-workbuddy-workbuddy-ai.md) · `com.workbuddy.workbuddy-ai` — P (one-click) · 按架构分两条 recipe · changelog 页滞后于自己的轨道（厂商侧）· 共用部分链到国内站那份 · 真实 DMG channel-verify ✓ · 2026-08-27
- [x] [**Canva**](com-canva-CanvaDesktop.md) · `com.canva.CanvaDesktop` — P (one-click, dmg + feed sha512) · Electron 套壳，端点取自 app 自带 `app-update.yml` · cask 是 `auto_updates` 且滞后一版 · beta 轨道 2024-11 起废弃，pattern 以数字点结尾拒读 · 真实 DMG + live probe + `duo check` 全链 ✓ · 2026-08-27
- [x] [**Little Snitch**](at-obdev-littlesnitch.md) · `at.obdev.littlesnitch` — P(stable/nightly) C(stable only) · 2 channels，共享 bundle id，channel 词烤进 `CFBundleShortVersionString`（`ReleaseChannel.detect()` 新增 0.7 步）· 端点是 Homebrew cask 自己 livecheck 也在用的 obdev 静态 feed，两 cask 均 `auto_updates` 故原本 `.unknown` · **detection-only**：网络防火墙 + System Extension，一键需要真机红→绿验证才能开 · 未装机审计，从官方 dmg 挂载验证 · 2026-08-29
- [x] [**Carbon Copy Cloner**](com-bombich-ccc.md) · `com.bombich.ccc` — P(CCC5/CCC6/CCC7 stable + CCC7 beta，均 detection-only) · **三个独立、仍可下载的大版本代际共用同一 bundle id**（真机核实），`?v=latest` 只给最新的 CCC7，跨代际比较会把 CCC5/6 用户导向一次付费大版本升级——修法是新增 `VendorProbeRecipe.installedVersionPattern`（`hostRequirement` 的对偶，锁定装机代际）+ `VendorProbeSource` 新增一道过滤，四条 recipe 各自独立 `variant` · 有 `SUFeedURL` 但两条(CCC7 自己的 + CCC5/6 共用的)都回空 body，Sparkle 静默失效；改读 cask 自带 livecheck 同款的 `download_ccc.php?v=<latest|ccc6|ccc5>` 重定向文件名 · cask 是 `auto_updates` · beta 用 `?v=latestbeta`（无连字符，2026-08-29 补齐）· channel 信号是版本串 `-b<N>` 短后缀，`ReleaseChannel.detect()` 新增 step 0.8 · 2026-08-29
- [x] [**Windscribe**](com-windscribe-client.md) · `com.windscribe.client`（**不是 cask 写的 `com.windscribe.gui.macos`**）— P(stable/beta/guinea pig) C B · 3 channels，共享 bundle id + `ChannelBinding` · 渠道读的是被 **SimpleCrypt 加密**的 `engineSettings.updateChannel`——密钥是厂商开源仓库里的明文常量，字段排在流的第 4 位、在所有 version 分支之前（真实 plist 对齐，三个取值全验过；当场抓出 qChecksum 写成了 Qt4 版本，往返测试结构上抓不到）· 三轨是**成熟度阶梯**不是平行列车（官方文档 + feed 回放确认），所以 beta recipe 读 `beta:[01]`、gp 读 `[0-2]` 再 `selectHighest` 取 max · stable 走更小的 `ChangeLogs/summary` · 一键**结构性拒绝**（dmg 里只有安装器壳，安装要写 LaunchDaemon + 特权 helper + system extension）· changelog 三轨各一条（非 stable 带 `includesPromotedStable`，正是阶梯语义）——代价是 GitHub 分不出 beta 与 guinea pig，面板会多列另一轨和未公告的构建，已钉成断言 · 五份真实构建 + 真机全链验证 ✓ · 2026-09-07

## Single-channel — GitHub Releases

- [x] **RustDesk** · `com.carriez.rustdesk` — G C (one-click) · ✓ src=GitHub
- [x] **GitHub Desktop** · `com.github.GitHubClient` — G · ✓ src=GitHub
- [x] **Stats** · `eu.exelban.Stats` — G (one-click) · ✓ src=GitHub · [audit](eu-exelban-Stats.md)
- [x] **DBeaver** · `org.jkiss.dbeaver.core.product` — G · ✓ src=GitHub
- [x] **Beekeeper Studio** · `io.beekeeperstudio.desktop` — G · ✓ src=GitHub
- [x] [**KeePassXC**](org-keepassxc-keepassxc.md) · `org.keepassxc.keepassxc` — G (one-click) · ✓ src=GitHub · snapshot 共享 bundle id，完全无签名 → **一键永久不可**，检测已可行（#93 已解决），尚未接 recipe（issue #95）
- [x] [**Insomnia**](com-insomnia-app.md) · `com.insomnia.app` — G C (one-click) · ✓ src=GitHub · changelog=insomnia.rest(`__NEXT_DATA__` JSON) · 修 stable 跨渠道误推（pattern 加 `$` 锚，2026-06-06）· beta 的 `-beta.N` 已可识别但尚未接 rule；alpha 仍受阻
- [x] **Pearcleaner** · `com.alienator88.Pearcleaner` — G · ✓ src=GitHub
- [x] [**OpenLogi**](org-openlogi-openlogi.md) · `org.openlogi.openlogi` — G (**一键 arm64 dmg**) · Homebrew `auto_updates:true` 会让位 · **端到端验过**：装 0.8.2 → 一键到 0.8.3 ✓ · ⚠️ 包无 stapled ticket（厂商习惯，闸不查装订）、`CFBundleVersion` 是时间戳（远端 build 恒 nil，只比 marketing）· 2026-09-03
- [x] **Macs Fan Control** · `com.crystalidea.macsfancontrol` — G · ✓ src=GitHub
- [x] **Alcove** · `com.henrikruscon.Alcove` — P(stable, detection-only) · ✓ src=Vendor `download.tryalcove.com/latest`（GitHub 镜像滞后已删；`update.tryalcove.com` 2026-07-29 起 NXDOMAIN，recipe 已改指 `/latest`）· 公开下载是滞后的 trial 构建（metadata 1.7.9 时 dmg 仍 1.7.7）故**不给一键** · 授权用户走 `AlcoveUpdateSource`（changelog + published_at + 一键）· 2026-07-29
- [ ] **Zen Browser** · `app.zen-browser.zen` — G C · (not installed; prerelease-tag channel, not a pure single-channel sweep target)
- [x] [**OpenCode Desktop**](ai-opencode-desktop.md) · `ai.opencode.desktop` — G C (one-click, native arch dmg) · real DMG verified ✓ · 2026-08-17
- [x] [**OpenChamber**](dev-openchamber-desktop.md) · `dev.openchamber.desktop` — G (one-click, native arch dmg) · real DMG verified ✓ · 2026-08-17
- [x] [**Jan**](jan-ai-app.md) · `jan.ai.app` — G (one-click universal zip) · real app verified ✓ · 2026-08-17
- [x] [**ChatGPT Classic**](com-openai-chat.md) · `com.openai.chat` — P (**detection-only**) · 真包 1.2026.184 挂载验证 ✓ · 一键**撤销**：vendor pkg 不声明任何 `.app` 目的地，`PackageInstaller` 的目的地闸 fail-closed 必拒；且其 postinstall 会把 app 搬到 `/Applications/ChatGPT Classic.app` 并自行重启 · **也没有 changelog**：appcast 的 `<description>` 是厂商推广新版 ChatGPT 的文案，不是发布说明 · 2026-09-03
- [x] [**Microsoft 365 Copilot**](com-microsoft-m365copilot.md) · `com.microsoft.m365copilot` — P (one-click pkg, versionIsBuild) · 真包 pkg 展开验证 ✓（short `1.2608` / build `1.2608.0301`，payload 含 `com.microsoft.autoupdate`）· **无 changelog**：learn.microsoft 的 release-notes 页按日期×产品组织，全页 `1.2608` 出现 0 次 · 2026-09-03
- [x] [**Qoder IDE**](com-qoder-ide.md) · `com.qoder.ide` — P C (one-click arm64 zip) · VS Code fork，走 VS Code 更新协议（`center.qoder.sh/algo`），**端点是条件式的**（当前 commit → 204 空 body），故用 `latest` 哨兵 · 真包 1.28.0 解包验证 ✓（Team T27K5A5ZWD）· changelog 走 docs 站（正则匹到 108 条，面板按 `maxEntries` 默认显示 40 条），**不用** `qoder.com/changelog`（RSC payload 混了所有产品和两种语言）· 2026-09-06
- [x] [**Qoder**](com-qoder-app.md) · `com.qoder.app` — P C (one-click arm64 zip) · **与 Qoder IDE 是两个 app，不是改名**（官方论坛证实并存），Team 也不同（B6U242QL73）· 版本读厂商自己的 `manifest.json` · 一键装的是不套壳的 `Qoder-mac-arm64.zip`，不是下载页给人的 installer 壳 · changelog 与 IDE 共用一个 entry pattern（同一套 docs 构建）· 2026-09-06
- [x] [**WhatCable**](uk-whatcable-whatcable.md) · `uk.whatcable.whatcable` — G(stable/beta，两轨一键 zip) · 共享 bundle id **和资产名**（两轨都叫 `WhatCable.zip`），beta 由版本后缀 `-beta.N` 分流；beta rule **也收 stable tag**（毕业版 + 防「厂商停发 beta 就永久红」），所以 channel proof 锚的是请求（`usePrereleases` + `versionPattern`）而不是 artifact · 真包 1.4.0 + 1.5.0-beta.8 解包验证 ✓（Team M4RUJ7W6MP）· changelog 走 GitHub release body，无需 recipe · app 内 `receiveBetaUpdates` 开关未读，缺口记在 CHANNEL_COVERAGE_TODO §2b · 2026-09-06
- [x] [**Cline Desktop**](bot-cline-app.md) · `bot.cline.app` — P(stable/beta，两轨一键 `.app.tar.gz`) · **两轨是两个独立 bundle id**（beta = `bot.cline.app.beta`），pattern A，无需 ChannelBinding · 端点是 Tauri updater 的 `latest.json`，**地址由各轨二进制的 `strings` 证明**（`desktop-latest` / `desktop-beta` 两个滚动 tag）· **不走 GitHub 源**：`cline/cline` 单仓四产品，`/releases/latest` 会翻到别的产品，列表端点无 `Last-Modified`，且 beta 轨周期性停更 · changelog 走 GitHub release body，新增 `tagPattern` 把另外三条产品线挡掉（不挡会多出 20 条外来条目）· 两轨真包下载解包验证 ✓（Team 6F2AYU54ZH，notarized，universal）· 2026-09-12
- [x] [**Yaak**](app-yaak-desktop.md) · `app.yaak.desktop` — G(stable/beta，两轨一键 arm64 dmg) · 共享 bundle id，beta 由版本后缀 `-beta.N` 分流（`detect` 第 4 步），两轨各自锚死资产名 · changelog 走 GitHub release body 的结构化解码，两轨分开 · ⚠️ 厂商 2025-11-11 改过 macOS 资产名（此前是 `_aarch64_darwin.dmg`），最新 100 条里最老的 8 条是旧名，现有 pattern 不收——按新旧边界钉在用例里 · 2026-09-06
- [x] [**Chatbox**](xyz-chatboxapp-app.md) · `xyz.chatboxapp.app` — P (one-click arm64 dmg + feed sha512) · **端到端验过**：装 1.22.6 → 一键到 1.23.1，日志里 `verifyingSignature` 证明 sha512 闸真的跑了 ✓ · **已接 changelog**（厂商 changelog 页，30 条，验过不吃 download 链接）· 2026-09-03
- [x] [**AnythingLLM**](com-anythingllm.md) · `com.anythingllm` — P (one-click arm64 dmg) · 真包 1.16.1 挂载验证 ✓ · **已接 changelog**（GitHub releases，`version.txt` 与 tag 同号；`docs.anythingllm.com/changelog` 404 不是源）· 2026-09-03
- [x] [**T3 Code**](com-t3tools-t3code.md) · `com.t3tools.t3code` — G(alpha/nightly) · 2 channels，共享 bundle id，app 名渠道词 + GitHub 双 rule · **两轨一键 ✓**（Team ARK85ZXQ4Z，真包挂载验证）· 2026-08-30 · 仓库出现了未覆盖的 `-preview.` 发布系列（tag 自 2026-09-12、release 自 2026-09-13；2026-09-14 复测）
- [x] [**Kun**](com-xingyuzhong-deepseekgui.md) · `com.xingyuzhong.deepseekgui` — G (one-click arm64 dmg) · 真包 v0.3.7 挂载验证 ✓ · 2026-08-30
- [x] [**DSH Desktop**](ai-deepseek-dsh-desktop.md) · `ai.deepseek.dsh.desktop` — G (one-click universal dmg) · 真包 v2.0.4 挂载验证 ✓ · 2026-08-30
- [x] [**Meetily**](com-meetily-ai.md) · `com.meetily.ai` — G (one-click arm64 dmg) · 真包 v0.4.0 挂载验证 ✓ · 2026-08-30
- [x] [**Paseo**](sh-paseo-desktop.md) · `sh.paseo.desktop` — G (one-click arm64 dmg) · 真包 v0.6.1 挂载验证 ✓（beta 是 prerelease 轨，未接入）· 2026-08-30
- [x] [**OpenSuperWhisper**](ru-starmel-OpenSuperWhisper.md) · `ru.starmel.OpenSuperWhisper` — G (one-click arm64 dmg) · 真包 0.1.0 挂载验证 ✓ · 2026-08-30
- [x] [**AgentsView**](io-agentsview-desktop.md) · `io.agentsview.desktop` — G (one-click arm64 dmg) · 真包 v0.41.1 挂载验证 ✓ · 2026-08-30
- [x] [**GitHub Copilot**](com-github-githubapp.md) · `com.github.githubapp` — G (one-click arm64 dmg) · 真包 v1.1.14 挂载验证 ✓ · 2026-08-30
- [x] [**FluidVoice**](com-FluidApp-app.md) · `com.FluidApp.app` — G (one-click universal dmg) · 真包 v1.6.9 挂载验证 ✓ · 2026-08-30
- [x] [**Helium**](net-imput-helium.md) · `net.imput.helium` — G (one-click arm64 dmg) · 真包 0.16.2.1 挂载验证 ✓ · **已改走 vendor 自己的 appcast**（`SparkleFeedCatalog` 补 feed 地址——包里没有 `SUFeedURL`，Sparkle 嵌在 Chromium framework 里）：stable+beta 两轨 + delta（40MB vs 124MB 全量），渠道由装机 build 在 feed 里反查得出、不读厂商偏好；GitHub rule 留作兜底。changelog 因此改走 catalog 兜底页 · 2026-08-31
- [x] [**Claude Status Bar**](com-local-claudestatusbar.md) · `com.local.claudestatusbar` — G (one-click dmg) · 真包 v0.4.4 挂载验证 ✓ · 有一个孤立 prerelease tag `v0.4.0-beta.1`，**决定不接** · 2026-08-31
- [x] [**claude-devtools**](com-claudecode-context.md) · `com.claudecode.context` — G (one-click arm64 dmg) · 真包 v0.5.0 挂载验证 ✓（GitHub 胜、up to date、release 正文即 changelog；`v0.4.13` 其实是 prerelease，原文说「全部非 prerelease」有误）· 2026-08-31
- [x] [**Ollama**](com-electron-ollama.md) · `com.electron.ollama` — C + G (one-click zip, best-effort)

## Changelog-only (detection via Sparkle or Homebrew)

- [x] [**Ghostty**](com-mitchellh-ghostty.md) · `com.mitchellh.ghostty` — C (two-stage), detection still unknown
- [x] [**AppCleaner**](net-freemacsoft-AppCleaner.md) · `net.freemacsoft.AppCleaner` — C + Sparkle verified
- [x] [**Calibre**](net-kovidgoyal-calibre.md) · `net.kovidgoyal.calibre` — C + Homebrew
- [x] [**Audacity**](org-audacityteam-audacity.md) · `org.audacityteam.audacity` — C + Homebrew
- [x] [**Homebrew (BrewUI)**](sh-brew-app.md) · `sh.brew.app` — C (GitHub releases) + Homebrew cask `homebrew-app` · GUI 版本独立于 brew，`brew update` 不升级它 · 运行中一键升级 + Relaunch 实测 ✓ · 2026-09-13
- [x] [**Blender**](org-blenderfoundation-blender.md) · `org.blenderfoundation.blender` — C (version-pinned) + Homebrew
- [x] [**JetBrains Air**](com-jetbrains-air.md) · `com.jetbrains.air` — C + Toolbox/Sparkle
- [x] [**欧路词典 (Eudic)**](com-eusoft-eudic.md) · `com.eusoft.eudic` — C + Sparkle **1**.27.3 · recipe 的 `source` 就是 appcast 本身：整部历史（1 个 `<h2>` + 34 个 `<h3>`、0 个 `<li>`）塞在最新一条 item 的 `<description>` 里，原本十六年记录全挂在「26.9.0」标题下；34 个标题里 7 个是标签「更新内容」，故按"含点分数字的标题"切而非按标签 · live feed + fixture 双证 29 条 ✓ · 另记两个已修的坑：`CFBundleDisplayName` 是**空串**（行里没名字）、未登录时的登录 sheet 挡住退出（Relaunch 静默失败）· 2026-09-01
- [x] [**Rockxy**](com-amunx-rockxy-community.md) · `com.amunx.rockxy.community` — C + Sparkle verified · appcast 是原地重写的单条文件（1 个 `<item>`），inline notes 只够一格版本轨，故 changelog 走 GitHub releases（40/40 解析，0 prerelease）· 只有一条轨：prod 与 staging 两个 xcconfig 指向同一个 feed、同一个 bundle id · 2026-09-09

## Electron-covered (auto-detected via the bundle's `app-update.yml`, no version recipe)

- [x] [**Kimi**](com-moonshot-kimichat.md) · `com.moonshot.kimichat` — C · 检测走 ElectronManifestSource · manifest 要带 `noCache` 查询串才过得了 CDN 边缘副本 · 官网 DMG 是安装器 · 2026-09-11

## Sparkle-covered (auto-detected, no custom recipe)

- [x] [**iTerm2**](com-googlecode-iterm2.md) · `com.googlecode.iterm2` — S
- [x] [**Arc**](company-thebrowser-Browser.md) · `company.thebrowser.Browser` — S
- [x] [**Rectangle**](com-knollsoft-Rectangle.md) · `com.knollsoft.Rectangle` — S
- [x] [**IINA**](com-colliderli-iina.md) · `com.colliderli.iina` — S
- [x] [**Proxyman**](com-proxyman-NSProxy.md) · `com.proxyman.NSProxy` — S
- [x] [**MonitorControl**](app-monitorcontrol-MonitorControl.md) · `app.monitorcontrol.MonitorControl` — S
- [x] [**Maccy**](org-p0deje-Maccy.md) · `org.p0deje.Maccy` — S
- [ ] [**Keka**](com-aone-keka.md) · `com.aone.keka` — S, needs download verification
- [x] [**Vivaldi**](com-vivaldi-Vivaldi.md) · `com.vivaldi.Vivaldi` — S
- [ ] [**OBS**](com-obsproject-obs-studio.md) · `com.obsproject.obs-studio` — S, needs download verification
- [x] [**HandBrake**](fr-handbrake-HandBrake.md) · `fr.handbrake.HandBrake` — S
- [x] [**Typeless**](now-typeless-desktop.md) · `now.typeless.desktop` — P+C · electron-builder feed (VendorProbe) · 一键 dmg + sha512 · 结构化 changelog（gzip __NEXT_DATA__，含图）· channel-verify ✓ · 2026-06-19
- [x] [**OpenClaw**](ai-openclaw-mac.md) · `ai.openclaw.mac` — S · real DMG/feed verified ✓ · 2026-08-17
- [x] [**Superwhisper**](com-superduper-superwhisper.md) · `com.superduper.superwhisper` — S · real zip/feed verified ✓ · 2026-08-17
- [x] [**Dia Browser**](company-thebrowser-dia.md) · `company.thebrowser.dia` — S · real DMG/feed verified ✓ · 2026-08-17
- [x] [**CodexBar**](com-steipete-codexbar.md) · `com.steipete.codexbar` — S · 真包 v0.56.1 验证 ✓（SUFeedURL 指向 repo 内 appcast.xml；ChangelogCatalog 已有 GitHub 兜底条目）· 2026-08-30
- [x] [**ClaudeBar**](com-tddworks-claudebar.md) · `com.tddworks.claudebar` — S · 真包 v0.4.85 解包验证 ✓ · 2026-08-30
- [x] [**VoiceInk**](com-prakashjoshipax-VoiceInk.md) · `com.prakashjoshipax.VoiceInk` — S · 真包 v2.13 挂载验证 ✓ · 2026-08-30
- [x] [**Mac Performance Monitor**](uk-co-bzwrd-macperfmonitor.md) · `uk.co.bzwrd.macperfmonitor` — S(stable) C · 检测本来就通（bundle 自带 `SUFeedURL`，指向 release 资产）· **appcast 一条说明都没有**（无 `releaseNotesLink`/`fullReleaseNotesLink`/`description`），release 正文只有一句"See CHANGELOG.md"，已加 recipe 解仓库的 Keep-a-Changelog 文件（17 条，`[Unreleased]` 排除）· 用户报 #374 · 未验真包 · 2026-09-06
- [x] [**GitHub Copilot for Xcode**](com-github-CopilotForXcode.md) · `com.github.CopilotForXcode` — S(stable+prerelease) C · 两轨 tag 过、共享 bundle id · **两轨真包验证 ✓**（stable 0.51.0 未被推 prerelease；prerelease 0.51.182 留在本轨）· feed 与 release 正文都无实质说明，已加 recipe 解 repo 的 `CHANGELOG.md`（21 条）· 2026-08-31
- [x] [**MacWhisper**](com-goodsnooze-MacWhisper.md) · `com.goodsnooze.MacWhisper` — S C · 真包 14.8 解包验证 ✓ · feed 全无 inline，只有 `releaseNotesLink`，当前条目共用同一张**不分版本**的总页（2026-09-14：211 条里 179 条，含最新）；已加 recipe 解那张页（121 条）· ⚠️ `api.whispertranscribe.com` 是另一个 app · 2026-08-31
- [x] [**ChatGPT Atlas**](com-openai-atlas.md) · `com.openai.atlas` — S · ⚠️ **已停产**（OpenAI 2026-08-09 停止运行，feed 停在 1.2026.189.1）· 真包挂载验证 ✓ · 原审计误称「无 delta」，实测 head 条目 5 个 `<sparkle:deltas>`；无 changelog · 2026-08-31
- [x] [**Perplexity**](ai-perplexity-macv3.md) · `ai.perplexity.macv3` — S · 真包 26.34.0 挂载验证 ✓（公证已恢复，一键可用）· ⚠️ **无 changelog**（feed 无 inline；docs.perplexity.ai 那份是 API 的，不是桌面端）· 2026-08-31
- [x] [**TypeWhisper**](com-typewhisper-mac.md) · `com.typewhisper.mac` — S(stable+rc+daily) C · 三轨 tag 过、共享 bundle id · 真包 1.6.0/rc2/daily 三轨验证 ✓ · **rc 轨当时被判成 stable**（rc 包 short 也是 `1.6.0`），引擎已修 + 装 rc2 上机复验 · changelog 走官网 recipe（feed 无 inline；页面 mac/Windows 混排，须锚平台徽章）· 2026-08-31
- [x] [**OpenUsage**](com-robinebers-openusage.md) · `com.robinebers.openusage` — S(stable+beta) C · 真包 v0.7.10 挂载验证 ✓（beta 显式 channel tag，beta 包实测正确升 stable）· **feed 51 条全无 `<description>`**，changelog 走 `ChangelogCatalog` 兜底到 GitHub releases（2026-08-31 补）· 2026-08-31
- [x] [**Supacode**](app-supabit-supacode.md) · `app.supabit.supacode` — S · default+tip 两轨真包验证 ✓（tip 经 build 反查推断，零 recipe）· **2026-08-31 复验发现 tip 轨当时被判成 default**（tip 包 short 与 default 条目同为 `0.10.8`，渠道推断按文档序先撞上 short），引擎已修为两趟匹配；tip 条目本身无 changelog · 2026-08-31
- [x] [**PDF Expert**](com-readdle-PDFExpert-Mac.md) · `com.readdle.PDFExpert-Mac` — S C · ⚠️ bundle 的 `SUFeedURL` 指着一份 **2022 年冻结**的 feed（build 764），其中一条没有 `maximumSystemVersion`，于是通用 Sparkle 源在现代 Mac 上读到 2.5.22 并判「已是最新」——零报错、cask 又是 `auto_updates` 无人兜底，这个 app 一直是隐形的。新增 `SparkleFeedCatalog.supersededFeeds` 按**死地址**（不是 bundle id）换到 pem3 feed；判据是 pem3 的 `edSignature` 用装机 bundle 自己的 `SUPublicEDKey` 验签通过 ✓。changelog 走 recipe 解 `fullReleaseNotesLink` 那张页（88 条，appcast 那份只有最新一版）· **一键真机端到端 ✓**（降到官方 3.13.1 再让引擎装回 3.13.2，走的是 781 KB 增量包而非 128 MB 全量，签名/公证/回滚点全绿）· 2026-09-04
- [x] [**CodeEdit**](app-codeedit-CodeEdit.md) · `app.codeedit.CodeEdit` — S · 每个 release 的 appcast 只有一条、且都打 `dev` tag（没有默认 channel），落后一版的副本会读成 unknown；加常量 `ChannelBinding` 放行 `dev` · 真包 v0.3.6 挂载验证 ✓ · 2026-09-12
- [x] [**coconutBattery**](com-coconut-flavour-coconutBattery.md) · `com.coconut-flavour.coconutBattery` — S · cask 是 `auto_updates`（Homebrew 让位），Sparkle 排在前面先应答 · 签名 feed，通用一键 ✓ · 真包 4.4.0 验证 ✓ · 2026-09-14 feed 无 beta 条目（08-29 有），beta needs-verify · 2026-09-14 复核
- [x] [**DaisyDisk**](com-daisydiskapp-DaisyDiskStandAlone.md) · `com.daisydiskapp.DaisyDiskStandAlone` — S · MAS 副本 `com.daisydiskapp.DaisyDisk` 由 App Store 通用覆盖 · cask `auto_updates` 不影响，Sparkle 先应答 · 无 EdDSA（只有 DSA），通用一键 ✓（code signature + Team 闸）· 真包 4.34.2 验证 ✓ · 2026-09-14 复核

## Investigated — blocked safely

- [x] [**CotEditor**](com-coteditor-CotEditor.md) · `com.coteditor.CotEditor` — P(stable/beta) B · **两轨全接（GitHub 两条规则 + ChannelBinding，一键 ✓，Team HT3Z3A72WZ 两轨真包核对）**；appcast **故意不读**——它只留一个预发布名额，旧 beta 副本找不到自己会被推 `7.0.9` 这个 marketing 降级包（守卫见 #368），换 GitHub 后渠道由 tag 和 `checksUpdatesForBeta` 决定，盲区消失 · 2026-09-06
- [x] [**TRAE**](com-trae-app.md) · `com.trae.app` — official API `2.3.61406` != real app `3.5.81`; no comparable remote version, deliberately left unknown · 2026-08-17
- [x] [**macFUSE**](io-macfuse-preferencepanes-macfuse.md) · `io.macfuse.preferencepanes.macfuse` — 装的是 `.prefPane` + `/Library/Filesystems/macfuse.fs`（嵌套的 `macfuse.app` 自报 `1.0`），都不在 `AppScanner` 的扫描目录里；GitHub 侧可行但接不到检查，是扫描模型的缺口不是 recipe 缺口 · 2026-09-14 复核

## 未编入分类（补录 2026-08-30）

这些审计文档早已存在但没有出现在本索引里，`scripts/check_app_audits.py` 上线时发现。

- [x] [**Amp**](com-ampcode-amp-macos.md) · `com.ampcode.amp.macos` — marketing 长期恒 `1.0`，只有 build 走动
- [x] [**百度网盘**](com-baidu-BaiduNetdisk-mac.md) · `com.baidu.BaiduNetdisk-mac`
- [x] [**Raycast**](com-raycast-macos.md) · `com.raycast.macos` — `CFBundleVersion = 0`，不可用作比较
- [x] [**QQ音乐**](com-tencent-QQMusicMac.md) · `com.tencent.QQMusicMac`
- [x] [**VSCodium Insiders**](com-vscodium-VSCodiumInsiders.md) · `com.vscodium.VSCodiumInsiders`

## 仅迁出历史（未审计）

从 recipe 注释迁出历史、但覆盖情况没审过的 family（格式见上面「从 recipe 注释迁出的历史」）。
这一节的条目**永远是 `- [ ]`**；真审计之后挪到对应分类再打勾。

- [ ] [**LM Studio**](ai-elementlabs-lmstudio.md) · `ai.elementlabs.lmstudio` — 仅迁出历史：`/changelog` 根路径改给 Bionic 的记录
- [ ] [**MarkEdit**](app-cyan-markedit.md) · `app.cyan.markedit` — 仅迁出历史：universal 与 `-apple-silicon` 两个 dmg 的核对
- [ ] [**ChatWise**](app-chatwise.md) · `app.chatwise` — 仅迁出历史：changelog 页 SvelteKit 壳的大小
- [ ] [**Zen Browser**](app-zen-browser-zen.md) · `app.zen-browser.zen` — 仅迁出历史：一键 dmg 的签名核对
- [ ] [**Shottr**](cc-ffitch-shottr.md) · `cc.ffitch.shottr` — 仅迁出历史：`latestVersion` 当时的值
- [ ] [**1Password**](com-1password-1password.md) · `com.1password.1password` — 仅迁出历史：一键 zip 的下载核对
- [ ] [**Pearcleaner**](com-alienator88-Pearcleaner.md) · `com.alienator88.Pearcleaner` — 仅迁出历史：一键 dmg 的签名核对
- [ ] [**Claude Desktop**](com-anthropic-claudefordesktop.md) · `com.anthropic.claudefordesktop` — 仅迁出历史：2026-08-15 灰度发布与 device id 分桶
- [ ] [**Xcode**](com-apple-dt-Xcode.md) · `com.apple.dt.Xcode` — 仅迁出历史：release notes SPA 壳
- [ ] [**Bitwarden**](com-bitwarden-desktop.md) · `com.bitwarden.desktop` — 仅迁出历史：monorepo 里 `desktop-v` tag 间隔的测量
- [ ] [**Brave Browser Beta / Nightly**](com-brave-Browser.md) · `com.brave.Browser.beta` / `com.brave.Browser.nightly` — 仅迁出历史：arm64 appcast 的签名核对
- [ ] [**MacUpdater**](com-corecode-MacUpdater.md) · `com.corecode.MacUpdater` — 仅迁出历史：一键 dmg 的签名核对
- [ ] [**Macs Fan Control**](com-crystalidea-macsfancontrol.md) · `com.crystalidea.macsfancontrol` — 仅迁出历史：一键 zip 的签名核对
- [ ] [**Things 3**](com-culturedcode-ThingsMac.md) · `com.culturedcode.ThingsMac` — 仅迁出历史：App Store 探测用例的上线核对
- [ ] [**Hidden Bar**](com-dwarvesv-minimalbar.md) · `com.dwarvesv.minimalbar` — 仅迁出历史：空 Sparkle feed 的抓取与一键 zip 核对
- [ ] [**Goose**](com-electron-goose.md) · `com.electron.goose` — 仅迁出历史：repo 改名导致匿名限流的测量
- [ ] [**GitHub Desktop**](com-github-GitHubClient.md) · `com.github.GitHubClient` — 仅迁出历史：两轨 zip 的签名核对、beta `listPageSize` 的测量
- [ ] [**Android Studio**](com-google-android-studio.md) · `com.google.android.studio` — 仅迁出历史：预览渠道旧实现的错误、按发布日期排序的实例
- [ ] [**Antigravity / Antigravity IDE**](com-google-antigravity.md) · `com.google.antigravity` / `com.google.antigravity-ide` — 仅迁出历史：端点的发现、IDE 端点的哨兵测量、changelog 页的 gzip 误读
- [ ] [**Gemini**](com-google-GeminiMacOS.md) · `com.google.GeminiMacOS` — 仅迁出历史：Omaha 版本方案核对、release-notes 页不对应
- [ ] [**Alcove**](com-henrikruscon-Alcove.md) · `com.henrikruscon.Alcove` — 仅迁出历史：旧端点 NXDOMAIN、公开 trial 包滞后、changelog 网页的旧形态
- [ ] [**IntelliJ IDEA**](com-jetbrains-intellij.md) · `com.jetbrains.intellij` — 仅迁出历史：版本段数被钉死时的故障
- [ ] [**The Unarchiver**](com-macpaw-site-theunarchiver.md) · `com.macpaw.site.theunarchiver` — 仅迁出历史：一键 zip 的签名核对
- [ ] [**Headlamp**](com-microsoft-Headlamp.md) · `com.microsoft.Headlamp` — 仅迁出历史：changelog 条目符号与计数的测量、repo 改名
- [ ] [**Microsoft OneNote**](com-microsoft-onenote-mac.md) · `com.microsoft.onenote.mac` — 仅迁出历史：套件 pkg 与独立 pkg 的解析核对
- [ ] [**Microsoft Outlook**](com-microsoft-Outlook.md) · `com.microsoft.Outlook` — 仅迁出历史：一键修复经过与 MAU 各 payload 的测量
- [ ] [**VS Code**](com-microsoft-VSCode.md) · `com.microsoft.VSCode` — 仅迁出历史：release 页加 blockquote 导致的回退
- [ ] [**MongoDB Compass**](com-mongodb-compass.md) · `com.mongodb.compass` — 仅迁出历史：download-center JSON 与挂载 dmg 的核对
- [ ] [**UURemote（网易UU远程）**](com-netease-uuremote.md) · `com.netease.uuremote` — 仅迁出历史：一键 pkg 的签名核对、changelog 页的排查
- [ ] [**ChatGPT（原 Codex 桌面端）**](com-openai-codex.md) · `com.openai.codex` — 仅迁出历史：静态 feed 与灰度端点不一致、`plan_type` 两条轨的测量
- [ ] [**Opera**](com-operasoftware-Opera.md) · `com.operasoftware.Opera` — 仅迁出历史：挂载 dmg 的版本方案核对
- [ ] [**AweSun**](com-oray-sunlogin-macclient.md) · `com.oray.sunlogin.macclient` — 仅迁出历史：changelog 接口「50 bytes」的复查
- [ ] [**AnyDesk**](com-philandro-anydesk.md) · `com.philandro.anydesk` — 仅迁出历史：一键 dmg 的签名核对、各平台版本号
- [ ] [**Postman**](com-postmanlabs-mac.md) · `com.postmanlabs.mac` — 仅迁出历史：旧正则截断条目的计数
- [ ] [**PureMac**](com-puremac-app.md) · `com.puremac.app` — 仅迁出历史：`cli-v1.0.0` tag 被读成版本号
- [ ] [**Alfred**](com-runningwithcrayons-Alfred.md) · `com.runningwithcrayons.Alfred` — 仅迁出历史：一键 tarball 的核对
- [ ] [**Shotbase**](com-shotbase-app.md) · `com.shotbase.app` — 仅迁出历史：appcast 条目数
- [ ] [**Spotify**](com-spotify-client.md) · `com.spotify.client` — 仅迁出历史：stub 安装器版本与 cask 的比较、changelog 的排查
- [ ] [**Sublime Merge**](com-sublimemerge.md) · `com.sublimemerge` — 仅迁出历史：一键 zip 的签名核对
- [ ] [**Sublime Text**](com-sublimetext-4.md) · `com.sublimetext.4` — 仅迁出历史：一键 zip 的签名核对
- [ ] [**Bartender**](com-surteesstudios-Bartender.md) · `com.surteesstudios.Bartender` — 仅迁出历史：bundle 的 `SUFeedURL`、一键 zip 的签名核对
- [ ] [**Telegram Desktop**](com-tdesktop-Telegram.md) · `com.tdesktop.Telegram` — 仅迁出历史：两次挂载 dmg 的核对、文件名改名的时间线
- [ ] [**VSCodium**](com-vscodium.md) · `com.vscodium` — family 占位：stable 未审计，尚无迁出内容；同 family 的 Insiders 已审计（见上「未编入分类」）

## 非 app 文档

- [Issue #111 — Sparkle appcast channel population](issue-111-appcast-channel-population.md) ·
  一次性测量任务的产出，不是 app 审计。留在此目录是历史原因。
