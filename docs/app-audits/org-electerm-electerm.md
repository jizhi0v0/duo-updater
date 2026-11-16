# electerm

## 基本信息

- App: electerm，MIT 开源终端 / SSH / SFTP 客户端。
- Bundle ID: `org.electerm.electerm`。
- 仓库: [electerm/electerm](https://github.com/electerm/electerm)；官网 [electerm.org](https://electerm.org/)。
- 分发: GitHub Releases、官网镜像、Homebrew `electerm`（`auto_updates true`）。官方 README 的安装入口未发现 MAS 产品或独立 macOS 付费版。
- 自更新机制: 自定义版本检查和完整 DMG 下载，不使用 electron-updater 自动替换。`app-update.yml` 是 electron-builder 生成的 GitHub provider 配置，generic Electron 源不能从中构造 manifest 地址。
- 观测日期: 2026-11-16；具体版本和签名见「历史与实测」。

## 覆盖矩阵

> ✓ = 已接入；— = 不适用。

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| stable | — | —（auto_updates） | — | ✓ | — |

复用 `GitHubReleaseRule` 提供版本、安装资产和 release 正文，不添加 vendor/changelog recipe。真实旧版/新版的生产检测和结构化 pane 均已核对；5.10.0→5.11.8 在 macOS 27.2 Apple Silicon VM 完成停用及运行中两轮一键安装，见[集中验收](../../verify/awesome-four-20261116/README.md)。

## 覆盖清单与渠道

- **身份 / 版本范围**: 当前、上一稳定版、1.0.0 与最后一个 0.x prerelease 真包均为 `org.electerm.electerm`、Team `38ZYC7L6N5`。最早带 macOS 资产的 v0.8.0 源码也声明同一 appId，无需 `BundleIDMigration`。没有逐一下载所有中间版本；若某旧副本的签名不同，现有 Team 闸会拒绝安装，检测仍由同一 ID 的规则提供。
- **历史 0.x**: GitHub 将 0.x 标为 prerelease，但版本是纯数字、与 stable 共用 ID。v0.27.105 的 `src/client/common/update-check.js` 只读同一个 `version.html` 和 release JSON，没有 beta 选择或平行更新入口。此规则保留这条连续升级路径，旧 0.x 副本转到当前 stable，不另外建立过时的 beta 轨。
- **当前轨道**: stable。完整 release 历史和当前构建/更新源码未发现独立 beta、rc、nightly 入口。`app-update.yml` 的 `channel: mac-arm` 来自 `WORKFLOW_NAME`，是 arm64 构建工作流名，不是发行质量轨。
- **架构 / OS**: 只选 `mac-arm64.dmg`；`mac-x64.dmg` 与 `mac10-x64.dmg` 是同产品的 Intel 构建，后者供旧系统使用。DuoUpdater 支持 Apple Silicon、macOS 15+，当前包的 macOS 13 下限不构成覆盖缺口。受支持主机上的旧 Intel 副本也能检测当前版本，在签名闸允许时换为 arm64。
- **许可**: 开源产品，无订阅、付费 major 或账户状态门控。

## 更新检测

- 源: `electerm/electerm` 的 `/releases/latest`，仅选 stable。
- `versionPattern`: `^v?([0-9]+(?:\.[0-9]+)+)$`，兼容无 `v` 的旧 tag 和将来 major；拒绝带 rc/beta 后缀或额外文字的 tag。
- `installAssetPattern`: `^electerm-[0-9]+(?:\.[0-9]+)+-mac-arm64\.dmg$`，排除 x64、mac10、Linux 和 `.blockmap`。
- `CFBundleShortVersionString` 是比较用的 dotted version；`CFBundleVersion` 的构建尾号不另作发行轨。

## 自更新与已停放整包

当前 tag 的 `src/client/common/update-check.js` 读取 `${homepage}/version.html` 和 `${homepage}/data/electerm-github-release.json`，失败时回退到 Gitee 的 `gh-pages` 镜像。`src/build/bin/build-mac-arm.js` 将 `installSrc` 写为 `mac-arm64.dmg`。用户触发 `upgrade.jsx` 的 `doUpgrade` 后，`src/app/server/download-upgrade.js` 下载匹配的完整资产到 `os.tmpdir()`，完成后只 `openFile` 并在 Finder 显示 DMG，没有退出时换包步骤。

它可以留下临时 DMG，但没有 Squirrel / electron-updater 的 pending queue 或退出安装任务；`SelfUpdaterStash` 不读取这种临时下载。本次 VM 启动了旧版并运行 Duo 更新，但未主动触发厂商下载按钮，没有测量其手工下载留下的临时文件。

## 增量更新（delta / binary patch）

自定义下载器使用完整 DMG 的单个 URL，没有 blockmap 差分请求或补丁应用步骤。GitHub 发布 DMG `.blockmap`，但当前无 macOS ZIP；DuoUpdater 的 Electron ZIP 差分路线不消费 DMG blockmap，因此本规则使用整包。

## Changelog

- 来源: GitHub release 正文，经现有 `GitHubMarkdownParser` 结构化，无额外 recipe。
- 当前正文为双语多个小标题；离线真响应节选测试验证 `Major updates`、`New features/UI/Updates`、`Bug fixes`、`重大更新` 和对应条目的顺序。
- 生产 `channel-verify` 的 `changelog pane` 已返回结构化 release 正文，保留上述双语标题，旧版显示更新、新版显示最新；原始关键行见集中验收。

## 一键安装

- 已接入 Developer ID DMG 路线，沿用签名、bundle ID、Team ID 闸。5.10.0→5.11.8 已完成停用、运行中两轮真实安装。运行中换包保留旧进程，随后显式 `duo restart` 切换新进程，复查为最新；合成偏好保留，替换后严格签名和公证检查通过。
- 当前和上一版 Team 相同、严格签名校验及公证通过，具体结果见下。
- Bundle 只有 `Contents/Frameworks/electerm Helper{, (GPU), (Plugin), (Renderer)}.app` 四个普通 Electron helper；未发现 `Library/LoginItems`、LaunchAgent、LaunchDaemon、SystemExtension 或外部 XPC 组件，无需单独 restart hook。
- 当前 DMG 字节与 GitHub SHA-256 相符，`GitHubReleasesSource` 自动携带 digest，安装器在解包前校验。
- **读的是**: 公开 GitHub GA 整包，不依赖安装副本的账户或升级授权。

## 夜扫覆盖

- `Verify.swift` 自动枚举 `GitHubReleaseRegistry.rules`，recipe ID 为 `github:electerm/electerm:stable`。
- `InstallVerify.swift` 枚举具有 `installAssetPattern` 的同一规则，archive 检查 recipe ID 同上，finding ID 为 `install:github:electerm/electerm:stable`，覆盖 stable arm64 DMG。无需在 `AuditedUpdateFeeds` 重复登记。
- 历史 0.x / 1.x / Intel 副本读取同一个当前 stable，无独立旧版 feed 或密钥。
- `duo verify --only electerm` 命中上述检测 ID；`duo verify-install --only electerm` 实际读取 123,930,165 bytes，`ok 1 / skipped 0 / unresolved 0`，ID/Team 符合。首观记录与精确 ID 集合见集中验收，未替换既有 continuity anchor。

## 已知问题

- 早期 Intel app 在当前 macOS 的运行能力未验证；规则提供当前原生 arm64 整包。
- 以上安装和启动测试不覆盖 SSH/SFTP 会话、插件及完整业务功能；未主动触发厂商自更新下载。

## 如何复验

```bash
gh api repos/electerm/electerm/releases/latest
gh api --paginate 'repos/electerm/electerm/releases?per_page=100' --jq '.[] | [.tag_name,.prerelease] | @tsv'
gh release download v5.10.0 --repo electerm/electerm --pattern 'electerm-5.10.0-mac-arm64.dmg'
gh release download v5.11.8 --repo electerm/electerm --pattern 'electerm-5.11.8-mac-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh electerm-5.10.0-mac-arm64.dmg electerm-5.11.8-mac-arm64.dmg
swift run --package-path application-test channel-verify electerm-5.10.0-mac-arm64.dmg --expect stable
swift run --package-path application-test channel-verify electerm-5.11.8-mac-arm64.dmg --expect stable
```

## 历史与实测

### 初次接入（2026-11-16）

- 完整 GitHub 历史 595 releases：403 stable、192 prerelease。所有 stable tag 都匹配 `^v?([0-9]+(?:\.[0-9]+)+)$`；其中 `2.4.35`、`1.13.4`、`1.10.0` 无 `v`。prerelease 都是历史 0.x 的纯数字，最后一个为 2019-12-26 的 v0.27.105；stable 从 2019-12-30 的 v1.0.0 起。未发现带 beta/rc/nightly 后缀的独立发布轨。
- 最新 v5.11.8 发布于 2026-11-16；上一 stable 为 2026-11-10 的 v5.10.0。arm64 真包分别报告 short/build `5.11.8 / 5.11.8.1`、`5.10.0 / 5.10.0.1`，ID 与 Team 相同；`codesign --verify --deep --strict` 退出 0，`spctl` 为 `Notarized Developer ID`，`LSMinimumSystemVersion` 均为 13.0。
- v2.3.100 arm64（scaffold 自动核对）也是同 ID、Team，版本匹配 tag。v1.0.0 和 v0.27.105 的 x86_64 真包分别为 `1.0.0 / 1.0.0.395`、`0.27.105 / 0.27.105.394`，同 ID、同 Team，严格签名校验退出 0；`spctl` 来源为 `Developer ID`（未公证）。只做身份调查，没有启动或安装。
- 最早发布的 v0.7.0 无资产；最早有 macOS 资产的 v0.8.0（2017-11-30）未下载，但其 `electron-builder.json` 声明 `appId: org.electerm.electerm`。
- v5.11.8 arm64 DMG SHA-256：`712d6b154341cfef71f463a1062bea26dfa25e80e85b6a3d9b34c1ccc5ee2ba3`；v5.10.0：`c0f5d5c5e7b5a4d5c83aaf7d891715727d40183cd8e3f660bfe9efe5524ec188`。二者与 GitHub 资产 digest 一致。
