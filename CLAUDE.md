# DuoUpdater — 给 agent 的工作须知

结构、渠道优先级、安装安全策略见 `README.md`,不在这里重复。这份文件只写"做事的规矩"。

## 说完成之前必须跑的验证

```sh
make test           # DuoUpdaterCore + CLI 两个包的 swift test(部分用例走网络)
```

改动碰到 recipe / 解析规则时,单元测试不够,必须再打真实端点:

```sh
duo verify --samples --report verify/report.json --baseline verify/baseline.json
duo verify --only <bundle-id-片段>        # 只验一个,快
```

规矩:

- **编译通过不算验证。** 说"修好了 / 可以提交了"之前贴出实际命令和结果。
- 修 recipe 要先复现红:拿到坏掉的原始响应体(`--samples`),确认新规则在**那份真实响应**上过,再跑全量。
- 新增/改 recipe **必须补一条回归测试**,而且用例要**从 registry 推导、覆盖全部 channel**,不要手写一份会漂移的清单(`RecipeHealthTests` / `RecipeVerificationTests` 是既有范式)。
- 全量 `duo verify` 约 150 个请求 / 3 分钟,别为了省时间只验一个就宣布全绿。
- **`make test` 本机一轮约 25 MB / 20 秒**,那道真下厂商包的闸默认关着(`DUO_DOWNLOAD_GATE`,
  见「发布」和「CI」两节)。想在本机过一遍就 `DUO_DOWNLOAD_GATE=1 make test`,约 185 MB。
- **卡住的时候用 `scripts/run-with-hang-report.sh 1800 make test`**,超时会抓线程栈再杀树
  ——ci.yml 就是这么跑的。为什么必须在进程外面,见「CI」那节。

## 行状态:两个界面读同一份,改渲染要跑 gallery

popover 和工作台是同一份数据的两个视图(工作台 = 放大版 popover + changelog),所以
**一行"现在是什么状态"只能有一个答案**:`RowAction.state`(Core),两边都经
`AppListModel.rowState(for:)` 读它,视图只决定怎么画。`ui = f(state)`。

以前不是这样,两边各有一条 `if/else if` 阶梯,顺序和覆盖面都不同,已经漂出两个真问题:

- **顺序不同**:popover 先判 `awaitingQuitConfirm`、后判安装阶段,工作台反过来。App Store
  安装等用户退出 app 时两者同时为真(`requestQuit` 的注释自己写了,安装仍占着
  `installing`),于是同一行 popover 显示退出确认、工作台显示进度条。
- **覆盖面不同**:`.error`、`.unknown`、三种 managed、ignored、skipped、justUpdated 在工作台
  **一个分支都没有**,直接渲染成空白——和"已经最新"长得一样,而这个窗口对有更新的行是给
  Update 按钮的,所以"空白"被读成"没事"。检查失败因此在工作台完全不可见。

规矩:

- **两个窗口的动作一律走 `RowActions.live(...)`**,不要直接用 `RowActions(...)`。九个闭包
  全都默认空实现(gallery 需要),于是漏接一个能编译、跑起来是个死按钮——工作台的
  `openTestFlight` 就这么静默死过一轮。`live` 没有默认值,加第十个动作会在两个调用点同时
  报错,而不是在被忘掉的那个点上安静下去。
- **`RowActionFacts.route` 是 `@autoclosure`,别改成值。** 只有 `.updateAvailable` 那一级读它,
  而算它是组装 facts 里最贵的部分(反复重建 `InstallEnvironment`,pkg 行还要 stat 磁盘)。
  写成普通参数就是每行每次重绘都算一遍,包括正在装、被忽略、等退出确认这些根本读不到它的行
  ——跟 `ListActivity.canOfferUpdateAll` 同一个坑。`routeIsDeferred` 数闭包调用次数钉住了它。
- **渲染所需的一切都放进 state 或视图入参**,别让视图回头问 model(staged 版本号、安装包
  文件名、`managedHere` 进了 state;`downloadReadout`/`showsStageLabel` 这类由行测量出来的
  布局量当入参传下去)。这不是洁癖:`PopoverRowAction` / `WorkbenchRowAction` 靠这条才能
  不构造 `AppListModel` 就被画出来——而 `AppListModel.init` 会注册通知权限、起定时器、装
  FS watcher,harness 里构造它既重又有副作用。动作一律走 `RowActions` 闭包。
- ⚠️ **别裸跑 `xcodegen generate`**:它会把 `DEVELOPMENT_TEAM` 写空,当场不报错,下一次
  `make install` 才炸在 "requires a development team"。`scripts/row-state-gallery.sh` 像
  `install.sh` 一样先 `export DUO_TEAM_ID` 再生成,照抄这个做法。
- **改了行的画法就跑 `make gallery`**,它把 40 个状态 × 两个界面渲染到
  `verify/row-states/{popover,workbench}/*.png`,共 80 张。**这些图是提交进仓库的**,
  所以改动会以图片 diff 的形式出现在 PR 里;两边对同一状态画得不一致,也会并排显示出来。
  脚本先 `rm -rf verify/row-states` 再渲染(渲染器只写不删,改名过一次就留下 8 张孤儿图),
  并用 `-AppleInterfaceStyle Light` 钉住外观 —— `ImageRenderer` 跟着宿主外观走,
  在深色模式下重跑会把 80 张全改写成与本次改动无关的 diff。
  ⚠️ 脚本里那两行 `export AppleLanguages` / `AppleLocale` **对字符串是空操作**,别当成
  它在"选语言"。原因见下面「只渲染英文」那条:这个 target 里根本没有译文可选。
- **新增状态必须在 `RowStateGalleryCases.all` 里登记**。那份清单是手写的、不是从 enum 派生的
  ——派生会自动把新状态画出来,正好掩盖"加了状态但没人画它"这件事。
