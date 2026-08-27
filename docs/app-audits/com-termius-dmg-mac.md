# Termius

审计 2026-08-27（issue #91）。

## 基本信息

Termius 的 stable 在这台机器上以 **两种完全不同的发行形态** 存在，各有自己的
bundle id——这是 issue #91 本身没有说清楚的地方，见下「issue 核对」。

- 官网 / 下载页: https://termius.com/download/macos
- Beta 计划页: https://termius.com/beta-program
- 观测版本（两条形态、两个渠道，当天全部相同）: `9.43.1`
- Team ID: `6KN952WR85` — Termius Corporation，`spctl` 判定 "Notarized Developer ID"
- 自更新机制: **electron-updater**（`NSPrincipalClass = AtomApplication`，
  `Contents/Resources/app-update.yml` 声明 `provider: s3`）

| 形态 | Bundle ID | 沙盒 | 来源 |
|---|---|---|---|
| Mac App Store 购买 | `com.termius.mac` | 是（`_MASReceipt` + `com.apple.security.app-sandbox`）| App Store |
| 官网直接下载 | `com.termius-dmg.mac` | 否 | `download.termius.com` / `autoupdate.termius.com` |
| Beta（官网） | `com.termius-beta.mac` | 否 | 同上，`-beta-universal` 路径 |

## issue 核对

**issue 说 `com.termius.mac`「appears in no registry — this is not only a
channel gap, it is a whole app we do not answer for」。这条断言不准确**：

- `com.termius.mac` 确实不在任何 registry 里——但那是因为它 **不需要**。装机验证
  （`itunes.apple.com/lookup?bundleId=com.termius.mac&country=us&entity=macSoftware`，
  2026-08-27）返回 `resultCount: 1`、`kind: "mac-software"`、`version: "9.43.1"`——
  和本机 `_MASReceipt` 的沙盒装机完全一致。`MacAppStoreSource` 对任何
  `app.isMASApp` 的装机都通用生效，**不经过任何 registry**，所以这条 bundle id
  已经被回答，issue 说的「we do not answer for it」不成立。
- issue 检查 registry 时漏了一件事：**同一个 vendor 用了两个不同的 bundle id**
  分流 MAS 与直接下载（`com.termius.mac` vs `com.termius-dmg.mac`），装机的
  `Info.plist` 是权威证据——`com.termius.mac` 是 MAS 沙盒副本，`com.termius-dmg.mac`
  才是官网 dmg 的真实 id。这条区分是这份审计新确认的。
- **真正需要覆盖、也真正缺失的 `com.termius-dmg.mac`，其实已经在 `VendorProbeRecipe`
  里注册了**（2026-08-16 提交，早于本 issue 提出的 2026-08-27），本 PR 之前就存在。
  issue 说它「appears in no registry」时查的显然是 `com.termius.mac`，从未查过
  `com.termius-dmg.mac`。
- issue 关于「where does a version come from — 这是没做的活」这条判断是**对的**，
  而且是本 PR 真正要交付的部分：Beta 此前完全没有 recipe，本 PR 补上。
- issue 提到「Whether stable and beta share a version scheme...both read 9.43.1
  today」——已验证：截至 2026-08-27，三份独立 feed（`mac-universal`、`mac-arm64`、
  `mac-beta-universal`）版本号相同，但这是**巧合而非架构保证**（三个是三份独立文件，
  不是一份共享 manifest），随时可能分叉，recipe 已按各自独立端点实现，不依赖这条
  巧合。

**本审计还发现两条 issue 未涉及、且发现前既存于仓库的问题**（均已作为独立任务标记，
不在本 PR 修复范围）：

1. **`com.termius-dmg.mac` 现有 recipe 的一键安装装错架构**：其 `install` 固定指向
   `https://autoupdate.termius.com/mac-arm64/Termius.dmg`——挂载后 `lipo -info`
   证实是 **纯 arm64**（Non-fat file）。Intel Mac 上一键安装会装上一个打不开的
   二进制。
