# iTerm2

## 基本信息
- Bundle ID: `com.googlecode.iterm2`（stable / test release / nightly 三条轨共用；zip 里的 bundle 目录名是 `iTerm.app`）
- Team ID: `H7V7XYVQ7D`（Developer ID Application: GEORGE NACHMAN；3.7.2、3.7.3、3.7.4beta1、两份 nightly 五个真包一致，`spctl` 判 Notarized Developer ID）
- 观测版本: stable 3.7.3（`CFBundleVersion` 3.7.3），上一版 3.7.2；test release 3.7.4beta1；nightly 3.7.20261008-nightly（上一份 3.7.20261007-nightly）。全部取自 iterm2.com 官方 zip，`ditto -x -k` 解包读取，2026-10-08
- 自更新机制: Sparkle（厂商自己的 fork，框架 `CFBundleVersion` 1.22.0，Info.plist 带 `SUPublicEDKey`）
- 架构 / OS: universal（x86_64 + arm64）；`LSMinimumSystemVersion` 13.0（stable / beta / nightly 相同）
- 开源: `gnachman/iTerm2`，下文「settled from source」均指该仓库 `master`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                  | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------------|---------|----------|-----|--------|-------------|
| **stable**       | ✓       | ✗        | —   | —      | —           |
| **beta**（test release） | ○ | ✗       | —   | —      | —           |
| **nightly**      | ✓       | 见注     | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（三条轨都是；Homebrew 例外见下）。

- Homebrew：cask `iterm2`（3.7.3）与 `iterm2@beta`（3.7.4beta1）都是 `auto_updates: true`，
  `HomebrewCaskSource` 让位，落到 Sparkle。`iterm2@nightly`（`3_7_20261007`）**没有** `auto_updates`，
  所以**用 brew 装的** nightly 副本会由排在 Sparkle 前面的 `HomebrewCaskSource` 应答（读代码得出，未端到端跑）。
  生产 `VersionComparator` 实测：`isNewer("3_7_20261007", than: "3.7.20261008-nightly") = false`、
  `isNewer("3_7_20261009", than: "3.7.20261008-nightly") = true`——下划线版本号按数字比较，不会出幻影更新，
  只是 cask 落后于 app 自己 Sparkle 装上的 nightly 时会显示「最新」。
- GitHub —：仓库只有 tag（`vYYYYMMDD-nightly` 等），没有带资产的 release。
- MAS —：不在 App Store 发布。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.googlecode.iterm2` | 共享 | 默认（`CheckTestRelease` 缺省 = NO） | Info.plist `SUFeedURL` = `final_modern.xml` | ✓ |
| beta（test release） | `com.googlecode.iterm2` | 共享 | CFPrefs `com.googlecode.iterm2` / `CheckTestRelease` = YES | feed-swap → `testing_modern.xml` | ○ 未接，见「已知问题」1 |
| nightly | `com.googlecode.iterm2` | 共享 | 构建自身：Info.plist 三个 feed 键都写 `nightly_modern.xml`；版本带 `-nightly` | bundle 自己的 `SUFeedURL` | ✓ |

**轨道与切换方式——settled from source**（`gnachman/iTerm2` `master`）：

- `plists/release-iTerm2.plist`、`plists/beta-iTerm2.plist`：`SUFeedURL` 与 `SUFeedURLForFinal` 都是
  `https://iterm2.com/appcasts/final_modern.xml`，`SUFeedURLForTesting` 是 `https://iterm2.com/appcasts/testing_modern.xml`。
  **beta 构建的 Info.plist 与 stable 指向同一个 `SUFeedURL`**（3.7.4beta1 真包实测同样如此）——构建本身不带轨道信号。
- `plists/nightly-iTerm2.plist`：三个键都是 `https://iterm2.com/appcasts/nightly_modern.xml`。
- `sources/iTermController/iTermController.m` `refreshSoftwareUpdateUserDefaults`：读
  `kPreferenceKeyCheckForTestReleases`（`sources/Settings/iTermPreferences.m`：键名 `CheckTestRelease`，默认 `@NO`），
  YES 取 `SUFeedURLForTesting`、NO 取 `SUFeedURLForFinal`，追加 `?shard=<0..99>` 后**写进 app 自己的 user defaults 的
  `SUFeedURL`**，Sparkle 从那里读，盖过 Info.plist。启动时调一次，`CheckTestRelease` 变化时再调。
