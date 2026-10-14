# OpenInTerminal

## 基本信息
- Bundle ID: `wang.jianing.app.OpenInTerminal`（2.1.1 起；2.0.5 及以前是 `wang.jianing.OpenInTerminal`，
  **未覆盖**，见「改名前旧 id」）
- Team ID: `C8VX3ZLX5U`（2.3.9 起；2.3.8 的签名 Team 是 `Q33U8R4U57`，同一署名 “Jianing Wang”）
- 观测版本: `2.3.9`（`CFBundleVersion` 恒为 `1`，不参与比较）
- 自更新机制: 无（包内无 `SUFeedURL`，无 Sparkle / electron-builder 配置；`feed-discover` 结论
  “no Sparkle and no electron-builder update config”）
- 分发: GitHub Releases（`Ji4n1ng/OpenInTerminal`）/ Homebrew cask `openinterminal`（下载同一个
  `OpenInTerminal.zip`，非 `auto_updates`）。无 MAS。
- 开源: 是。仓库根的 `build-signed.sh` 构建、Developer ID 签名、公证并 staple 三个 app，
  输出 `export/<App>.zip` 供手动上传；仓库没有 release workflow，tag 与上传是手工的。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`channel-verify` 实测）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `wang.jianing.app.OpenInTerminal` | 单一渠道 | — | tag `^vX.Y.Z$` + 资产名 `OpenInTerminal.zip` | ✓ |
| 改名前旧 id | `wang.jianing.OpenInTerminal`（≤ 2.0.5） | 独立 | bundle id | 无规则 | 未接入（有意，见下） |

单渠道：最近 30 个 release 全部非 prerelease、非 draft（2026-09-29，`gh api .../releases?per_page=30`）。

### 同仓库的另外两个产品
同一仓库、同一 tag 命名空间还发布 OpenInTerminal-Lite 与 OpenInEditor-Lite：主 app 是 `v2.x`
（资产 `OpenInTerminal.zip`），Lite 是 `v1.x`（资产 `OpenInTerminal-Lite.zip`、
`OpenInEditor-Lite.zip`，有时带 `Icons.zip`）。两者通常同时发布（v2.3.9 与 v1.2.8 的
`created_at` 相同，`published_at` 相差 14 秒）。tag 形状区分不了两者，所以规则靠资产名：
- 规则设了 `installAssetPattern: ^OpenInTerminal\.zip$`。若 `/releases/latest` 返回的是 Lite
  release，它没有匹配资产，`settle()` 回落到 releases 列表并跳过所有 Lite release。
- 2026-09-29 `/releases/latest` 实际返回 `v2.3.9`；Lite 在前的情形用临时 Swift 测试验证过
  （stub 让 `/releases/latest` 回 `v1.2.8`，列表为 `v1.2.8, v2.3.9, v1.2.7, v2.3.8`，
  真实规则经 `resolveDiagnostic` 得到 `2.3.9` / `OpenInTerminal.zip`、failure=nil；测试未提交）。
- 余量：Lite release 的 tag 同样匹配 `versionPattern`，会计入 `maxReleasesWithoutMacOSAsset`（5）。
  历史上主 app 与 Lite 基本成对出现，连续 5 个仅 Lite 的 release 没有出现过；若出现，规则会
  报资产未匹配（不会给出错误版本）。

OpenInTerminal-Lite 的 bundle id 是 `wang.jianing.app.OpenInTerminal-Lite`（v1.2.8 真包：
short `1.2.8` == tag，universal，Team `C8VX3ZLX5U`，`spctl` Notarized Developer ID）。本次**未接入**，
见「建议下一步」。

### 改名前旧 id（≤ 2.0.5）：有意不覆盖
主 app 在 2.0.5 与 2.1.1 之间改过 bundle id（中间没有 2.1.0 tag/release）。直接下载的 2.0.5
及更早副本是 `wang.jianing.OpenInTerminal`，recipe 只按新 id 建键，所以这类副本**没有检测**。
这是 2026-10-14 审过之后的取舍，不是遗漏。

实测（2026-10-14）：
- 源码：`OpenInTerminal.xcodeproj/project.pbxproj` 的主 app `PRODUCT_BUNDLE_IDENTIFIER`，tag
  `0.10.0`、`2.0.1`、`2.0.5` 是 `wang.jianing.OpenInTerminal`，`2.1.1`、`2.2.3`、`v2.3.9` 是
  `wang.jianing.app.OpenInTerminal`。
- 真包（release 资产 `OpenInTerminal.app.zip`，`ditto -x -k` 解压，只读不运行）：

  | | 2.0.5 | 2.1.1 |
  |---|---|---|
  | `CFBundleIdentifier` | `wang.jianing.OpenInTerminal` | `wang.jianing.app.OpenInTerminal` |
  | short / build | `2.0.5` / `1`（short == tag） | `2.1.1` / `1` |
  | Team / 证书 | `C8VX3ZLX5U`，`Mac Developer: Jianing Wang`（开发证书） | `Q33U8R4U57`，Developer ID |
  | 公证 | 无 ticket，`spctl` rejected | stapled，`spctl` Notarized Developer ID |
  | 架构 | x86_64 | x86_64 |
  | zip SHA-256 | `ecc02de4…18df22` | `9267950f…c999b1` |

