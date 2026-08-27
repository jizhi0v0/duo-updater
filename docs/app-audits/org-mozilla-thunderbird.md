# Thunderbird

> 审计 2026-06-04 · 本机严格验证 + **修复完成**（4 个真实 bundle 跑 `channel-verify` 全绿）
> stable/beta/esr/nightly 全部正确路由；曾发现 beta/esr recipe 已坏，已用 RemotingName 修。
> 证据：[`application-test/records/org-mozilla-thunderbird.md`](../../application-test/records/org-mozilla-thunderbird.md)

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
- 状态: **仅检测**。Thunderbird 自带 Mozilla 更新器，按本仓"Sparkle/自更新永不强杀"
  原则，不做一键替换。三条 recipe 均无 `downloadURL` 安装链（`downloadURL` 仅作为
  "打开官网"的展示链接）。
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

## 部署提醒
- 改的是 core 的扫描/检测逻辑。菜单栏 App 要 `xcodebuild` 重建才会生效（`swift test`
  只编 core 包，不更新 app 二进制）。