- 设置界面：Settings → General 的 test release 复选框（`GeneralPreferencesViewController.m` `_checkTestRelease`，
  绑定同一个键）；nightly 构建上该复选框禁用，并显示「nightly 不能更新到 beta/release」的提示。
- 存储位置：`iTermUserDefaults.userDefaults` = `NSUserDefaults.standardUserDefaults`，即 CFPrefs 域
  `com.googlecode.iterm2`。例外：用 `-suite <name>` 参数启动时改用该 suite（`sources/AppKit/main.m`），属非常规用法。
- `shard` 不影响响应：2026-10-08 对 `final_modern.xml` 与 `testing_modern.xml` 各请求 `shard=0..99`，
  100 份响应体 sha256 全部相同，且等于不带参数的响应——目前没有按设备灰度。

**duo 今天跟不跟这条 test-release 轨（实测 + 读代码）**：不跟。`channel-verify` 对 3.7.3 报
`ChannelBinding  <none for this app>`、`SUFeedURL https://iterm2.com/appcasts/final_modern.xml`；`AppScanner`
只读 Info.plist 的 `SUFeedURL`，读不到 app 运行时写进 user defaults 的那个地址。没有在真 app 上翻 `CheckTestRelease`
（本次审计不启动 app、不写其偏好），所以「打开后 iTerm2 自己会提示 3.7.4beta1」是从源码 + feed 内容推出的，
不是实测：`testing_modern.xml` 唯一一条是 3.7.4beta1，生产 `VersionComparator.isNewer("3.7.4beta1", than: "3.7.3") = true`。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点:
  - stable `https://iterm2.com/appcasts/final_modern.xml` — 2 条 item，均无 `<sparkle:channel>`：
    3.6.11（`minimumSystemVersion` 12.4）、3.7.3（`minimumSystemVersion` 13）。**按 OS 分桶**：macOS 12.4–12.x 停在 3.6.11。
    `SparkleAppcastSource.usableItems` 按 item 的 min/max 过滤；duo 自身要求 macOS 15，两条都可用，取 3.7.3。
  - test release `https://iterm2.com/appcasts/testing_modern.xml` — 1 条 item 3.7.4beta1（min 13.0），无 channel 标签。
  - nightly `https://iterm2.com/appcasts/nightly_modern.xml` — 3 条 item：3.4.20200713-nightly、3.5.20250702-2-nightly、
    3.7.20261008-nightly（min 12.4，而包内 `LSMinimumSystemVersion` 是 13.0），无 channel 标签。
- 三份 feed 都没有 `maximumSystemVersion`、`hardwareRequirements`、`phasedRolloutInterval`、`criticalUpdate`、
  `sparkle:shortVersionString`；`sparkle:version` = `CFBundleShortVersionString` = `CFBundleVersion`，不需要 `versionIsBuild`。
- 注意事项:
  - 厂商发版脚本只让 `tools/release_stable.sh` 写 `final_*.xml`、`tools/release_beta.sh` 写 `testing*.xml`
    （settled from source）。test release feed 不会随 stable 发版更新，它可能落后于 stable。
  - beta 副本（3.7.4beta1）在 duo 里被判为 **stable**（`inferred stable`：`beta1` 直接接在数字后，版本后缀判据不认），
    对照 stable feed 得「最新」——这与 iTerm2 自己在 `CheckTestRelease = NO` 时的行为一致；开着 test release 的
    beta 副本则看不到下一个 beta（`isNewer("3.7.4beta2", than: "3.7.4beta1") = true`，但 stable feed 里没有它）。
    下一个 stable 3.7.4 出来时会正常提示（`isNewer("3.7.4", than: "3.7.4beta1") = true`）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 无可消费 |