2. **该 recipe 的 `changelogURL` 已经 404**：`https://termius.com/release-notes`
   在 2026-08-27 直接返回 404（`curl` 复测，不是 HEAD 误报），且该路径不在
   `https://termius.com/sitemap.xml` 里——网站已经改版，没有替代的 changelog 页。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable (MAS)** `com.termius.mac` | — | — | ✓（通用） | — | — |
| **stable (dmg)** `com.termius-dmg.mac` | — | ✗ | — | — | ✓ 一键（**已存在的架构 bug，见上**）|
| **beta** `com.termius-beta.mac` | — | — | — | — | ✓ 一键（本 PR 新增）|

当前生效源：MAS 装机 → **App Store**（通用，无 registry）；官网 dmg 装机 →
**VendorProbe**（stable/beta 各自独立 recipe）。

- **Sparkle** — 三种形态的 `Info.plist` 都没有 `SUFeedURL`。
- **Homebrew** — cask `termius` 存在，`auto_updates true`，`HomebrewCaskSource`
  按设计返回 nil；cask 的 `livecheck` 反而是找到官网 feed host 的线索（见下）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable (MAS) | `com.termius.mac` | 独立 | — | — | ✓（`MacAppStoreSource` 通用覆盖）|
| stable (dmg) | `com.termius-dmg.mac` | 独立 | — | — | ✓（已存在，本 PR 未改）|
| beta | `com.termius-beta.mac` | 独立 | `CFBundleName`="Termius Beta" | `channelWord` 标准词匹配，无需新规则 | ✓（本 PR 新增）|

Beta 是 Pattern A（issue 判断准确）：三个 bundle id 两两独立，`ReleaseChannel.detect()`
不需要任何新规则——`channelWord` 现有的标准词表（`beta`）已经能从
`CFBundleName`/`CFBundleDisplayName` = "Termius Beta" 里识别出来（`DuoUpdaterCore/
Sources/DuoUpdaterCore/Models/ReleaseChannel.swift` 未改动，直接用测试验证了这个行为，
见 `TermiusProbeRecipeTests.detectResolvesTermiusBetaFromItsDisplayNameAlone`）。

## 更新检测

### 端点是怎么找到的

app 自带的 `Contents/Resources/app-update.yml`：

```yaml
provider: s3
bucket: termius.desktop.autoupdate
region: us-east-1
endpoint: https://s3.amazonaws.com
acl: private
path: mac-universal
updaterCacheDirName: termius-updater
```

`acl: private` 不是摆设——直接对着这份 config 猜出的 S3 路径（
`https://download.termius.com/mac-universal/latest-mac.yml`、
`https://download.termius.com/latest-mac.yml`）实测均为 **403**（`urllib` 复测，
非 HEAD 误报）。真正能公开读到 `latest-mac.yml` 的host不是这个S3域，而是
**`autoupdate.termius.com`**——线索来自 Homebrew cask 的 `livecheck` 块：

```ruby
# Casks/t/termius.rb
livecheck do
  url "https://autoupdate.termius.com/mac/latest-mac.yml"
  strategy :electron_builder
end
```

这条 cask 元数据是 2026-08-16 那条既存 recipe 的落地依据（其注释未明写来源，
本次审计重新核实并补充）；本 PR 沿着同一台 host 找到了 Beta 的路径。

### 各路径的真实内容（2026-08-27 实测，`curl`/`urllib` 直读，非猜测）

| 路径 | `version` | dmg size (bytes) | 架构（`lipo -info` 挂载实测）|
|---|---|---|---|
| `autoupdate.termius.com/mac/latest-mac.yml` | 9.43.1 | 175860846 | 未挂载（Intel-only，cask 的无后缀 arch）|
| `autoupdate.termius.com/mac-arm64/latest-mac.yml` | 9.43.1 | 169439149 | **纯 arm64**（Non-fat，已挂载验证）|
| `autoupdate.termius.com/mac-universal/latest-mac.yml` | 9.43.1 | 249384231 | **x86_64 + arm64**（已挂载验证）|
| `autoupdate.termius.com/mac-beta-universal/latest-mac.yml` | 9.43.1 | 249396295 | **x86_64 + arm64**（已挂载验证）|

