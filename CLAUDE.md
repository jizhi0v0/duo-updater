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
