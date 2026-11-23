# nospeaker

[nospeaker](https://github.com/os6/nospeaker) 是用 MacBook 触控板触觉马达发声的独立 CLI。
[官方脚本](https://github.com/os6/nospeaker/blob/v1.0/play.sh) 从 GitHub Releases 取
`nospeaker.zip`，把单个可执行文件放到 `~/.local/bin/nospeaker`，随后运行演示。
发布包是 universal Mach-O，签名标识是 `nospeaker`，Developer ID Team 为
`ZST375P5XB`（Spoken Systems LLC）。

## 覆盖

- **检测**扫描官方脚本的默认路径和手动安装常用的 `/usr/local/bin`，支持 bin 目录链接，
  核对 Apple Silicon 架构、Developer ID 和签名标识。v1.0 没有内嵌版本，也没有
  `--version`，Duo 以官方可执行文件的 SHA-256 识别它。首次发现其他官方副本时，
  在同一个短时限内和校验过的最新包、GitHub 最近一页（10 条）里的正式发布包比对，
  将匹配指纹记在本地。超出这页且缺少本地指纹的旧版会显示版本未知。源码自编译和随意解压到其他目录的副本无覆盖。
- **发布轨道**只有 GitHub Stable。最新版本来自 `os6/nospeaker` 的 Releases API。
  接受两段和三段数字 tag，拒绝草稿、预发布和后缀 tag。
- **更新日志**按版本和发布日期显示 GitHub Release 的正文。
- **一键更新**固定检查时返回的 tag 和 ZIP 摘要，核对可执行文件的开发者签名及架构，
  然后保留原文件权限和 ACL，在原路径原子替换。安装要求文件归当前用户所有，路径可写，
  符号链接和硬链接的副本可检测。自动替换要求可执行文件没有链接或隔离标记，且当前未运行。Duo App 和 CLI 对同一旧文件串行提交。
  检查与更新过程中均不执行 nospeaker。
- **图标**上游 README 使用终端 ASCII 字标。CLI 工作台使用波形 SF Symbol。

## 夜扫覆盖

`duo verify` 和 `duo verify-install` 枚举 App recipe 与审计过的 App feed。
`NospeakerProvider` 是独立 CLI provider，当前夜扫没有对应目标 ID 或 ZIP 检查。

## 历史与实测

2026-11-23，直接检查 [v1.0 官方 ZIP](https://github.com/os6/nospeaker/releases/tag/v1.0)。
ZIP 内只有根目录的 `nospeaker`，本地摘要与 GitHub asset 一致，`codesign --verify --strict`
及 Apple notarization 查询通过。上游只发布了 v1.0，真实旧版到新版的升级待下一版发布后验证。

签名 Release CLI 在 Apple Silicon macOS 27.3 的隔离目录里以真包运行
`duo check nospeaker --all --json`，返回 installed 1.0、latest 1.0、upToDate。
Core 用模拟发布包验证了历史版本识别、摘要错误、指纹写入失败、并发冲突与 ACL 保留。
Apple Silicon macOS 27.2 (26B123) VM 运行签名 App Release（源码 `43a99169`），
从菜单栏打开 CLI 工作台并选择真包副本。列表和详情标题均显示波形图标。详情显示
Version 1.0、Latest 1.0、Up to date 以及结构化 GitHub 发布说明。
