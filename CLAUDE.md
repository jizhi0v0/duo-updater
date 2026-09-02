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

- **渲染所需的一切都放进 state 或视图入参**,别让视图回头问 model(staged 版本号、安装包
  文件名、`managedHere` 进了 state;`downloadReadout`/`showsStageLabel` 这类由行测量出来的
  布局量当入参传下去)。这不是洁癖:`PopoverRowAction` / `WorkbenchRowAction` 靠这条才能
  不构造 `AppListModel` 就被画出来——而 `AppListModel.init` 会注册通知权限、起定时器、装
  FS watcher,harness 里构造它既重又有副作用。动作一律走 `RowActions` 闭包。
- ⚠️ **别裸跑 `xcodegen generate`**:它会把 `DEVELOPMENT_TEAM` 写空,当场不报错,下一次
  `make install` 才炸在 "requires a development team"。`scripts/row-state-gallery.sh` 像
  `install.sh` 一样先 `export DUO_TEAM_ID` 再生成,照抄这个做法。
- **改了行的画法就跑 `make gallery`**,它把 30 个状态 × 两个界面渲染到
  `verify/row-states/{popover,workbench}/*.png`,共 60 张。**这些图是提交进仓库的**,
  所以改动会以图片 diff 的形式出现在 PR 里;两边对同一状态画得不一致,也会并排显示出来。
  脚本先 `rm -rf verify/row-states` 再渲染(渲染器只写不删,改名过一次就留下 8 张孤儿图),
  并 pin 住 `AppleLanguages` / `AppleLocale` / Light —— `ImageRenderer` 跟着宿主的外观和
  语言走,在深色模式或非英文环境下重跑会把 60 张全改写成与本次改动无关的 diff。
- **新增状态必须在 `RowStateGalleryCases.all` 里登记**。那份清单是手写的、不是从 enum 派生的
  ——派生会自动把新状态画出来,正好掩盖"加了状态但没人画它"这件事。
- `make gallery` 有两道闸,都会让构建失败:

  1. **某个状态什么都没画**。只有 `workbench/30-up-to-date` 在 `mayBeBlank` 里,而且
     白名单的 key 是「界面/状态」不是「状态」—— popover 对同一状态画的是对勾,按名字
     豁免会把检测器在 popover 那半边一起卸掉。⚠️ 判空要**逐像素扫**:第一版用采样网格,
     把 `no-source-covers` 误报成空白——它只有一个几像素高的淡 em dash,网格跨过去了。
  2. **同一界面上两个状态画出完全相同的像素**。这条抓的是「视图没读 state 里的东西」:
     popover 曾经在阶梯搬进 Core 之后仍留着自己的 `stagedFileName` / `storeManagedHere` /
     `result.status`,于是 `.installer` 的两种、`.appStore` 的三种各自糊成一张图,而判空
     照样全绿——它只问「画了没有」,不问「画对没有」。真的只差 tooltip 的成对状态登记进
     `mayLookAlike`,**带上理由**。

- ⚠️ **fixture 的分布本身就是一个坑,而且犯过两次。** 判空全绿可能只是在量 fixture 而不是量
  代码:2026-09 那次多语言 harness 给每行喂 `remote: nil`,整屏截出「Reveal in Finder」,
  看着像真 UI 其实全落在兜底分支;这次 gallery 用一份 `remote.appStore == nil` 的行,
  三个 App Store 状态全掉进 `openButton`,`appStoreTrailing` 一次都没被画过。所以
  `all` 里每个 case 各自带一份 `UpdateResult`,区域锁 / Mac 不兼容都有专门的行。
- ⚠️ **`ImageRenderer` 画不出 `.buttonStyle(.borderless)` 里的 SF Symbol**,会渲染成黄底
  红斜杠的占位图(三方对照探针验过:裸 `Image(systemName:)` 正常,包进 borderless button
  就坏,跟 `.popover` 无关)。受影响的三张登记在 `notFaithful` 里,每次运行都打印出来:
  popover 的两个琥珀徽章和地球徽章。**这三张的画面不能当真**,同一状态看工作台那张
  (它用 `Label`,渲染是对的)。

顺带:`App/project.yml` 仍然没有测试 target,所以 `App/Sources` 里的判断没人执行。
`RowActionStateTests`(Core)钉的是**哪个条件赢**,gallery 钉的是**画出来长什么样**,
两者都不能替代对方。

## 修 issue:三条不能省的

这个仓库的 issue 基本都是我自己写的,没有第二个人会替我抓错。所以:

