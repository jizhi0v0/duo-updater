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

## 修 issue:三条不能省的

这个仓库的 issue 基本都是我自己写的,没有第二个人会替我抓错。所以:

- **先核 issue 本身,再动手——尤其是我自己写的。** 论证充分的 issue 更容易被照单全收,不是更不容易。要问的不只是"缺陷真的存在吗",更是"**这条 issue 哪里说漏了**"。#72 只分析了 `AppListModel`,漏了 CLI 的 `Restart.swift`(退出码也 switch 在同一个枚举上);#76 只点名 install URL 是 first-match,漏了 `displayVersionPattern` 和 `publishedAtPattern` 同样是——不发现这条,就会按 issue 自己警告过的那个错法去改。发现的东西要在动手前写进方案,别让它半路冒出来。

- **高风险改动上一次对抗复审,brief 明写"找我漏的"。** 风险看**波及面**不看行数:十行改在所有请求都要走的路径上,大过两百行改在一个功能里。派一个更强的模型,给它编号的攻击面清单(没启用新开关的那些路径会不会回归、编码与边界、新选项和既有选项的未记录交互、静默失效面、诊断信息会不会开始说假话),并禁止它跑构建和测试(会和你撞)。**转发它的结论前先自己核一条**——#78 那次,一条看着像缺陷的(`VendorAppcastDeltas.patches` 仍读整个 body)其实是对的:它解析的是整份 Sparkle 文档,切片喂进去根本解析不出来。核完结论从"这是 bug"变成"这是对的,但缺注释,下一个人会把它改坏"。

- **合并前独立复算。** 凡是正确性落在一条**规则**上的(正则、版本比较、条目选择),把规则移植到 Python 打真实响应体,而不是重读 Swift。#76 靠这个确认了 feed 是发布时间序、以及新加的"winner 条目只能含一次匹配"不会误伤 671 条里的任何一条。两个独立证人胜过一个。

顺带:`make test` 会跑 `scripts/check_localizable_keys.py`,它用固定路径 `/tmp/duo-loc-check` 做构建缓存,**两个 worktree 同时跑会锁冲突**。看到 `database is locked` 先查是不是自己撞自己(`ps` 要 grep `xcodebuild`,不只是 `swift-test`),别当成真失败。

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
