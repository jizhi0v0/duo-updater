# Mattermost Desktop

## 基本信息

- 当前直接下载 Bundle ID：`Mattermost.Desktop`；Team：`UQ8HT4Q2XM`。
- 当前包：6.4.0，short version `6.4.0`、build `438145774761`；上一稳定包 6.3.2，build `414060254821`。两包均为 arm64、有效 Developer ID 签名并通过公证检查。
- 官方项目仍在发布；[6.4.0 release](https://github.com/mattermost/desktop/releases/tag/v6.4.0) 和[官方更新说明](https://docs.mattermost.com/product-overview/desktop-app-changelog)均有对应记录。
- `app-update.yml` 的 `provider: github` 是发布配置；通用 `ElectronManifestSource` 不为它构造地址。当前上游 [`UpdateNotifier`](https://github.com/mattermost/desktop/blob/v6.4.0/src/main/updateNotifier.ts)读取 `releases.mattermost.com/desktop/latest.txt`（预发布版本读取 `rc.txt`），通知用户后在浏览器打开安装包；不后台暂存自更新。
- 四个正常 Electron Helper 位于 app 内；当前包检查未发现独立外部 agent/daemon。更新沿用现有 Electron 退出、换包和重启路径。

## 覆盖矩阵

| 拷贝组 | 检测 | 一键安装 | 结构化更新说明 |
|---|---|---|---|
| 直接下载 stable，`Mattermost.Desktop` | GitHub stable | arm64 ZIP，签名/Team 闸 | 官方文档，保留分节及平台标题 |
| 官方 RC，`Mattermost.Desktop`，`-rc.N` / `-rcN` | 本地产品版本识别后，VendorProbe `rc.txt` | 当前 RC 专用 arm64 ZIP | 缺口：当前官方文档没有 RC 版本条目；GitHub release 也可能不存在，不冒充变更说明 |
| 6.2 Extended Support Release | 与普通 stable 相同的 latest 轨；可更新到后续 stable | 复用 stable ARM ZIP | 官方文档中 ESR 补丁逐项保留 |
| 签名旧版 `com.mattermost.desktop` | `BundleIDMigration` 复用当前 stable rule | 同 Team、低于观察边界时允许迁移 | 复用当前 stable recipe |
| 早期 `com.electron.electron-mattermost` | 独立 stable rule，variant `legacy-electron` | 不提供：观察包没有签名，不能用同 Team 迁移 | 官方文档 |
| 后续旧版 `com.electron.mattermost` | 独立 stable rule，variant `legacy-mattermost` | 不提供：观察包没有签名，不能用同 Team 迁移 | 官方文档 |
| 0.1.0，缺少 `CFBundleShortVersionString` | 不进入现有扫描器 | 手动升级 | 不可选择该拷贝；不能拿 Electron build `0.33.6` 当产品版本 |
| Homebrew `mattermost` | 相同官方二进制；非托管时由 GitHub 回答，实际 brew 托管时沿用现有管理器规则 | 沿用现有来源策略 | 官方文档 |
| Mac App Store | 通用 MAS 路径 | 商店管理 | 商店说明；`isMASApp` 阻止此 GitHub/文档配方覆盖商店拷贝 |
| 上游 nightly / daily 测试构建 | 当前 ARM 包身份和完整 asar 版本已核对；本补丁未登记产品更新配方 | 包签名已验，安装路由待整合 | 未宣称支持 |

官方 [Mac App Store listing](https://apps.apple.com/us/app/mattermost-desktop/id1614666244?mt=12) 与[部署文档](https://docs.mattermost.com/deployment-guide/desktop/macos-desktop-install)确认商店发行存在；本次未取得商店包，未推断其 Bundle ID。没有 licence、账号或付费状态分支。

## Channel 与版本规则

- stable 使用 `^v?([0-9]+(?:\.[0-9]+)+)$`，兼容未带 `v` 的旧稳定 tag，排除 RC/beta 尾缀；安装 pattern 仅接收稳定 arm64/m1 `.zip`，不选 DMG、Intel ZIP 或 blockmap。
- 真实 6.1.0-rc.4 包的 short/build 均为 `6.1.0-rc.4`；6.2.5-rc.5 的 plist short 为 `6.2.5`、build 为 `410455984891`，但 `app.asar/package.json` 的完整产品版本仍为 `6.2.5-rc.5`。新包须由扫描器恢复该产品版本后判断 channel 和比较更新，不能把 plist 的正式版本形状当作 stable 证明。
- `ReleaseChannel.detect` 的 `Mattermost.Desktop` 专用分支按完整 `-rc.N` / `-rcN` 产品版本后缀直接返回 `.rc`；其他 app 的 RC 约定保持各自语义，包括 DeepSeek 普通更新轨中的 `-rc.N`。
- RC 使用上游 `UpdateNotifier` 实际读取的 `https://releases.mattermost.com/desktop/rc.txt`，整份响应只接受一个完整 RC 版本，并用同一解析版本填充官方 `.../{version}/mattermost-desktop-{version}-mac-arm64.zip`。最新 RC 可以只存在于 CDN：实测 `6.2.5-rc.5` 已公开，GitHub 对应 release 端点为 404，而 GitHub release list 停在 `6.1.0-rc.4`。
- RC 身份由已装包决定，不依赖其精确 GitHub tag；删除旧 tag、tag 端点 404 或不可访问均不会将此拷贝重新归到 stable。source fixture 中所有精确 tag 端点均为 404，RC 拷贝只请求 `rc.txt`，GitHub stable rule 不适用于 `.rc` 拷贝。
- 官方文档称 6.2 为 Extended Support Release，但[6.2.0 的 `UpdateNotifier`](https://github.com/mattermost/desktop/blob/v6.2.0/src/main/updateNotifier.ts)对无预发布后缀的版本始终使用 `latest.txt`，其[同版本 buildConfig](https://github.com/mattermost/desktop/blob/v6.2.0/src/common/config/buildConfig.ts)指向相同 `https://releases.mattermost.com/desktop`。该实现没有 ESR 更新偏好或独立端点分支；因此这里沿用上游普通 stable 检查行为，不将 6.2 锁在 ESR 补丁线。
- 上游 [nightly 版本脚本](https://github.com/mattermost/desktop/blob/v6.4.0/.github/actions/patch-nightly-version/patch-version.go)把 `package.json` 写成 `X.Y.Z-nightly.YYYYMMDD`；[`generate_latest_version.sh`](https://github.com/mattermost/desktop/blob/v6.4.0/scripts/generate_latest_version.sh)生成 `nightly.txt`，[nightly workflow](https://github.com/mattermost/desktop/blob/v6.4.0/.github/workflows/nightly-main.yml)另行上传同一 S3 release bucket，并非 GitHub Releases 的 RC。公开 [nightly.txt](https://releases.mattermost.com/desktop/nightly.txt)实测 200，返回 `6.5.0-nightly.20261116`；对应真实 ARM ZIP 的 plist short 为 `6.5.0`，asar 完整产品版本为 `6.5.0-nightly.20261116`。产品检测、安装和监控由整合分支继续补充，本补丁不声称已经覆盖。

## Changelog

来源是[官方文档 Markdown 源码](https://raw.githubusercontent.com/mattermost/mattermost/master/docs/main/product-overview/desktop-app-changelog.mdx)。逐个完整版本的粗体标记分 entry，补丁说明不会吞并 `.0` 的原始变更；`###` / `####` 保留类别与平台；链接、行内代码及实体交给现有清理器。`Download Binaries` 和 `Original v… release` 不作为变更项目。stable recipe 显式排除 RC/nightly，阻止 registry 的 stable fallback 把正式版说明当 RC 说明。

## 旧 ID 与签名边界

- 实包 0.1.0 / 1.0.0：`com.electron.electron-mattermost`；1.0.0 未签名。
- 实包 1.1.0 / 3.4.0：`com.electron.mattermost`；1.1.0 未签名。
- 实包 4.0.0 / 4.1.0：`com.mattermost.desktop`，Team `UQ8HT4Q2XM`，x86_64。已有扫描无需运行旧包；在本项目 Apple Silicon/macOS 15+ 主机上可用当前 arm64 包升级。
- 实包 6.3.2 / 6.4.0：`Mattermost.Desktop`，同 Team。迁移记录 `lastFromVersion: 4.1.0`、`firstToVersion: 6.3.2` 是已观察的包边界，未声称精确改名发生在 6.3.2。旧 ID 在该边界及以上不映射；签名迁移必须两侧 Team 相同。
- 无签名的两个 `com.electron.*` ID 不能套 `BundleIDMigration` 的同 Team 假设，也不能以 GitHub digest-only 信任跨到不同 ID 的 Developer ID 包；保留检测和手动下载。

## 夜扫覆盖

由现有 registry 自动枚举，不增加重复 generic feed：

- `github:mattermost/desktop:stable`
- `vendor:Mattermost.Desktop:rc`
- `github:mattermost/desktop:stable:legacy-electron`
- `github:mattermost/desktop:stable:legacy-mattermost`
- `changelog:Mattermost.Desktop:stable`
- `changelog:com.electron.electron-mattermost:stable`
- `changelog:com.electron.mattermost:stable`

安装字节检查对应 `install:github:mattermost/desktop:stable` 与 `install:vendor:Mattermost.Desktop:rc`；签名旧 ID 映射复用 stable 监控。无签名旧 ID 的检测行没有 install spec，不能算安装字节检查通过。nightly、MAS 商店包及 0.1.0 扫描缺口不由这两个 ZIP 行覆盖。

本分支已运行 focused fixture/source-selection tests；现场 `duo verify --only mattermost`、`duo verify-install --only mattermost`、整体 `make test` 和旧到新安装验证由整合分支执行，未在此把它们写成通过。

## 历史与实测

2026-11-16：读取完整 GitHub Releases 历史，并直接下载检查 0.1.0、1.0.0、1.1.0、3.4.0、4.0.0、4.1.0 和 6.1.0-rc.4 实包身份；当前 6.3.2 / 6.4.0 身份来自同日 VM 包检查记录，两个 ARM ZIP 也已下载作为整合安装验证输入。

RC 6.1.0-rc.4 ARM ZIP 为 113,761,398 bytes，`codesign --verify --deep --strict` 成功，`spctl --assess --type execute --verbose` 为 `accepted / source=Notarized Developer ID`，Team 为 `UQ8HT4Q2XM`。未安装或启动下载包。

同日补查官方 RC feed，返回 `6.2.5-rc.5`。该版本 ARM ZIP 为 123,262,733 bytes，真实包 Team 为 `UQ8HT4Q2XM`，严格深度签名检查成功，Gatekeeper 为 `accepted / source=Notarized Developer ID`。两个观察 RC 的 asar `package.name` 都是 `mattermost-desktop`。plist 短版本与 asar 完整产品版本的区别如上，已交由整合分支扫描器处理；此处的 source fixture 使用恢复后的产品版本。

同日下载公开 nightly feed 对应的 `6.5.0-nightly.20261116` ARM ZIP，123,243,637 bytes。`Mattermost.Desktop` 的 plist short/build 为 `6.5.0` / `438026459481`，asar `package.name` / `version` 为 `mattermost-desktop` / `6.5.0-nightly.20261116`；Team `UQ8HT4Q2XM`，严格深度签名检查成功，Gatekeeper 为 `accepted / source=Notarized Developer ID`。未安装或启动该包。

同日官方文档 Markdown 原文 regex 得到 72 个完整版本 entry；首项 6.4.0 有 29 个项目，6.3.2 有 1 个项目，6.3.1 有 6 个项目，6.3.0 的正文保持独立。离线 fixture 覆盖实体清理、代码/链接、类别/平台标题及补丁边界。RC source fixture 覆盖本地后缀识别、精确已装 tag 端点不可用、vendor RC feed 及安装 URL、stable `/latest` 不被访问。

当前 [`electron-builder.ts`](https://github.com/mattermost/desktop/blob/v6.4.0/electron-builder.ts)会 coerce macOS short version；真实已发布 6.1.0-rc.4 保留后缀、6.2.5-rc.5 与当前 nightly 则已剥离后缀，各包 asar 都保存完整产品版本。
