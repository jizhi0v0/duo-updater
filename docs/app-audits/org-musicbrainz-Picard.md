# MusicBrainz Picard

审计 2026-10-16（coverage-discovery 批量接入）。

## 基本信息
- Bundle ID: `org.musicbrainz.Picard`（2.0.x 及更早是全小写的 `org.musicbrainz.picard`，见「旧 bundle id」）
- Team ID: `8D89TSJ88H`（3.0.2、3.0.1、3.0.0rc4、2.13.3、2.3.1、2.0.4 六个真包相同）
- 观测版本: `3.0.2`（short = build），上一版 `3.0.1`。`LSMinimumSystemVersion` 13.0；每个架构单独一个 dmg
  （`-arm64.dmg` / `-x86_64.dmg`），arm64 包只含 arm64
- 自更新机制: 自研检查，不下载。`picard/util/checkupdate.py` 读
  `https://picard.musicbrainz.org/api/v2/releases`（`PLUGINS_API['urls']['releases']`），按用户的
  `update_level`（0 stable / 1 beta / 2 dev）取最高版本，有新版就用浏览器打开下载页。没有 Sparkle、
  没有 electron-builder 配置（triage 的 feed-discover 结论 `—`）
- 开源: `metabrainz/picard`。版本号写在 `picard/__init__.py` 的 `PICARD_VERSION`，打包脚本 `picard.spec`
  把 `PICARD_APP_ID` 写进 `CFBundleIdentifier`（settled from source）
- Homebrew: cask `musicbrainz-picard`，`auto_updates` 未设，URL 是厂商镜像上的同一个 arm64 dmg
- MAS: 没有（iTunes 搜索 "musicbrainz picard" 前 5 条都是别的 app）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（仅 brew 装的拷贝） | — | ✓ 一键 | — |
| **beta**     | —       | —        | —   | ○      | —           |
| **dev**      | —       | —        | —   | —（2023 年后无新构建） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`GitHubReleasesSource`，rule 在
`Recipes/org-musicbrainz-Picard.swift`）；brew 装的拷贝由 `HomebrewCaskSource` 先应答。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `org.musicbrainz.Picard` | — | — | `/releases/latest`，tag `release-<版本>` | ✓ |
| beta | `org.musicbrainz.Picard` | 共享 | 版本串带 `rc`/`b`/`a`（`3.0.0rc4`），GitHub 的 `prerelease` 位；用户偏好 `update_level` | — | ○ |
| dev | 同上 | 共享 | 同上 | — | — |

- 发布轨（settled from source + 接口实测）: releases 接口有 `stable`（3.0.2）、`beta`（3.0.0rc4）、`dev`
  （2.9.0a1，2023-01）、`old_stable`（2.13.3，给 macOS 10.12/10.14）四个对象。
- beta 构建与 stable 同 bundle id、同 Team。3.0.0rc4 真包 `CFBundleShortVersionString` = `3.0.0rc4`、
  `CFBundleVersion` = `3.0.0`；`ReleaseChannel.detect()` 把它判成 stable（channel-verify 实测），所以
  beta 拷贝走 stable rule，被推 3.0.2。这和 Picard 自己 beta 档的行为一致（beta 档取 stable 与 beta
  里较高的那个）。
- **缺口**: 当 beta 比 stable 新时（如将来 3.1.0b1 对 3.0.x），beta 拷贝拿不到下一个 beta，只会在
  stable 追上时被推送。接法有两条，都没做：
  1. `installedTagPrefix: "release-"` 的 beta rule（UTM 的做法，按已装版本对应 tag 的 `prerelease`
     位认渠道），要配 channel proof 和测试；
  2. `ChannelBinding` 读用户偏好 `update_level`（`IntOption('setting', 'update_level')`，`in_profile=True`，
     即可能被 profile 覆盖）。Qt `IniFormat` + `UserScope` + org `MusicBrainz` / app `Picard` 在 macOS 上的
     位置是 `~/.config/MusicBrainz/Picard.ini`（2026-10-16 真机 3.0.2 确认，见「建议下一步」）。
  当前 beta 轨（3.0.0rc4）落后于 stable，没有构建会被漏掉。
- `old_stable` 是给 macOS 10.12–12 的 2.x 线。DuoUpdater 最低 macOS 15、只跑 arm64，这些 Mac 都能跑 3.x，
  不需要 2.x 线。

## 更新检测
- 源: `GitHubReleasesSource`，`metabrainz/picard` 的 `/releases/latest`
- versionPattern `^release-([0-9]+(?:\.[0-9]+)+)$`。tag 去掉 `release-` 就是 marketing 版本，与两个
  Info.plist 版本字段相同（3.0.1、3.0.2、2.13.3、2.3.1、2.0.4 真包）
