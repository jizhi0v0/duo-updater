# Cutter

审计日期 2026-11-28。Bundle ID 为 `re.rizin.cutter`。厂商在同一个 GitHub 仓库发布正式版和 RC，每个版本按架构提供 DMG。Homebrew 的 `cutter` cask 跟随 GitHub 正式版，并为 Apple Silicon 选择 arm64 包。[厂商发布](https://github.com/rizinorg/cutter/releases) · [Homebrew cask](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/c/cutter.rb)

## 覆盖矩阵

| 副本 | Sparkle | GitHub | VendorProbe | 一键安装 | Changelog |
|---|---|---|---|---|---|
| 厂商正式版 | 无 feed | 未接入 | — | 未接入 | 厂商有 GitHub 发布说明。Duo 尚未结构化 |
| 厂商 RC | 无 feed | 未接入 | — | 未接入 | 厂商有独立的 GitHub 发布说明。Duo 尚未结构化 |

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

## 渠道识别与更新检测

- **同一个包内版本曾用在两个公开发布轨。** 官方 2.4.0 和 2.4.0-rc1 的 `Info.plist` 字节相同，两个 tag 指向同一个 commit `ec6a6fb`。2.3.4、2.3.0 也各有与正式 tag 同 commit 的公开 RC。2.5.0 的正式 tag 与 RC4 tag 共用 commit，但 GitHub API 对 RC4 的 Release 查询返回 404。[2.4 的 tag refs](https://api.github.com/repos/rizinorg/cutter/git/matching-refs/tags/v2.4) · [2.3 的 tag refs](https://api.github.com/repos/rizinorg/cutter/git/matching-refs/tags/v2.3) · [2.5 的 tag refs](https://api.github.com/repos/rizinorg/cutter/git/matching-refs/tags/v2.5)
- 上游构建用版本、可选打包后缀、Git 分支与短 commit 生成包内版本。厂商自带更新器查询 GitHub 的 `releases/latest`、比较三段数字并给出正式发布页链接。Duo 若照搬该端点，2.4.0-rc1 会收到后续正式版的提示。现有 GitHub tag 反查和 VendorProbe 安装版本筛选均依赖可区分的本地版本，无法分开这两个包。受测样本的 Team 差异可供安装签名校验使用，未找到厂商为各发布轨承诺这个签名分界的规则。[构建版本逻辑](https://github.com/rizinorg/cutter/blob/v2.5.0/CMakeLists.txt#L30-L61) · [厂商更新器](https://github.com/rizinorg/cutter/blob/v2.5.0/src/common/UpdateWorker.cpp)
- 在 Apple Silicon macOS 27.2 VM 用生产来源链的 `channel-verify` 核对 2.4.0、2.4.0-rc1、2.4.1、2.5.0 和 2.5.0-rc1。五份均显示 `detected channel → stable`（默认值）、`winning source <none>`、`status unknown (no source answered)`。2.4.0 正式版与 RC 的 `Info.plist` 在 VM 中也通过了逐字节比较。两条轨均保留当前覆盖缺口。

## 一键安装

2.4.1 与 2.5.0 的 arm64 DMG 可作为同 Team 旧新对。厂商的包内版本带 commit，正式发布 tag 只包含三段版本。安装信任检查无法决定发布轨归属，`OneClickGate` 也仅能限制安装，因此本次未登记安装规则，未做原位升级。

## Changelog

正式版和 RC 的说明随各自 Release 发布。用包内短 hash 选择说明会遇到同一 commit 对应两篇说明的情况。上述五份副本的 `channel-verify` 均显示 `changelog pane none — the pane says there are no release notes`。

## 夜扫覆盖

未登记 Cutter 的检测或安装规则，无夜扫 recipe ID。GitHub 的 release 记录可以区分远端条目，现有本地信号无法把受测副本可靠配到这些条目。

## 如何复验

- 在发布页分别取 2.4.0 与 2.4.0-rc1 的 arm64 DMG。用 `hdiutil attach -nobrowse -readonly` 分开挂载，再用 `cmp` 比较两份 `Cutter.app/Contents/Info.plist`。
- 对各包运行 `codesign -dv --verbose=4`、`codesign --verify --deep --strict`、`spctl -a -vv -t exec` 及 `swift run --package-path application-test channel-verify <Cutter.app 路径>`。
