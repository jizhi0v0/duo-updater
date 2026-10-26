# Museeks

## 基本信息
- App: Museeks — 开源音乐播放器，MIT。0.13.1 及以前是 Electron，0.20.0 起是 Tauri 2（0.20.0 release 正文「Bye Electron, Hello Tauri!」；版本从 0.13 直接跳到 0.20）
- Bundle ID: `io.museeks.app`（0.22.0 起；0.20.0–0.21.1 是 `Museeks`；Electron 版是 `io.museeks.app`，见「覆盖清单」）
- 仓库: `martpie/museeks`（默认分支 `master`，未归档，最近 push 2026-07-03）
- Team ID: `YK6MWU3892`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 0.23.4（tag `0.23.4`，资产 `Museeks_0.23.4_universal.dmg`）；上一版 0.23.3；观测日期: 2026-10-26
- 自更新机制: **没有自更新器，只有提示**。settled from source: `src/api/SettingsAPI.ts` on `master` 的 `checkForUpdate`：启动时（配置 `auto_update_checker`，默认 true）`fetch('https://api.github.com/repos/martpie/museeks/releases')`，找第一个 `semver.gt(tag, 当前版本)` 的 release，弹 toast「Museeks X is available, check https://museeks.io!」。不下载、不换包。`Cargo.toml` 没有 `tauri-plugin-updater`，`tauri.conf.json` 没有 `plugins.updater`，release 里没有 `latest.json`；0.23.4 可执行文件里 `latest.json` / `tauri_updated_app` / `with administrator privileges` 的 strings 计数都是 0。Electron 0.13.1 的 `SettingsActions.ts` 是同一段逻辑；它的包里有 electron-builder 生成的 `app-update.yml`（provider github），但 `package.json` 不依赖 `electron-updater`，release 也没有 `latest-mac.yml`，没人读它
- 分发: GitHub Releases（每版一个 universal dmg）；Homebrew cask `museeks`（0.23.4，**不是** `auto_updates`，url 就是同一个 GitHub dmg）；App Store 没有（`itunes.apple.com/lookup?bundleId=io.museeks.app` resultCount 0）；官网 museeks.io 的下载链接直接指向 GitHub 的 0.23.4 资产（2026-10-26 读页面）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | brew 装的副本走 Homebrew 源 | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`、没有 `app-update.yml`（Tauri 版）、没有 MyGo feed：feed-discover 对 0.23.4 报 `no Sparkle, no electron-builder update config and no MyGo feed`。cask 不是 `auto_updates`，所以 brew 装的副本由 `HomebrewCaskSource` 回答（`SourceStack` 里在 GitHub 之前），其他副本由 GitHub rule 回答。

## 覆盖清单
- 各版本的 bundle id / Team（`check-bundle.sh` 读真包）:
  - 0.23.4: `io.museeks.app`，Team YK6MWU3892，Notarized，universal（x86_64 arm64）
  - 0.23.3: 同上
  - 0.22.0: 同上（第一个 `io.museeks.app` 的 Tauri 版）
  - 0.21.1: **`Museeks`**，Team YK6MWU3892，Notarized，universal
  - 0.20.0: **`Museeks`**，同 Team，Notarized，`CFBundleVersion` 是时间戳 `20250101.204903`（只比 short version，不影响）
  - 0.13.1（Electron 最后一版，`museeks-arm64.dmg`）: `io.museeks.app`，Team YK6MWU3892，spctl `source=Developer ID`（没有公证票据），arm64 单架构；带四个 `io.museeks.app.helper*` 嵌套 helper（Electron 标准）
  - 源码佐证: Electron 的 `electron-builder.yml` `appId: io.museeks.app`（tag 0.13.1）；`src-tauri/tauri.conf.json` `identifier` 在 0.20.0、0.20.9、0.21.0、0.21.1 是 `Museeks`，0.22.0、0.22.3、0.23.0 起是 `io.museeks.app`
- **旧 id `Museeks`（0.20.0–0.21.1）: 缺口，未覆盖。** 现有机制是 `BundleIDMigration`，条目应为 `BundleIDMigration(from: "Museeks", to: "io.museeks.app", teamID: "YK6MWU3892", lastFromVersion: "0.21.1", firstToVersion: "0.22.0")`（边界都读自真包）。它是改名不是重写：Tauri 的存储目录是 `dirs::config_dir()/museeks`（`src-tauri/src/plugins/config.rs` `get_storage_dir`），macOS 上即 `~/Library/Application Support/museeks`；0.20/0.21 用的是 `…/Museeks`，0.22.0 的 `libs/init.rs` 只在旧目录存在而新目录不存在时 rename，默认的大小写不敏感 APFS 上两者是同一目录，数据原样沿用（推断自源码，未在真机上跑 0.21.1→0.23.4）。`BundleIDMigration.swift` 在 `Models/`，属于本次 brief 禁止改动的引擎文件，所以没有加，交主会话决定。不加时，这些副本 channel-verify 实测 `winning source <none>`、`status unknown (no source answered)`；它们自己的 toast 仍会提示新版
- **Electron 副本（≤0.13.1，同 id 同 Team）: 检测 ✓，一键被 `OneClickGate` 挡。** 厂商 0.20.0 正文: 存储层不向后兼容（tracks、playlists、config），要从 app 里重新导入曲库，且应在装 0.20 **之前**先导出播放列表。一键原地换包后，用户手上就没有能导出播放列表的旧 app 了。所以 gate 只放行 0.20 及以上（`.installedVersion`，`^(?:0\.(?:[2-9][0-9]|[1-9][0-9]{2,})|[1-9][0-9]*)(?:\.[0-9]+)*$`）。Electron 与 Tauri 版的包标记（实测）: Electron 0.13.1 有 `Contents/Frameworks/` 和四个 `Museeks Helper*.app`，`Resources/app-update.yml`；Tauri 0.23.4 的 `Contents/` 只有 `Info.plist`、`MacOS/museeks`、`Resources/{icon.icns,icons/icon.png}`、`_CodeSignature`、`CodeResources`。两条产品线按版本号严格分界（0.13.1 → 0.20.0，中间没有 release），所以 gate 用版本号就够
- 其他轨: 无。53 个 release 没有一个 `prerelease` 或 draft；源码里没有 beta/nightly 开关（`Config` 类型没有 channel 字段）。`.github/workflows/build.yml` 在每次 push 到 `master`、PR 和手动触发时构建，并把 universal dmg 作为 workflow artifact 上传（`actions/upload-artifact`，要登录 GitHub 才能下、有保留期）；这不是发布的轨，版本号就是 `tauri.conf.json` 里的当期版本，装了这种构建的人会被当成那个版本（没有实测这种 artifact 的签名）。tag 里有远古的 `0.4.0-rc1`、`0.4.0-rc2`，没有 release，`versionPattern` 锚定不读它们
- 版本范围: 53 个 release 的 tag 全是 `数字(.数字)+`，`versionPattern` 都读得出（含两段式）；下个大版本 `1.0.0` 也读得出。0.20.0 起每个 release 恰好一个 `Museeks_<version>_universal.dmg`。Electron 时代的 mac 资产名是 `museeks-arm64.dmg` / `museeks-x64.dmg`（0.13.x）、`museeks.dmg`（0.11.5 等），都不匹配安装模式，也不需要匹配（只会装最新版）。0.1.0 是最老的 release，没有 mac 资产
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Museeks `LSMinimumSystemVersion` 10.13、universal，都在下限之下，不需要 `hostRequirement`
- 更老的 Electron 版（0.11.5 及以前）的 Team 没有读真包；它们都被 gate 挡在一键之外，检测不看 Team，所以不影响结论

## Channel 详情

只有 stable 一条轨。settled from source: release 列表（53 个，`prerelease` 全 false）、`src/generated/typings.ts` 的 `Config`（无 channel 字段）、`.github/workflows/build.yml`（只上传 workflow artifact，不发 release）。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.museeks.app` | — | 版本号纯数字 | GitHub `/releases/latest` | ✓ |