- `make gallery` 有五道闸,都会让构建失败:

  1. **某个状态什么都没画**。`mayBeBlank` 目前是工作台的 `30-up-to-date` 加三张解释面板
     (`38`/`39`/`40`,工作台没有对应视图),而且
     白名单的 key 是「界面/状态」不是「状态」—— popover 对同一状态画的是对勾,按名字
     豁免会把检测器在 popover 那半边一起卸掉。⚠️ 判空要**逐像素扫**:第一版用采样网格,
     把 `no-source-covers` 误报成空白——它只有一个几像素高的淡 em dash,网格跨过去了。
  2. **同一界面上两个状态画出完全相同的像素**。这条抓的是「视图没读 state 里的东西」:
     popover 曾经在阶梯搬进 Core 之后仍留着自己的 `stagedFileName` / `storeManagedHere` /
     `result.status`,于是 `.installer` 的两种、`.appStore` 的三种各自糊成一张图,而判空
     照样全绿——它只问「画了没有」,不问「画对没有」。真的只差 tooltip 的成对状态登记进
     `mayLookAlike`,**带上理由**。

  ⚠️ **两份白名单的 key 都必须带界面前缀,`mayLookAlike` 也是。** 第一版用裸状态名,
  七条豁免里四条只在一个界面上挣到、却把另一个界面白送掉——最坏的是那对 App Store 闸,
  理由写的是"**工作台**故意把两个闸合并成一个 Label",顺手关掉了 popover 那半边,而
  popover 恰恰必须把它们画成地球徽章和三角徽章。判空那条的文档里写过这个道理,
  重复图这条上又犯了一遍。
  3. **某张图根本没写到盘上**(渲染返回 nil,或写盘抛错)。输出目录每次先 `rm -rf`,
     所以这两种情况都等于「committed sheet 里永久少一张」,而第一版只往 stderr 写一行就
     `continue`、`written` 照加,构建全绿——正好绕开这个工具存在的理由。
  4. **豁免已经不需要了**。`mayLookAlike` 是手维护的,一条不再匹配任何东西的豁免就是给
     未来的漂移发的免检证。把视图改严的那个人,正是该顺手撤掉豁免的人,所以这条也让
     构建失败(加 TestFlight 按钮时当场抓到一条)。
     ⚠️ **`mayBeBlank` 没有这道检测**(#271):一条不再匹配的判空豁免留着照样全绿,那张图
     就永久免检。改了某个状态的画法、让它从空白变成有内容时,得**自己**回去撤掉那条。
  5. **`DownloadReadout` 的枚举顺序被改了**。`AppRow` 走 `allCases` 取第一个合身的,所以
     那个声明顺序就是算法本身,重排会静默改掉每一行下载中的读数,没有编译错误、也没有
     别的测试看得见。图片 diff 是现象不是断言,所以单独一道闸钉它。

  ⚠️ **碰撞比对要跟「所有」同摘要的前驱比,不能只比一个。** 三个状态撞在一起、其中两对
  已豁免时,只留一个前驱会让第三对永远不报,而且报不报取决于这份清单的编号顺序——它
  被重编过号。判空豁免掉的图不参与碰撞比对(空白跟空白必然相同,那不是信号)。

- ⚠️ **fixture 的分布本身就是一个坑,而且犯过两次。** 判空全绿可能只是在量 fixture 而不是量
  代码:2026-09 那次多语言 harness 给每行喂 `remote: nil`,整屏截出「Reveal in Finder」,
  看着像真 UI 其实全落在兜底分支;这次 gallery 用一份 `remote.appStore == nil` 的行,
  三个 App Store 状态全掉进 `openButton`,`appStoreTrailing` 一次都没被画过。所以
  `all` 里每个 case 各自带一份 `UpdateResult`。**同一个坑在同一个文件里犯了两次**:
  修完 App Store 那三个,`sourceHint` 的三个分支和 `.upToDate` 的三个分支仍然各自只画得出
  一个,因为那份行恒定是 `isMASApp: false` / `sparkleFeedURL: nil`。现在 MAS、Sparkle、
  TestFlight 都有专门的行。**加分支时先问:它是看 state 还是看行?看行的就需要新 fixture。**
- ⚠️ **`ImageRenderer` 画不出 `.buttonStyle(.borderless)` 里的 SF Symbol**,会渲染成黄底
  红斜杠的占位图(三方对照探针验过:裸 `Image(systemName:)` 正常,包进 borderless button
  就坏,跟 `.popover` 无关)。受影响的三张登记在 `notFaithful` 里,每次运行都打印出来:
  popover 的两个琥珀徽章和地球徽章。**这三张的画面不能当真**,同一状态看工作台那张
  (它用 `Label`,渲染是对的)。
- ⚠️ **gallery 只渲染英文,而且换语言也没用**。`RowStateGallery` 是 `type: tool`,产物是裸
  Mach-O 不是 `.app`,`App/project.yml` 里只有 app 那一个 target 有 resources 阶段——所以
  `Localizable.xcstrings` 根本没被编进去,视图里的 `String(localized:)` 无论进程 locale 是什么
  都返回英文。(实测:`Build/Products/Debug/RowStateGallery` 下没有 `.lproj`、没有
  `Localizable.strings`;#263 第一版正是照 gallery 的做法渲染真视图,结果**在每种语言里都在量英文**。)
  所以**译文溢出这类事故它结构性看不见,而且现在没有任何东西看得见**。#263 曾经加过一个
  `make width-check` 来量译文宽度,2026-09-03 删掉了:它的 320pt 闸余量 1.65 倍(最宽实测是
  ru 的 `Not supported on this Mac` 194.5pt),现实中不可能红,而且没挂进 `make test`、
  没有任何东西会去跑它——一个没人跑又不会红的检查,正是本文件反复警告的那种免检证。
  **量译文要量"组合后的宽度",不是单条字符串**——这条有实例,见下。
  在有常设检查之前,跟着 popover 抄状态文案时,`.lineLimit(1)` + `.minimumScaleFactor(0.7)`
  要一起抄——工作台第一版把这两个丢了,而它用的是更大的 `.callout`,俄语
  `Ограничение частоты запросов` 27 个字符会直接挤掉应用名。
- **量译文挤不挤,要按 popover 行的真实预算算,而且要量组合后的控件。** 2026-09-03 实测的算法:
  `MenuLayoutMetrics.width` 370 − `AppRow` 左右 padding 24 − 图标 30 − `HStack(spacing:10)` 的三个
  间隔 30 = **286pt**,由"名字列 + Spacer + 尾部控件"分。名字列剩多少 = 286 − 尾部控件宽度,
  再拿它去比**本机真实装的 147 个 app 名**(`.body` 字体)有几个放不下。
  ⚠️ **尾部控件必须按组合量**:`errorBadge` 是 `Text` + 6 + 32pt 的重试按钮,不是一个 `Text`。
  当时量出来 ru 的 `Ограничение частоты запросов` 组合后 **201.9pt**,名字只剩 **84.1pt**,
  **147 个名字里 26 个被截断**;换成 `Лимит запросов` 后是 122.2pt / 163.8pt / 1 个
  (剩下那个 `Another Redis Desktop Manager` 195pt 在英文下也一样截,那是地板)。
  **同一条字符串,#281 那个已删掉的按条量的工具给的结论是"ok"**(163.9pt 对 320pt 预算)——
  差别就在组合和真实预算这两件事上,这也是那个工具被删的原因。
  其余三条 ru 长串(`Перезапустить сейчас` / `Проверка целостности` / `Перезапустить`)量下来
  各自只多截 1~2 个名字,已在地板附近,**没有跟着一起改**——按量到的改,不按看着长的改。
- **`.help()` 的文案在 PNG 里根本不存在**,所以"只差 tooltip"这个豁免理由是有代价的。
  #263 补了一半:`mayLookAlike` 的 12 对里,**只有两对**的注释真的声称"靠 tooltip 区分"
  (10/11 和 13/19),现在有检查用 `Mirror` 反射把两边的 `.help()` 收出来比对。⚠️ 那是
  SwiftUI 私有的 `HelpView<Content>` 形状,OS/Xcode 升级可能失配——所以"到处都没收到 help
  文案"会单独报 `TOOLTIP EXTRACTOR FOUND NOTHING` 而不是静默放行。剩下十对的注释写的是
  **故意画成一样**(不是靠 tooltip 区分),没有被这条检查覆盖,也不该被覆盖。

顺带:`App/Sources` 现在有一个**很窄的**测试 target(见下面「App 层的测试 target」),
它只编译被点名的文件,gallery 覆盖的这几个视图**不在里面**。所以对行的画法而言,
下面这三者仍然各管各的、都不能替代对方:`RowActionStateTests`(Core)钉的是
**哪个条件赢**,gallery 钉的是**画出来长什么样**,`DuoUpdaterAppTests` 钉的是
**App 这一侧有没有按 state 去组装行**。

## 修 issue:三条不能省的

这个仓库的 issue 基本都是我自己写的,没有第二个人会替我抓错。所以:

- **先核 issue 本身,再动手——尤其是我自己写的。** 论证充分的 issue 更容易被照单全收,不是更不容易。要问的不只是"缺陷真的存在吗",更是"**这条 issue 哪里说漏了**"。#72 只分析了 `AppListModel`,漏了 CLI 的 `Restart.swift`(退出码也 switch 在同一个枚举上);#76 只点名 install URL 是 first-match,漏了 `displayVersionPattern` 和 `publishedAtPattern` 同样是——不发现这条,就会按 issue 自己警告过的那个错法去改。发现的东西要在动手前写进方案,别让它半路冒出来。

- **高风险改动上一次对抗复审,brief 明写"找我漏的"。** 风险看**波及面**不看行数:十行改在所有请求都要走的路径上,大过两百行改在一个功能里。派一个更强的模型,给它编号的攻击面清单(没启用新开关的那些路径会不会回归、编码与边界、新选项和既有选项的未记录交互、静默失效面、诊断信息会不会开始说假话),并禁止它跑构建和测试(会和你撞)。**转发它的结论前先自己核一条**——#78 那次,一条看着像缺陷的(`VendorAppcastDeltas.patches` 仍读整个 body)其实是对的:它解析的是整份 Sparkle 文档,切片喂进去根本解析不出来。核完结论从"这是 bug"变成"这是对的,但缺注释,下一个人会把它改坏"。

- **每个 PR 合并前跑一遍 `/code-review`,不分高低风险。** 上一条那种对抗复审留给高风险改动,
  这一条是下限。2026-09-06 那天三个 PR:走了复审的 #375 抓到 6 条(其中 3 条改了设计),
  **跳过复审的 #377 和 #378 各带一个真 bug 合进了 main** —— #377 把 CotEditor 的 beta 规则
  按 Yaak 抄成 `-beta` 锚死(周期性 beta 轨上转不了正,轨一停 `duo verify` 每台机器报红),
  #378 的条目 pattern 没给 Keep a Changelog 的末尾链接块留边界(最老那条的最后一项吞进 17 条
  compare URL,1709 字符)。两条都是后来撞见的,不是被闸拦下的。**复审自己的 diff 是有产出的**:
  #379 那轮查出一条"改坏了也不会红"的用例,和一句写错了的实测数字。

- **合并前独立复算。** 凡是正确性落在一条**规则**上的(正则、版本比较、条目选择),把规则移植到 Python 打真实响应体,而不是重读 Swift。#76 靠这个确认了 feed 是发布时间序、以及新加的"winner 条目只能含一次匹配"不会误伤 671 条里的任何一条。两个独立证人胜过一个。

顺带:**构建缓存路径一律经 `scripts/derived_data_path.py` 取,别写死。** 它按 checkout 派生
(`/tmp/duo-<用途>-<hash8>`)并顺手回收已经不存在的 checkout 留下的那些。
`check_localizable_keys.py`(在 `make test` 里)、`row-state-gallery.sh`、`app-tests.sh` 都走它。

以前 loc-check 用死路径 `/tmp/duo-loc-check`,**两个 worktree 同时 `make test` 会撞
xcodebuild 的 SQLite 锁**,症状是 `database is locked` 或者干脆卡住——而这两种都长得像真失败。
现在这个前提没了(实测 28 个 worktree 算出 28 个不同路径)。如果**还是**看到
`database is locked`,先查是不是自己撞自己(`ps` 要 grep `xcodebuild`,不只是 `swift-test`),
再看是不是同一个 checkout 里跑了两遍——**同 checkout 并发是唯一剩下的碰撞面**,没修。

⚠️ **回收是刻意 fail-closed 的**:只删同时满足「名字是 `duo-<用途>-<8 位 hex>`」和「带 `origin`
标记且标记指向的 checkout 已经没了」的目录。手工造的那些(`/tmp/duo-dd-292`、`/tmp/duo-pr240-dd`
之类)一律不碰——2026-09-04 量的时候 `/tmp` 里有 **19G** 这类缓存、每份约 450M,而磁盘只剩
38G。**给每个 checkout 发一个独立路径而不回收,等于把一个会误判的失败换成一块满了的盘。**

## 断言「没有 X」「到处都 Y」之前，先量一遍

代码注释在这个仓库写得好,好到读起来像规格书。但注释写的是**意图**,意图可能是局部的、
过时的、或者只描述了主流情况。**把注释里的范围词当成实测结论,是这里最容易犯的错。**

尤其是这两类断言,写下之前必须先 grep 量一遍覆盖面:

- **「没有任何地方检查 X」**——缺失最难证明。守卫可能在另一个 registry、另一层、
  或者干脆由 API 端点的语义兜住。
- **「整个 registry 都是 Z」**——注释说 "pins arm64 **throughout**",实际 61 条
  install pattern 里有 4 条是双架构 alternation,而且 `GitHubAssetSelectionTests`
  有一条从 registry 推导的检查**专门要求**这类 pattern 登记进 `multiCandidateCases`。
  少数派不等于疏漏。

**本机这条先记住,省得再翻**:DuoUpdater 是 **arm64-only**,这是产品决策不是构建细节,
理由写在 `App/project.yml`(`ARCHS: arm64`)——registry 大面积 pin arm64 端点/资源,
universal 的 DuoUpdater 会在 Intel Mac 上跑起来然后给它装 arm64-only 的包,
"装成功了但打不开"。所以**没有 Intel 宿主**,任何以「Intel Mac 上会装错架构」开头的
issue 都是无效的,提之前先看这个文件。第三方 app 只有 Intel 版本是另一回事,
由 `HostArch.canRunIntelBuilds` + `isArchIncompatibleOnly` 处理(macOS 28 起不再推荐)。

背景:2026-08-27 修 #91~#95 那批,我和两个 subagent **各自独立地**从
`project.yml` 那句 "throughout" 推出「Intel Mac 会装错架构」,提了 issue #102 才发现
根本没有 Intel 宿主;同一天 #101 又断言「stable GitHub rule 解析出 prerelease 也没人
检查」,而 `usePrereleases: false` 走 `/releases/latest`,GitHub 定义上就不返回
prerelease。三个 agent 同一个错误形状,所以这条写进 CLAUDE.md 而不是 memory——
subagent 读不到 memory。

## 版本比较:显示版本不一定动,build 才是变的那个

macOS bundle 带两个版本串:`CFBundleShortVersionString`(marketing,给人看的)和
`CFBundleVersion`(build)。**有些 app 只涨 build,marketing 长期不动** —— Amp 2026-08-29
一天发了十个 build,全叫 `1.0`;Surge 有四个发布都叫 `6.9.0`;JetBrains 的 preview 同理。

对这类 app,**任何拿 marketing 串做的判断都会静默退化**:`isNewer("1.0","1.0")` 恒假,
`"1.0" == "1.0"` 恒真。于是「变了吗」永远答"没变",「到位了吗」永远答"到了" —— 守卫还在,
判据废了。2026-08-29 一次修了 **14 处**,其中 `UpdatePolicy` 里对的写法和错的写法
**相隔五行**。用户侧的后果包括:Relaunch 空转 189 秒然后报假失败(交换其实早成功了)、
skip 一次把 app **永久静音**、真实更新后 Rollback 行被藏起来。

规矩:

- **不要在调用点挑一个版本"串"**。传 `VersionSide`(marketing + build 一起),用
  `VersionComparator.isNewer(_:than:)` / `isSame(_:as:)` / `hasReached(_:disk:)`。它们
  marketing 优先、打平时才由 build 裁决、**绝不跨命名空间比**(`45830` 不得读作比 `1.96.0` 新)、
  判断不了时失败关闭。
- **`shortVersion ?? buildVersion` 用于显示可以,喂给比较就是 bug**;`buildVersion ?? shortVersion`
  才是比较用的顺序。`RemoteVersion.displayVersion` 同理——它是显示用的,比较要 `versionSide`。
- ⚠️ **`AppScanner.buildVersionIsOverridden` 的 app(Xcode、豆包输入法)存的 build 不是 bundle 自己的**。
  豆包真实的 `CFBundleVersion` 每个 build 都是平的 `1`,scanner 存的是自定义 key 里那个数。
  **拿它跟直接读 plist 的结果比就是两个命名空间**,会恒假。要么退回只比 marketing,要么两边都用同一来源。
- `scripts/check_staged_version_use.py`(挂在 `make test` 里)会拦住 marketing-first 喂进比较、
  以及只读 marketing 半边做变化检测。**它是兜底不是证明**:窗口按语句算,**看不见跨文件的数据流**
  —— 备份标签喂给 workbench 过滤器那处就是这样漏的。合法的 marketing-first 比较用
  `version-lint:allow-marketing-first` 加理由豁免,别改规则。

顺带一条会决定你把代码放哪:**`App/Sources` 有两万行,其中只有被 `DuoUpdaterAppTests`
点名的那几个文件在跑**(见下节),其余的判断没人执行。14 处里 9 处长在那儿,不是巧合。
**判断逻辑放 Core**(`RelaunchProgress`、`PackageRestartState`、`VisibilityRules`、
`UpdatePolicy.needsAction`、`BadgeReadout`、`RowActionFacts.assemble` 都是这么落的),
App 只留接线;接线本身要可测,就放进 `ScanRowAssembly` 这类无 UI 依赖的文件。

⚠️ **"接线"不等于"必须留在 App"。** 2026-09-04 搬 `needsAction` / `badgeCount` /
`rowState` 时先量了一遍依赖:那三处引用的 `InstallStage`、`RowActionFacts`、`UpdateRoute`、
`stagedRelaunchLine` **全都已经在 Core**,`AppListModel` 的七张表也全是
`[String: X]` / `Set<String>` 这种 Core 看得见的类型。所以它们整块搬进 Core 就行,
根本不需要用 App 那个窄 target。**动手前先量依赖,别默认"它在 App 里所以只能在 App 测"**
——`App/Sources` 里剩下的东西有多少是这种情况,没量过。

## App 层的测试 target

`make test` 里多了一步 `scripts/app-tests.sh`,跑 `DuoUpdaterAppTests`(`App/project.yml`)。
在它之前,`App/Sources` 那两万行**只被编译、从不被执行**:`make test` 跑的是两个 SwiftPM 包,
唯一碰到 App 代码的 `check_localizable_keys.py` 只取编译器吐的字符串元数据、不运行任何代码。
2026-09-03 那批 13 条缺陷里有 4 条长在这儿,条条编译通过、条条 `make test` 全绿,而且
**其中 3 条是修上一条时新引入的**——反馈回路断了,复审就成了唯一的网。

规矩:

- **它覆盖的是「纯的那一半」,接线仍然只有复审看着。** `ScanRowAssembly` 被执行了,但
  「哪份快照在什么时候取」还在 `AppListModel` 里、还在 target 之外——而 #314 那 4 条缺陷
  恰恰是这类。可以真的试一下:把 `performRefresh` 里的
  `let provenNow = ResolvedChannelStore.Snapshot()` 挪到 `await checker.check(checkable)`
  **之前**,它就违反了紧挨着的那句注释("Read after the check, not before"),而**编译通过、
  9 条测试全绿**。给 `merged` 传一份过期的 `prior` 同理。别把这一节读成「App 层的行组装
  现在有覆盖了」。
  (⚠️ 第一版这里写的是「把 `proofs` 和 `provenNow` 对调」——那两个变量在**两个不同的函数**里,
  从来不同时在作用域内,照着做会发现根本改不了。举例的变异必须是真能做出来的那一个。)
- **这个 target 只编译被点名的文件,不是整个 `Sources`。** 这不是为了省时间:
  `AppListModel.swift` 引用 `SettingsView`,会把整棵 SwiftUI 拉进来;而
  `AppListModel.init` 会注册通知、装两个 FSEvent 流、KVO 观察全机进程、起周期检查循环
  ——**一个构造它的测试 bundle 就是一个会去打厂商端点的测试 bundle**。
  往 `sources` 里加文件是一个决定:加进去的东西必须不依赖 SwiftUI、不依赖 `AppListModel`,
  违反了会当场编译失败,**那个失败就是这条规矩本身**。
- **它是 hostless 的**(没有 `TEST_HOST`),所以不需要 app bundle、不签名、不要
  `DEVELOPMENT_TEAM`。但 `app-tests.sh` 仍然像 `row-state-gallery.sh` 一样先
  `export DUO_TEAM_ID` 再 `xcodegen generate`——理由同那边:生成时缺 team 会把
  `DEVELOPMENT_TEAM` 写空,炸的是下一次 `make install`。
- **只在 `project.yml` 比 `project.pbxproj` 新的时候才重新生成。** 无条件生成会重写
  `project.pbxproj`,让紧随其后的 `check_localizable_keys.py` 的增量构建每次失效,
  `make test` 从此每次全量重编整个 app。
- **derived data 路径走 `scripts/derived_data_path.py`**(见上),`APP_TESTS_DD` 可覆盖。
  写死路径会复刻多 worktree 撞锁的坑,而这里的症状是**测试随机失败**,
  比"构建变慢"更容易被误读成真回归。
- **每条用例都要写清它对应哪一行变异**,并且合并前真的跑一遍那个变异确认它变红。
  `ScanRowAssemblyTests` 现在是 9 条用例 / 10 个变异,10 个全部**编译通过**(不是靠编译
  错误变红)且只打中该打中的用例。没有对应变异的用例(`anUnprovenCopyFallsBackToItsBundle`
  是 fixture 守卫)要在注释里说明。
- ⚠️ **「这个分支的 carry 没丢」不等于「这个分支还在」。** 第一版把 Toolbox 和 TestFlight
  两个早返回合成一条用例、只断言 channel 活着,于是**把这两个分支整个删掉,8 条测试全绿**
  ——那份 fixture 让 `evaluateToolbox`、`evaluate`、`was.status` 三者答案相同,状态那一半是
  `f(X)==f(X)`。现在两条用例各自断言 status,并且 fixture 刻意让三者**互不相同**。
  加用例时先问:**有没有一份输入能让"正确实现"和"删掉这段"给出不同答案?** 造不出来
  就说明这条用例没在量这段代码。
  ⚠️ 准确的说法是「**正确答案与每一个错答案都不同**」,不是「三个候选互不相同」——实测这两份
  fixture 里 `evaluate` 和 `was.status` 恰好相等,闸照样成立,但照着"三者互不相同"去推下一份
  fixture 会瞄错属性。
- ⚠️ **防空过闸要比「名字集合」,不要比两个总数。** 这条闸被写错过三次,每次都是实测才发现:
  1. **读运行摘要**:某条用例标了 `.disabled()` 时,swift-testing 的摘要**仍然**是
     `Test run with 9 tests` —— 它数的是它知道的、不是它跑过的,所以闸在用例被关掉时放行。
  2. **拿逐条行数去比声明条数**:`@Test(.disabled("…"))` 换行写(**这个仓库的主流写法**,
     理由长了必然换行)会把两边**同时减一**,闸自己抵消掉。
  3. **同一个总数闸**会在第一条参数化用例出现时**把全绿的运行判红**。
  所以现在是 `scripts/app_test_coverage.py`:从源码抽出声明的用例名(跨行的 `@Test` 也算,
  跳过注释),从日志抽出真的跑过的用例名,断言前者 ⊆ 后者,并且**把没跑的那条名字打出来**。
  三个变异实测:同行 `.disabled()`、换行 `.disabled()`、target 里拿掉 `- path: Tests`,
  三个都红且点名;参数化用例不再误红。
- ⚠️ **从日志抽用例名的两个坑,都是量出来的、不是猜出来的**:
  (1) 行首**不能锚 `^`** —— xcodebuild 会在某些行前面加 `XCTestOutputBarrier` 标记(有时还
  被截断成半个 token),swift-testing 还会吐一个 U+200B,实测让 `grep -c "^✔ Test …"`
  把 8 条数成 7 条。要数**出现次数**。(我第一版把原因写成"并行输出交织、两条记录挤到一行",
  复审去数了九份真实日志:**零行**含两条记录 —— 现象对、机制错。)
  (2) 括号**不一定是空的、`passed` 也不一定紧跟在括号后面**:参数化用例打的是
  `Test foo(_:) with 2 test cases passed`。两个假设各让闸错过一次。
- ⚠️ **「用例是否真的在跑」这件事目前只有 `app-tests.sh` 那条闸在管;「用例是否真的在量代码」
  只有这份文件的一段话在管。** 没有任何挂进 `make test` 的东西会去跑变异——
  `make gallery` 的 `mayLookAlike`/`mayBeBlank` 是这个仓库把同类规矩变成构建失败的先例,
  这里还没有等价物。所以上面那两条是**约定**,不是闸。
- ⚠️ **fixture 不能比生产的判据宽。** `Proofs` 第一版按路径答,而真正的
  `provenChannelSnapshot` 要求 path + `shortVersion` + `buildVersion` 三者全中——于是一条
  用例断言了**生产代码根本产生不出来的结果**。fixture 现在按「一份拷贝的一个版本」作键。
- **harness 自己也要有防空过闸,而且这条闸也要变异验证。** `app-tests.sh` 会在
  「执行了 0 个用例」时失败(target 不再编译 `App/Tests`、或 xcodebuild 改了摘要行),
  实测:把 `- path: Tests` 从 target 里拿掉,它红;拿回来,9 executed。没有这条闸的话,
  `App/Tests` 被改名之后 `make test` 会永远绿着什么都不跑。
- ⚠️ **`set -o pipefail` 会让「grep 没匹配到」变成脚本失败。** 第一版在 `set -e` 恢复之后
  用 `... | grep ... | head` 输出结果,于是**成功路径上**只要 xcodebuild 改了摘要措辞,
  一次全绿的运行就会以无任何信息的失败告终。现在每个过滤都带 `|| true`,完整日志落盘到
  `$DD/app-tests.log` 并在失败信息里报出路径(第一版让人「重跑一遍看完整日志」,而重跑
  给出的是同样被过滤的 40 行——那条提示是假的)。

## 别在协作池上做阻塞调用

Swift concurrency 的协作池**宽度约等于核数,而且线程阻塞时不扩容**。所以一个同步的、会
把线程停住的调用,占掉的是极少数线程之一;并发几个,整个运行时就**不再调度任何东西**
——不是变慢,是停住。

这在这个仓库里发生过,而且长在安装路径上。2026-09-05 在 3 核的 GitHub runner 上实测
(#351、run 33959023008):三个并发的 `SecStaticCodeCheckValidity` 把三条协作线程全部
压进 `Dispatch::Group::wait()`,**相隔 60 秒的两次采样显示两个进程各只烧了 0.00 秒和
0.01 秒 CPU** —— 卡死,不是慢。整个测试进程此后一个字都不再输出。

规矩:

- **从 async 里调这些,必须走 `offCooperativePool`**(`Support/OffPool.swift`):
  `SecStaticCode*` 全家(`verifyCodeSignature` / `teamIdentifier` / `signingIdentifier`)、
  `Process.waitUntilExit()`、`DispatchGroup.wait()`、`DispatchSemaphore.wait()`、
  `readDataToEndOfFile()` 配对的那种等待。`ArchiveExtractor.run` 一个函数里就有四个。
- **`Task.detached` 不是替代品**,它仍然跑在协作池上。这条 `BrewFormulaReleaseService`
  的注释早就写过,并且带着测量(23 路扇出,detached 让无关任务多停 0.95~1.07s,
  `DispatchQueue.global` 只多 0.02~0.06s,墙钟相同)——**Dispatch 在线程阻塞时会扩池**。
- **一段连续的闸序列用一次 hop,不要每个闸一次。** 顺序是承重的(gate 5 必须在 5b 前),
  多次 hop 就是多次意外打乱它的机会。
- ⚠️ **这不是 CI 专属问题。** `InstallPermits(applies: 2)` 意味着产品里就有两个并发 apply,
  `recoverInterruptedSwapsOnce` 还从 `Task.detached` 再加。**CI 只是核数低到能撞上的地方。**
- ⚠️ **修法能救池,不保证能救那个调用。** 那个 Security 的 group 到底在等什么,至今不知道
  (栈里没有 XPC 帧,没有任何线程在推进校验)。所以它把「整进程死掉」换成「一个操作卡住」,
  这已经是巨大的改善,但别把它说成"修好了那个调用"。

**复现它需要核少的机器。** `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 能把池宽钉到 1
(用 8 个 CPU-bound 任务验过旋钮:不设比值 1.0,设了 8.0),但**那样复现不出来**——
全套 2256 条在池宽 1 下 32.8 秒全绿。真正复现它的是把三个并发签名校验推到 3 核 runner 上,
本机 14 核一次都没复现过。**核少的机器是更严格的测试环境,不是更差的。**

## CI:存在了,而且 `test` 是合并门槛

2026-09-05 起这个仓库有 CI,以前没有。写规矩之前先知道这些:

- **`.github/workflows/ci.yml`** —— hosted runner(`macos-latest`,**arm64 3 核**)、
  `pull_request` + `push: main` + `workflow_dispatch`、**不带任何 secret**、action 按 SHA 钉住。
  公开仓库的标准 runner 免费不限量;单 job 上限 6 小时,我们自己设 60 分钟。
- **`test` 是 main 的必需状态检查**,直推 main 被拒(实测退出码 1)。
- ⚠️ **`[skip ci]` 会把 PR 永久焊死。** GitHub 文档明说:被 commit message / path filter /
  branch filter 跳过的 workflow,它的 check **停在 Pending**,而要求它的 PR 无法合并。
  实测:带 `[skip ci]` 的 PR `mergeStateStatus=BLOCKED`、`statusCheckRollup` 长度 0、
  `gh pr merge` 退 1。**`paths-ignore` 同理,不能当豁免用。**
  ⚠️ ⚠️ **扫描不限于第一行,所以「写到」这个标记就会触发它。** 2026-09-05 实测:一条
  记录这个坑的提交,主题行干净、标记只出现在**正文**里(而且是包在反引号里的),
  GitHub 照样跳过了整个 workflow —— PR #353 停在 BLOCKED、零个 check、**根本没有 run**。
  在提交信息里提到它时要改写(比如写成「a skip-ci marker」),**文件里怎么写都行**,
  被扫的只有提交信息。
- ⚠️ **`gh pr merge --auto` 成功 ≠ 已合并**,它在 check 还没报告时就返回 0。任何拿返回值
  当"合并完成"的脚本,会在 CI 变红时静默丢东西。两处自动流程(mini 夜间基线、发版的
  appcast)都改成轮询 PR 的 `state` 到 `MERGED`,上限 30 分钟。
- **`make test` 经 `scripts/run-with-hang-report.sh` 跑**,超时会对每个候选进程抓
  `sample(1)`、打两轮相隔 60 秒的 CPU 增量和线程栈、杀进程树、退 124。
  ⚠️ **看门狗必须在进程外**:进程内的要靠跑到的代码上膛(上一版在下载闸里上膛,
  结果闸关着那轮它根本不存在),而异步超时是**它要报告的那个池上的 Task**,
  运行时停止调度时它永远不会触发——实测 5 分钟的 `firstToFinish` 坐穿了 16 分钟静默。
- ⚠️ **必需检查验的是 PR 的头,不是合并结果。** `strict_required_status_checks_policy`
  是 **false**,即不要求分支与 main 同步就能合。这是刻意的:开了它,每次 main 前进,那两条
  自动 PR(mini 夜间基线、发版 appcast)都得 rebase —— 正是它们刚被重写来避开的失败,
  而这个仓库常有多个 PR 并行。
  **代价**:一个基于旧 main 验过的 PR 可以合进新 main,**这个组合从没被测过**。
  真出了那种事再考虑打开,别把它当成"已经防住了"。
- ⚠️ **发版那道闸验的是「工作树」,不是 main。** `publish-release.sh` 只要求提交
  **在某个远端分支上**(`is on no remote branch, so GitHub cannot tag it`),**不要求在 main 上**。
  而那道真下厂商包的闸只在 CI 上跑过 main。实际都是从 main 打 tag、差异为零,
  **但那是惯例不是保证**。从侧分支发版时那棵树没被那道闸验过。
- **还有一件「代码最新」也管不了的**:那道闸验的是厂商的**真实字节**,而厂商可以随时换
  Team ID、改签名、坏掉。CI 每轮重新下当前的包,所以是持续覆盖的——但最后一轮 CI 到
  发版之间的窗口不可能被覆盖。这是固有的,不是疏漏。
- **`release-build.yml`** 只能 `workflow_dispatch`,Apple 的 secret 放在 `release`
  Environment(只有 `main` 和 `v*` 能拿到,特性分支 dispatch 实测 2 秒 0 步骤失败),
  产物带 Sigstore 证明,`publish-release.sh` 用 `gh attestation verify --signer-workflow
  --source-digest --deny-self-hosted-runners` 消费。Sparkle 的 EdDSA 私钥**留在本机**。

## 供应商 recipe 的失效是常态

vendor 换 DNS、改 manifest 结构、端点开始要 license,都发生过。所以:

- 报根因前先把**原始响应体**读出来,不要从 HTTP 状态码猜。
- 区分「vendor 真的变了」和「我们这边逻辑错了」——前者改 recipe,后者改代码,别混成一个 commit。
- 拿不准就标「未验证」,不要给一个看起来合理的推测当结论。

## 跑长命令:重定向到文件,杀的时候杀进程树

`make release` / `make notarize` / 全量 `duo verify` / `make test` 都会刷出几十万字节。

- **把输出直接重定向到文件,别让它走管道捕获。** 管道缓冲区只有 64KB,读端不排空就会把进程
  堵死在 `write` 上——现象是 CPU 恒为 `0:00.00`、日志文件 0 字节、看起来"特别慢"。
  判据三条:`lsof` 看 fd 1/2 是不是 PIPE、stdin 是不是 `/dev/null`(排除等输入)、
  日志有没有在长。2026-09-02 发 0.3.80 时它在前置检查阶段就堵住了。
- ⚠️ **杀这类命令必须杀整棵进程树。** 同一次里我只 kill 了两个 `bash publish-release.sh`,
  没杀它们派生的 `swift test`,那条孤儿链(`sh → swift-test → swiftpm-testing-helper`)
  一直攥着 `DuoUpdaterCore/.build` 的 SwiftPM 锁。下一轮于是停在
  `Another instance of SwiftPM (PID: …) is already running … waiting until that process
  has finished execution`,等一个永远不会结束的东西——**症状同样伪装成"某某工具好慢"**。
  杀之前先 `pgrep -lf 'publish-release|swift-test|swiftpm-testing-helper|xcodebuild'`,
  杀完再查一遍(注意自己的轮询 shell 会因为命令行里含关键字而被 grep 命中,不是残留)。
- **判断"卡住了"要看有没有在推进,不是看 CPU。** 我一度断言下载卡死,实测那个
  `.partial` 文件 20 秒涨了 966KB —— CPU 为 0 只是在等网络。量文件大小,别看 `%CPU`。
  ⚠️ **反过来用是成立的,而且是唯一能区分"卡死"和"慢"的判据**:**间隔一分钟量两次
  累计 CPU 时间**,不涨就是没在执行。2026-09-05 就是靠这个把 #351 定死的——两个进程
  60 秒里各烧了 0.00 秒和 0.01 秒。单看一次栈做不到:慢的调用和卡住的调用长得一模一样。
  `scripts/run-with-hang-report.sh` 把这套做成了工具,别再手搓。
- ⚠️ **「输出停了」不等于「执行停了」。** CI 的日志是缓冲的,退出时才刷,实测偏差约
  **235 秒**。我据此断言过"它从没到某一行",而那行其实早就印过了——只是还没刷出来。
  要定位就插阶段行 + 拿栈,别拿最后一行日志当现场。

## 发布

- `CHANGELOG.md` 是发布说明的**唯一真源**:`scripts/publish-release.sh` 直接读对应版本那一节,塞进 GitHub Release 和 Sparkle appcast。**英文**,写给用户看的人话,不要写 commit 流水账。
- **写用户得到了什么,不写我们是怎么查出来的。** 一句加粗的收益,最多再补一句"以前是什么样",格式规范写在 `CHANGELOG.md` 开头。**0.3.80 起改的**,之前那些是旧的长篇体例,保持原样别动。具体不要写的:排查过程、量到的毫秒数、文件名和符号名、issue 号、复审抓到了什么。用户感知不到的改动(重构、内部加固、多数性能优化)合并成结尾一句 "Under the hood:",或者干脆不写——性能优化只有在用户真的会感觉到时才单独成条。
- ⚠️ 我在 0.3.80 那次先用中文重写了整节才发现:**这个文件历来是英文的**,而且会原样发给全量用户。改之前先看一眼相邻版本。
- `make install` / `make cli` 用的是**稳定的 Developer ID 签名**,这不是洁癖:macOS 把 TCC 授权(完全磁盘访问、辅助功能、App 管理)绑在代码身份上,ad-hoc 签名每次重编 CDHash 都变,授权就掉。别为了图快改成 ad-hoc。
- `make notarize` → `dist/DuoUpdater-notarized.zip`;`make release` 才推 GitHub Release。
- **发版不再在本机下厂商的包了,别再按旧说法预留那段等待。** `publish-release.sh` 跑的是
  同一个 `make test`,而那道真下包的闸(`vendorDownloadPassesSignatureGate`)现在由
  `DUO_DOWNLOAD_GATE` 控制,**只有 ci.yml 设它**。本机一轮实测从 **~185 MB 降到 ~25 MB**
  ——数字来自仓库自己的请求账本(见下面「量流量」那条),不是估算。
  这条以前写的是「gate 测试要真下厂商的包,所以耗时取决于下行带宽,2026-09-02 实测经
  Surge 代理只有 ~48 KB/s」。那个场景**不会再发生**,除非你手动 `DUO_DOWNLOAD_GATE=1 make release`。
- ⚠️ **缺口要知道**:`make release` 跑的是「即将发布的那棵树」,而那道闸只在 CI 上跑过 main。
  发版都是从 main 打 tag、差异为零,**但那是惯例不是保证**。要在发版那一刻也过一遍就
  `DUO_DOWNLOAD_GATE=1 make release`,代价是每次 +160 MB。
- **量流量走仓库自己的账本,别用 `curl -sI` 估。** `Traffic/` 在调用点打 `RequestPurpose`、
  用 `URLSessionTaskMetrics` 数真实字节。测试进程的账本被特意引到临时目录
  (`EventStore.defaultFileURL()`,避免污染 `duo requests`),所以直接查:
  `sqlite3 "${TMPDIR}duo-events-tests/com.duoupdater.app/events.sqlite"`,`at` 是**微秒**。
  2026-09-05 拿它量出来:开着闸一轮 185 MB(install 169.1),关掉 ~25 MB;
  而这套件一天累计下了 **8.4 GB**。我当时用 `curl -sI` 量两个 URL 得到的 "161 MB" 偏低,
  漏掉了 ~150 个元数据请求。
- 顺带:`SKIP_NOTARIZE=1` 会复用 `dist/DuoUpdater-notarized.zip`,脚本自己会校验 zip 里的
  版本号和即将打的 tag 一致,所以中途失败重跑不必重新公证(公证一次好几分钟)。
  发布顺序是 **先克隆仓库更新 appcast,后 `gh release create`**,所以卡在克隆那步时
  tag / release / appcast 都还没动,是一次干净的失败,直接重试即可。

## Git

- 本仓库常有多个 worktree 同时开着(`.claude/worktrees/*`),而且 `main` 可能在你干活时已经前进。
  `git stash` / `merge` / `commit` 前先 `git status` + `git stash list`,确认没有另一个会话的在途改动。
- ⚠️ **recipe 巡检任务跑在这个 checkout 里,一天四次,会换你的分支。**
  `com.bobby.duo-recipe-verify`(launchd,`WorkingDirectory` 就是这个工作副本,
  04:17 / 10:17 / 16:17 / 22:17,日志 `~/Library/Logs/duo-recipe-verify.log`)。
  它**开头 `git checkout main`**,然后跑完整轮扫(几分钟),**最后才**
  `git checkout -b verify/baseline-<时间戳>` —— 而那一步是从**当时的 HEAD** 切的,
  不是从 main 切的,尽管脚本自己的注释写着"$BRANCH is left exactly where origin has it"。
  于是有一个几分钟的窗口,两个方向都会出事,2026-09-06 一次跑里两个都出了:
  1. 它开头切走 main,**不切回来** —— 我随后的 `git commit` 落在了它的分支上。
  2. 我在窗口里切回自己的特性分支,它的 PR 就从**我的分支**切了出去 ——
     #386 的 diff 里因此躺着我三个没复审的文件,而它开了 `--auto` squash,
     CI 一绿就会进 main。**这是「每个 PR 合并前跑复审」那条闸的一个绕行口。**
  规矩:**跑完任何长命令、或隔了一段时间之后,`commit` / `push` 前先
  `git branch --show-current`**,别假设还在自己那条分支上。
  撞上了先 `gh pr merge <n> --disable-auto` 止损 —— 这一步不需要 force-push、
  也不动别人的分支;分支已经和 main 分叉的(比如你的 PR 已经单独 squash 合了),
  关掉让它重跑,别去 rebase 另一个进程的分支。
  ⚠️ 顺带把没量的那半边说清楚:**发版那条自动流程不在这里面**。
  `publish-release.sh` 刻意把 appcast 放进一个临时 clone 改,理由写在它自己的注释里
  ——"Committing the appcast into the working tree would mean the release touches
  whatever branch happens to be checked out"。**同一个坑,那边防住了,这边没有。**
- 找不到某个文件或命令时,先考虑"它在另一个 checkout 里还没提交",不要断言"它不存在"。
- 解冲突就在冲突块里改,不要把内容追加到文件末尾。
- 分组提交(引擎 / CLI / 测试 / 文档 / CHANGELOG),提交前先把分组方案给用户过目。
- **`docs/` 要带进来**,尤其是 `docs/app-audits/`。审计文档是改动的一部分,不是附属品:
  「厂商包名里的 channel token 是什么」「两轨的版本字段是反的」「这个端点的必填参数会选灰度桶」
  这类东西,下一个人重新发现一次的代价远高于多提交一个文件。近几个 recipe PR(Canva、
  WorkBuddy、CapCut)都是连审计文档一起提的,这条曾经写成"默认不带",与实际做法相反。
