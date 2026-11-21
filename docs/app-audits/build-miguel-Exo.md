# Exo

## 分发与更新检测

- Miguel Piedrafita 的 Gmail 客户端，Bundle ID 和签名标识均为 `build.miguel.Exo`。GitHub 已发布的 0.1.0 和 0.2.0 均为 Stable，DMG 内是 Apple Silicon 版，最低 macOS 13。
- 规则读取 `m1guelpf/Exo` 的 `/releases/latest`。两个真包的营销版本和构建号都与 tag 的三段版本相同。安装规则只选 `exo-v<VERSION>-macos-arm64.dmg`。
- Homebrew 的 `exo` cask 指向 Exo Labs 的分布式计算应用 `exolabs.EXO`，有独立厂商和更新源。

## 自更新与一键安装

- [Exo 的自更新器](https://github.com/m1guelpf/Exo/blob/v0.2.0/crates/exo/src/update/mod.rs) 从同一仓库下载整张 DMG，可在后台准备更新。FastFrame 在目标 bundle 的父目录准备 `.exo-update-*`，用 `staged.json` 记录待安装载荷。Duo 的规则选用公开发布的 DMG，未接入这个私有暂存目录。
- 两个 DMG 的 app 均通过严格签名校验，Team ID 同为 `LR4RJT6586`，Gatekeeper 均返回 Notarized Developer ID。Duo 复用 GitHub 资产摘要和 Developer ID Team 连续性检查。源码自建的 ad-hoc 副本可以检测版本，一键安装缺少可比对的 Team ID。

## 更新说明

0.2.0 的 [GitHub 发布正文](https://github.com/m1guelpf/Exo/releases/tag/v0.2.0) 只给出版本比较链接。`channel-verify` 在 0.1.0 真包上得到 `raw inline notes, 75 chars, no structure`，并保留发布页入口。

## 夜扫覆盖

`duo verify --github --only build.miguel.Exo` 枚举 `github:m1guelpf/Exo:stable`，`duo verify-install --only build.miguel.Exo --full` 从同一规则解析并检查完整 DMG。2026-11-22 首次检查均通过。

## VM 复验

在 Apple Silicon macOS 27.2 VM 中，从官方 0.1.0 DMG 取出真实副本。签名 Release CLI 的 `duo check --all --json` 报告 GitHub 0.2.0，`duo install --yes --json` 返回 `applied: true`。更新后营销版本和构建号均为 0.2.0，严格签名校验与 Gatekeeper 均通过，复查报告 `up-to-date`。
