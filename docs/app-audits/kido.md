# kido

[kido](https://github.com/kido-sh/kido) 是 Apple Silicon macOS 上运行 Darwin 微型虚拟机的 CLI。官网仓库维护网站和安装入口，实际安装包从 kido-sh/kido 的 GitHub Releases 发布。

## 覆盖

- **更新检测**读取官方脚本布局 `~/.local/bin/kido` 与 `~/.local/libexec/kido`，支持当前进程的绝对路径 `KIDO_PREFIX`。用 Mach-O 架构及 Go build info 的主模块和主包确认身份，直接读取版本。官方首发包 v0.1.0 的 Go 模块只有伪版本，凭发布包内可执行文件的 SHA-256 识别。
- **发行轨道**是 GitHub Stable。只有正式三段数字 tag，且同时发布 Darwin arm64 档案、`SHA256SUMS` 与 `SHA256SUMS.sig` 时才报告该版本。Linux 包及 GitHub 预发布不参与。
- **更新日志**读取 GitHub Releases 正文，保留版本、发布日期和 Markdown 结构。
- **更新命令**由 CLI 工作台和 `duo check kido` 提供所选副本的绝对路径与 `upgrade`。厂商命令验证固定的发布公钥签名及包摘要，再替换主程序和两个 helper。Duo 不执行从本地 Go 元数据识别出的 ad-hoc 签名程序。通用单文件替换会漏掉 helper，Duo 的一键更新没有开放。
- **Homebrew** 官方 `kido-sh/tap/kido` formula 由通用 Homebrew 路径处理。独立扫描排除链接至 Homebrew Cellar、Nix store 或 App bundle 的路径。仅用 `--prefix` 安装但未设置 `KIDO_PREFIX` 的非默认副本不在独立扫描范围内。

## 夜扫覆盖

独立 CLI provider 没有 App recipe ID。`duo verify` 与 `duo verify-install` 枚举 App recipe 和公开 App feed，未检查 kido CLI 的版本或安装档案。

## 历史与实测

2026-11-28，检查 GitHub 发布的 v0.1.0、v0.1.1、v0.2.0、v0.3.0、v0.4.0 五份 Darwin arm64 档案。均包含 `bin/kido`、`kido-agent` 和 `kido-vmm`。主程序是 arm64 Mach-O，ad-hoc 签名标识均为 `sh.kido.kido`，没有 Developer ID Team。v0.1.1 起 Go build info 与发布 tag 一致，v0.1.0 的档案经 GitHub asset 摘要比对后提取首发主程序指纹。

可在隔离 macOS VM 用 [v0.3.0 官方脚本](https://github.com/kido-sh/kido/blob/v0.3.0/install.sh) 的 `--version 0.3.0 --no-setup` 安装测试副本，无需下载 Darwin 客体镜像。用 `duo check kido --all --json` 检测，再运行该副本的 `kido upgrade`，重查版本并检查 helper。
