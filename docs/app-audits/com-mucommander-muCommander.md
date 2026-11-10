# muCommander

## 基本信息
- Bundle ID: `com.mucommander.muCommander`（1.3.0 到 1.6.2 的所有 dmg 都是这个 id，noarch 版也是）
- Team ID: `CZHQQ65L42`（Developer ID Application: Arik Hadas，1.4.0 起）；1.3.0 是 `JCDTMS22B4`
  （Eclipse Foundation），noarch 版不签名
- 观测版本: `1.6.2`（tag `1.6.2-1`；`CFBundleShortVersionString` = `CFBundleVersion` = `1.6.2`）
- 自更新机制: 自研，只提示。启动时（或菜单 Check for updates）读
  `https://www.mucommander.com/version/version.xml`，有新版就弹窗，按钮用浏览器打开 release 页
  （上游 `mucommander-core/.../ui/dialog/startup/CheckVersionDialog.java`，`DesktopManager.BROWSE`）。
  不下载、不替换，所以不会和一键抢。2026-11-11 那个 xml 是
  `<latest_version>1.6.2-1</latest_version>`，`<download_url>` 指向 GitHub release 页，`<jar_url>` 为空。
- 分发: GitHub Releases（`mucommander/mucommander`）/ Homebrew cask `mucommander`（`auto_updates` 未设，
  装 aarch64 dmg）。无 MAS。Java 应用，jpackage 打包，自带 JRE。
- 开源: 是。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（cask 装的副本归 brew） | — | ✓ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（非 brew 安装的副本；`channel-verify` 实测）。
brew 装的副本由 `HomebrewCaskSource` 应答（brew 拥有已装的 cask）。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，2026-11-11）:

  | 包 | id | short / build | Team | spctl | 主可执行文件 |
  |---|---|---|---|---|---|
  | 1.6.2-1-aarch64.dmg | `com.mucommander.muCommander` | 1.6.2 / 1.6.2 | `CZHQQ65L42` | Notarized Developer ID | `muCommander`，Mach-O arm64 |
  | 1.6.1-1-aarch64.dmg | 同上 | 1.6.1 / 1.6.1 | `CZHQQ65L42` | Notarized Developer ID | 同上 |
  | 1.4.0-1-aarch64.dmg（最早的 arm64 包） | 同上 | 1.4.0 / 1.4.0 | `CZHQQ65L42` | Notarized Developer ID | 同上 |
  | 1.3.0-1.dmg（最后一个单包） | 同上 | 1.3.0 / 1.3.0 | `JCDTMS22B4` | 拒绝（签名缺资源） | `muCommander`，Mach-O x86_64 |
  | 1.6.2-1-noarch.dmg | 同上 | 1.6.2 / 1.6.2 | 无签名 | 拒绝（no usable signature） | `universalJavaApplicationStub`，bash 脚本 |
  | 1.6.2-1-portable-x86_64.zip | 不是 `.app`（jar + `mucommander.sh` / `.exe`） | — | — | — | — |

- 其他轨: 没有。GitHub 上从没有 release 标过 prerelease；tag 里只有早年的 `0.9.1rc`、`0.9.1rc2`
  两个 rc（没有 release），pattern 不收。
- 版本范围: 有 release 的 tag 是 `0.9.4-2` 到 `1.6.2-1`；1.0.x 及以前的 release 没有资产。所有有 Mac
  包的版本 id 相同，不需要 `BundleIDMigration`。
- 副本分组与处理:
  - **jpackage 版、Team `CZHQQ65L42`（1.4.0 起的 aarch64 / x86_64 dmg、cask）**: 检测 + 一键（换成 aarch64 dmg）。
    x86_64 副本在 Apple Silicon 上走 Rosetta，换成 arm64 不是架构降级（gate 5b 只拦降级）。
  - **jpackage 版、Team `JCDTMS22B4`（≤ 1.3.0）**: 检测 ✓（1.3.0 → 1.6.2）；一键在安装时被 Team 闸拒绝
    （`teamIdentifierMismatch`），最坏情况是一次手动更新。
  - **noarch 版（同 id、无签名、bash 启动脚本 + 系统 Java）**: 检测 ✓；一键由 `OneClickGate` 挡住，
    不出现一键按钮。aarch64 包会把它换成另一个 edition（自带 JRE、Developer ID 签名），所以这是 gate，
    不是缺口。`.publishedDigestOnly` 不适用：noarch 不是 ad-hoc 签名的同一个包，而是另一种打包。
    给它单独装 noarch dmg 也不行：没有 Team ID 可比、也没有签名可验，`.publishedDigestOnly` 要求
    seal 通过 `codesign --verify --deep --strict`，noarch 包没有 seal。
  - **portable zip**: 不是 app bundle，扫描不到，不适用。