不接入的理由：
- **`BundleIDMigration` 闸门上走得通，但不登记**：
  - 走得通：表只拿已装副本与下载的 Team 跟条目比（`BundleIDMigration.migration`、Gate 3 都只比这两个），
    2.0.5 与今天的 2.3.9 都是 `C8VX3ZLX5U`；2.1.1–2.3.8 的 `Q33U8R4U57` 不参与比较；Gate 3 也不要求
    已装副本是 Developer ID。登记后检测走主规则，Lite 的资产名回退照样生效。
    2026-10-14 用临时 Swift 测试在真包上跑过（已装 = 2.0.5 解压包，下载 = v2.3.9 解压包；测试未提交）：
    不登记时 Gate 4 拒绝（`Bundle identifier mismatch: installed “wang.jianing.OpenInTerminal” vs
    downloaded “wang.jianing.app.OpenInTerminal”`）；传入上面那条假设条目后 Gate 2、3、4、5、5b、6
    全部通过，`recipeBundleID` 把旧副本归到新 id。
  - 不登记的理由是设置：新版读不到旧版的设置。
    - 2.0.5 把设置写在 `UserDefaults.standard`，即旧 bundle id 的域 `wang.jianing.OpenInTerminal`
      （上游 2.0.5 `OpenInTerminalCore/Defaults.swift`：`let Defaults = UserDefaults.standard`）。
    - v2.3.9 主 app 读 `UserDefaults(suiteName: "group.wang.jianing.app.OpenInTerminal")`，取不到时
      回落到自己的 `UserDefaults.standard`（新 id 的域）（上游 v2.3.9 同一文件）。两个域都不是旧域。
    - v2.3.9 真包里每个 Mach-O 的 `strings`（不分大小写）：旧 id 只出现在 login-item helper（判断主 app
      是否在跑），没有旧 group，也没有 `addSuiteNamed`；唯一的 persistent-domain 调用是
      `removePersistentDomainForName:`，对应上游 `DefaultsManager.removeAllUserDefaults()` 删除**新** group 域
      （`Constants.Id.Group`）的重置功能。即发布的二进制里没有读旧域的代码。
    - 所以换成新 id 的包从空设置起步，旧设置留在旧域里不会被读。以上读源码与真包二进制得出，
      没有实际运行 app。
    登记会连一键一起打开（表的四处读取不分检测与一键），而这跟 Spotifast 不登记的理由相同：
    会丢设置的跨 id 替换，指向 release 页让用户自己装才是诚实的做法。
- **Spotifast 式的只检测规则在这里不安全**：只检测规则不设 `installAssetPattern`，`settle()` 就不做
  缺资产回退，也就挡不住同仓库 Lite 的 `v1.x` release（见上一节，主规则正是靠资产名挡它）。
  GitHub 的 `/releases/latest` 按 `created_at`（release 所指 commit 的日期，不是发布时间）排序
  （[文档](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)），而 v2.3.9 与
  v1.2.8 的 `created_at` 完全相同（`2026-07-13T11:56:06Z`）；相同时取哪个文档没说。2026-10-14
  实测返回 v2.3.9，但一旦返回 v1.2.8，旧副本会被报成「已是最新」（1.2.8 < 2.0.5），而且版本历史
  会混入 Lite 的版本——比不检测更糟。把 tag 锚到 `^v(2\.…)$` 能挡住 Lite，但主 app 到 v3 或 Lite
  到 v2 时就要重改，为 2019 年的未公证开发签名包不值得。
- 版本比较本身没问题：旧包 short == tag，按主规则的 tag 方案 2.0.5 < 2.3.9。将来若改主意接入，
  可走的路是登记 `BundleIDMigration`（`teamID: "C8VX3ZLX5U"`、`lastFromVersion: "2.0.5"`、
  `firstToVersion: "2.1.1"`），前提是接受或先实测上面的设置丢失；单独按旧 id 写规则则卡在 Lite 歧义。

## 更新检测
- 源: `Ji4n1ng/OpenInTerminal` GitHub Releases，`/releases/latest`（资产不匹配时回落列表）
- 版本方案: tag `v2.3.9` → `2.3.9` == 包的 `CFBundleShortVersionString`（2.3.8 同样相等）。
  资产名不带版本号；2022 年及以前叫 `OpenInTerminal.app.zip`，自 v2.3.7 起是 `OpenInTerminal.zip`。
- 注意事项: 早年 tag 有不带 `v` 的（`2.2.3`、`1.1.5` 等，2020 年），不匹配 pattern，均非最新，不影响。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 无自更新器（无 `SUFeedURL`） | release 只有整包 zip（2026-09-29） | — |

