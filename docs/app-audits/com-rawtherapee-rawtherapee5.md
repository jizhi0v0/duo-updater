# RawTherapee

官网 Universal 正式版。5.11、5.12 与 5.13 都由 Team `5SJ86G6Q2R` 签名，但 5.13 更换了 bundle ID。官网包与 Homebrew cask 使用同一款应用，cask 仍由 Homebrew 管理。

| 官网正式版 | Bundle ID | short / build | `LSMinimumSystemVersionByArchitecture` |
|---|---|---|---|
| [5.11](https://rawtherapee.com/downloads/5.11/) | `com.rawtherapee.RawTherapee` | `5.11` / `5.11` | arm64 12.3，x86_64 12.3 |
| [5.12](https://rawtherapee.com/downloads/5.12/) | `com.rawtherapee.RawTherapee` | `5.12` / `5.12` | arm64 15.4，x86_64 12.3 |
| [5.13](https://rawtherapee.com/downloads/5.13/) | `com.rawtherapee.rawtherapee5` | `5.13` / `5.13` | arm64 26.0，x86_64 12.0 |

## 更新检测

官网稳定包无 `SUFeedURL`。VendorProbe 一次读取[官网 macOS 下载目录](https://rawtherapee.com/shared/builds/mac/)，对两代正式版都选出本机可运行的最新正式 Universal ZIP。目录按文件名排序，版本与 Apple Silicon 系统下限取自同一条包链接。以当前发布为例，macOS 15.0–15.3 对应 5.11，15.4–15.x 对应 5.12，macOS 26.0 及以上对应 5.13。出现新版或某包下架后，下一次检查重新比较目录内容。若现有正式包均不兼容，按目录中的最高版本列出其系统要求。手动更新入口指向所选版本的发布页。

[Automated Builds](https://github.com/RawTherapee/RawTherapee/releases/tag/nightly-github-actions) 的 arm64 开发包也使用旧 ID。两份版本字段都带 `-42-g3458b9a18` 这样的 Git 后缀。在旧 ID 上识别为 Nightly，跳过正式版检测和日志。正式版探针另外要求纯数字点分版本。开发包使用滚动 GitHub release 和提交版本，未接入该轨的更新。GitHub 上 5.12 和 5.13 的 RC 条目没有 macOS 安装资产。

## 一键安装

本次提供检测和官网入口。5.11–5.13 的官方 ZIP 都把 `RawTherapee.app` 放在内层 DMG，外层另带独立的 `rawtherapee-cli` 和安装说明。普通 ZIP 路径展开后查找应用，`nestedArchivePath` 从已验证的外层安装器应用内读载荷。5.12 → 5.13 还涉及 bundle ID 改名，整包替换需进一步验证身份迁移、用户数据和命令行组件。

## Changelog

两代 ID 按目标正式版本访问 `/downloads/{version}/`。结构化结果保留 New Features、Other Important Changes Since 5.12 等标题和条目。嵌套条目在面板中按阅读顺序展开，安装说明与校验值不进入 changelog。

## 夜扫覆盖

- VendorProbe 自动枚举 `vendor:com.rawtherapee.RawTherapee:stable` 与 `vendor:com.rawtherapee.rawtherapee5:stable`。两项都读当次验证宿主能运行的最高版本，兼容范围随目录内容变化。
- 对应日志监控为 `changelog:com.rawtherapee.RawTherapee:stable` 和 `changelog:com.rawtherapee.rawtherapee5:stable`。夜扫按找到的首个正式版本检查对应页面。macOS 26+ 正常发布时检查当前版日志，5.11 与 5.12 的归档日志不各自占一个独立夜扫项。仅检测的 recipe 无 `install` spec，因此安装字节夜扫无目标。滚动开发包不在本次监控覆盖内。

## 历史与实测

- 2026-11-28。核对 [5.11 官网 ZIP](https://rawtherapee.com/shared/builds/mac/RawTherapee_macOS_12.3_Universal_5.11.zip)、[5.12 GitHub ZIP](https://github.com/RawTherapee/RawTherapee/releases/download/5.12/RawTherapee_macOS_15.4_Universal_5.12.zip)、[5.13 GitHub ZIP](https://github.com/RawTherapee/RawTherapee/releases/download/5.13/RawTherapee_MacOS_26.0_Universal_5.13.zip)。三款通过严格签名与 Gatekeeper 公证检查。官网目录中 5.12 与 5.13 均只列出 ZIP，按同名请求裸 DMG 均返回 404。
- 2026-11-28。[arm64 开发 ZIP](https://github.com/RawTherapee/RawTherapee/releases/download/nightly-github-actions/RawTherapee_dev_macOS_arm64_Release.zip) 解出的 5.13-42-g3458b9a18 是 arm64 ad-hoc 签名包，macOS 下限为 14.0。
