# Antigravity CLI

`agy` 的独立稳定版由 [Google 的 shell 安装器](https://antigravity.google/cli/install.sh) 安装在
`~/.local/bin/agy`。macOS Apple Silicon 发布包内是平铺的 Mach-O 可执行文件。DuoUpdater
在 CLI 工具中显示它，`duo list`、`duo check` 和 `duo install` 使用同一个 provider。
CLI 工具台使用 [Google 发布的彩色图标](https://antigravity.google/assets/image/antigravity-logo.png)。

## 覆盖

- **检测**读取 [Google 的 darwin_arm64 manifest](https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/darwin_arm64.json)。
  执行 `agy --version` 前检查 Google Developer ID（Team `EQHXZ8M8AV`）、签名标识 `cli`、
  签名完整性和 quarantine 标记。
- **一键更新**运行已验证的 `agy update`，由 Google 的自更新器下载、校验和替换可执行文件。
  完成后重新验证签名并读取版本。Google 的 advisory lock 负责串行化终端、后台和 Duo 发起的更新。
  Duo 的进程环境设置 `AGY_CLI_DISABLE_AUTO_UPDATE=true` 时，更新仍会显示，并提供可复制的手动命令。
- **更新日志**读取 [Google 的 CLI CHANGELOG.md](https://github.com/google-antigravity/antigravity-cli/blob/main/CHANGELOG.md)
  并按版本解析。
- [Homebrew cask](https://formulae.brew.sh/cask/antigravity-cli) 用自己的 launcher 禁用后台自更新，
  由 Homebrew 路径管理。安装器的 `--dir` 可把独立版装到任意目录，自定义位置目前不参与独立版扫描。
  官方发布页提供稳定版历史，Apple Silicon 安装脚本只公布这一条 manifest 路径。

## 夜扫覆盖

`duo verify` 和 `duo verify-install` 枚举 App recipe 与审计过的 App feed。
独立 CLI provider 的版本和原始 Mach-O 安装包未进入这些清单。

## 历史与实测

2026-11-19，macOS 27.2（Apple Silicon VM）。官方脚本安装 1.5.12，同一版本的
`agy update` 返回已是最新版。Google 的 [1.5.11 发布包](https://github.com/google-antigravity/antigravity-cli/releases/tag/1.5.11)
与 manifest 发布的 1.5.12 都通过签名验证并输出纯版本号。用旧包运行一次 `agy update`，
内置更新器把二进制从 1.5.11 替换为 1.5.12。更新完成后锁文件仍存在。持有该文件的
排他性 advisory lock 时，内置更新器退出 1 并报告 `Error: update already in progress`。

同一 VM 上，Duo 的 `duo list` 读出 1.5.11，`duo check` 提供 1.5.12，`duo install`
调用 `agy update` 完成升级。复查返回 `upToDate`，新版通过严格签名校验。带
`AGY_CLI_DISABLE_AUTO_UPDATE=true` 启动的 `duo check` 仍显示更新，并把更新命令交给用户。
打开 App 工作台的 CLI 标签后，Antigravity CLI 显示为 1.5.12，详情页展示了 1.5.12 的结构化更新日志。