## 按 OS 分轨
- `LSMinimumSystemVersion` = `10.13`（2.3.8、2.3.9 相同）；无上限声明。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 经 `GitHubMarkdownParser` 结构化带回；
  `channel-verify` 显示 changelogURL 指向 `releases/tag/v2.3.9`）
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 2.3.8 检查）: ✓ 8 条纯列表，无小标题（正文本身没有标题行）；只带回最新一版的说明（1 个条目）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（从 2.3.9 起的安装）
- 格式: zip — `OpenInTerminal.zip`，universal（`x86_64 arm64`）
- Pattern: `^OpenInTerminal\.zip$`, kind `.zip`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；Homebrew cask 下载的是同一个 URL）
- 包验（2026-09-29，v2.3.9 解压）: `wang.jianing.app.OpenInTerminal` / `2.3.9`，
  Team `C8VX3ZLX5U`，`Notarization Ticket=stapled`，`spctl accepted / Notarized Developer ID`
- 包内有 Finder Sync 扩展与登录项 helper（`Contents/Library/LoginItems`），整包替换会一起换掉。
  helper（`OpenInTerminalHelper/AppDelegate.swift`）只在登录时拉起主 app 后即退出，不常驻，
  所以不存在换包后旧进程继续跑的问题。
- ⚠️ Team 变更: v2.3.8 包的 Team 是 `Q33U8R4U57`，v2.3.9 是 `C8VX3ZLX5U`。`SignatureVerifier`
  的 Team-ID 闸要求已装与下载一致，所以从 2.3.8（以及其他 `Q33U8R4U57` 签名的旧版）一键到 2.3.9
  会被拒绝；检测仍会报出更新，用户需手动下载一次。2.3.9 之后的版本
  若保持 `C8VX3ZLX5U`，一键正常。
- 端到端（2026-09-29）: 装 2.3.8 → `duo check` 报 `2.3.8 → 2.3.9 [GitHub, in-place]` → `duo install --yes`
  在 verifyingCodeSignature 失败：`Team Identifier mismatch: installed “Q33U8R4U57” vs downloaded
  “C8VX3ZLX5U”. Refusing to install.`；已装的 2.3.8 原样保留（版本、Team、`codesign --verify` 均不变）

## 已知问题
- 上述 Team 变更使旧版一键被 Team-ID 闸拒绝（fail-closed，不会替换）。
- 改名前旧 id `wang.jianing.OpenInTerminal`（≤ 2.0.5）的副本没有检测，有意为之，理由见
  「改名前旧 id（≤ 2.0.5）」。

## 如何复验
```
# GET https://api.github.com/repos/Ji4n1ng/OpenInTerminal/releases/latest → v2.3.9
# ditto -x -k OpenInTerminal.zip（v2.3.9）→ wang.jianing.app.OpenInTerminal / 2.3.9 / Team C8VX3ZLX5U
swift run --package-path application-test channel-verify <v2.3.9>/OpenInTerminal.app --expect stable
#   → winning source GitHub, latest 2.3.9, status up to date
swift run --package-path application-test channel-verify <v2.3.8>/OpenInTerminal.app --expect stable
#   → winning source GitHub, latest 2.3.9, status UPDATE → 2.3.9
# 改名前旧 id（2.0.5 → wang.jianing.OpenInTerminal，2.1.1 起 wang.jianing.app.OpenInTerminal）
gh api 'repos/Ji4n1ng/OpenInTerminal/contents/OpenInTerminal.xcodeproj/project.pbxproj?ref=2.0.5' --jq .content | base64 -d | grep PRODUCT_BUNDLE_IDENTIFIER
gh release download 2.0.5 -R Ji4n1ng/OpenInTerminal -p OpenInTerminal.app.zip   # 解压后只读，不运行
gh api 'repos/Ji4n1ng/OpenInTerminal/contents/OpenInTerminalCore/Defaults.swift?ref=2.0.5' --jq .content | base64 -d | grep 'UserDefaults'   # → UserDefaults.standard
gh api 'repos/Ji4n1ng/OpenInTerminal/contents/OpenInTerminalCore/Defaults.swift?ref=v2.3.9' --jq .content | base64 -d | grep -n 'Defaults'   # → GroupDefaults ?? .standard
find <v2.3.9>/OpenInTerminal.app -type f -exec sh -c 'file -b "$1" | grep -q Mach-O && strings -a "$1" | grep -iE "jianing|persistentDomain|addSuiteNamed" | sed "s|^|$1: |"' _ {} \;   # 旧 id 只在 helper；无旧 group；只有 removePersistentDomainForName:（删新 group 的重置）
# Lite 与主 app 的 created_at 是否仍相同（决定 /releases/latest 能否落到 Lite）
gh api 'repos/Ji4n1ng/OpenInTerminal/releases?per_page=4' --jq '.[]|[.tag_name,.created_at]|@tsv'
```

## 建议下一步
1. OpenInTerminal-Lite（`wang.jianing.app.OpenInTerminal-Lite`）可同法接入：同仓库，资产
   `^OpenInTerminal-Lite\.zip$` 会让规则跳过主 app 的 `v2.x` release。需先做同样的旧→新
   `channel-verify`。OpenInEditor-Lite 同理（bundle id 未读）。