`download.termius.com/mac-universal/Termius.dmg` 与
`download.termius.com/mac-beta-universal/Termius%20Beta.dmg`（issue 原文引用的两条
"latest" 链接）与 `autoupdate.termius.com` 对应路径下的同名文件 **字节相同**
（`Content-Length`、`Last-Modified`、`ETag` 全部一致）——是同一份产物挂在两个
CNAME 下，不是两份不同的构建。

### stable（`com.termius-dmg.mac`）——本 PR 未改动，仅审计说明

既存 recipe 读 `mac-arm64/latest-mac.yml`，一键装 `mac-arm64/Termius.dmg`——
装机验证（挂载）它是纯 arm64。本机是 Apple Silicon，`duo verify --only termius`
在这台机器上因此表现正常；架构 bug 只在 Intel 机器上炸，本 PR 未修（见「已知问题」）。

### beta（`com.termius-beta.mac`）——本 PR 新增

```yaml
version: 9.43.1
files:
  - url: Termius Beta.zip
    sha512: 08ovSDodx5wGBfp/vLCwf49uVACJ9Xj95aPgn7Lm+Z0exazThLdCOVf/LwrRF4hjY+lBUzm4l45lG8rk6D9cLQ==
    size: 239947907
  - url: Termius Beta.dmg
    sha512: Eo4XFtmNeDRfMA9X9N2yw2jHf7TS2o2GH4pbIbWpl2qEYBoXb7CIgIdQlLRzUb38LXO59/xUciQXgwuExlBE+w==
    size: 249396295
path: Termius Beta.zip
sha512: 08ovSDodx5wGBfp/vLCwf49uVACJ9Xj95aPgn7Lm+Z0exazThLdCOVf/LwrRF4hjY+lBUzm4l45lG8rk6D9cLQ==
releaseDate: '2026-08-12T07:56:45.216Z'
rollout:
  freeUsers: 100
  paidUsers: 100
```

- **版本方案对齐**：feed `version` = `9.43.1` = 挂载后 `CFBundleShortVersionString`。
  没有 `versionIsBuild`。
- **架构**：用的是 `mac-beta-universal`（不是 stable 那条 bug 复用的 `mac-arm64`），
  挂载确认 `lipo -info` → `x86_64 arm64`，所以 Beta 这条 **没有** stable 那个
  架构 bug，一台 recipe 服务任何 Mac，不需要 `hostRequirement`。
- **checksum 已武装**：feed 的 dmg sha512（base64）与 **实际下载字节**的
  `shasum -a 512 | base64` 完全一致——与 stable Termius 自己的两份构建
  （`mac-universal`、`mac-arm64`）一样，都不像 Signal Beta 那样被 CDN 二次 staple
  过，所以 `checksumPattern` 是安全的，不是形同虚设的字段。
- **`rollout: freeUsers/paidUsers: 100`**：当前是满量发布（100/100），这条 feed
  读的是**轨道最新**而不是**本机被分配到的构建**——没有 device id 之类的选择器，
  request 不携带任何本机身份。今天两者恰好相同（100% 全量），但架构上不等价：
  如果 vendor 未来把这两个数字调低做灰度，这条 recipe 依然会读到「轨道上已发布
  的最新版」而不是「这台机器的灰度桶」。跟 CapCut beta 是同一类可接受的例外
  （读轨道最新），记录在案，不是本 PR 引入的新风险，因为 stable 那条既存 recipe
  本来就是同一种读法。
- **没有 changelogURL**：`https://termius.com/release-notes`（stable 那条既存
  recipe 用的）已经 404，站点地图里也没有替代页，所以没有给 Beta 编一个同样会
  404 的链接，UI 走「no release notes」。`downloadURL` 用了确认存在的
  `https://termius.com/beta-program`（200，真实的 Beta Program 落地页）。

生产验证（`swift run --package-path CLI duo verify --only termius`，2026-08-27，
本 worktree 构建）：

```
vendor probe  ✓ 2  ⚠ 0  ✗ 0  ~ 0  - 0
```

