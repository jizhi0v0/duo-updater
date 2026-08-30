# Thunderbird

> 审计 2026-06-04 · 本机严格验证 + **修复完成**（4 个真实 bundle 跑 `channel-verify` 全绿）
> stable/beta/esr/nightly 全部正确路由；曾发现 beta/esr recipe 已坏，已用 RemotingName 修。
> 真实 bundle 验证证据见下文「如何复验」。

## 基本信息
- Bundle ID: `org.mozilla.thunderbird`
- Team ID: `43AQ936H96`（与 Firefox / Mozilla 同签名）
- 已安装版本: `151.0.1`（`CFBundleShortVersionString`）/ `15126.5.22`（`CFBundleVersion`）
- 自更新机制: Mozilla 自研更新器（Balrog/AUS，非 Sparkle）—— `SUFeedURL` 不存在
- Homebrew cask: `thunderbird`，**`auto_updates: true`** → `HomebrewCaskSource` 返回 nil，
  穿透到 VendorProbe（cask 只是元数据，不是检测通道）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

> ✓ = 已验证可用  ○ = 可接入(未实现)  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —(auto)  | —   | —      | ✓           |
| **beta**     | —       | —        | —   | —      | ✓（独立 bundle id `…thunderbirdbeta`）|
| **esr**      | —       | —        | —   | —      | ✓（RemotingName 检测）|
| **nightly**  | —       | —        | —   | —      | ✓（Daily，独立 bundle id）|

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**
（Sparkle 无；Homebrew `auto_updates` 让位；无 MAS / GitHub 源）。

## Channel 详情（本机真实 bundle 实测，非 JSON 推断）

**修复后**：channel 由 `ReleaseChannel.detect()` 最高优先级的 Mozilla `RemotingName`
信号判定（`AppScanner` 从 `Contents/Resources/application.ini` 读取，每个 Mozilla 构建
烤死、不启动即可读）。product-details JSON 的 `…esr`/`…b3` 后缀**不进**安装包的
`CFBundleShortVersionString`，所以旧的版本后缀检测对 beta/esr 失效——已不再依赖它。

| Channel | 真实 Bundle ID | 真实短版本 | `RemotingName` | detect() 结果 | recipe 触发？ |
|---------|---------------|-----------|----------------|--------------|--------------|
| stable  | `org.mozilla.thunderbird`       | `151.0.1` | `thunderbird`         | `stable` ✓ | ✓ |
| esr     | `org.mozilla.thunderbird`       | `140.11.1`（无 esr） | `thunderbird-esr` | `esr` ✓ | ✓（RemotingName，不再被推 stable） |
| beta    | `org.mozilla.thunderbirdbeta`   | `152.0`（无 b3） | `thunderbird-beta` | `beta` ✓ | ✓（recipe bundle id 已改对） |
| nightly | `org.mozilla.thunderbird-daily` | `153.0a1` | `thunderbird-nightly` | `nightly` ✓ | ✓ |

> 四个真实 bundle 都跑过 `channel-verify` 实测确认。nightly 的 `a1` 后缀是唯一**没被**
> 安装包剥掉的（版本后缀检测对它仍成立），但现在统一由 RemotingName 主判，更稳。

## 更新检测
- 源: VendorProbe（`VendorProbeRecipe.swift:624` 起）
- 端点: `https://product-details.mozilla.org/1.0/thunderbird_versions.json`（一个 JSON 全 channel）
- **版本方案校验（Phase 3½）**：
  - stable `151.0.1` == 安装版短版本 ✓；nightly `153.0a1` == Daily 短版本 ✓。
  - esr：端点 `140.11.1esr` ≠ 安装版 `140.11.1`（带 esr 后缀，需剥）。
  - beta：端点 `152.0b3` ≠ 安装版 `152.0`，且**整个 beta 周期内安装版恒为 `152.0`**
    （b1…bN 不变）→ beta→beta 升级从短版本根本不可检测。

## Changelog
- 来源: 无结构化 ChangelogRecipe；三条 recipe 的 `changelogURL` 指向
  `https://www.thunderbird.net/thunderbird/releases/`，由工作台 WebView 内嵌官网页兜底
- 跟随 channel: 否（一个 releases 页覆盖全部 channel）
- Recipe 状态: 不需要（WebView 兜底足够；如要内联结构化条目可后补）

## 一键安装
- 状态: **已接入**，best-effort 就地 dmg 替换，叠在 Thunderbird 自己的更新器之上
  （Team `43AQ936H96`）。此前本节记为「仅检测」、并称「三条 recipe 均无安装链」——
  两句都已不成立，recipe 带 `install: VendorInstallSpec`。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- ⚠️ 与 Firefox 同理：Mozilla 更新器不是 Squirrel/Sparkle，`SelfUpdaterStaging` 不覆盖它，
  唯一的闸是 `vendorInstallPolicy`。