- 在 GitHub 全部 99 条 release（最早 `release-1.4.2`）的 tag 上跑过: 读出 59 条，正是 `prerelease` 位为
  false 的全部 final 版（含两段的 `release-3.0`、`release-2.3` 等 11 条）；拒读 40 条，其中 39 条带
  `prerelease` 位，剩下一条是没打这个位的 beta `release-2.6.0b3`。`2.0.0dev*` 等无前缀的旧 tag 也拒读
- 厂商自己的接口 `picard.musicbrainz.org/api/v2/releases`（Picard 内置检查读的那条）同样答 3.0.2。没用它当源：
  JSON 里没有下载文件名，只能拼出含 `macOS-13.0` 系统下限的文件名；摘要是 MD5（不支持）。GitHub 资产与
  厂商镜像 `data.musicbrainz.org/pub/musicbrainz/picard/` 是同一份文件（SHA-256 相同，见「一键安装」），还自带
  SHA-256 `digest`
- 按 OS 分轨: 文件名带系统下限（`macOS-13.0`；3.0.0b1 及更早的 3.0 预发布是 `macOS-11.0`；2.x 是
  `macOS-10.12` / `10.14` 两份）。rule 的资产模式不钉下限。Release 本身不声明上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `checkupdate.py` 只打开下载页，不下载 | release 资产只有整包 dmg/exe/msix/源码 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（第二轮未跑） | — |
| 证据 | `checkupdate.py`：`webbrowser2.open(...['urls']['download'])`，不下载 | — | — |

- 自更新器不会和一键抢：它不下载也不替换 bundle。

## Changelog
- 来源: `ChangelogRecipe`，读 `https://picard.musicbrainz.org/changelog/`（由仓库 NEWS.md 生成，每版一个
  `<h3 id="release-…">`，下面 `<h4>` 分节 + `<ul>`）
- 结构化（channel-verify 原文，3.0.1 / 3.0.2 两个包同一行）:
  `changelog pane  recipe changelog:org.musicbrainz.Picard:-: 40 entries; newest 3.0.2: 5 items, headings ["Bugfixes"]; first items ["PICARD-3484 - Hardcoded link styling in ", "PICARD-3485 - Sticky grey background in ", "PICARD-3490 - Program crash after wizard"]`
- 生产解析器在整页上: 128 个版本块全部匹配（`maxEntries` 截到 40）；分节标题保留（3.0 有 Bugfixes 与
  Improvements 两节），条目里的工单链接被剥成纯文本，`&quot;` 解码
- 预发布条目（`3.0.0rc4` 等）保留：一个 .0 正式版只列最后一个 rc 之后的修复
- GitHub release 正文也带同样的分节说明；面板优先用 recipe
- 跟随 channel: 否（一页覆盖所有轨）
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（`installAssetPattern` `^MusicBrainz-Picard-[0-9][0-9A-Za-z.]*-macOS-[0-9.]+-arm64\.dmg$`，`.dmg`）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：3.0.1 → 3.0.2（含 `verifyingSignature`），`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg（arm64，3.0.2 为 60,445,028 B）
- 校验: GitHub 资产 `digest`（SHA-256），每条 rule 自动带上。实测 3.0.2 arm64 dmg SHA-256
  `15f9054dfc381c6fe3884844361efc119e92d418aa88c6b1bcbf10492a5e7b7b`、3.0.1 `69c438f5c41bd951ac3451b052a697d0aaf618cedf6f335fce5eac4c7296b609`，
  都与 GitHub `digest` 相等；从厂商镜像下载的同名文件就是这两份（字节相同）
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`，与厂商下载页、Homebrew cask 同一文件）
- Team: 3.0.1 / 3.0.2 同为 `8D89TSJ88H`，`codesign --verify` 退出 0，`spctl` `Notarized Developer ID`。
  2.13.3、2.3.1 也是 `8D89TSJ88H` + Notarized；2.0.4 是 `8D89TSJ88H` + `Developer ID`（未公证）
- 嵌套: 3.0.2 包里没有 `LSUIElement` / `LSBackgroundOnly` 的嵌套 app，没有 LoginItem
- 2.x → 3.0.2: 2.x 是 x86_64 包，一键换成 arm64 的 3.0.2。Picard 自己的检查也会给 2.13.3 推 3.0.2
  （2.13.3 读同一个接口，`stable` = 3.0.2）
- 阻塞: 无已知硬阻塞

## 旧 bundle id
- 2.0.4 真包: `org.musicbrainz.picard`（全小写），Team `8D89TSJ88H`。2.3.1 真包: `org.musicbrainz.Picard`
- 源码: `picard.spec` 在 release-2.1.3 仍写死小写 id，release-2.2.0 起写 `PICARD_APP_ID`
  （`org.musicbrainz.Picard`）。厂商镜像上没有 2.1.x / 2.2.x 的 dmg，没量真包
- duo 按字符串比对 bundle id，所以小写 id 的拷贝原先没有任何源应答（channel-verify 2.0.4：
  `VendorProbe ✗`、`winning source <none>`、`status unknown`）。加了 `BundleIDMigration`
  （`org.musicbrainz.picard` → `org.musicbrainz.Picard`，Team `8D89TSJ88H`，`lastFromVersion` 2.0.4，
  `firstToVersion` 2.3.1）后，2.0.4 由 GitHub rule 应答，`UPDATE → 3.0.2`
