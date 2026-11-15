# Lens

- Bundle ID: `com.electron.kontena-lens`
- 这里只记录安装容器迁移，未完成全量应用审计。

2026-11-15 路线更新：当前一键安装使用已在 VM 验证的 ZIP；下文原有 DMG 包与端到端记录保留为历史证据。Duo 的 blockmap 优化以所选 ZIP 的发布方整包校验值为前提，缺少校验值时仍全量下载。详见文末「Electron ZIP 迁移」。

## 历史与实测

### Electron ZIP 迁移（2026-11-15）

安装容器改为 `Lens-2026.11.91422-latest-arm64-mac.zip`。在 macOS 27.2 Apple Silicon VM 中，从本次对应 DMG 准备的独立副本，经生产 `VendorInstaller.apply` 校验与替换为同版本 ZIP，再通过 LaunchServices 启动指定路径，确认 PID 存活后退出测试实例。版本、bundle ID、Team、arm64 与代码签名检查均通过。本次对应 DMG/ZIP 的 arm64 主程序 CDHash 与 app.asar 相同。既有旧 bundle ID、版本门控、edition 与仅检测渠道的范围沿用原规则；没有新增跨组安装。
整包发布校验值存在时才会尝试 blockmap；旧 GitHub 发布缺少 digest 时仍走全量 ZIP 与原有签名检查。

本次包、逐项结果与限制见 [集中验证记录](../../verify/electron-blockmap-20261115/README.md)。这些是一次验证的结果，不代表应用所有版本或功能均已测试。
