# TextMate

## 基本信息
- App: TextMate 2 — MacroMates 的开源文本编辑器（`textmate/textmate`，GPL-3.0，仓库未归档；最后一次代码提交 2021-10-12，与 v2.0.23 同日）
- Bundle ID: `com.macromates.TextMate`
- Team ID: `45TL96F76G`（Developer ID Application: MacroMates Ltd.）；spctl: Notarized Developer ID
- 观测版本: 2.0.23（tag `v2.0.23`，2021-10-12，资产 `TextMate_2.0.23.tbz`，18019467 字节，bzip2 tar）；上一个正式版 2.0.19（tag `v2.0.19`，`TextMate_2.0.19.tbz`，18492495 字节）；观测于 2026-11-11
- 自更新机制: 自研（`Frameworks/SoftwareUpdate`），轮询 `https://api.textmate.org/releases/<release|beta|nightly>?v=<short>&os=<x.y.z>`，无 Sparkle、无 `SUFeedURL`；`feed-discover` 判定 `noKnownUpdater`
- 分发: GitHub Releases（每个 release 一个 `.tbz`）；`api.textmate.org/downloads/…` 302 到同一个 GitHub 资产；Homebrew cask `textmate`（2.0.23，`auto_updates: true`，url 即 GitHub 资产）；无 Mac App Store 版
- 是否还有更新: 2026-11-11 核对 —— GitHub 最新 release / 最新 tag 都是 v2.0.23；`api.textmate.org` 的 release、beta、nightly 三条轨都答 2.0.23；macromates.com/download 指向 `api.textmate.org/downloads/release`（302 到 v2.0.23）。没有找到终止维护的公告（仓库未归档，README 没有声明），只是 2021 年后没有新版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（auto_updates） | — | ✓ 一键 universal `.tbz` | ✗（见「更新检测」，与 GitHub 同字节、签名无法校验） |
| **beta**     | —       | —        | —   | ○（偏好 `SoftwareUpdateChannel`，见 Channel 详情） | — |
| **nightly**  | —       | —        | —   | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`channel-verify` 实测 `winning source GitHub`）

## 覆盖清单
- 各版本的 bundle id / Team（都读自真包 `.tbz` 解出的 `TextMate.app`）:
  - v2.0.23: `com.macromates.TextMate`，45TL96F76G，Notarized，universal（x86_64 arm64），short 2.0.23，build 9800，`LSMinimumSystemVersion` 10.12
  - v2.0.22（prerelease）: 同 id、同 Team，universal，short 2.0.22，build 9800
  - v2.0.19: 同 id、同 Team，Notarized，universal，short 2.0.19，build 9800
  - v2.0（最早的 2.0 正式版）: 同 id、同 Team，Notarized，**仅 x86_64**，short 2.0，build 9800
  - v2.0-rc.31: 同 id、同 Team，Notarized，仅 x86_64，short `2.0-rc.31`，build 9800