- 主机下限: `LSMinimumSystemVersion` = `10.11`（arm64 包；noarch 无此键）。我们的下限是 Apple Silicon、
  macOS 15，没有影响。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.mucommander.muCommander` | 单一渠道 | — | tag `^X.Y.Z(-N)?$` + 资产 `-aarch64.dmg` | ✓ |
| noarch edition | 同 id | 共享 | 主可执行文件里没有 `JLI_Launch` | `OneClickGate.executableContains` | 检测 ✓，一键挡 |

## 更新检测
- 源: `mucommander/mucommander` GitHub Releases，`/releases/latest`。
- 版本方案: tag 是 `<版本>-<打包号>`（`1.6.2-1`），包内两个版本键都只有 `1.6.2`。pattern
  `^([0-9]+(?:\.[0-9]+)+)(?:-[0-9]+)?$` 只取版本：
  - 重打包（历史上有 `0.9.3-2`、`0.9.3-3`、`0.9.4-2`、`1.2.0-2`；1.2.0 的 release 叫 `1.2.0-1`、dmg 叫
    `muCommander-1.2.0-2.dmg`）读成同一个版本，对已装的同版本副本显示 up to date，不会反复提示。
    代价：同版本的重打包不会被推送（包内版本没变，也没有可比的东西）。
  - `-N` 可选，兼容早年的裸 tag（`1.3.0`）；`$` 锚定挡住 `0.9.1rc2`、`1.7.0-rc1`，也不收 `v0.8.4`。
- 注意事项: 每个 release 有 12 个资产（dmg ×3、tgz、rpm、deb、msi、portable zip），pattern 钉 `-aarch64.dmg`。

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（`-aarch64.dmg`、`-x86_64.dmg`、`-noarch.dmg`），没有 universal；一键取 aarch64。
- `LSMinimumSystemVersion`: `10.11`（1.4.0、1.6.1、1.6.2 相同）；无上限声明。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 自研检查只打开浏览器（`CheckVersionDialog.java`） | version.xml 只有版本、release 页链接、空的 `jar_url`（2026-11-11） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（第二轮由主会话跑） | 不适用 |
| 证据 | 源码：不下载，只 `DesktopManager.BROWSE` | — | — |

## Changelog
- 来源: GitHub release 正文（GitHub 自动生成的 `## What's Changed`）
- 结构化: `changelog pane  source structured: 1 entries; newest 1.6.2: 4 items, headings []; first items ["Update previous release to 1.6.1 in the ", "Granting the application permission to a", "Document mucommander#1471"]`
- 跟随 channel: 单渠道
- Recipe 状态: 不需要（`GitHubMarkdownParser` 直接渲染正文）

## 一键安装
- 状态: 支持（jpackage 版）；noarch 版仅检测
- 端到端: 待主会话
- 格式: dmg（UDZO，**带软件许可协议**：`hdiutil imageinfo` 显示 `Software License Agreement: true`，
  不答 stdin 的 `hdiutil attach` 会失败）。引擎的 `DiskImageMount` 在 stdin 上回答 `yes\n`，
  `hdiutil` 和 `diskutil image attach` 两条路都这样，所以引擎不用改。注意
  `scaffold-github-rule.py`、`channel-verify` 和 `feed-discover` 自己挂 dmg 时不回答协议，会报 attach 失败；
  这次是手动 `yes | hdiutil attach -nobrowse -readonly` 后把 `.app` 交给 `channel-verify`。
- 校验: GitHub 资产 `digest`（1.6.0 起有）。真实下载的 SHA-256 与之相等：
  1.6.2-1-aarch64 `212a290f…dca2103c0`，1.6.1-1-aarch64 `1bf4ef59…c8703149b64`。规则不需要额外字段。
- Edition gate: `OneClickGate(.executableContains(marker: "JLI_Launch"))`。jpackage 启动器
  （1.3.0 x86_64、1.4.0 / 1.6.1 / 1.6.2 arm64，181264 / 159984 字节）都含 `JLI_Launch`；noarch 的
  `universalJavaApplicationStub`（32910 字节的 bash 脚本）不含。不读 `CFBundleExecutable` 名字，
  因为 gate 看的是字节内容。
- 嵌套 app: 无（`Contents/` 下没有 `.app`、LoginItems、Helpers）。
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`，也是 app 自己的 version.xml 指的版本）
- 阻塞: 无

## 已知问题
- noarch 副本要手动更新（gate 的 reason 会说明）。
- ≤ 1.3.0 的副本 Team 不同，一键在安装时被拒，需要手动装一次。

## 如何复验
```sh
B=https://github.com/mucommander/mucommander/releases/download
curl -fLO $B/1.6.1-1/mucommander-1.6.1-1-aarch64.dmg
mkdir mnt && yes | hdiutil attach mucommander-1.6.1-1-aarch64.dmg -nobrowse -readonly -mountpoint mnt
swift run --package-path application-test channel-verify mnt/muCommander.app --expect stable
grep -caF JLI_Launch mnt/muCommander.app/Contents/MacOS/muCommander   # ≥ 1
hdiutil detach mnt
```
2026-11-11 结果（每个包都 `detected channel → stable`、`winning source GitHub`、`latest 1.6.2`、
下载 `…/1.6.2-1/mucommander-1.6.2-1-aarch64.dmg`）:
- 1.6.1-1-aarch64 → `UPDATE → 1.6.2`
- 1.6.2-1-aarch64 → `up to date`
- 1.6.2-1-noarch → `up to date`
- 1.4.0-1-aarch64 → `UPDATE → 1.6.2`
- 1.3.0-1（x86_64）→ `UPDATE → 1.6.2`

## 建议下一步
1. 主会话跑一键端到端（1.6.1 → 1.6.2，未运行 / 运行中两轮），确认引擎对带协议 dmg 的挂载。
2. 可选：让 `channel-verify` / `feed-discover` / scaffold 挂 dmg 时也回答协议（工具改动，不影响产品）。