| 证据 | `Sparkle.framework/Versions/A/Sparkle` 的 strings 含 `SUBinaryDeltaUnarchiver`、`sparkle:deltas`、`sparkle:deltaFrom`（3.7.3 真包） | 三份 feed 均无 `<sparkle:deltas>`；`channel-verify` `deltas 0`（2026-10-08） | 若厂商开始发，`VendorAppcastDeltas` + `DeltaApplier` 是现成机制 |

- 格式: Sparkle binary delta（客户端支持，服务端未用）
- 阻塞项: 厂商不发

## Changelog
- 来源: 每条 item 的 `<sparkle:releaseNotesLink>`，指向纯文本：stable `https://iterm2.com/appcasts/full_changes.txt`、
  test release `https://iterm2.com/appcasts/testing_changes3.txt`、nightly `https://iterm2.com/appcasts/nightly_changes.txt`
  （均为 `text/plain; charset=utf-8`）。feed 里没有 inline `<description>`。
- 结构化: ✗。`channel-verify` 的 `changelog pane` 行原文：
  - stable：`web page https://iterm2.com/appcasts/full_changes.txt, no structure`
  - nightly：`web page https://iterm2.com/appcasts/nightly_changes.txt, no structure`
- 文本形状：`Version 3.7.3 of iTerm2 was built on September 22, 2026.`，然后 `Bug Fixes:` / `New Features:` /
  `Improvements:` 这类小节标题，条目以 `- ` 开头、按约 50 列硬换行（续行缩进两格）。`full_changes.txt` **只含最新一个 stable**；
  每个版本另有 `https://iterm2.com/downloads/stable/iTerm2-<ver>.changelog`（3.7.2、3.7.3 均 200），内容同一格式，
  末尾附一段 PGP 签名的 zip SHA-256。
- 跟随 channel: 是（每条轨各自一个 txt）
- Recipe 状态: 需要（○）。可用 `ChangelogRecipe` 读纯文本（`com-philandro-anydesk.swift` 是读 `.txt` 的先例），
  `sourceTemplate` 指向按版本的 `.changelog`，`headingPattern` 取 `^[A-Z][A-Za-z ]+:$`。条目是多行硬换行，
  抽取器是否会把续行的换行 + 缩进折叠成空格**未验证**，写 recipe 时要在真实响应上确认。

## 一键安装
- 状态: 需要验证（Sparkle 通用一键路径；前提已在真包上核对，端到端未跑）
- 端到端: 未跑（由协调会话串行执行）
- 格式: zip（顶层 `iTerm.app`）
- 校验:
  - EdDSA：feed 中 3.7.3 的 `sparkle:edSignature` 用 bundle 的 `SUPublicEDKey`（`xdqAa0KX…Z0w=`）对真实 zip 验签 **VALID**，
    翻转一个字节后 **INVALID**（负对照）。`length` 57887250 与下载字节数一致。
  - Team：3.7.2 与 3.7.3 都是 `H7V7XYVQ7D`，`codesign --verify --deep --strict` 通过——上一版到最新版不会被 Team 闸拒。
  - 摘要：feed 不带 sha；按版本的 `.changelog` 末尾有 PGP 签名的 SHA-256，3.7.3 为 `eb7a1660…8dc39`，与真实 zip 的
    `shasum -a 256` 相等。Sparkle 路径不读这个文件，EdDSA 已覆盖完整性，不接。
- 嵌套 bundle（`check-bundle.sh`）：只有 `Contents/MacOS/iTerm2ImportStatus.app`（`LSUIElement=true`），是设置导入时显示进度的
  小窗口，由主 app 按需拉起（`sources/Settings/ImportExport.swift`），不常驻。另有 `Contents/MacOS/iTermServer`：
  会话恢复用的常驻服务进程，但按源码（`sources/Tasks/iTermServerDeleter.swift`）它以 `iTermServer-<CFBundleVersion>`
  的**版本化副本**运行在 bundle 之外，旧副本由新版本清理——替换 bundle 不会把可执行文件从运行中的 shell 下面抽走
  （读源码得出，未实测）。
- **读的是**: 人人可手动下载的 GA——enclosure 就是 iterm2.com 下载页上公开的 zip；`shard` 参数实测不改变响应。
- 阻塞: 无已知阻塞；运行中替换 + app 自己的 Sparkle 是否抢装，待端到端那轮看。