## 更新检测
- 源: `martpie/museeks` GitHub Releases，`/releases/latest`
- 版本方案: tag `0.23.4` → `CFBundleShortVersionString` `0.23.4`、`CFBundleVersion` `0.23.4`（`tauri.conf.json` `version`）
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`（锚定：`0.24.0-rc.1` 不匹配）
- install pattern `^Museeks_[0-9]+(?:\.[0-9]+)+_universal\.dmg$`。同一 release 里其他资产是 Linux（rpm、deb、AppImage、flatpak）、Windows（`-setup.exe`）和各自的 `.sha256`，都不匹配
- `versionPattern` 读得出列表里 53 个 stable tag 的 53 个

## 按架构 / 按 OS 分轨
- 0.20.0 起只有一个 universal dmg（`archs=x86_64 arm64`），`LSMinimumSystemVersion` 10.13；release 不声明 OS 上限。Electron 0.13.x 曾分 arm64 / x64 两个 dmg，被 gate 挡，不涉及

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见「自更新机制」） | release 里只有整包和 `.sha256` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | 不需要 |
| 证据 | `checkForUpdate` 只弹 toast，不下载（源码） | — | — |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 0.23.3 起）: `source structured: 1 entries; newest 0.23.4: 1 items, headings []; first items ["Fixed issues with traffic lights positio"]`
- 是结构化条目，不是 raw inline notes。`headings []` 是因为 0.23.4 正文本身就是一个无标题的 `-` 列表（一条），没有被压平的标题。较大的版本（0.22.0、0.20.0）正文带 `###` / `##` 标题，那些版本的解析结果没有实测
- 0.23.3 与 0.23.4 之间没有别的 release，所以只有 1 条；从 0.13.1 起 channel-verify 也只报 `release history 1 entries`
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（Tauri 副本 0.20 及以上）**；Electron 副本（≤0.13.1）被 `OneClickGate` 挡，只检测；旧 id `Museeks` 的副本目前连检测都没有（见「覆盖清单」）
- 端到端: 待主会话（真机从 0.23.3 装到 0.23.4）
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Museeks.app` + `Applications` 软链 + `.VolumeIcon.icns`
- 嵌套 / 常驻组件: 无。0.23.4 的 `Contents/` 下只有 `Info.plist`、`MacOS/museeks`、`Resources/icon.icns`、`Resources/icons/icon.png`、`_CodeSignature`、`CodeResources`；没有 Frameworks、Helpers、LoginItems、LaunchAgent。可执行文件 strings 里 `SMAppService`、`LaunchAgents`、`LoginItems`、`/.claude`、`/.agents`、`/.codex` 计数都是 0
- 签名: 0.20.0、0.21.1、0.22.0、0.23.3、0.23.4 都是 Team `YK6MWU3892`、Notarized Developer ID；Electron 0.13.1 同 Team，未公证。Team 没换过
- 校验: GitHub digest `sha256:ff8b3053fefdabb99c54868e74b4857087ac501bf91a026df60776bded2befb7`，与下载的包一致（8946394 字节），也与厂商自己的 `.sha256` 资产一致；0.23.3 dmg `5322dfbbb3791b9efc3c103908bfefea26dda335ee06abacc615e122776112ef` 同样与 `.sha256` 资产一致
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 网络类 app 检查: 不是代理 / VPN / 抓包工具，不改系统代理、不装根证书或 Network Extension（strings `networksetup`、`SystemConfiguration`、`NEVPN`、`NETunnel` 计数 0）。它有一个本机流媒体服务（`src-tauri/src/plugins/stream_server.rs`）：配置 `audio_stream_server` 打开时在 `127.0.0.1` 的随机端口上起 axum，给自己的播放器读本地音频文件，0.23.3 正文说是为 Linux 加的
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 首启会请求 `api.github.com/repos/martpie/museeks/releases`，从 0.23.3 启动会弹一个「Museeks 0.23.4 is available」toast，只是提示
  - Info.plist 为 aac / mp3 / m4a / 3gp / wav / ogg / flac / weba 声明文档类型，`LSHandlerRank` 是 **`Default`**（不是 Alternate）；没装过别的播放器时，LaunchServices 可能把这些类型的默认打开方式交给它。URL scheme `museeks`
  - 数据写在 `~/Library/Application Support/museeks/`（`config.toml`、`museeks.db`）；本机若有旧的 Electron 版数据也在同一目录（大小写不敏感）
  - `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` 声明了（WebRTC 模板），正常使用不应触发

## 已知问题
- 旧 id `Museeks`（0.20.0–0.21.1）的副本没有检测，需要在 `BundleIDMigration.all` 加一条（见「覆盖清单」），引擎文件，本次没改
- Electron 副本检测会提示 0.23.4，但一键被挡；理由是厂商写明的数据不兼容，不是签名问题

## 如何复验
```bash
gh release download 0.23.4 --repo martpie/museeks --pattern 'Museeks_0.23.4_universal.dmg'
gh release download 0.23.3 --repo martpie/museeks --pattern 'Museeks_0.23.3_universal.dmg'
gh release download 0.21.1 --repo martpie/museeks --pattern 'Museeks_0.21.1_universal.dmg'
gh release download 0.13.1 --repo martpie/museeks --pattern 'museeks-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Museeks_0.23.4_universal.dmg Museeks_0.21.1_universal.dmg museeks-arm64.dmg
swift run --package-path application-test channel-verify Museeks_0.23.3_universal.dmg --expect stable   # GitHub, UPDATE → 0.23.4
swift run --package-path application-test channel-verify Museeks_0.23.4_universal.dmg --expect stable   # up to date
swift run --package-path application-test channel-verify Museeks_0.21.1_universal.dmg --expect stable   # 旧 id: unknown
swift run --package-path application-test channel-verify museeks-arm64.dmg --expect stable              # Electron: UPDATE → 0.23.4（一键被 gate 挡）
swift test --package-path DuoUpdaterCore --filter museeksOneClickIsForTauriCopiesOnly
```

channel-verify 原始输出（2026-10-26）:
```
0.23.3 dmg: detected channel → stable; winning source GitHub; latest 0.23.4;
  download https://github.com/martpie/museeks/releases/download/0.23.4/Museeks_0.23.4_universal.dmg;
  changelog pane source structured: 1 entries; newest 0.23.4: 1 items, headings []; status UPDATE → 0.23.4
0.23.4 dmg: winning source GitHub; latest 0.23.4; status up to date
0.21.1 dmg (bundle id Museeks): winning source <none>; status unknown (no source answered)
0.13.1 dmg (Electron): winning source GitHub; latest 0.23.4; status UPDATE → 0.23.4
```

## 建议下一步
1. 主会话真机（0.23.3 → 0.23.4），结果写回「一键安装」并把 README 行改成 ✓
2. 决定是否在 `BundleIDMigration.all` 加 `Museeks` → `io.museeks.app`（Team YK6MWU3892，0.21.1 / 0.22.0），再在真机上从 0.21.1 跑一次，确认曲库沿用