- 2.0.4 没有内置更新检查（该 tag 的 `picard/util/checkupdate.py` 里没有 releases 接口）

## 已知问题
- beta 轨未接（见「Channel 详情」）
- 2.0.x 没公证；它被一键替换成已公证的 3.0.2，替换前后都过 Team 闸

## 建议下一步
1. （已做）真机一键 3.0.1 → 3.0.2，见「一键安装」的端到端一行
2. beta: 等下一个 beta 周期再决定用 `installedTagPrefix` rule 还是 `update_level` 偏好。偏好已在真机确认（2026-10-16，3.0.2，
   全新配置）：Options ▸ Advanced ▸ Updates to check 选 “Stable and Beta releases” 并点 OK 后，`~/.config/MusicBrainz/Picard.ini`
   的 `[setting]` 段出现 `update_level=1`。点 OK 会把所有选项的默认值一起写进去，所以没有这个键时按默认 0（stable）读；
   第三项 “Stable, Beta and Dev releases” 另起全新配置实测，写成 `update_level=2`。profile 覆盖的情形没测（`user_profiles=@Invalid()`，没有 profile）

## 如何复验

2026-10-16。dmg 只读挂载检查，不安装、不启动。

```bash
curl -sSL https://picard.musicbrainz.org/api/v2/releases            # stable.tag 3.0.2, beta.tag 3.0.0rc4
gh api "repos/metabrainz/picard/releases/latest" -q .tag_name        # release-3.0.2
gh api "repos/metabrainz/picard/releases/tags/release-3.0.2" -q '.assets[] | [.name,.size,.digest] | @tsv'
curl -fLO https://github.com/metabrainz/picard/releases/download/release-3.0.2/MusicBrainz-Picard-3.0.2-macOS-13.0-arm64.dmg
curl -fLO https://github.com/metabrainz/picard/releases/download/release-3.0.1/MusicBrainz-Picard-3.0.1-macOS-13.0-arm64.dmg
shasum -a 256 MusicBrainz-Picard-3.0.*-arm64.dmg
.claude/skills/coverage-discovery/scripts/check-bundle.sh MusicBrainz-Picard-3.0.2-macOS-13.0-arm64.dmg
swift run --package-path application-test channel-verify MusicBrainz-Picard-3.0.1-macOS-13.0-arm64.dmg --expect stable
swift run --package-path application-test channel-verify MusicBrainz-Picard-3.0.2-macOS-13.0-arm64.dmg --expect stable
```

| 包 | bundle id | short / build | Team | detected | winning | status |
|---|---|---|---|---|---|---|
| 3.0.1 arm64 | `org.musicbrainz.Picard` | 3.0.1 / 3.0.1 | 8D89TSJ88H | stable | GitHub | **UPDATE → 3.0.2** |
| 3.0.2 arm64 | `org.musicbrainz.Picard` | 3.0.2 / 3.0.2 | 8D89TSJ88H | stable | GitHub | **up to date** |
| 3.0.0rc4 arm64 | `org.musicbrainz.Picard` | 3.0.0rc4 / 3.0.0 | 8D89TSJ88H | stable | GitHub | UPDATE → 3.0.2 |
| 2.13.3（macOS-10.14，x86_64） | `org.musicbrainz.Picard` | 2.13.3 / 2.13.3 | 8D89TSJ88H | stable | GitHub | UPDATE → 3.0.2 |
| 2.0.4（x86_64） | `org.musicbrainz.picard` | 2.0.4 / 2.0.4 | 8D89TSJ88H | stable | GitHub | UPDATE → 3.0.2 |

`download` 都是 `https://github.com/metabrainz/picard/releases/download/release-3.0.2/MusicBrainz-Picard-3.0.2-macOS-13.0-arm64.dmg`。

## 历史与实测
- 2026-10-16: 先按厂商接口写过一版 VendorProbe（`"stable"` 对象的 `tag` + `.versionTemplate` 拼镜像文件名），
  channel-verify 3.0.1 → `UPDATE 3.0.1 → 3.0.2`、3.0.2 → `up to date`。随后发现 GitHub release 带同一批
  dmg 和 SHA-256 `digest`（triage 记的「GitHub release asset: False」不对），改用 GitHub rule：有摘要校验，
  也不用把 `macOS-13.0` 写死进 URL。接口 JSON 的 `mac_arm64_hash` 是 MD5（3.0.2 为
  `da00a785327dfd3dda682bc5adfa9ce7`，与下载文件的 MD5 相等）
- 2026-10-16: GitHub 上共 99 条 release（最早 `release-1.4.2`）；`release-2.6.0b3` 没打 `prerelease` 位
- 2026-10-16: changelog 页 128 个版本块，其中 50 个是预发布