- 其他 bundle id: TextMate 1.x（1.5.11，`archive.textmate.org`）是 `com.macromates.textmate`（小写），**仅 i386**、未签名。macOS 10.15 起不再运行 32 位程序，我们的主机下限是 macOS 15，所以这一组副本在支持的主机上根本无法运行；而且 1.x 是付费的旧产品、2.0 是重写，不能当作同一 app 的下一版。不建 `BundleIDMigration`
- 其他轨: prerelease 与正式版同形（`v2.0.22` 标 `prerelease: true`，资产名同样是 `TextMate_<version>.tbz`，包内版本是纯数字）。另有 2013–2018 年的 `v2.0-alpha.N` / `v2.0-beta.N` / `v2.0-rc.N` 在 GitHub 上**没有**标 prerelease（如 `v2.0-rc.10`、`v2.0-beta.12.4`），`versionPattern` 整串锚定把它们排除
- 版本范围: 每个 prerelease 之后都有更高的正式版（2.0.20–2.0.22 → 2.0.23；2.0.18 → 2.0.19；2.0-rc.31 → 2.0），所以装着 prerelease 的副本按 stable 读，被推到毕业版，不会被降级。`CFBundleVersion` 在所有 2.0.x 包里都是常量 9800，只能比 marketing 版本
- 主机下限: 资产 universal；`LSMinimumSystemVersion` 10.12，远低于我们的 macOS 15 下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.macromates.TextMate` | — | 纯数字 short version | `/releases/latest`（GitHub 排除 prerelease） | ✓ |
| beta    | 同 id | 共享 | CFPrefs `com.macromates.TextMate` / `SoftwareUpdateChannel` = `beta` | 厂商端点换 URL（`/releases/beta`） | ○ |
| nightly | 同 id | 共享 | 无持久信号：只有按住 ⌥ 点「Check for Test Build」时临时查 `/releases/nightly` | — | — |

settled from source: `Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm` on `master` —— `kUserDefaultsSoftwareUpdateChannelKey = @"SoftwareUpdateChannel"`，取值 `release`（默认，`registerDefaults` 注册）/ `beta` / `nightly`；`Frameworks/Preferences/src/SoftwareUpdatePreferences.mm` 的弹出菜单只提供 `release` 与 `beta` 两项；`checkForTestBuild:YES`（⌥ 菜单项）才用 `nightly`，不写偏好。

beta 轨没有接：端点在 2026-11-11 对 release / beta / nightly 三条都答同一个 2.0.23，GitHub 上最新的 prerelease（v2.0.22）低于最新正式版，所以 beta rule 今天只会给出与 stable 相同的答案。勾了 beta 的副本今天走 stable rule，得到的正是厂商 beta 端点给它的版本。是否为将来的 prerelease 加 `ChannelBinding` + beta rule，待用户决定。

## 更新检测
- 源: `textmate/textmate` GitHub Releases，`/releases/latest`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：`v2.0.23`、`v2.0.19`、两段式 `v2.0`、下一个大版本 `v3.0.0` 都读得出；`v2.0-rc.10`、`v2.0-beta.12.4`、`v2.0-alpha.9561` 读不出
- `installAssetPattern` `^TextMate_[0-9]+(?:\.[0-9]+)+\.tbz$`，`installerKind .tarGz`
- 为什么不用厂商端点（`VendorProbeRecipe`）:
  - `GET https://api.textmate.org/releases/release?os=15.0`（2026-11-11）答 `text/plain` 的旧式 plist：`{ url = 'https://api.textmate.org/downloads/TextMate_2.0.23.tbz'; version = '2.0.23'; revision = 9999; signee = 'org.textmate.duff'; signature = 'MC0CFHAZ…'; }`
  - `url` 302 到 `github.com/textmate/textmate/releases/download/v2.0.23/TextMate_2.0.23.tbz`，即 GitHub 那份字节
  - `signature` 是厂商自有密钥（`org.textmate.duff`）的 DSA 签名，我们没有校验它的机制；安装闸仍是 Team ID + 公证
  - 端点按 OS 分桶：不带 `os` 答 `2.0-rc.4`，`os=10.9` 答 `2.0-rc.10`，`os=10.12` 及以上答 2.0.23。我们的主机全部落在最新桶
  - 端点不带发布说明；GitHub 同时给出资产和 release 页，所以走 GitHub
- `channel-verify`（2026-11-11）: 2.0.19 → `UPDATE → 2.0.23`；2.0 → `UPDATE → 2.0.23`；2.0-rc.31（`detected channel → stable`）→ `UPDATE → 2.0.23`；2.0.23 → `up to date`

## 按架构 / 按 OS 分轨
- 架构: 当前 release 是 universal 单资产；2.0 与 rc 期是仅 x86_64。`LSMinimumSystemVersion` 10.12
- 厂商端点按 `os` 分桶（见上），10.12 以下的桶停在 2.0-rc 版本；GitHub 不分桶，我们的主机下限在最新桶内

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不需要 |
| 证据 | `SoftwareUpdate.mm` 的 `downloadSoftwareUpdateAtURL:` 只下整包 `.tbz` 并解开 | 端点响应只有 `url`/`version`/`revision`/`signee`/`signature` 五个字段（2026-11-11，三条轨） | 整包下载 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（一键端到端由主会话跑） | — |
| 证据 | `SoftwareUpdate.mm`：下载后解到临时位置，在对话框里等用户点「Install & Relaunch」，对话框关闭时删掉（`_downloadedArchiveURL … Will be deleted in viewDidDisappear`）；不写完成记录 | 未测（运行中一轮未做） | 没有可拿的 |

- 记录文件与字段: 无
- 容器: `.tbz`，包根是 `TextMate.app`
- 两份副本会不会共用这个目录: 不适用