- 格式: dmg（官网直发）
- 阻塞: 无需求——自更新器接管。

## 已修（2026-06-04）
1. `ReleaseChannel.detect()` 加最高优先级 `mozillaRemotingName` 信号；`AppScanner`
   对 `org.mozilla.*` app 读 `application.ini` 的 `RemotingName`。
2. beta recipe `bundleID` 改 `org.mozilla.thunderbirdbeta`。
3. esr 不再误判 stable → 跨 channel 误推已消除。
4. 同根问题的 **Firefox** 也一并修了（beta/esr/devedition），见
   [`docs/app-audits/org-mozilla-firefox.md`](org-mozilla-firefox.md)。
5. 加了单测 `mozillaRemotingNameIsAuthoritative` + `scannerTagsMozillaChannelViaRemotingName`；
   270 个 core 测试全过。

## 已知限制
- **beta→beta 周期内不可检测**：安装版整周期恒 `152.0`（b1…bN 不变），短版本比不出，
   只能检测跨大版本（153.0bN）。已接受。若要周期内检测需用 `application.ini` 的 `BuildID`
   （`20260522225032`，单调递增）——新机制，暂不做。
- **alpha (`54.0a2`)**：陈旧冻结值，`detect()` 把 `a` 后缀统一归 `.nightly`，不单独覆盖。
- **nightly/daily 周期内同样不可检测，而且比 beta 严重**（测于 2026-08-30）。
   Mozilla 的 nightly **每天**出构建，整个周期全叫 `157.0a1`；product-details 报的
   marketing 串与安装版逐字相同，recipe 又不发 build，于是 `UpdateChecker.evaluate()`
   走 marketing 分支、`isNewer("157.0a1","157.0a1")` 恒假 → **整整一个 ~4 周周期一次
   更新都不报**。beta 至少每两天才漏一次，nightly 是天天漏。适用 `org.mozilla.nightly`
   与 `org.mozilla.thunderbird-daily`。
   2026-06-04 那次记录把「远程 == 安装版」记成了 ✓（确实没有幽灵更新），没有往下推出
   「因此新构建永远看不见」这一步。
- **远程侧的 BuildID 来源已找到：Mozilla 自己的 AUS**（`aus5.mozilla.org`，即
   `application.ini` 里 `[AppUpdate] URL` 指的那个）。它直接返回
   `buildID="20260826090609"`，与安装版 `application.ini` 的 `BuildID` **逐字节相同**，
   同时给 `displayVersion="155.0 Beta 5"`。2026-08-30 实测 5 条通道全部作答
   （FF beta / FF aurora=DevEdition / FF nightly / TB beta / TB daily），
   且与 `…-latest` 下载链接给的包一致。
   URL 形状：`/update/6/<Product>/<Version>/<BuildID>/Darwin_aarch64-gcc3/en-US/<channel>/Darwin%2025.0.0/default/default/default/update.xml`
   —— 注意必须凑满 10 段（漏掉 `%SYSTEM_CAPABILITIES%` 会返回空）。
   **未解决的一点**：AUS 的应答取决于**传入的版本号**，传 `100.0` 会返回 watershed 的
   `125.0 Beta 9` 而不是最新；所以锚点不能写死（约两年后静默退化，且 verify 抓不到，
   因为 watershed 的 build id 是往上走的、不构成版本回退）。正确做法是代入**已装版本**，
   而 `resolveEndpoint` 目前拿不到 `InstalledApp` —— 那是共享请求路径的改动，
   另案处理，不在本次范围。
   （已排除的两条路：buildhub 的「频道最新」是已构建未推送的 `156.0b1`，与
   `beta-latest` 实际服务的 `155.0b5` 不一致，用它会造成永久幻影；`firefox.json`
   的 key 是按字符串排序的全量历史，`entryStartPattern` 切片会吞掉文件尾部。）

## 部署提醒
- 改的是 core 的扫描/检测逻辑。菜单栏 App 要 `xcodebuild` 重建才会生效（`swift test`
  只编 core 包，不更新 app 二进制）。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify "/Applications/Thunderbird.app" --expect stable
swift run --package-path application-test channel-verify "/tmp/tb-daily.dmg" --expect nightly
swift run --package-path application-test channel-verify "/tmp/tb-esr.dmg"   --expect esr
swift run --package-path application-test channel-verify "/tmp/tb-beta.dmg"  --expect beta
```