## 已知问题
1. **test release 轨没接（与 OBS 同型）。** stable 副本在 iTerm2 里打开 test release（`CheckTestRelease = YES`）后，
   iTerm2 自己会从 `testing_modern.xml` 拿到 3.7.4beta1，duo 仍读 Info.plist 的 `final_modern.xml` 并显示「最新」。
   beta 副本同理看不到下一个 beta。需要一个 `ChannelBinding`（见建议下一步 1）。
2. **test release feed 可能落后 stable。** 只有 `release_beta.sh` 写它。iTerm2 自己在 test release 模式下只读这一份，
   所以 binding 照搬时，test release 用户会在 beta feed 追上之前看不到更新的 stable——这是厂商行为，照搬即可，
   但要在 binding 注释里写明。
3. `changelog pane` 只是一页纯文本 WebView，没有结构；`full_changes.txt` 只覆盖最新 stable，跨多版升级看不到中间版本的说明。
4. 旧版审计（2026-06-04）的几处结论不成立：只列了 stable 一条轨（漏了 test release 与 nightly）；「Changelog: Sparkle
   inline … no custom recipe needed」不对——feed 没有 inline 说明，pane 是无结构的纯文本页；「一键安装: 阻塞 无」
   当时没有任何真包验证。

## 如何复验

```sh
# 下载到自己的新目录；三份 feed 与真包
D=$(mktemp -d)
for f in final_modern testing_modern nightly_modern; do curl -sS -o "$D/$f.xml" "https://iterm2.com/appcasts/$f.xml"; done
curl -sSL -o "$D/iTerm2-3_7_3.zip" "https://iterm2.com/downloads/stable/iTerm2-3_7_3.zip"
curl -sSL -o "$D/iTerm2-3_7_2.zip" "https://iterm2.com/downloads/stable/iTerm2-3_7_2.zip"
mkdir "$D/x373" "$D/x372"; ditto -x -k "$D/iTerm2-3_7_3.zip" "$D/x373"; ditto -x -k "$D/iTerm2-3_7_2.zip" "$D/x372"

# 生产判定（仓库根目录）
swift run --package-path application-test feed-discover "$D/iTerm2-3_7_3.zip"
swift run --package-path application-test channel-verify "$D/x372/iTerm.app"
swift run --package-path application-test channel-verify "$D/x373/iTerm.app"
.claude/skills/coverage-discovery/scripts/check-bundle.sh "$D/iTerm2-3_7_3.zip"

# shard 是否改变响应
for s in $(seq 0 99); do curl -sS "https://iterm2.com/appcasts/final_modern.xml?shard=$s" | shasum -a 256; done | sort | uniq -c

# 轨道切换的源码
gh search code --repo gnachman/iTerm2 "kPreferenceKeyCheckForTestReleases"
curl -sS "https://raw.githubusercontent.com/gnachman/iTerm2/master/sources/iTermController/iTermController.m" | grep -n -A10 "refreshSoftwareUpdateUserDefaults {"
```

2026-10-08 实测：

| 包 | short / build | `SUFeedURL`（Info.plist） | Team | detected | winning source | latest | status |
|---|---|---|---|---|---|---|---|
| 3.7.2 stable | 3.7.2 / 3.7.2 | `final_modern.xml` | H7V7XYVQ7D | stable | Sparkle | 3.7.3 | **UPDATE → 3.7.3** |
| 3.7.3 stable | 3.7.3 / 3.7.3 | `final_modern.xml` | H7V7XYVQ7D | stable | Sparkle | 3.7.3 | up to date |
| 3.7.4beta1 test release | 3.7.4beta1 / 3.7.4beta1 | `final_modern.xml` | H7V7XYVQ7D | stable | Sparkle | 3.7.3 | up to date |
| nightly 20261007 | 3.7.20261007-nightly | `nightly_modern.xml` | H7V7XYVQ7D | nightly | Sparkle | 3.7.20261008-nightly | **UPDATE → 3.7.20261008-nightly** |
| nightly 20261008 | 3.7.20261008-nightly | `nightly_modern.xml` | H7V7XYVQ7D | nightly | Sparkle | 3.7.20261008-nightly | up to date |