- **先核 issue 本身,再动手——尤其是我自己写的。** 论证充分的 issue 更容易被照单全收,不是更不容易。要问的不只是"缺陷真的存在吗",更是"**这条 issue 哪里说漏了**"。#72 只分析了 `AppListModel`,漏了 CLI 的 `Restart.swift`(退出码也 switch 在同一个枚举上);#76 只点名 install URL 是 first-match,漏了 `displayVersionPattern` 和 `publishedAtPattern` 同样是——不发现这条,就会按 issue 自己警告过的那个错法去改。发现的东西要在动手前写进方案,别让它半路冒出来。

- **高风险改动上一次对抗复审,brief 明写"找我漏的"。** 风险看**波及面**不看行数:十行改在所有请求都要走的路径上,大过两百行改在一个功能里。派一个更强的模型,给它编号的攻击面清单(没启用新开关的那些路径会不会回归、编码与边界、新选项和既有选项的未记录交互、静默失效面、诊断信息会不会开始说假话),并禁止它跑构建和测试(会和你撞)。**转发它的结论前先自己核一条**——#78 那次,一条看着像缺陷的(`VendorAppcastDeltas.patches` 仍读整个 body)其实是对的:它解析的是整份 Sparkle 文档,切片喂进去根本解析不出来。核完结论从"这是 bug"变成"这是对的,但缺注释,下一个人会把它改坏"。

- **合并前独立复算。** 凡是正确性落在一条**规则**上的(正则、版本比较、条目选择),把规则移植到 Python 打真实响应体,而不是重读 Swift。#76 靠这个确认了 feed 是发布时间序、以及新加的"winner 条目只能含一次匹配"不会误伤 671 条里的任何一条。两个独立证人胜过一个。

顺带:`make test` 会跑 `scripts/check_localizable_keys.py`,它用固定路径 `/tmp/duo-loc-check` 做构建缓存,**两个 worktree 同时跑会锁冲突**。看到 `database is locked` 先查是不是自己撞自己(`ps` 要 grep `xcodebuild`,不只是 `swift-test`),别当成真失败。

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

顺带一条会决定你把代码放哪:**`App/Sources` 有一万三千行、`App/project.yml` 里没有测试 target**,
所以那里的判断没人执行。14 处里 9 处长在那儿,不是巧合。**判断逻辑放 Core**(`RelaunchProgress`、
`PackageRestartState`、`VisibilityRules` 都是这么落的),App 只留接线。

## 供应商 recipe 的失效是常态

vendor 换 DNS、改 manifest 结构、端点开始要 license,都发生过。所以:

- 报根因前先把**原始响应体**读出来,不要从 HTTP 状态码猜。
- 区分「vendor 真的变了」和「我们这边逻辑错了」——前者改 recipe,后者改代码,别混成一个 commit。
- 拿不准就标「未验证」,不要给一个看起来合理的推测当结论。

## 发布

- `CHANGELOG.md` 是发布说明的**唯一真源**:`scripts/publish-release.sh` 直接读对应版本那一节,塞进 GitHub Release 和 Sparkle appcast。写给用户看的人话,不要写 commit 流水账——照着已有版本的语气写。
- `make install` / `make cli` 用的是**稳定的 Developer ID 签名**,这不是洁癖:macOS 把 TCC 授权(完全磁盘访问、辅助功能、App 管理)绑在代码身份上,ad-hoc 签名每次重编 CDHash 都变,授权就掉。别为了图快改成 ad-hoc。
- `make notarize` → `dist/DuoUpdater-notarized.zip`;`make release` 才推 GitHub Release。

## Git

- 本仓库常有多个 worktree 同时开着(`.claude/worktrees/*`),而且 `main` 可能在你干活时已经前进。
  `git stash` / `merge` / `commit` 前先 `git status` + `git stash list`,确认没有另一个会话的在途改动。
- 找不到某个文件或命令时,先考虑"它在另一个 checkout 里还没提交",不要断言"它不存在"。
- 解冲突就在冲突块里改,不要把内容追加到文件末尾。
- 分组提交(引擎 / CLI / 测试 / 文档 / CHANGELOG),提交前先把分组方案给用户过目。
- **`docs/` 要带进来**,尤其是 `docs/app-audits/`。审计文档是改动的一部分,不是附属品:
  「厂商包名里的 channel token 是什么」「两轨的版本字段是反的」「这个端点的必填参数会选灰度桶」
  这类东西,下一个人重新发现一次的代价远高于多提交一个文件。近几个 recipe PR(Canva、
  WorkBuddy、CapCut)都是连审计文档一起提的,这条曾经写成"默认不带",与实际做法相反。
