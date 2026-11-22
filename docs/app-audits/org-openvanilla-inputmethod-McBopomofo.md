# 小麥注音 McBopomofo

## 分发与更新入口

- 稳定版以 `org.openvanilla.inputmethod.McBopomofo` 分发。作者的 GitHub Release 列出签名安装器 ZIP，API 的同一个 asset 给出 SHA-256。[正式版发布](https://github.com/openvanilla/McBopomofo/releases)
- 厂商安装器的目标固定为当前用户的 `~/Library/Input Methods/McBopomofo.app`。灰色 Update 仅向该标准路径中的厂商签名副本开放交接。系统级和改名副本仍可查看版本和厂商发布页。[厂商安装器源码](https://github.com/openvanilla/McBopomofo/blob/3.1.1/Source/Installer/AppDelegate.swift)
- Duo 下载 ZIP、验证摘要和安装器签名后在用户会话打开安装器。用户在厂商界面确认安装，输入法注册及 macOS 的输入源授权由厂商和系统处理。自动更新和 Update All 跳过交接。
- 可识别的 Homebrew 管理副本沿用 Brew 路径。[Homebrew cask](https://formulae.brew.sh/cask/mcbopomofo)

## 历史与实测

- 2026-11-22，官网 Release 3.1.1 的 ZIP 内签名安装器为 `org.openvanilla.McBopomofo.McBopomofoInstaller`，Team ID 为 `JK5M8ENA23`。最近十二个公开 GitHub Release 均为稳定发行。
- Apple Silicon macOS 27.2 VM，以厂商安装器从用户级 3.1 升级到 3.1.1。macOS 对输入源变更要求确认。完成后输入法可用，实际进行了注音输入。此处记录直接运行厂商安装器的实测。