## Changelog
- 来源: recipe —— 厂商自己的 `Applications/TextMate/about/Changes.md`（app 里 Help → Release Notes 渲染的就是它），按 release 的 tag 读：`https://raw.githubusercontent.com/textmate/textmate/v{version}/Applications/TextMate/about/Changes.md`
- 为什么不用 GitHub release 正文: stable 轨不显示 prerelease 正文，而这个厂商的改动都写在 prerelease 里 —— v2.0.23 的正文只有一句「Miscellaneous improvements, see changes since v2.0.22」，内容在 v2.0.20–v2.0.22；v2.0.19 之前的正式版正文为空（`.gitHubReleases` 在 stable 轨上只读得出 2 条）
- 为什么读 tag 不读 `master`: `master` 上的 `Changes.md` 停在 v2.0.22，v2.0.23 那条只在 tag 上
- 结构化: `changelog pane  recipe changelog:com.macromates.TextMate:-: 20 entries; newest 2.0.23: 1 items, headings []; first items ["Miscellaneous improvements, see changes "]`（compare 链接已压平）。2.0 那条里的 `###` 小标题与散文段落被丢掉，只取 `* ` 条目
- 跟随 channel: 不分轨（文件本身就把 prerelease 与正式版排在一条时间线上，和 app 内显示一致）
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（universal `.tbz`，Team 闸）
- 端到端: ✓ 第一轮（2026-11-11，本机，未运行）：/Applications 放 2.0.19，`duo install com.macromates.TextMate --yes` → `verifyingCodeSignature … installed.`（无 GitHub digest，故无 `verifyingSignature`）；结果 2.0.23、Team `45TL96F76G`、`codesign --verify --deep --strict` 0、spctl Notarized Developer ID。`.tbz` 经 `.tarGz` 路径解包，实测可用。运行中一轮未做。
- 格式: `.tbz`（bzip2 tar）。`VendorInstaller.normalizedArchive` 把它改名 `download.tar.gz`，`ArchiveExtractor.fromTar` 跑 `/usr/bin/tar -xf`，libarchive 按内容识别 bzip2。已在真包上按同样步骤（改名 `.tar.gz` 后 `tar -xf`）解出 `TextMate.app`，codesign / spctl 通过
- 校验: 资产上传于 2021 年，GitHub 没有 `digest`；端点的 DSA `signature` 用的是厂商自有密钥，不支持。只靠 Team ID 闸（45TL96F76G）+ 公证。真包 sha256 `f8dba933209bd01070028892474bf0b72f36c673f7bcb8da5973f93ddc387420`
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`，也是 macromates.com 下载页 302 的那份）
- 嵌套: 没有嵌套 `.app`、XPC、`Contents/Library/LoginItems` 或 LaunchAgent。`Contents/MacOS` 里除主程序外是命令行工具 `mate`、`tm_query`、`CommitWindowTool`；另有 `Contents/Library/QuickLook/TextMateQL.qlgenerator` 和 `Contents/PlugIns/Dialog{,2}.tmplugin`，都不是常驻进程
- 阻塞: 无

## 已知问题
- 自更新器每小时检查一次（`_updateCheckInterval = 60*60`），默认先问用户（`SoftwareUpdateAskBeforeUpdating`）；它与我们拿到的是同一份字节，不会把副本带到另一个版本
- prerelease 副本没有本地标记（版本纯数字、build 恒为 9800），按 stable 读，只能等毕业版

## 如何复验
```bash
# 真包
curl -L -o /tmp/tm.tbz https://github.com/textmate/textmate/releases/download/v2.0.23/TextMate_2.0.23.tbz
mkdir -p /tmp/tm && cp /tmp/tm.tbz /tmp/tm/download.tar.gz && tar -xf /tmp/tm/download.tar.gz -C /tmp/tm
codesign -dvv /tmp/tm/TextMate.app; spctl -a -vv /tmp/tm/TextMate.app
# 规则与 changelog
swift run --package-path application-test channel-verify /tmp/tm/TextMate.app --expect stable
# 厂商端点（三条轨）
curl -s 'https://api.textmate.org/releases/release?os=15.0'
curl -s 'https://api.textmate.org/releases/beta?os=15.0'
curl -s 'https://api.textmate.org/releases/nightly?os=15.0'
```

## 建议下一步
1. 一键端到端（主会话）：装 2.0.19 后 `duo install TextMate --yes`
2. beta 轨（待用户决定）：若厂商再发 prerelease，加 `TextMateChannel`（读 `SoftwareUpdateChannel` = `beta`）+ `usePrereleases: true` 的 beta rule；prerelease 与正式版同形，只能靠 GitHub 的 `prerelease` 位分轨，一键还需要 `ChannelProofRegistry` 条目

## 历史与实测
- 2026-11-11: `.gitHubReleases` 版 changelog 在 stable 轨只读出 2 条（v2.0.23 一句话、v2.0.19 三条；v2.0.17 / v2.0.6 / v2.0 正文为空），改用 tag 上的 `Changes.md`，读出 20 条
- 2026-11-11: `Changes.md` 在 `master` 停在 v2.0.22；`v2.0.23` tag 上第一条是 `## 2021-10-12 (v2.0.23)`
- 2026-11-11: `api.textmate.org/releases/{release,beta,nightly}?os=15.0` 都答 2.0.23、`revision = 9999`；`downloads/release?os=10.12` 302 到 v2.0.23 的 GitHub 资产
