# Cutter

审计日期 2026-11-28。Bundle ID 为 `re.rizin.cutter`。厂商在同一个 GitHub 仓库发布正式版和 RC，每个版本按架构提供 DMG。Homebrew 的 `cutter` cask 跟随 GitHub 正式版，并为 Apple Silicon 选择 arm64 包。[厂商发布](https://github.com/rizinorg/cutter/releases) · [Homebrew cask](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/c/cutter.rb)

## 覆盖矩阵

| 副本 | Sparkle | GitHub | VendorProbe | 一键安装 | Changelog |
|---|---|---|---|---|---|
| 厂商正式版 | 无 feed | 检查最新正式版 | — | ARM64 DMG，按已安装副本的 Developer ID 验证 | 最新正式版的 GitHub 正文结构化 |
| 手动安装的厂商 RC | 无 feed | 同样检查最新正式版 | — | 受测 RC 无 Team ID，有更新时从正式发布页手动安装 | 同一份正式版说明 |

## 官方实包

从 GitHub Releases 下载并只读挂载下列 arm64 DMG。所有样本的 ID 相同，包内 short 和 build 也各自相同，均未声明 `SUFeedURL`。

| 发布 | 包内 short / build | 代码签名及 Gatekeeper |
|---|---|---|
| [2.5.0](https://github.com/rizinorg/cutter/releases/tag/v2.5.0) | `2.5.0-HEAD-a6f6ad7` | Team `7C89959B9X`，严格签名校验通过，Gatekeeper 识别为已公证 |
| [2.5.0-rc1](https://github.com/rizinorg/cutter/releases/tag/v2.5.0-rc1) | `2.5.0-HEAD-2f053dd` | Ad-hoc，无 Team，严格签名校验通过，Gatekeeper 拒绝 |
| [2.4.1](https://github.com/rizinorg/cutter/releases/tag/v2.4.1) | `2.4.1-HEAD-a5f88d1` | Team `7C89959B9X`，严格签名校验通过，Gatekeeper 识别为已公证 |
| [2.4.0](https://github.com/rizinorg/cutter/releases/tag/v2.4.0) | `2.4.0-HEAD-ec6a6fb` | Team `7C89959B9X`，严格签名校验通过，Gatekeeper 识别为已公证 |
| [2.4.0-rc1](https://github.com/rizinorg/cutter/releases/tag/v2.4.0-rc1) | `2.4.0-HEAD-ec6a6fb` | Ad-hoc，无 Team，严格签名校验通过，Gatekeeper 拒绝 |
| [2.3.4](https://github.com/rizinorg/cutter/releases/tag/v2.3.4) | `2.3.4-stable-209c26b` | Team `7C89959B9X`，严格签名校验通过，Gatekeeper 识别为已公证 |

主要可执行文件的 Mach-O 最低系统版本为 11.0（2.4.x 和 2.5.0 的受测包）或 13.0（2.3.4 的受测包）。发布页还提供独立的 Intel DMG，本次只验证 arm64 实包。

## 更新检测

- Stable 和 RC 的内置检查都查询 GitHub 的 `releases/latest`，只在远端的三段数字更高时提示并给出正式发布页链接。RC 是 GitHub 上可手动下载安装的预发布包。Duo 沿用同一个正式版来源，2.4.0-rc1 可看到 2.5.0，2.5.0-rc1 等到三段数字更高的正式版才会收到提示。[正式版检查](https://github.com/rizinorg/cutter/blob/v2.5.0/src/common/UpdateWorker.cpp) · [RC 检查](https://github.com/rizinorg/cutter/blob/v2.5.0-rc1/src/common/UpdateWorker.cpp) · [RC 版本比较](https://github.com/rizinorg/cutter/blob/v2.5.0-rc1/src/Main.cpp#L90-L102)
- 官方 2.4.0 和 2.4.0-rc1 的 `Info.plist` 字节相同，两个 tag 指向同一个 commit `ec6a6fb`。包内版本由版本号、可选打包后缀、Git 分支与短 commit 生成。Duo 比较 GitHub 或 Homebrew 的版本时取包内开头的三段数字，显示和安装检查仍用原始包内版本。[2.4 的 tag refs](https://api.github.com/repos/rizinorg/cutter/git/matching-refs/tags/v2.4) · [构建版本逻辑](https://github.com/rizinorg/cutter/blob/v2.5.0/CMakeLists.txt#L30-L61)

## 一键安装

GitHub 规则只选择正式版的 ARM64 DMG。已安装副本需有可验证的 Developer ID，且安装包通过现有签名和 Team ID 校验。已测正式版的 Team 为 `7C89959B9X`。受测 RC 是无 Team ID 的 ad-hoc 包，更新时需手动安装；签名用于安装信任校验。

## Changelog

复用 GitHub Releases 的结构化解析。正式版和手动安装的 RC 都显示正式发布说明。[2.5.0 发布说明](https://github.com/rizinorg/cutter/releases/tag/v2.5.0)

## 夜扫覆盖

GitHub 规则由夜扫枚举，检测 ID 为 `github:rizinorg/cutter:stable`，安装检查 ID 为 `install:github:rizinorg/cutter:stable`。两项都针对正式发布的 ARM64 安装包。

## 如何复验

- 在发布页分别取 2.4.0 与 2.4.0-rc1 的 arm64 DMG。用 `hdiutil attach -nobrowse -readonly` 分开挂载，再用 `cmp` 比较两份 `Cutter.app/Contents/Info.plist`。
- 对各包运行 `codesign -dv --verbose=4`、`codesign --verify --deep --strict`、`spctl -a -vv -t exec` 及 `swift run --package-path application-test channel-verify <Cutter.app 路径>`。
