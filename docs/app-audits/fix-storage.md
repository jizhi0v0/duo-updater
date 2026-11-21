# fix-storage

[官方安装脚本](https://raw.githubusercontent.com/govijr/fix-storage/main/install.sh)
把 GitHub Releases 的 `fix-storage.tgz` 装入 `~/.fix-storage`，并在
`~/.local/bin/fix-storage` 建立链接。运行需要 Node.js 20.11 或更新版本及 npm。
2026-11-21 查到的唯一发布版是 [v0.1.0](https://github.com/govijr/fix-storage/releases/tag/v0.1.0)。

## 覆盖

- **检测**识别默认安装的两级链接，读取 npm 包的 `package.json`。v0.1.0 没有
  `--version`，扫描期间只读磁盘。最新版本采用与官方安装脚本相同的
  [GitHub Releases 稳定版跳转](https://github.com/govijr/fix-storage/releases/latest)。
- **更新日志**从已发布 tag 读取 [CHANGELOG.md](https://github.com/govijr/fix-storage/blob/v0.1.0/CHANGELOG.md)，
  显示按版本、日期和小节组织的条目。
- **更新**有新版时提供锁定目标版本的官方脚本命令。官方脚本先完成 npm 安装，再删除旧安装目录
  并移动暂存目录，没有原子替换或并发更新锁。Duo 不代为执行这个流程。
- **安装范围**覆盖默认路径的 Apple Silicon macOS 副本。
  使用 `FIX_STORAGE_HOME` 或 `FIX_STORAGE_BIN` 改路径的安装、源码运行及 Linux 不在该扫描范围。
  调研时未找到公开 npm 包或 Homebrew formula。

## 夜扫覆盖

`duo verify` 和 `duo verify-install` 枚举 App recipe 和审计过的 App feed。
独立 CLI provider 与其 npm tarball 当前未进入这些清单。

## 历史与实测

2026-11-21，macOS 27.2 (26B123) Apple Silicon VM。Node.js 22.22.2 与 npm
10.9.7 下，官方脚本校验发布包并安装 v0.1.0，创建默认的两级链接。