`--samples --report` 的 JSON 输出（两条都 `"status": "ok"`，`"warnings": []`）：

```json
{
  "bundleID": "com.termius-beta.mac", "channel": "beta",
  "version": "9.43.1", "status": "ok", "warnings": []
},
{
  "bundleID": "com.termius-dmg.mac", "channel": "stable",
  "version": "9.43.1", "status": "ok", "warnings": []
}
```

空 `warnings` 说明 `installURLUnresolved` 和 `checksumPatternNoMatch` 都没触发——
Beta 的一键 URL 和 sha512 都在生产路径上解出来了。

`swift test`（DuoUpdaterCoreTests 的 `vendorResolvesInstallPlans`，同一天，打生产
端点）里 Termius Beta 一行：

```
• com.termius-beta.mac [beta]: v9.43.1  [dmg] sha512✓
    https://autoupdate.termius.com/mac-beta-universal/Termius%20Beta.dmg
```

## Changelog

**没有接。** 站点没有可用的 release notes 页（见上「issue 核对」的第 2 条发现）。
既存 stable recipe 的 `changelogURL` 已死，Beta 新 recipe 干脆不设。

## 一键安装

- **stable (`com.termius-dmg.mac`)**：已启用（本 PR 之前就有），但**装的是 arm64-only
  产物，Intel Mac 上会装出打不开的 app**——已知问题，已拆分为独立任务，未在本 PR 修。
- **beta (`com.termius-beta.mac`)**：本 PR 新启用，`kind: .dmg`，`urlSource: .fixed`
  （feed 里的文件名 `Termius Beta.dmg` 不带版本号，无法从 body 里解析出来，只能用固定
  URL——和既存 stable recipe 处理未带版本号文件名的方式一致）。装的是 **universal**
  产物（挂载验证 `x86_64 arm64`），Intel/Apple Silicon 都能装。
  - **读的是**：轨道最新（`rollout: 100/100`，见上）。今天等价于「人人可从
    `termius.com/beta-program` 拿到的构建」，vendor 未来做灰度时可能不再等价，
    已在「更新检测」一节记录，接受同 stable 一致的既有做法。
  - `ChannelProofRegistry` 已登记（`ChannelArtifactProof.swift`）：
    `ChannelProofKey("com.termius-beta.mac", .beta): .artifact(#"/mac-beta-universal/"#)`——
    独立 bundle id 已经隔离了跨渠道风险，这条是 belt-and-suspenders，断言解析出的
    安装 URL 路径里确实带 `mac-beta-universal`。
  - 强制闸（`VendorInstaller`）：Notarized Developer ID + Team `6KN952WR85` +
    bundle id 一致——挂载已验证 Team 与 stable 相同。

## 已知问题

1. **`com.termius-dmg.mac` 一键安装在 Intel Mac 上会装错架构**（详见上文「issue
   核对」与「更新检测」）。已拆分为独立任务，不在本 PR 范围。
2. **`com.termius-dmg.mac` 的 `changelogURL` 已死**（404，站点无替代页）。已拆分
   为独立任务的一部分记录，不在本 PR 范围（不影响功能，只影响 changelog 展示，
   降级为「no release notes」）。
3. Beta 的一键读的是**轨道最新**而非**本机分配**（`rollout` 字段今天满量，无 device
   id 选择器）——继承自既存 stable recipe 的同一读法，不是本 PR 引入的新差异。

## 建议下一步

1. 修 `com.termius-dmg.mac` 的架构 bug：改用 `mac-universal` 的 feed + dmg（已验证
   版本相同、universal 架构），而不是 `mac-arm64`。
2. 修或移除 `com.termius-dmg.mac` 的 `changelogURL`（当前 404）。
3. 若 vendor 未来把 `rollout.freeUsers`/`paidUsers` 降到 100 以下，需要重新评估
   Beta（以及既存 stable）recipe 是否应该改读「本机分配」而非「轨道最新」——目前
   无法从这份 electron-builder 静态 manifest 得到 device 级别的分配信息。