- `feed-discover`（3.7.3 zip）→ `declared  https://iterm2.com/appcasts/final_modern.xml`
- 所有 `channel-verify` 都报 `ChannelBinding  <none for this app>`、`deltas 0`；stable 行 `release history 2 entries`，nightly 行 3
- `changelog pane`：stable 两行与 beta 行均为 `web page https://iterm2.com/appcasts/full_changes.txt, no structure`；
  nightly 两行为 `web page https://iterm2.com/appcasts/nightly_changes.txt, no structure`
- feed 形状：final 2 条 / testing 1 条 / nightly 3 条，全部无 `<sparkle:channel>`；无 deltas、phasedRollout、max OS、hardwareRequirements
- `shard=0..99`：两份 feed 各 100 份响应体 sha256 相同，且等于无参数响应
- EdDSA：3.7.3 zip VALID，翻一字节 INVALID；zip sha256 `eb7a166061e58602e3d4bdf69d92f2c8cf6a63feed002f6adc07128a71c8dc39`
- `check-bundle.sh`（3.7.2、3.7.3）：`codesign-verify-exit=0`、`spctl source=Notarized Developer ID`、
  nested 仅 `Contents/MacOS/iTerm2ImportStatus.app`（`LSUIElement=true`）
- 生产 `VersionComparator.isNewer`（临时测试，跑完已删）：`(3.7.4beta1, 3.7.3)` true、`(3.7.3, 3.7.4beta1)` false、
  `(3.7.4, 3.7.4beta1)` true、`(3.7.4beta2, 3.7.4beta1)` true、`(3.7.20261008-nightly, 3.7.20261007-nightly)` true、
  `(3.7.3, 3.7.20261008-nightly)` false、`(3_7_20261007, 3.7.20261008-nightly)` false、`(3_7_20261009, 3.7.20261008-nightly)` true

## 建议下一步
1. **加 `ChannelBinding`（IINA 型 feed-swap）**：新建 `ITerm2Channel.swift`，读 CFPrefs 域 `com.googlecode.iterm2` 的
   `CheckTestRelease`（Bool，缺省 / 读不到 → stable）。YES → `ResolvedChannel(channel: .beta, feedOverride:
   https://iterm2.com/appcasts/testing_modern.xml)`；NO → `.stable` + `final_modern.xml`。加进 `resolver(for:)`、
   `allResolutions`、`boundBundleIDs`；在新的 `Recipes/com-googlecode-iterm2.swift` 里登记 beta 的
   `bindingProofs`（照 `com-colliderli-iina.swift`：`.recipeAnchor(#"testing_modern\.xml"#, in: ["feedOverride"])`）；
   在 app-audit skill 的 2c½ 表里加一行。**nightly 必须排除**：nightly 构建的 Info.plist `SUFeedURL` 含 `nightly`
   （iTerm2 自己用这个判 `it_isNightlyBuild`，并禁用该复选框），binding 对这种副本应返回 nil 或保留 bundle 自己的 feed，
   不能因为 `CheckTestRelease` 残留为 YES 就把 nightly 改到 testing feed。
   验收：先在真 app 里翻复选框确认写入的键与值（开 / 关两种状态都读一遍），再 `channel-verify --check com.googlecode.iterm2`
   看 detected channel 跟着变；3.7.3 副本在 YES 时应得 `UPDATE → 3.7.4beta1`。
2. **结构化 changelog**：`/fragile-recipe iTerm2`（ChangelogRecipe，纯文本），stable 读
   `https://iterm2.com/downloads/stable/iTerm2-{version}.changelog`（或 `full_changes.txt`），beta 读
   `https://iterm2.com/downloads/beta/iTerm2-{version}.changelog`；小节标题形如 `Bug Fixes:`，条目 `- ` 开头、硬换行。
3. 端到端一键（协调会话）：3.7.2 → 3.7.3，两轮（未运行 / 运行中且 iTerm2 自己的 Sparkle 已暂存）。
