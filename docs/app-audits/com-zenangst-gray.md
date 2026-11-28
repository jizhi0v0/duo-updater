# Gray

Gray 按应用设置 macOS 明暗外观。作者 README 将当前下载直接指向 GitHub 正式版 ZIP，Homebrew cask 也引用同一发布资产。[官网及下载](https://github.com/zenangst/Gray) · [Homebrew](https://formulae.brew.sh/cask/gray)

## 版本与分发

| 官方包 | 可执行架构 | 营销版本 / 构建号 | 严格签名检查与 Gatekeeper |
|---|---|---|---|
| 0.17.0 正式 | universal（arm64、x86_64） | 0.17.0 / 1 | 通过，Notarized Developer ID |
| 0.16.0 正式 | x86_64 | 0.16.0 / 1 | 通过，Notarized Developer ID |
| 0.10.1 预发布 | x86_64 | 0.10.1 / 1 | 通过，Developer ID |
| 0.0.1 预发布 | x86_64 | 0.0.1 / 1 | 严格签名通过，Mac Developer 签名被 Gatekeeper 拒绝 |

四份实包的 Bundle ID 均为 `com.zenangst.Gray`，Team 为 `E23HUP39A3`，最低系统声明为 macOS 10.14。0.0.1 至 0.10.1 的历史 GitHub 标签标为预发布，后续 0.11.0 至 0.17.0 均为正式发布。历史预发布与正式版使用相同 ID、数字标签及文件名，项目只提供一个当前下载。Duo 对这些副本检查最新正式版。[发布记录](https://github.com/zenangst/Gray/releases)

## 检测、安装与更新说明

GitHub 规则以正式标签比较营销版本，选择该发布的 `Gray.zip`。安装时核对签名包的营销版本与标签，拒绝同名旧包；多版共用的构建号 1 无法区分发布。0.17.0 发布资产包含一份 universal 应用，包内未见嵌套应用、Sparkle 框架或声明的更新 feed。厂商发布完整 ZIP，Duo 用现有安装器校验签名并替换，更新前无需更改 Gray 写入的各应用外观偏好。版本说明直接使用 GitHub 发布正文；0.17.0 的三条变更没有分节标题。[正式版说明及安装包](https://github.com/zenangst/Gray/releases/tag/0.17.0)

2026-11-28 对上述四份官方实包运行 `channel-verify --expect stable`。0.0.1、0.10.1、0.16.0 均由 GitHub 提示更新至 0.17.0，0.17.0 显示已是最新。四者的日志面板均显示 0.17.0 的一组版本记录、三条正文。

macOS 27.2 Apple Silicon VM 使用签名 Release CLI，从 GitHub 实时检查并将运行中的 0.16.0 原地升级至 0.17.0。严格签名、公证及升级后复查通过。Gray 有窗口时，Duo 保留旧进程；退出后可启动新版。

## 夜扫覆盖

正式规则由 GitHub 夜扫及安装包核验自动枚举，对应 `github:zenangst/Gray:stable` 和 `install:github:zenangst/Gray:stable`。两项均以当前正式发布为目标。
